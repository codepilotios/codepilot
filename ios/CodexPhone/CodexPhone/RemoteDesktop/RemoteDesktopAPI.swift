import Foundation

enum RemoteDesktopAPIError: Error, Equatable {
    case invalidURL
    case invalidResponse
    case server(status: Int, code: String)
}

struct RemoteDesktopAPI {
    typealias Transport = (URLRequest) async throws -> (Data, HTTPURLResponse)

    let baseURL: URL
    let token: String
    let transport: Transport

    init(
        baseURL: URL,
        token: String,
        transport: @escaping Transport = RemoteDesktopAPI.defaultTransport
    ) {
        self.baseURL = baseURL
        self.token = token
        self.transport = transport
    }

    func startPairing(deviceID: String, name: String, publicKey: Data) async throws -> RemotePairingChallenge {
        try await request(
            "POST",
            path: "/api/remote/pairing/start",
            body: [
                "deviceId": deviceID,
                "name": name,
                "publicKey": publicKey.base64EncodedString()
            ]
        )
    }

    func completePairing(challengeID: String, deviceID: String, signature: Data) async throws -> RemotePairingApprovalStatus {
        try await request(
            "POST",
            path: "/api/remote/pairing/complete",
            body: [
                "challengeId": challengeID,
                "deviceId": deviceID,
                "signature": signature.base64EncodedString()
            ]
        )
    }

    func startSession(deviceID: String, nonce: String, signature: Data) async throws -> RemoteDesktopLease {
        try await request(
            "POST",
            path: "/api/remote/sessions",
            body: [
                "deviceId": deviceID,
                "nonce": nonce,
                "signature": signature.base64EncodedString()
            ]
        )
    }

    func status() async throws -> RemoteDesktopHostStatus {
        try await request("GET", path: "/api/remote/status", body: nil)
    }

    func sendSignal(
        sessionID: String,
        sequence: UInt64,
        kind: RemotePeerSignal.Kind,
        payload: Data
    ) async throws -> [RemotePeerSignal] {
        let response: RemoteSignalAcknowledgement = try await request(
            "POST",
            path: "/api/remote/sessions/\(sessionID)/signal",
            body: [
                "sequence": sequence,
                "kind": kind.rawValue,
                "payload": payload.base64EncodedString()
            ]
        )
        return response.signals ?? []
    }

    func frame() async throws -> Data {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw RemoteDesktopAPIError.invalidURL
        }
        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + ([basePath, "api", "remote", "frame"].filter { !$0.isEmpty }.joined(separator: "/"))
        components.queryItems = [URLQueryItem(name: "t", value: String(Date().timeIntervalSince1970))]
        guard let url = components.url else {
            throw RemoteDesktopAPIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 5
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("image/jpeg", forHTTPHeaderField: "Accept")

        let (data, response) = try await transport(request)
        guard (200..<300).contains(response.statusCode) else {
            let code = (try? JSONDecoder().decode(RemoteDesktopAPIErrorResponse.self, from: data).error) ?? "remote_desktop_error"
            throw RemoteDesktopAPIError.server(status: response.statusCode, code: code)
        }
        return data
    }

    func sendInput(_ event: RemoteInputEvent) async throws -> RemoteInputAcknowledgement {
        guard let url = URL(string: "/api/remote/input", relativeTo: baseURL)?.absoluteURL else {
            throw RemoteDesktopAPIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 5
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(event)
        let (data, response) = try await transport(request)
        guard (200..<300).contains(response.statusCode) else {
            let code = (try? JSONDecoder().decode(RemoteDesktopAPIErrorResponse.self, from: data).error) ?? "remote_desktop_error"
            throw RemoteDesktopAPIError.server(status: response.statusCode, code: code)
        }
        return try JSONDecoder().decode(RemoteInputAcknowledgement.self, from: data)
    }

    private func request<T: Decodable>(_ method: String, path: String, body: [String: Any]?) async throws -> T {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw RemoteDesktopAPIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await transport(request)
        guard (200..<300).contains(response.statusCode) else {
            let code = (try? JSONDecoder().decode(RemoteDesktopAPIErrorResponse.self, from: data).error) ?? "remote_desktop_error"
            throw RemoteDesktopAPIError.server(status: response.statusCode, code: code)
        }
        do {
            return try JSONDecoder.remoteDesktop.decode(T.self, from: data)
        } catch {
            throw RemoteDesktopAPIError.invalidResponse
        }
    }

    private static func defaultTransport(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await GatewayURLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw RemoteDesktopAPIError.invalidResponse
        }
        return (data, http)
    }
}

struct RemoteInputAcknowledgement: Decodable, Equatable {
    struct Cursor: Decodable, Equatable {
        let x: Double
        let y: Double
    }

    let ok: Bool
    let cursor: Cursor?
}

struct RemotePeerSignal: Codable, Equatable {
    enum Kind: String, Codable {
        case offer
        case answer
        case ice
    }

    let leaseID: String
    let sequence: UInt64
    let kind: Kind
    let payload: Data
}

private struct RemoteSignalAcknowledgement: Decodable {
    let sequence: UInt64
    let signals: [RemotePeerSignal]?
}

struct RemoteDesktopHostStatus: Codable, Equatable {
    let ok: Bool?
    let screenRecordingGranted: Bool?
    let accessibilityGranted: Bool?
    let macUnlocked: Bool?
    let trustedDeviceCount: Int?
    let displayFrame: RemoteDisplayFrame?
    let cursor: RemoteCursorPosition?
    let iceServers: [RemoteIceServer]?
    let capabilities: RemoteDesktopCapabilities?
}

struct RemoteDisplayFrame: Codable, Equatable {
    let width: Double
    let height: Double
}

struct RemoteCursorPosition: Codable, Equatable {
    let x: Double
    let y: Double
}

struct RemoteDesktopCapabilities: Codable, Equatable {
    let relayAvailable: Bool?
}

struct RemoteIceServer: Codable, Equatable {
    let urls: [String]
    let username: String?
    let credential: String?
}

private struct RemoteDesktopAPIErrorResponse: Decodable {
    let error: String
}

private extension JSONDecoder {
    static var remoteDesktop: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.dataDecodingStrategy = .base64
        return decoder
    }
}
