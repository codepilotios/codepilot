import AppKit
import ApplicationServices
import CryptoKit
import Foundation

protocol RemoteDesktopPermissionChecking: AnyObject {
    var screenRecordingGranted: Bool { get }
    var accessibilityGranted: Bool { get }
    var macUnlocked: Bool { get }
}

final class SystemRemoteDesktopPermissions: RemoteDesktopPermissionChecking {
    var screenRecordingGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    var accessibilityGranted: Bool {
        AXIsProcessTrustedWithOptions(nil)
    }

    var macUnlocked: Bool {
        true
    }

    func requestScreenRecording() {
        _ = CGRequestScreenCaptureAccess()
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}

struct PendingPairing: Equatable {
    let deviceID: String
    let name: String
    let challenge: RemotePairingChallenge
    let publicKeyRawRepresentation: Data
    let keyFingerprint: String
    var approvalToken: VerifiedPairingApprovalToken?
}

struct ActiveRemoteSession: Equatable {
    let deviceID: String
    let leaseID: String
    let startedAt: Date
}

struct RemoteDesktopStatus: Equatable {
    let screenRecordingGranted: Bool
    let accessibilityGranted: Bool
    let macUnlocked: Bool
    let pendingPairing: PendingPairing?
    let trustedDevices: [TrustedRemoteDevice]
    let activeSession: ActiveRemoteSession?
    let auditEvents: [RemoteDesktopAuditEvent]
}

final class RemoteDesktopCoordinator {
    let pairingStore: PairingStore

    private let permissions: RemoteDesktopPermissionChecking
    private let auditLog: RemoteDesktopAuditLog
    private let lock = NSLock()
    private var lockObserver: NSObjectProtocol?
    private var unlockObserver: NSObjectProtocol?
    private var pendingPairing: PendingPairing?
    private var activeSession: ActiveRemoteSession?

    private(set) var snapshot: RemoteDesktopStatus

    init(
        permissions: RemoteDesktopPermissionChecking = SystemRemoteDesktopPermissions(),
        pairingStore: PairingStore? = nil,
        auditLog: RemoteDesktopAuditLog? = nil
    ) throws {
        self.permissions = permissions
        self.pairingStore = try pairingStore ?? PairingStore()
        self.auditLog = try auditLog ?? RemoteDesktopAuditLog()
        self.snapshot = RemoteDesktopStatus(
            screenRecordingGranted: permissions.screenRecordingGranted,
            accessibilityGranted: permissions.accessibilityGranted,
            macUnlocked: permissions.macUnlocked,
            pendingPairing: nil,
            trustedDevices: self.pairingStore.trustedDevices(),
            activeSession: nil,
            auditEvents: (try? self.auditLog.loadAll()) ?? []
        )
        refreshStatus()
        lockObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.sessionDidResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleMacDidLock()
        }
        unlockObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshStatus()
        }
    }

    deinit {
        if let lockObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(lockObserver)
        }
        if let unlockObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(unlockObserver)
        }
    }

    func refreshStatus() {
        lock.lock()
        defer { lock.unlock() }
        rebuildSnapshotLocked()
    }

    @discardableResult
    func beginPairing(
        deviceID: String,
        name: String,
        publicKeyRawRepresentation: Data,
        macName: String
    ) throws -> PendingPairing {
        lock.lock()
        defer { lock.unlock() }

        let challenge = pairingStore.issueChallenge(
            deviceID: deviceID,
            name: name,
            publicKeyRawRepresentation: publicKeyRawRepresentation,
            macName: macName
        )
        let pending = PendingPairing(
            deviceID: deviceID,
            name: name,
            challenge: challenge,
            publicKeyRawRepresentation: publicKeyRawRepresentation,
            keyFingerprint: Self.keyFingerprint(publicKeyRawRepresentation),
            approvalToken: nil
        )
        pendingPairing = pending
        try appendAuditLocked(.pairingChallengeIssued, deviceID: deviceID, sessionID: nil, leaseID: nil, reason: nil)
        rebuildSnapshotLocked()
        return pending
    }

    func verifyPendingPairing(
        challengeID: String,
        deviceID: String,
        signature: Data
    ) throws -> RemotePairingApprovalStatus {
        lock.lock()
        defer { lock.unlock() }

        guard var pendingPairing,
              pendingPairing.challenge.id == challengeID,
              pendingPairing.deviceID == deviceID else {
            throw RemoteDesktopSecurityError.challengeUnknown
        }
        let token = try pairingStore.verifyChallenge(
            pendingPairing.challenge,
            deviceID: deviceID,
            signature: signature
        )
        pendingPairing.approvalToken = token
        self.pendingPairing = pendingPairing
        try appendAuditLocked(.pairingChallengeVerified, deviceID: deviceID, sessionID: nil, leaseID: nil, reason: nil)
        rebuildSnapshotLocked()
        return RemotePairingApprovalStatus(
            status: "pending_mac_approval",
            challengeID: challengeID,
            deviceID: deviceID,
            macName: pendingPairing.challenge.macName
        )
    }

    func approvePendingPairing() throws {
        lock.lock()
        defer { lock.unlock() }

        guard let pendingPairing, let approvalToken = pendingPairing.approvalToken else { return }
        _ = try pairingStore.approveDevice(using: approvalToken)
        self.pendingPairing = nil
        try appendAuditLocked(.pairingApproved, deviceID: pendingPairing.deviceID, sessionID: nil, leaseID: nil, reason: nil)
        rebuildSnapshotLocked()
    }

    func rejectPendingPairing() {
        lock.lock()
        defer { lock.unlock() }
        pendingPairing = nil
        rebuildSnapshotLocked()
    }

    func registerActiveSession(deviceID: String, leaseID: String, startedAt: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        activeSession = ActiveRemoteSession(deviceID: deviceID, leaseID: leaseID, startedAt: startedAt)
        try? appendAuditLocked(.leaseGranted, deviceID: deviceID, sessionID: nil, leaseID: leaseID, reason: nil)
        rebuildSnapshotLocked()
    }

    func emergencyDisconnect() {
        lock.lock()
        defer { lock.unlock() }
        if let activeSession {
            try? appendAuditLocked(.leaseEnded, deviceID: activeSession.deviceID, sessionID: nil, leaseID: activeSession.leaseID, reason: nil)
        }
        activeSession = nil
        rebuildSnapshotLocked()
    }

    func revokeDevice(id: String) throws {
        lock.lock()
        defer { lock.unlock() }
        _ = try pairingStore.revokeDevice(id: id)
        if activeSession?.deviceID == id {
            activeSession = nil
        }
        try appendAuditLocked(.deviceRevoked, deviceID: id, sessionID: nil, leaseID: nil, reason: .revoked)
        rebuildSnapshotLocked()
    }

    func handleMacDidLock() {
        lock.lock()
        defer { lock.unlock() }
        activeSession = nil
        rebuildSnapshotLocked()
    }

    private func rebuildSnapshotLocked() {
        snapshot = RemoteDesktopStatus(
            screenRecordingGranted: permissions.screenRecordingGranted,
            accessibilityGranted: permissions.accessibilityGranted,
            macUnlocked: permissions.macUnlocked,
            pendingPairing: pendingPairing,
            trustedDevices: pairingStore.trustedDevices(),
            activeSession: permissions.macUnlocked ? activeSession : nil,
            auditEvents: (try? auditLog.loadAll()) ?? []
        )
    }

    private func appendAuditLocked(
        _ kind: RemoteDesktopAuditEventKind,
        deviceID: String?,
        sessionID: String?,
        leaseID: String?,
        reason: RemoteDesktopAuditReason?
    ) throws {
        try auditLog.append(RemoteDesktopAuditEvent(
            id: UUID().uuidString,
            timestamp: .distantPast,
            kind: kind,
            deviceId: deviceID,
            sessionId: sessionID,
            leaseId: leaseID,
            sequence: nil,
            reason: reason
        ))
    }

    private static func keyFingerprint(_ data: Data) -> String {
        SHA256.hash(data: data)
            .prefix(8)
            .map { String(format: "%02x", $0) }
            .joined(separator: ":")
    }
}
