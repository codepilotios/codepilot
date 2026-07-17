import Foundation
import Security
import SwiftUI

enum GatewayEndpoint {
    static func baseURL(from rawValue: String) -> URL? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              var components = URLComponents(string: value),
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(),
              !host.isEmpty,
              scheme == "https" || (scheme == "http" && isLoopbackHost(host)) else {
            return nil
        }

        components.scheme = scheme
        components.host = host
        return components.url
    }

    static func hasSameOrigin(_ first: URL?, _ second: URL?) -> Bool {
        guard let first,
              let second,
              let firstComponents = URLComponents(url: first, resolvingAgainstBaseURL: false),
              let secondComponents = URLComponents(url: second, resolvingAgainstBaseURL: false),
              let firstScheme = firstComponents.scheme?.lowercased(),
              let secondScheme = secondComponents.scheme?.lowercased(),
              let firstHost = firstComponents.host?.lowercased(),
              let secondHost = secondComponents.host?.lowercased() else {
            return false
        }
        return firstScheme == secondScheme
            && firstHost == secondHost
            && effectivePort(firstComponents) == effectivePort(secondComponents)
    }

    private static func effectivePort(_ components: URLComponents) -> Int? {
        if let port = components.port {
            return port
        }
        switch components.scheme?.lowercased() {
        case "http": return 80
        case "https": return 443
        default: return nil
        }
    }

    private static func isLoopbackHost(_ host: String) -> Bool {
        host == "localhost" || host == "::1" || host.hasPrefix("127.")
    }
}

private final class GatewayRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard GatewayEndpoint.hasSameOrigin(task.currentRequest?.url, request.url) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

enum GatewayURLSession {
    static let shared: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration, delegate: GatewayRedirectDelegate(), delegateQueue: nil)
    }()
}

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
