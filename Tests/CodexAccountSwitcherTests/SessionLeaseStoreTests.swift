import CryptoKit
import Foundation
import XCTest
@testable import CodexAccountSwitcher

final class SessionLeaseStoreTests: XCTestCase {
    func testNonceProofCannotBeReplayedToCreateOrRenewLeases() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let pairingStore = try makeTrustedPairingStore(clock: { now })
        let leaseStore = makeLeaseStore(clock: { now }, pairingStore: pairingStore)
        let privateKey = try trustedPrivateKey(using: pairingStore)

        let nonce = leaseStore.issueNonce(for: "device-1")
        let proof = try verifiedNonce(
            pairingStore: pairingStore,
            privateKey: privateKey,
            deviceID: "device-1",
            nonce: nonce
        )

        let lease = try leaseStore.createLease(using: proof)
        XCTAssertEqual(lease.deviceId, "device-1")

        XCTAssertThrowsError(try leaseStore.renewLease(leaseID: lease.id, using: proof)) { error in
            XCTAssertEqual(error as? RemoteDesktopSecurityError, .nonceAlreadyUsed)
        }

        leaseStore.endLease(leaseID: lease.id)
        XCTAssertThrowsError(try leaseStore.createLease(using: proof)) { error in
            XCTAssertEqual(error as? RemoteDesktopSecurityError, .nonceAlreadyUsed)
        }
    }

    func testOnlyOneControllerCanHoldLeaseAtATime() throws {
        let pairingStore = try makeTrustedPairingStore(clock: Date.init)
        let leaseStore = makeLeaseStore(clock: Date.init, pairingStore: pairingStore)
        let privateKey = try trustedPrivateKey(using: pairingStore)

        let firstNonce = leaseStore.issueNonce(for: "device-1")
        let firstProof = try verifiedNonce(
            pairingStore: pairingStore,
            privateKey: privateKey,
            deviceID: "device-1",
            nonce: firstNonce
        )
        _ = try leaseStore.createLease(using: firstProof)

        let secondNonce = leaseStore.issueNonce(for: "device-1")
        let secondProof = try verifiedNonce(
            pairingStore: pairingStore,
            privateKey: privateKey,
            deviceID: "device-1",
            nonce: secondNonce
        )

        XCTAssertThrowsError(try leaseStore.createLease(using: secondProof)) { error in
            XCTAssertEqual(error as? RemoteDesktopSecurityError, .controllerBusy)
        }
    }

    func testLeaseExpiresAfterTenMinutes() throws {
        var now = Date(timeIntervalSince1970: 2_000_000_000)
        let pairingStore = try makeTrustedPairingStore(clock: { now })
        let leaseStore = makeLeaseStore(clock: { now }, pairingStore: pairingStore)
        let privateKey = try trustedPrivateKey(using: pairingStore)

        let nonce = leaseStore.issueNonce(for: "device-1")
        let proof = try verifiedNonce(
            pairingStore: pairingStore,
            privateKey: privateKey,
            deviceID: "device-1",
            nonce: nonce
        )
        let lease = try leaseStore.createLease(using: proof)

        now = now.addingTimeInterval(601)
        XCTAssertNil(leaseStore.activeLease())

        XCTAssertThrowsError(try leaseStore.validateSequence(1, for: lease.id)) { error in
            XCTAssertEqual(error as? RemoteDesktopSecurityError, .leaseExpired)
        }
    }

    func testSequenceReplayIsRejected() throws {
        let pairingStore = try makeTrustedPairingStore(clock: Date.init)
        let leaseStore = makeLeaseStore(clock: Date.init, pairingStore: pairingStore)
        let privateKey = try trustedPrivateKey(using: pairingStore)

        let nonce = leaseStore.issueNonce(for: "device-1")
        let proof = try verifiedNonce(
            pairingStore: pairingStore,
            privateKey: privateKey,
            deviceID: "device-1",
            nonce: nonce
        )
        let lease = try leaseStore.createLease(using: proof)

        try leaseStore.validateSequence(1, for: lease.id)

        XCTAssertThrowsError(try leaseStore.validateSequence(1, for: lease.id)) { error in
            XCTAssertEqual(error as? RemoteDesktopSecurityError, .sequenceReplay)
        }
    }

    func testFreshProofCanRenewLeaseButWrongStaleAndRevokedProofsCannot() throws {
        var now = Date(timeIntervalSince1970: 2_000_000_000)
        let pairingStore = try makeTrustedPairingStore(clock: { now })
        let leaseStore = makeLeaseStore(clock: { now }, pairingStore: pairingStore)
        let privateKey = try trustedPrivateKey(using: pairingStore)

        let startNonce = leaseStore.issueNonce(for: "device-1")
        let startProof = try verifiedNonce(
            pairingStore: pairingStore,
            privateKey: privateKey,
            deviceID: "device-1",
            nonce: startNonce
        )
        let lease = try leaseStore.createLease(using: startProof)

        let wrongNonce = "nonce-wrong"
        let wrongProof = try pairingStore.verifyNonce(
            deviceID: "device-1",
            nonce: wrongNonce,
            signature: try privateKey.signature(for: Data(wrongNonce.utf8)).derRepresentation
        )

        XCTAssertThrowsError(try leaseStore.renewLease(leaseID: lease.id, using: wrongProof)) { error in
            XCTAssertEqual(error as? RemoteDesktopSecurityError, .nonceUnknown)
        }

        let renewalNonce = leaseStore.issueNonce(for: "device-1")
        let renewalProof = try verifiedNonce(
            pairingStore: pairingStore,
            privateKey: privateKey,
            deviceID: "device-1",
            nonce: renewalNonce
        )
        now = now.addingTimeInterval(1)
        let renewed = try leaseStore.renewLease(leaseID: lease.id, using: renewalProof)
        XCTAssertGreaterThan(renewed.expiresAt, lease.expiresAt)

        let staleNonce = leaseStore.issueNonce(for: "device-1")
        let staleProof = try verifiedNonce(
            pairingStore: pairingStore,
            privateKey: privateKey,
            deviceID: "device-1",
            nonce: staleNonce
        )
        now = now.addingTimeInterval(61)
        XCTAssertThrowsError(try leaseStore.createLease(using: staleProof)) { error in
            XCTAssertEqual(error as? RemoteDesktopSecurityError, .nonceExpired)
        }

        let revokedNonce = leaseStore.issueNonce(for: "device-1")
        let revokedProof = try verifiedNonce(
            pairingStore: pairingStore,
            privateKey: privateKey,
            deviceID: "device-1",
            nonce: revokedNonce
        )
        _ = try pairingStore.revokeDevice(id: "device-1")

        XCTAssertThrowsError(try leaseStore.createLease(using: revokedProof)) { error in
            XCTAssertEqual(error as? RemoteDesktopSecurityError, .deviceRevoked)
        }
        XCTAssertThrowsError(try leaseStore.renewLease(leaseID: lease.id, using: revokedProof)) { error in
            XCTAssertEqual(error as? RemoteDesktopSecurityError, .deviceRevoked)
        }
    }

    func testValidateSequenceFailsAfterRevocationEvenForActiveLease() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let pairingStore = try makeTrustedPairingStore(clock: { now })
        let leaseStore = makeLeaseStore(clock: { now }, pairingStore: pairingStore)
        let privateKey = try trustedPrivateKey(using: pairingStore, deviceID: "device-1")

        let nonce = leaseStore.issueNonce(for: "device-1")
        let proof = try verifiedNonce(
            pairingStore: pairingStore,
            privateKey: privateKey,
            deviceID: "device-1",
            nonce: nonce
        )
        let lease = try leaseStore.createLease(using: proof)

        _ = try pairingStore.revokeDevice(id: "device-1")

        XCTAssertThrowsError(try leaseStore.validateSequence(1, for: lease.id)) { error in
            XCTAssertEqual(error as? RemoteDesktopSecurityError, .deviceRevoked)
        }
    }

    func testRevokedLeaseIsFreedForReplacementController() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let pairingStore = try makeTrustedPairingStore(clock: { now })
        let leaseStore = makeLeaseStore(clock: { now }, pairingStore: pairingStore)
        let firstPrivateKey = try trustedPrivateKey(using: pairingStore, deviceID: "device-1")
        let secondPrivateKey = try trustedPrivateKey(using: pairingStore, deviceID: "device-2")

        let firstNonce = leaseStore.issueNonce(for: "device-1")
        let firstProof = try verifiedNonce(
            pairingStore: pairingStore,
            privateKey: firstPrivateKey,
            deviceID: "device-1",
            nonce: firstNonce
        )
        let firstLease = try leaseStore.createLease(using: firstProof)
        _ = try pairingStore.revokeDevice(id: "device-1")

        XCTAssertNil(leaseStore.activeLease())
        XCTAssertThrowsError(try leaseStore.validateSequence(1, for: firstLease.id)) { error in
            XCTAssertEqual(error as? RemoteDesktopSecurityError, .deviceRevoked)
        }

        let secondNonce = leaseStore.issueNonce(for: "device-2")
        let secondProof = try verifiedNonce(
            pairingStore: pairingStore,
            privateKey: secondPrivateKey,
            deviceID: "device-2",
            nonce: secondNonce
        )
        let secondLease = try leaseStore.createLease(using: secondProof)
        XCTAssertEqual(secondLease.deviceId, "device-2")
    }

    private func makeTrustedPairingStore(clock: @escaping PairingStore.Clock) throws -> PairingStore {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("trusted-devices.json")
        addTeardownBlock {
            try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
        }
        return try PairingStore(fileURL: fileURL, clock: clock)
    }

    private func makeLeaseStore(
        clock: @escaping SessionLeaseStore.Clock,
        pairingStore: PairingStore
    ) -> SessionLeaseStore {
        SessionLeaseStore(clock: clock, currentTrustValidator: { deviceID in
            guard let device = pairingStore.trustedDevice(id: deviceID) else {
                throw RemoteDesktopSecurityError.untrustedDevice
            }
            guard device.revokedAt == nil else {
                throw RemoteDesktopSecurityError.deviceRevoked
            }
        })
    }

    private func trustedPrivateKey(
        using store: PairingStore,
        deviceID: String = "device-1"
    ) throws -> P256.Signing.PrivateKey {
        let privateKey = P256.Signing.PrivateKey()
        let challenge = store.issueChallenge(
            deviceID: deviceID,
            name: deviceID,
            publicKeyRawRepresentation: privateKey.publicKey.rawRepresentation,
            macName: "Studio Mac"
        )
        let token = try store.verifyChallenge(
            challenge,
            deviceID: deviceID,
            signature: try privateKey.signature(for: Data(challenge.code.utf8)).derRepresentation
        )
        _ = try store.approveDevice(using: token)
        return privateKey
    }

    private func verifiedNonce(
        pairingStore: PairingStore,
        privateKey: P256.Signing.PrivateKey,
        deviceID: String,
        nonce: String
    ) throws -> VerifiedRemoteDesktopNonce {
        try pairingStore.verifyNonce(
            deviceID: deviceID,
            nonce: nonce,
            signature: try privateKey.signature(for: Data(nonce.utf8)).derRepresentation
        )
    }
}
