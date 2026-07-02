import CryptoKit
import Foundation
import LocalAuthentication
import Security
import UIKit

protocol RemoteDeviceIdentity {
    var deviceID: String { get }
    var publicKeyRawRepresentation: Data { get }
    func sign(_ message: Data) throws -> Data
}

struct SoftwareRemoteDeviceIdentity: RemoteDeviceIdentity {
    let deviceID: String
    private let privateKey: P256.Signing.PrivateKey

    init(deviceID: String, privateKey: P256.Signing.PrivateKey = P256.Signing.PrivateKey()) {
        self.deviceID = deviceID
        self.privateKey = privateKey
    }

    var publicKeyRawRepresentation: Data {
        privateKey.publicKey.rawRepresentation
    }

    func sign(_ message: Data) throws -> Data {
        try privateKey.signature(for: message).derRepresentation
    }

    func verify(signature: Data, message: Data) throws -> Bool {
        let parsed = try P256.Signing.ECDSASignature(derRepresentation: signature)
        return privateKey.publicKey.isValidSignature(parsed, for: message)
    }
}

final class SecureEnclaveRemoteDeviceIdentity: RemoteDeviceIdentity {
    let deviceID: String
    private let privateKey: SecureEnclave.P256.Signing.PrivateKey

    init(deviceID: String = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString) throws {
        guard SecureEnclave.isAvailable else {
            throw RemoteDeviceIdentityError.secureEnclaveUnavailable
        }
        let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            [.privateKeyUsage, .userPresence],
            nil
        )
        guard let access else {
            throw RemoteDeviceIdentityError.secureEnclaveUnavailable
        }
        self.deviceID = deviceID
        self.privateKey = try SecureEnclave.P256.Signing.PrivateKey(accessControl: access)
    }

    var publicKeyRawRepresentation: Data {
        privateKey.publicKey.rawRepresentation
    }

    func sign(_ message: Data) throws -> Data {
        try privateKey.signature(for: message).derRepresentation
    }
}

enum RemoteDeviceIdentityError: Error, Equatable {
    case secureEnclaveUnavailable
    case authenticationCancelled
}
