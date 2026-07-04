import CryptoKit
import Foundation
import XCTest
@testable import CodexAccountSwitcher

final class RemoteDesktopCoordinatorTests: XCTestCase {
    func testSnapshotReflectsPermissionState() throws {
        let permissions = FakeRemoteDesktopPermissions(
            screenRecordingGranted: false,
            accessibilityGranted: true,
            macUnlocked: true
        )
        let coordinator = try makeCoordinator(permissions: permissions)

        XCTAssertEqual(coordinator.snapshot.screenRecordingGranted, false)
        XCTAssertEqual(coordinator.snapshot.accessibilityGranted, true)
        XCTAssertEqual(coordinator.snapshot.macUnlocked, true)

        permissions.screenRecordingGranted = true
        coordinator.refreshStatus()

        XCTAssertEqual(coordinator.snapshot.screenRecordingGranted, true)
    }

    func testPairingCanBeApprovedOrRejectedLocally() throws {
        let coordinator = try makeCoordinator()
        let privateKey = P256.Signing.PrivateKey()
        let publicKey = privateKey.publicKey.rawRepresentation

        let pending = try coordinator.beginPairing(
            deviceID: "phone-1",
            name: "Beta iPhone",
            publicKeyRawRepresentation: publicKey,
            macName: "Mac host"
        )

        XCTAssertEqual(coordinator.snapshot.pendingPairing?.deviceID, "phone-1")
        XCTAssertFalse(pending.keyFingerprint.isEmpty)

        coordinator.rejectPendingPairing()
        XCTAssertNil(coordinator.snapshot.pendingPairing)

        let approvalPending = try coordinator.beginPairing(
            deviceID: "phone-1",
            name: "Beta iPhone",
            publicKeyRawRepresentation: publicKey,
            macName: "Mac host"
        )
        _ = try coordinator.verifyPendingPairing(
            challengeID: approvalPending.challenge.id,
            deviceID: "phone-1",
            signature: try privateKey.signature(for: Data(approvalPending.challenge.code.utf8)).derRepresentation
        )
        try coordinator.approvePendingPairing()

        XCTAssertNil(coordinator.snapshot.pendingPairing)
        XCTAssertEqual(coordinator.snapshot.trustedDevices.map(\.id), ["phone-1"])
    }

    func testVerifiedPairingWaitsForMacApprovalBeforeTrustingDevice() throws {
        let coordinator = try makeCoordinator()
        let privateKey = P256.Signing.PrivateKey()
        let pending = try coordinator.beginPairing(
            deviceID: "phone-1",
            name: "Beta iPhone",
            publicKeyRawRepresentation: privateKey.publicKey.rawRepresentation,
            macName: "Mac host"
        )

        let approval = try coordinator.verifyPendingPairing(
            challengeID: pending.challenge.id,
            deviceID: "phone-1",
            signature: try privateKey.signature(for: Data(pending.challenge.code.utf8)).derRepresentation
        )

        XCTAssertEqual(approval.status, "pending_mac_approval")
        XCTAssertEqual(approval.challengeID, pending.challenge.id)
        XCTAssertEqual(approval.deviceID, "phone-1")
        XCTAssertEqual(approval.macName, "Mac host")
        XCTAssertEqual(coordinator.snapshot.pendingPairing?.deviceID, "phone-1")
        XCTAssertEqual(coordinator.snapshot.trustedDevices, [])

        try coordinator.approvePendingPairing()

        XCTAssertNil(coordinator.snapshot.pendingPairing)
        XCTAssertEqual(coordinator.snapshot.trustedDevices.map(\.id), ["phone-1"])
    }

    func testActiveSessionAndEmergencyDisconnect() throws {
        let coordinator = try makeCoordinator()

        coordinator.registerActiveSession(deviceID: "phone-1", leaseID: "lease-1", startedAt: Date(timeIntervalSince1970: 10))

        XCTAssertEqual(coordinator.snapshot.activeSession?.deviceID, "phone-1")
        XCTAssertEqual(coordinator.snapshot.activeSession?.leaseID, "lease-1")

        coordinator.emergencyDisconnect()

        XCTAssertNil(coordinator.snapshot.activeSession)
    }

    func testRevokingActiveDeviceClearsTrustedDeviceAndSession() throws {
        let coordinator = try makeCoordinator()
        let key = P256.Signing.PrivateKey()
        let challenge = coordinator.pairingStore.issueChallenge(
            deviceID: "phone-1",
            name: "Beta iPhone",
            publicKeyRawRepresentation: key.publicKey.rawRepresentation,
            macName: "Mac host"
        )
        let approval = try coordinator.pairingStore.verifyChallenge(
            challenge,
            deviceID: "phone-1",
            signature: try key.signature(for: Data(challenge.code.utf8)).derRepresentation
        )
        _ = try coordinator.pairingStore.approveDevice(using: approval)
        coordinator.refreshStatus()
        coordinator.registerActiveSession(deviceID: "phone-1", leaseID: "lease-1", startedAt: Date())

        try coordinator.revokeDevice(id: "phone-1")

        XCTAssertNotNil(coordinator.snapshot.trustedDevices.first?.revokedAt)
        XCTAssertNil(coordinator.snapshot.activeSession)
    }

    func testMacLockClearsActiveSessionAndBlocksStatus() throws {
        let permissions = FakeRemoteDesktopPermissions(macUnlocked: true)
        let coordinator = try makeCoordinator(permissions: permissions)
        coordinator.registerActiveSession(deviceID: "phone-1", leaseID: "lease-1", startedAt: Date())

        permissions.macUnlocked = false
        coordinator.handleMacDidLock()

        XCTAssertFalse(coordinator.snapshot.macUnlocked)
        XCTAssertNil(coordinator.snapshot.activeSession)
    }

    private func makeCoordinator(
        permissions: FakeRemoteDesktopPermissions = FakeRemoteDesktopPermissions()
    ) throws -> RemoteDesktopCoordinator {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        return try RemoteDesktopCoordinator(
            permissions: permissions,
            pairingStore: PairingStore(fileURL: root.appendingPathComponent("trusted-devices.json")),
            auditLog: RemoteDesktopAuditLog(fileURL: root.appendingPathComponent("audit.jsonl"))
        )
    }
}

final class FakeRemoteDesktopPermissions: RemoteDesktopPermissionChecking {
    var screenRecordingGranted: Bool
    var accessibilityGranted: Bool
    var macUnlocked: Bool

    init(
        screenRecordingGranted: Bool = true,
        accessibilityGranted: Bool = true,
        macUnlocked: Bool = true
    ) {
        self.screenRecordingGranted = screenRecordingGranted
        self.accessibilityGranted = accessibilityGranted
        self.macUnlocked = macUnlocked
    }
}
