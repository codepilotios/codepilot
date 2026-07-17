import Foundation
import Security
import SwiftUI

enum SecureGatewayTokenStore {
    private static let service = "io.codepilot.gateway"
    private static let account = "gatewayToken"
    private static let legacyDefaultsKey = "gatewayToken"

    static func read() -> String {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return ""
        }
        return token
    }

    @discardableResult
    static func save(_ rawToken: String) -> Bool {
        let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if token.isEmpty {
            let status = SecItemDelete(baseQuery() as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                return false
            }
            UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)
            return true
        }

        let data = Data(token.utf8)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        var status = SecItemUpdate(baseQuery() as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var query = baseQuery()
            query.merge(attributes) { _, newValue in newValue }
            status = SecItemAdd(query as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            return false
        }
        UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)
        return true
    }

    @discardableResult
    static func migrateLegacyTokenIfNeeded() -> String {
        let current = read()
        let legacy = UserDefaults.standard.string(forKey: legacyDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if current.isEmpty, !legacy.isEmpty {
            return save(legacy) ? legacy : ""
        }
        if !current.isEmpty {
            UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)
        }
        return current
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

@MainActor
final class GatewayCredentials: ObservableObject {
    @Published var gatewayURL: String {
        didSet {
            UserDefaults.standard.set(gatewayURL, forKey: "gatewayURL")
        }
    }

    @Published private(set) var gatewayToken: String

    init() {
        gatewayURL = UserDefaults.standard.string(forKey: "gatewayURL") ?? ""
        gatewayToken = SecureGatewayTokenStore.migrateLegacyTokenIfNeeded()
    }

    func updateGatewayToken(_ token: String) {
        let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if SecureGatewayTokenStore.save(normalized) {
            gatewayToken = normalized
        }
    }
}
