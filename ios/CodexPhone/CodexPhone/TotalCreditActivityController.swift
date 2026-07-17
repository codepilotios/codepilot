import ActivityKit
import Foundation

enum LiveActivityPreference {
    static func resolvedEnabled(requested: Bool, activitiesEnabled: Bool) -> Bool {
        requested && activitiesEnabled
    }
}

enum CodePilotRoute: Equatable {
    case threadList

    init?(url: URL) {
        guard url.scheme == "codepilot", url.host == "threads" else { return nil }
        self = .threadList
    }
}

@MainActor
protocol CreditActivitySessionManaging: AnyObject {
    var activeActivityIDs: [String] { get }
    func configureRegistration(baseURL: String, token: String, environment: String)
    func start(state: TotalCreditActivityAttributes.ContentState) async throws
    func updateAll(state: TotalCreditActivityAttributes.ContentState) async
    func endAll() async
}

@MainActor
final class TotalCreditActivityController {
    private let sessions: CreditActivitySessionManaging

    init(sessions: CreditActivitySessionManaging) {
        self.sessions = sessions
    }

    convenience init() {
        self.init(sessions: ActivityKitCreditActivitySessions())
    }

    func reconcile(
        enabled: Bool,
        state: TotalCreditActivityAttributes.ContentState,
        baseURL: String = "",
        gatewayToken: String = "",
        environment: String = defaultLiveActivityAPNSEnvironment
    ) async throws {
        sessions.configureRegistration(baseURL: baseURL, token: gatewayToken, environment: environment)
        guard enabled else {
            await sessions.endAll()
            return
        }

        if sessions.activeActivityIDs.isEmpty {
            try await sessions.start(state: state)
        } else {
            await sessions.updateAll(state: state)
        }
    }
}

@MainActor
final class ActivityKitCreditActivitySessions: CreditActivitySessionManaging {
    private let registrar = LiveActivityGatewayRegistrar()
    private var registration = LiveActivityRegistrationContext(baseURL: "", token: "", environment: "production")
    private var observedActivityIDs = Set<String>()

    var activeActivityIDs: [String] {
        Activity<TotalCreditActivityAttributes>.activities.map(\.id)
    }

    func configureRegistration(baseURL: String, token: String, environment: String) {
        registration = LiveActivityRegistrationContext(
            baseURL: baseURL,
            token: token,
            environment: environment
        )
        for activity in Activity<TotalCreditActivityAttributes>.activities {
            observePushTokenUpdates(for: activity)
        }
    }

    func start(state: TotalCreditActivityAttributes.ContentState) async throws {
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(10 * 60))
        let activity = try Activity.request(
            attributes: TotalCreditActivityAttributes(identifier: UUID().uuidString),
            content: content,
            pushType: .token
        )
        observePushTokenUpdates(for: activity)
    }

    func updateAll(state: TotalCreditActivityAttributes.ContentState) async {
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(10 * 60))
        for activity in Activity<TotalCreditActivityAttributes>.activities {
            await activity.update(content)
        }
    }

    func endAll() async {
        for activity in Activity<TotalCreditActivityAttributes>.activities {
            try? await registrar.unregister(activityID: activity.id, context: registration)
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        observedActivityIDs.removeAll()
    }

    private func observePushTokenUpdates(for activity: Activity<TotalCreditActivityAttributes>) {
        guard observedActivityIDs.insert(activity.id).inserted else { return }
        let registrar = registrar
        let context = registration
        Task {
            for await tokenData in activity.pushTokenUpdates {
                let pushToken = tokenData.map { String(format: "%02x", $0) }.joined()
                try? await registrar.register(
                    activityID: activity.id,
                    pushToken: pushToken,
                    context: context
                )
            }
        }
    }
}

struct LiveActivityRegistrationContext {
    let baseURL: String
    let token: String
    let environment: String
}

private struct LiveActivityRegistrationRequest: Encodable {
    let activityId: String
    let pushToken: String
    let environment: String
    let bundleId: String
}

actor LiveActivityGatewayRegistrar {
    func register(
        activityID: String,
        pushToken: String,
        context: LiveActivityRegistrationContext
    ) async throws {
        guard let url = endpoint(path: "/api/live-activities", context: context) else { return }
        let payload = LiveActivityRegistrationRequest(
            activityId: activityID,
            pushToken: pushToken,
            environment: context.environment,
            bundleId: Bundle.main.bundleIdentifier ?? "io.codepilot.iOS"
        )
        var request = authorizedRequest(url: url, method: "POST", context: context)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)
        try await send(request)
    }

    func unregister(activityID: String, context: LiveActivityRegistrationContext) async throws {
        let encodedID = activityID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? activityID
        guard let url = endpoint(path: "/api/live-activities/\(encodedID)", context: context) else { return }
        try await send(authorizedRequest(url: url, method: "DELETE", context: context))
    }

    private func endpoint(path: String, context: LiveActivityRegistrationContext) -> URL? {
        guard !context.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let root = URL(string: context.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        return URL(string: path, relativeTo: root)?.absoluteURL
    }

    private func authorizedRequest(
        url: URL,
        method: String,
        context: LiveActivityRegistrationContext
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("Bearer \(context.token.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        return request
    }

    private func send(_ request: URLRequest) async throws {
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}

#if DEBUG
let defaultLiveActivityAPNSEnvironment = "development"
#else
let defaultLiveActivityAPNSEnvironment = "production"
#endif
