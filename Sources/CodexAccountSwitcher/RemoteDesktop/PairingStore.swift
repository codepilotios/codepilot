import CryptoKit
import Foundation

enum RemoteDesktopSecurityError: Error, Equatable, LocalizedError {
    case challengeUnknown
    case challengeExpired
    case challengeAlreadyUsed
    case invalidSignature
    case untrustedDevice
    case deviceRevoked
    case nonceUnknown
    case nonceExpired
    case nonceAlreadyUsed
    case controllerBusy
    case leaseUnknown
    case leaseExpired
    case sequenceReplay
    case prohibitedAuditContent

    var errorDescription: String? {
        switch self {
        case .challengeUnknown:
            return "Unknown pairing challenge."
        case .challengeExpired:
            return "Pairing challenge expired."
        case .challengeAlreadyUsed:
            return "Pairing challenge already used."
        case .invalidSignature:
            return "Invalid signature."
        case .untrustedDevice:
            return "Untrusted device."
        case .deviceRevoked:
            return "Device revoked."
        case .nonceUnknown:
            return "Unknown nonce."
        case .nonceExpired:
            return "Nonce expired."
        case .nonceAlreadyUsed:
            return "Nonce already used."
        case .controllerBusy:
            return "A controller is already active."
        case .leaseUnknown:
            return "Unknown lease."
        case .leaseExpired:
            return "Lease expired."
        case .sequenceReplay:
            return "Sequence replay rejected."
        case .prohibitedAuditContent:
            return "Prohibited audit content."
        }
    }
}

struct VerifiedPairingApprovalToken: Equatable {
    let id: UUID
    let challengeID: String
    let deviceID: String
    let issuedAt: Date

    fileprivate init(challengeID: String, deviceID: String, issuedAt: Date) {
        self.id = UUID()
        self.challengeID = challengeID
        self.deviceID = deviceID
        self.issuedAt = issuedAt
    }
}

struct VerifiedRemoteDesktopNonce: Equatable {
    let id: UUID
    let nonce: String
    let deviceID: String
    let verifiedAt: Date
    let expiresAt: Date

    fileprivate init(nonce: String, deviceID: String, verifiedAt: Date, expiresAt: Date) {
        self.id = UUID()
        self.nonce = nonce
        self.deviceID = deviceID
        self.verifiedAt = verifiedAt
        self.expiresAt = expiresAt
    }
}

private struct PairingChallengeRecord: Equatable {
    let challenge: RemotePairingChallenge
    let deviceID: String
    let deviceName: String
    let publicKeyRawRepresentation: Data
    let issuedAt: Date
    var verifiedAt: Date?
    var approvalToken: VerifiedPairingApprovalToken?
    var approvalConsumedAt: Date?
}

private struct VerifiedNonceRecord: Equatable {
    let nonce: String
    let deviceID: String
    let verifiedAt: Date
    let expiresAt: Date
}

private struct NonceReplayKey: Hashable {
    let deviceID: String
    let nonce: String
}

final class PairingStore {
    typealias Clock = () -> Date
    typealias DevicePersistence = ([TrustedRemoteDevice]) throws -> Void

    private let clock: Clock
    private let fileURL: URL
    private let persistTrustedDevices: DevicePersistence
    private let lock = NSLock()
    private var trustedDevicesByID: [String: TrustedRemoteDevice]
    private var pairingChallengesByID: [String: PairingChallengeRecord] = [:]
    private var verifiedNonceRecordsByKey: [NonceReplayKey: VerifiedNonceRecord] = [:]

    init(
        fileURL: URL? = nil,
        clock: @escaping Clock = Date.init,
        persistTrustedDevices: DevicePersistence? = nil
    ) throws {
        self.clock = clock
        let resolvedFileURL = fileURL ?? Self.defaultTrustedDevicesURL()
        self.fileURL = resolvedFileURL
        self.persistTrustedDevices = persistTrustedDevices ?? { devices in
            try Self.persistTrustedDevices(devices, to: resolvedFileURL)
        }
        self.trustedDevicesByID = [:]
        try Self.ensureStorage(for: resolvedFileURL)
        self.trustedDevicesByID = try Self.loadTrustedDevices(from: resolvedFileURL).reduce(into: [:]) { result, device in
            result[device.id] = device
        }
    }

    func issueChallenge(
        deviceID: String,
        name: String,
        publicKeyRawRepresentation: Data,
        macName: String
    ) -> RemotePairingChallenge {
        lock.lock()
        defer { lock.unlock() }

        let now = clock()
        let challenge = RemotePairingChallenge(
            id: UUID().uuidString,
            code: Self.randomChallengeCode(),
            macName: macName,
            expiresAt: now.addingTimeInterval(Self.challengeTTL)
        )
        pairingChallengesByID[challenge.id] = PairingChallengeRecord(
            challenge: challenge,
            deviceID: deviceID,
            deviceName: name,
            publicKeyRawRepresentation: publicKeyRawRepresentation,
            issuedAt: now,
            verifiedAt: nil,
            approvalToken: nil,
            approvalConsumedAt: nil
        )
        return challenge
    }

    func verifyChallenge(
        _ challenge: RemotePairingChallenge,
        deviceID: String,
        signature: Data
    ) throws -> VerifiedPairingApprovalToken {
        lock.lock()
        defer { lock.unlock() }

        let now = clock()
        guard var record = pairingChallengesByID[challenge.id], record.deviceID == deviceID else {
            throw RemoteDesktopSecurityError.challengeUnknown
        }
        guard record.verifiedAt == nil else {
            throw RemoteDesktopSecurityError.challengeAlreadyUsed
        }
        guard now <= record.challenge.expiresAt else {
            throw RemoteDesktopSecurityError.challengeExpired
        }

        let publicKey = try P256.Signing.PublicKey(rawRepresentation: record.publicKeyRawRepresentation)
        let challengeSignature = try P256.Signing.ECDSASignature(derRepresentation: signature)
        guard publicKey.isValidSignature(challengeSignature, for: Data(record.challenge.code.utf8)) else {
            throw RemoteDesktopSecurityError.invalidSignature
        }

        let token = VerifiedPairingApprovalToken(
            challengeID: challenge.id,
            deviceID: deviceID,
            issuedAt: now
        )
        record.verifiedAt = now
        record.approvalToken = token
        pairingChallengesByID[challenge.id] = record
        return token
    }

    func challenge(id: String) -> RemotePairingChallenge? {
        lock.lock()
        defer { lock.unlock() }
        return pairingChallengesByID[id]?.challenge
    }

    func approveDevice(using token: VerifiedPairingApprovalToken) throws -> TrustedRemoteDevice {
        lock.lock()
        defer { lock.unlock() }

        let now = clock()
        guard var record = pairingChallengesByID[token.challengeID], record.deviceID == token.deviceID else {
            throw RemoteDesktopSecurityError.challengeUnknown
        }
        guard let approvalToken = record.approvalToken, approvalToken.id == token.id else {
            throw RemoteDesktopSecurityError.challengeAlreadyUsed
        }
        guard record.approvalConsumedAt == nil else {
            throw RemoteDesktopSecurityError.challengeAlreadyUsed
        }
        guard now <= record.challenge.expiresAt else {
            throw RemoteDesktopSecurityError.challengeExpired
        }

        let approvedDevice = TrustedRemoteDevice(
            id: record.deviceID,
            name: record.deviceName,
            publicKeyRawRepresentation: record.publicKeyRawRepresentation,
            approvedAt: now,
            revokedAt: nil
        )
        var updatedDevices = trustedDevicesByID
        updatedDevices[approvedDevice.id] = approvedDevice
        try persistTrustedDevices(updatedDevices.values.sorted(by: { $0.id < $1.id }))
        trustedDevicesByID = updatedDevices
        record.approvalConsumedAt = now
        pairingChallengesByID[token.challengeID] = record
        return approvedDevice
    }

    func verifyNonce(deviceID: String, nonce: String, signature: Data) throws -> VerifiedRemoteDesktopNonce {
        lock.lock()
        defer { lock.unlock() }

        purgeExpiredNonceRecords()

        let now = clock()
        let key = NonceReplayKey(deviceID: deviceID, nonce: nonce)
        if let record = verifiedNonceRecordsByKey[key], record.expiresAt > now {
            throw RemoteDesktopSecurityError.nonceAlreadyUsed
        }

        guard let device = trustedDevicesByID[deviceID] else {
            throw RemoteDesktopSecurityError.untrustedDevice
        }
        guard device.revokedAt == nil else {
            throw RemoteDesktopSecurityError.deviceRevoked
        }
        try Self.verify(signature: signature, message: Data(nonce.utf8), device: device)

        let proof = VerifiedRemoteDesktopNonce(
            nonce: nonce,
            deviceID: deviceID,
            verifiedAt: now,
            expiresAt: now.addingTimeInterval(Self.nonceProofTTL)
        )
        verifiedNonceRecordsByKey[key] = VerifiedNonceRecord(
            nonce: nonce,
            deviceID: deviceID,
            verifiedAt: now,
            expiresAt: proof.expiresAt
        )
        return proof
    }

    func verify(signature: Data, message: Data, deviceID: String) throws {
        guard let device = trustedDevice(id: deviceID) else {
            throw RemoteDesktopSecurityError.untrustedDevice
        }
        try Self.verify(signature: signature, message: message, device: device)
    }

    func trustedDevice(id: String) -> TrustedRemoteDevice? {
        lock.lock()
        defer { lock.unlock() }
        return trustedDevicesByID[id]
    }

    func trustedDevices() -> [TrustedRemoteDevice] {
        lock.lock()
        defer { lock.unlock() }
        return trustedDevicesByID.values.sorted(by: { $0.id < $1.id })
    }

    @discardableResult
    func trustPreverifiedDevice(
        id: String,
        name: String,
        publicKeyRawRepresentation: Data
    ) throws -> TrustedRemoteDevice {
        lock.lock()
        defer { lock.unlock() }

        let device = TrustedRemoteDevice(
            id: id,
            name: name,
            publicKeyRawRepresentation: publicKeyRawRepresentation,
            approvedAt: clock(),
            revokedAt: nil
        )
        var updatedDevices = trustedDevicesByID
        updatedDevices[id] = device
        try persistTrustedDevices(updatedDevices.values.sorted(by: { $0.id < $1.id }))
        trustedDevicesByID = updatedDevices
        return device
    }

    @discardableResult
    func revokeDevice(id: String) throws -> TrustedRemoteDevice {
        lock.lock()
        defer { lock.unlock() }

        guard var device = trustedDevicesByID[id] else {
            throw RemoteDesktopSecurityError.untrustedDevice
        }

        device.revokedAt = clock()
        var updatedDevices = trustedDevicesByID
        updatedDevices[id] = device
        try persistTrustedDevices(updatedDevices.values.sorted(by: { $0.id < $1.id }))
        trustedDevicesByID = updatedDevices
        return device
    }

    private static let challengeTTL: TimeInterval = 120
    private static let nonceProofTTL: TimeInterval = 60

    private static func defaultTrustedDevicesURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codepilot/remote-desktop/trusted-devices.json")
    }

    private static func randomChallengeCode() -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        return Data(bytes).base64EncodedString()
    }

    private static func ensureStorage(for fileURL: URL) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directoryURL.path)
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: Data(), attributes: [.posixPermissions: 0o600])
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    private static func loadTrustedDevices(from fileURL: URL) throws -> [TrustedRemoteDevice] {
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.dataDecodingStrategy = .base64
        return try decoder.decode([TrustedRemoteDevice].self, from: data)
    }

    private static func persistTrustedDevices(_ devices: [TrustedRemoteDevice], to fileURL: URL) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directoryURL.path)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.dataEncodingStrategy = .base64
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(devices)

        let tempURL = directoryURL.appendingPathComponent(".\(UUID().uuidString).trusted-devices.json.tmp")
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        guard FileManager.default.createFile(atPath: tempURL.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tempURL.path)

        let _ = try FileManager.default.replaceItemAt(
            fileURL,
            withItemAt: tempURL,
            backupItemName: nil
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    private static func verify(signature: Data, message: Data, device: TrustedRemoteDevice) throws {
        guard device.revokedAt == nil else {
            throw RemoteDesktopSecurityError.deviceRevoked
        }

        let key = try P256.Signing.PublicKey(rawRepresentation: device.publicKeyRawRepresentation)
        let signature = try P256.Signing.ECDSASignature(derRepresentation: signature)
        guard key.isValidSignature(signature, for: message) else {
            throw RemoteDesktopSecurityError.invalidSignature
        }
    }

    private func purgeExpiredNonceRecords() {
        let now = clock()
        verifiedNonceRecordsByKey = verifiedNonceRecordsByKey.filter { $0.value.expiresAt > now }
    }
}
