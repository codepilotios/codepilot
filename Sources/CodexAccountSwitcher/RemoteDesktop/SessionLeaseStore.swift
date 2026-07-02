import Foundation

final class SessionLeaseStore {
    typealias Clock = () -> Date
    typealias CurrentTrustValidator = (String) throws -> Void

    private struct NonceRecord: Equatable {
        let nonce: String
        let deviceID: String
        let issuedAt: Date
        let expiresAt: Date
        var usedAt: Date?
    }

    private struct LeaseRecord: Equatable {
        var lease: RemoteDesktopLease
        let issuedAt: Date
        var expiresAt: Date
        var revokedAt: Date?
        var endedAt: Date?
        var lastAcceptedSequence: UInt64?

        var isActive: Bool {
            revokedAt == nil && endedAt == nil
        }
    }

    private let clock: Clock
    private let currentTrustValidator: CurrentTrustValidator
    private let lock = NSLock()
    private var noncesByValue: [String: NonceRecord] = [:]
    private var leasesByID: [String: LeaseRecord] = [:]
    private var activeLeaseID: String?

    init(
        clock: @escaping Clock = Date.init,
        currentTrustValidator: @escaping CurrentTrustValidator
    ) {
        self.clock = clock
        self.currentTrustValidator = currentTrustValidator
    }

    func issueNonce(for deviceID: String) -> String {
        lock.lock()
        defer { lock.unlock() }

        purgeExpiredState()

        let nonce = Self.randomToken()
        let now = clock()
        noncesByValue[nonce] = NonceRecord(
            nonce: nonce,
            deviceID: deviceID,
            issuedAt: now,
            expiresAt: now.addingTimeInterval(Self.nonceTTL),
            usedAt: nil
        )
        return nonce
    }

    func createLease(using proof: VerifiedRemoteDesktopNonce) throws -> RemoteDesktopLease {
        lock.lock()
        defer { lock.unlock() }

        purgeExpiredState()
        do {
            try currentTrustValidator(proof.deviceID)
        } catch {
            invalidateActiveLeaseIfNeeded(for: proof.deviceID)
            throw error
        }
        try consume(proof: proof)
        guard activeLeaseID == nil else {
            throw RemoteDesktopSecurityError.controllerBusy
        }

        let now = clock()
        let lease = RemoteDesktopLease(
            id: UUID().uuidString,
            deviceId: proof.deviceID,
            expiresAt: now.addingTimeInterval(Self.leaseTTL)
        )
        leasesByID[lease.id] = LeaseRecord(
            lease: lease,
            issuedAt: now,
            expiresAt: lease.expiresAt,
            revokedAt: nil,
            endedAt: nil,
            lastAcceptedSequence: nil
        )
        activeLeaseID = lease.id
        return lease
    }

    func renewLease(leaseID: String, using proof: VerifiedRemoteDesktopNonce) throws -> RemoteDesktopLease {
        lock.lock()
        defer { lock.unlock() }

        purgeExpiredState()
        do {
            try currentTrustValidator(proof.deviceID)
        } catch {
            invalidateActiveLeaseIfNeeded(for: proof.deviceID)
            throw error
        }
        guard var record = leasesByID[leaseID] else {
            throw RemoteDesktopSecurityError.leaseUnknown
        }
        guard record.lease.deviceId == proof.deviceID else {
            throw RemoteDesktopSecurityError.leaseUnknown
        }
        guard record.isActive else {
            throw RemoteDesktopSecurityError.leaseExpired
        }
        guard activeLeaseID == leaseID else {
            throw RemoteDesktopSecurityError.leaseUnknown
        }

        try consume(proof: proof)

        let now = clock()
        record.lease = RemoteDesktopLease(
            id: record.lease.id,
            deviceId: record.lease.deviceId,
            expiresAt: now.addingTimeInterval(Self.leaseTTL)
        )
        record.expiresAt = record.lease.expiresAt
        leasesByID[leaseID] = record
        return record.lease
    }

    func validateSequence(_ sequence: UInt64, for leaseID: String) throws {
        lock.lock()
        defer { lock.unlock() }

        purgeExpiredState()
        guard var record = leasesByID[leaseID] else {
            throw RemoteDesktopSecurityError.leaseUnknown
        }
        do {
            try currentTrustValidator(record.lease.deviceId)
        } catch {
            invalidateActiveLeaseIfNeeded(for: record.lease.deviceId)
            throw error
        }
        guard record.isActive else {
            throw RemoteDesktopSecurityError.leaseExpired
        }
        if let lastAcceptedSequence = record.lastAcceptedSequence, sequence <= lastAcceptedSequence {
            throw RemoteDesktopSecurityError.sequenceReplay
        }
        record.lastAcceptedSequence = sequence
        leasesByID[leaseID] = record
    }

    func endLease(leaseID: String) {
        lock.lock()
        defer { lock.unlock() }

        guard var record = leasesByID[leaseID] else {
            return
        }
        let now = clock()
        record.endedAt = now
        record.expiresAt = now
        leasesByID[leaseID] = record
        if activeLeaseID == leaseID {
            activeLeaseID = nil
        }
    }

    func revokeLease(leaseID: String) {
        lock.lock()
        defer { lock.unlock() }

        guard var record = leasesByID[leaseID] else {
            return
        }
        let now = clock()
        record.revokedAt = now
        record.expiresAt = now
        leasesByID[leaseID] = record
        if activeLeaseID == leaseID {
            activeLeaseID = nil
        }
    }

    func activeLease() -> RemoteDesktopLease? {
        lock.lock()
        defer { lock.unlock() }

        purgeExpiredState()
        guard let activeLeaseID,
              let record = leasesByID[activeLeaseID],
              record.isActive else {
            return nil
        }
        do {
            try currentTrustValidator(record.lease.deviceId)
        } catch {
            invalidateLeaseLocked(leaseID: activeLeaseID)
            return nil
        }
        return record.lease
    }

    private static let nonceTTL: TimeInterval = 60
    private static let leaseTTL: TimeInterval = 10 * 60

    private static func randomToken() -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        return Data(bytes).base64EncodedString()
    }

    private func consume(proof: VerifiedRemoteDesktopNonce) throws {
        let now = clock()
        guard now <= proof.expiresAt else {
            throw RemoteDesktopSecurityError.nonceExpired
        }
        guard var record = noncesByValue[proof.nonce] else {
            throw RemoteDesktopSecurityError.nonceUnknown
        }
        guard record.deviceID == proof.deviceID else {
            throw RemoteDesktopSecurityError.nonceUnknown
        }
        guard proof.verifiedAt >= record.issuedAt else {
            throw RemoteDesktopSecurityError.nonceUnknown
        }
        guard now <= record.expiresAt else {
            throw RemoteDesktopSecurityError.nonceExpired
        }
        guard record.usedAt == nil else {
            throw RemoteDesktopSecurityError.nonceAlreadyUsed
        }
        record.usedAt = now
        noncesByValue[proof.nonce] = record
    }

    private func purgeExpiredState() {
        let now = clock()

        noncesByValue = noncesByValue.filter { $0.value.expiresAt > now }

        guard let activeLeaseID, let record = leasesByID[activeLeaseID] else {
            return
        }
        if record.isActive && record.expiresAt <= now {
            var expiredRecord = record
            expiredRecord.expiresAt = now
            expiredRecord.endedAt = now
            leasesByID[activeLeaseID] = expiredRecord
            self.activeLeaseID = nil
        }
    }

    private func invalidateActiveLeaseIfNeeded(for deviceID: String) {
        guard let activeLeaseID,
              let record = leasesByID[activeLeaseID],
              record.lease.deviceId == deviceID else {
            return
        }
        invalidateLeaseLocked(leaseID: activeLeaseID)
    }

    private func invalidateLeaseLocked(leaseID: String) {
        guard var record = leasesByID[leaseID] else {
            return
        }
        let now = clock()
        record.revokedAt = now
        record.endedAt = now
        record.expiresAt = now
        leasesByID[leaseID] = record
        if activeLeaseID == leaseID {
            activeLeaseID = nil
        }
    }
}
