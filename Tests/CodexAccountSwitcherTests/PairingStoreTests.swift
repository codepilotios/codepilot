import CryptoKit
import Foundation
import XCTest
@testable import CodexAccountSwitcher

final class PairingStoreTests: XCTestCase {
    func testChallengeCanBeUsedOnceAndExpiresAfterTwoMinutes() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let store = try makeStore(clock: { now })
        let privateKey = P256.Signing.PrivateKey()

        let challenge = store.issueChallenge(
            deviceID: "device-1",
            name: "Test iPhone",
            publicKeyRawRepresentation: privateKey.publicKey.rawRepresentation,
            macName: "Studio Mac"
        )
        let token = try store.verifyChallenge(
            challenge,
            deviceID: "device-1",
            signature: try privateKey.signature(for: Data(challenge.code.utf8)).derRepresentation
        )
        _ = try store.approveDevice(using: token)

        XCTAssertThrowsError(try store.approveDevice(using: token)) { error in
            XCTAssertEqual(error as? RemoteDesktopSecurityError, .challengeAlreadyUsed)
        }

        _ = try store.revokeDevice(id: "device-1")
        XCTAssertThrowsError(try store.approveDevice(using: token)) { error in
            XCTAssertEqual(error as? RemoteDesktopSecurityError, .challengeAlreadyUsed)
        }

        var expiredNow = Date(timeIntervalSince1970: 1_700_000_000)
        let expiredStore = try makeStore(clock: { expiredNow })
        let expiredChallenge = expiredStore.issueChallenge(
            deviceID: "device-1",
            name: "Test iPhone",
            publicKeyRawRepresentation: privateKey.publicKey.rawRepresentation,
            macName: "Studio Mac"
        )
        expiredNow = expiredNow.addingTimeInterval(121)
        XCTAssertThrowsError(
            try expiredStore.verifyChallenge(
                expiredChallenge,
                deviceID: "device-1",
                signature: try privateKey.signature(for: Data(expiredChallenge.code.utf8)).derRepresentation
            )
        ) { error in
            XCTAssertEqual(error as? RemoteDesktopSecurityError, .challengeExpired)
        }
    }

    func testNonceVerificationIsSingleUseAndPersistsOnlyAfterSuccess() throws {
        let store = try makeStore()
        let privateKey = P256.Signing.PrivateKey()
        let challenge = store.issueChallenge(
            deviceID: "device-1",
            name: "Test iPhone",
            publicKeyRawRepresentation: privateKey.publicKey.rawRepresentation,
            macName: "Studio Mac"
        )
        let token = try store.verifyChallenge(
            challenge,
            deviceID: "device-1",
            signature: try privateKey.signature(for: Data(challenge.code.utf8)).derRepresentation
        )
        _ = try store.approveDevice(using: token)

        let nonce = "nonce-1"
        let proof = try store.verifyNonce(
            deviceID: "device-1",
            nonce: nonce,
            signature: try privateKey.signature(for: Data(nonce.utf8)).derRepresentation
        )

        XCTAssertThrowsError(
            try store.verifyNonce(
                deviceID: "device-1",
                nonce: nonce,
                signature: try privateKey.signature(for: Data(nonce.utf8)).derRepresentation
            )
        ) { error in
            XCTAssertEqual(error as? RemoteDesktopSecurityError, .nonceAlreadyUsed)
        }

        XCTAssertEqual(proof.nonce, nonce)
    }

    func testVerifySignatureRejectsInvalidSignature() throws {
        let store = try makeStore()
        let privateKey = P256.Signing.PrivateKey()
        let wrongPrivateKey = P256.Signing.PrivateKey()
        let challenge = store.issueChallenge(
            deviceID: "device-1",
            name: "Test iPhone",
            publicKeyRawRepresentation: privateKey.publicKey.rawRepresentation,
            macName: "Studio Mac"
        )
        let token = try store.verifyChallenge(
            challenge,
            deviceID: "device-1",
            signature: try privateKey.signature(for: Data(challenge.code.utf8)).derRepresentation
        )
        _ = try store.approveDevice(using: token)

        XCTAssertThrowsError(
            try store.verify(
                signature: try wrongPrivateKey.signature(for: Data("message".utf8)).derRepresentation,
                message: Data("message".utf8),
                deviceID: "device-1"
            )
        ) { error in
            XCTAssertEqual(error as? RemoteDesktopSecurityError, .invalidSignature)
        }
    }

    func testVerifySignatureRejectsRevokedDevice() throws {
        let store = try makeStore()
        let privateKey = P256.Signing.PrivateKey()
        let challenge = store.issueChallenge(
            deviceID: "device-1",
            name: "Test iPhone",
            publicKeyRawRepresentation: privateKey.publicKey.rawRepresentation,
            macName: "Studio Mac"
        )
        let token = try store.verifyChallenge(
            challenge,
            deviceID: "device-1",
            signature: try privateKey.signature(for: Data(challenge.code.utf8)).derRepresentation
        )
        _ = try store.approveDevice(using: token)
        _ = try store.revokeDevice(id: "device-1")

        XCTAssertThrowsError(
            try store.verify(
                signature: try privateKey.signature(for: Data("message".utf8)).derRepresentation,
                message: Data("message".utf8),
                deviceID: "device-1"
            )
        ) { error in
            XCTAssertEqual(error as? RemoteDesktopSecurityError, .deviceRevoked)
        }
    }

    func testReplayedApprovalTokenDoesNotReapproveAfterRevocation() throws {
        let store = try makeStore()
        let privateKey = P256.Signing.PrivateKey()
        let challenge = store.issueChallenge(
            deviceID: "device-1",
            name: "Test iPhone",
            publicKeyRawRepresentation: privateKey.publicKey.rawRepresentation,
            macName: "Studio Mac"
        )
        let token = try store.verifyChallenge(
            challenge,
            deviceID: "device-1",
            signature: try privateKey.signature(for: Data(challenge.code.utf8)).derRepresentation
        )
        _ = try store.approveDevice(using: token)
        _ = try store.revokeDevice(id: "device-1")

        XCTAssertThrowsError(try store.approveDevice(using: token)) { error in
            XCTAssertEqual(error as? RemoteDesktopSecurityError, .challengeAlreadyUsed)
        }
        XCTAssertNotNil(store.trustedDevice(id: "device-1")?.revokedAt)
    }

    func testApprovalDoesNotMutateInMemoryStateWhenPersistenceFails() throws {
        let store = try makeFailingPersistenceStore()
        let privateKey = P256.Signing.PrivateKey()
        let challenge = store.issueChallenge(
            deviceID: "device-1",
            name: "Test iPhone",
            publicKeyRawRepresentation: privateKey.publicKey.rawRepresentation,
            macName: "Studio Mac"
        )
        let token = try store.verifyChallenge(
            challenge,
            deviceID: "device-1",
            signature: try privateKey.signature(for: Data(challenge.code.utf8)).derRepresentation
        )

        XCTAssertThrowsError(try store.approveDevice(using: token))
        XCTAssertNil(store.trustedDevice(id: "device-1"))
    }

    private func makeStore(clock: @escaping PairingStore.Clock = Date.init) throws -> PairingStore {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("trusted-devices.json")
        addTeardownBlock {
            try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
        }
        return try PairingStore(fileURL: fileURL, clock: clock)
    }

    private func makeFailingPersistenceStore() throws -> PairingStore {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("trusted-devices.json")
        addTeardownBlock {
            try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
        }
        return try PairingStore(
            fileURL: fileURL,
            clock: Date.init,
            persistTrustedDevices: { _ in throw NSError(domain: "PairingStoreTests", code: 1) }
        )
    }
}
