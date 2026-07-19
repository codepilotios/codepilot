import ActivityKit
import AuthenticationServices
import Foundation
import Network
import PhotosUI
import QuickLook
import SafariServices
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import UserNotifications
import WebKit

@main
struct CodexPhoneApp: App {
    @UIApplicationDelegateAdaptor(CodexPhoneAppDelegate.self) private var appDelegate

    init() {
        applyLaunchConfiguration()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }

    private func applyLaunchConfiguration() {
        let arguments = ProcessInfo.processInfo.arguments
        for index in arguments.indices {
            switch arguments[index] {
            case "--gateway-url" where arguments.indices.contains(index + 1):
                UserDefaults.standard.set(arguments[index + 1], forKey: "gatewayURL")
            case "--gateway-token" where arguments.indices.contains(index + 1):
                UserDefaults.standard.set(arguments[index + 1], forKey: "gatewayToken")
            default:
                break
            }
        }
    }
}

final class CodexPhoneAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        sendDeviceTokenToGateway(deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        UserDefaults.standard.set(error.localizedDescription, forKey: "lastRemoteNotificationRegistrationError")
    }

    private func sendDeviceTokenToGateway(_ deviceToken: Data) {
        let gatewayURL = UserDefaults.standard.string(forKey: "gatewayURL") ?? ""
        let gatewayToken = UserDefaults.standard.string(forKey: "gatewayToken") ?? ""
        guard !gatewayToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let root = GatewayEndpoint.baseURL(from: gatewayURL),
              let url = URL(string: "/api/notifications/device", relativeTo: root)?.absoluteURL else {
            return
        }

        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        let environment = apnsEnvironment()
        let body = NotificationDeviceRegistrationRequest(
            token: token,
            environment: environment,
            bundleId: Bundle.main.bundleIdentifier ?? "io.codepilot.iOS",
            platform: "ios"
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(gatewayToken.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(body)
        GatewayURLSession.shared.dataTask(with: request).resume()
    }

    private func apnsEnvironment() -> String {
        if let environment = Bundle.main.object(forInfoDictionaryKey: "CodexPhoneAPNSEnvironment") as? String,
           environment == "development" || environment == "production" {
            return environment
        }
        #if DEBUG
        return "development"
        #else
        return "production"
        #endif
    }
}

struct RootView: View {
    @StateObject private var model = CodexPhoneModel()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("gatewayURL") private var gatewayURL = ""
    @AppStorage("gatewayToken") private var gatewayToken = ""
    @AppStorage("totalCreditLiveActivityEnabled") private var totalCreditLiveActivityEnabled = false
    @State private var showingSettings = false
    @State private var showingStatus = false
    @State private var showingNewThread = false
    @State private var showingAccountSwitcher = false
    @State private var showingRemoteDesktop = false
    @State private var openedThread: CodexThread?
    @State private var liveActivityError = ""

    var body: some View {
        NavigationStack {
            Group {
                if gatewayToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    EmptySettingsView(gatewayURL: $gatewayURL, gatewayToken: $gatewayToken)
                } else if model.threads.isEmpty && model.isLoading {
                    ProgressView("Loading")
                } else {
                    ThreadListView(model: model) {
                        showingRemoteDesktop = true
                    }
                }
            }
            .navigationTitle("CodePilot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingAccountSwitcher = true
                    } label: {
                        Label {
                            Text(model.activeAccount.isEmpty ? "Account" : model.activeAccount)
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                        } icon: {
                            Image(systemName: "person.crop.circle")
                        }
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Switch OpenAI Account")
                    .disabled(gatewayToken.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingNewThread = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("New Thread")
                    .disabled(gatewayToken.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingRemoteDesktop = true
                    } label: {
                        Image(systemName: "desktopcomputer")
                    }
                    .accessibilityLabel("Remote Desktop")
                    .disabled(gatewayToken.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingStatus = true
                    } label: {
                        Image(systemName: "chart.bar.xaxis")
                    }
                    .accessibilityLabel("Usage Status")
                    .disabled(gatewayToken.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await model.loadThreads(baseURL: gatewayURL, token: gatewayToken) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh")
                    .disabled(gatewayToken.isEmpty)
                }
            }
            .refreshable {
                await model.loadThreads(baseURL: gatewayURL, token: gatewayToken)
            }
            .task {
                await model.loadThreads(baseURL: gatewayURL, token: gatewayToken)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(
                    gatewayURL: $gatewayURL,
                    gatewayToken: $gatewayToken,
                    model: model,
                    liveActivityError: $liveActivityError
                )
                    .presentationDetents([.large])
            }
            .sheet(isPresented: $showingStatus) {
                AccountStatusView(model: model, gatewayURL: gatewayURL, gatewayToken: gatewayToken)
            }
            .fullScreenCover(isPresented: $showingRemoteDesktop) {
                RemotePairingView(gatewayURL: gatewayURL, gatewayToken: gatewayToken)
            }
            .sheet(isPresented: $showingAccountSwitcher) {
                AccountSwitcherView(model: model, gatewayURL: gatewayURL, gatewayToken: gatewayToken)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showingNewThread) {
                NewThreadView(
                    model: model,
                    gatewayURL: gatewayURL,
                    gatewayToken: gatewayToken
                ) { thread in
                    openedThread = thread
                    showingNewThread = false
                }
                .presentationDetents([.medium, .large])
            }
            .navigationDestination(item: $openedThread) { thread in
                ChatView(model: model, thread: thread)
            }
            .alert("CodePilot", isPresented: .constant(model.errorMessage != nil)) {
                Button("OK") { model.errorMessage = nil }
            } message: {
                Text(model.errorMessage ?? "")
            }
            .task(id: gatewayToken) {
                await model.pollAccountStatus(baseURL: gatewayURL, token: gatewayToken)
            }
            .task(id: liveActivityReconciliationID) {
                guard scenePhase == .active else { return }
                await reconcileLiveActivity()
            }
            .onOpenURL { url in
                guard CodePilotRoute(url: url) == .threadList else { return }
                openedThread = nil
                showingSettings = false
                showingStatus = false
                showingNewThread = false
                showingAccountSwitcher = false
                showingRemoteDesktop = false
            }
        }
    }

    private var gatewayURL: String {
        credentials.gatewayURL
    }

    private var gatewayToken: String {
        credentials.gatewayToken
    }

    private var gatewayURLBinding: Binding<String> {
        Binding(
            get: { credentials.gatewayURL },
            set: { credentials.gatewayURL = $0 }
        )
    }

    private var gatewayTokenBinding: Binding<String> {
        Binding(
            get: { credentials.gatewayToken },
            set: { credentials.updateGatewayToken($0) }
        )
    }

    private var liveActivityReconciliationID: String {
        "\(totalCreditLiveActivityEnabled)-\(model.accountStatusGeneratedAt ?? 0)-\(scenePhase == .active)"
    }

    @MainActor
    private func reconcileLiveActivity() async {
        let systemEnabled = ActivityAuthorizationInfo().areActivitiesEnabled
        let shouldEnable = LiveActivityPreference.resolvedEnabled(
            requested: totalCreditLiveActivityEnabled,
            activitiesEnabled: systemEnabled
        )
        if totalCreditLiveActivityEnabled && !shouldEnable {
            totalCreditLiveActivityEnabled = false
            liveActivityError = "Live Activities are disabled in iOS Settings. Enable them for CodePilot, then try again."
        }

        let state = TotalCreditStatus(accounts: model.accountStatuses, now: .now).activityState
        do {
            try await TotalCreditActivityController().reconcile(
                enabled: shouldEnable,
                state: state,
                baseURL: gatewayURL,
                gatewayToken: gatewayToken
            )
            if shouldEnable {
                liveActivityError = ""
            }
        } catch {
            liveActivityError = "The credit Live Activity could not be updated: \(error.localizedDescription)"
        }
    }
}

struct EmptySettingsView: View {
    @Binding var gatewayURL: String
    @Binding var gatewayToken: String
    @AppStorage("gatewayConnectionKind") private var gatewayConnectionKind = GatewayConnectionKind.local.rawValue
    @State private var isTestingConnection = false
    @State private var connectionMessage = ""
    private let client = CodexGatewayClient()

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Connect to CodePilot", systemImage: "link.circle")
                        .font(.title2.weight(.semibold))
                    Text("CodePilot connects to a Mac running the CodePilot gateway. Enter the gateway URL and bearer token from the Mac setup screen.")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Gateway") {
                Picker("Connection", selection: $gatewayConnectionKind) {
                    ForEach(GatewayConnectionKind.publicBetaCases) { kind in
                        Text(kind.title).tag(kind.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                Text(selectedConnectionKind.helpText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("Gateway URL", text: $gatewayURL)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                SecureField("Bearer token", text: $gatewayToken)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section {
                Button {
                    Task { await testConnection() }
                } label: {
                    if isTestingConnection {
                        ProgressView()
                    } else {
                        Label("Test Connection", systemImage: "checkmark.shield")
                    }
                }
                .disabled(!canTestConnection || isTestingConnection)

                if !connectionMessage.isEmpty {
                    Text(connectionMessage)
                        .font(.caption)
                        .foregroundStyle(connectionMessage.hasPrefix("Connected") ? .green : .orange)
                }
            } footer: {
                Text("The token is stored on the Mac at ~/.codex-account-switcher/phone-gateway-token.")
            }
        }
        .navigationTitle("CodePilot")
        .onAppear {
            if !selectedConnectionKind.isPublicBetaAvailable {
                gatewayConnectionKind = GatewayConnectionKind.cloudflare.rawValue
            }
        }
    }

    private var canTestConnection: Bool {
        !gatewayURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !gatewayToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var selectedConnectionKind: GatewayConnectionKind {
        GatewayConnectionKind(rawValue: gatewayConnectionKind) ?? .local
    }

    @MainActor
    private func testConnection() async {
        isTestingConnection = true
        defer { isTestingConnection = false }
        do {
            let status = try await client.accountStatus(baseURL: gatewayURL, token: gatewayToken)
            let accountText = status.activeAccount.isEmpty ? "unknown account" : status.activeAccount
            connectionMessage = "Connected as \(accountText)."
        } catch {
            connectionMessage = connectionFailureMessage(error)
        }
    }

    private func connectionFailureMessage(_ error: Error) -> String {
        if let gatewayError = error as? GatewayError {
            switch gatewayError {
            case .invalidURL:
                return "Enter a valid gateway URL."
            case .http(let status) where status == 401 || status == 403:
                return "Invalid or expired bearer token."
            case .http(let status) where status == 502:
                return "Cloudflare reached the hostname, but the gateway is not reachable behind it."
            case .http(let status):
                return "Gateway returned HTTP \(status)."
            case .gateway(let payload):
                return GatewayErrorPresenter.recovery(for: payload)
            case .server(let message):
                return message
            case .invalidResponse:
                return "The gateway response could not be read."
            }
        }
        return error.localizedDescription
    }
}

enum GatewayConnectionKind: String, CaseIterable, Identifiable {
    case local
    case cloudflare

    var id: String { rawValue }

    static var publicBetaCases: [GatewayConnectionKind] {
        allCases.filter(\.isPublicBetaAvailable)
    }

    var isPublicBetaAvailable: Bool {
        switch self {
        case .local:
            false
        case .cloudflare:
            true
        }
    }

    var title: String {
        switch self {
        case .local:
            "Same Network"
        case .cloudflare:
            "Cloudflare"
        }
    }

    var helpText: String {
        switch self {
        case .local:
            "Same Network is disabled for public beta until LAN binding has explicit firewall and trust guidance."
        case .cloudflare:
            "Use your Cloudflare Tunnel hostname for access when you are away from the Mac."
        }
    }
}

struct ThreadProjectSection: Identifiable {
    let id: String
    let title: String
    let path: String
    let threads: [CodexThread]

    var latestUpdatedAt: Int {
        threads.map(\.updatedAt).max() ?? 0
    }

    static func groupedThreads(_ threads: [CodexThread]) -> [ThreadProjectSection] {
        Dictionary(grouping: threads, by: { normalizedPath($0.cwd) })
            .map { path, threads in
                ThreadProjectSection(
                    id: path,
                    title: projectTitle(for: path),
                    path: path,
                    threads: threads.sorted { $0.updatedAt > $1.updatedAt }
                )
            }
            .sorted {
                if $0.latestUpdatedAt == $1.latestUpdatedAt {
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
                return $0.latestUpdatedAt > $1.latestUpdatedAt
            }
    }

    private static func normalizedPath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "No workspace"
        }
        return URL(fileURLWithPath: trimmed, isDirectory: true).standardizedFileURL.path
    }

    private static func projectTitle(for path: String) -> String {
        if path == "No workspace" {
            return path
        }
        let title = URL(fileURLWithPath: path, isDirectory: true).lastPathComponent
        return title.isEmpty ? path : title
    }
}

enum ReasoningLevel: String, CaseIterable, Codable, Identifiable {
    case keep
    case none
    case minimal
    case low
    case medium
    case high
    case xhigh

    var id: String { rawValue }

    var apiValue: String? {
        self == .keep ? nil : rawValue
    }

    var title: String {
        switch self {
        case .keep:
            "Keep Current"
        case .none:
            "None"
        case .minimal:
            "Minimal"
        case .low:
            "Low"
        case .medium:
            "Medium"
        case .high:
            "High"
        case .xhigh:
            "XHigh"
        }
    }

    var shortTitle: String {
        switch self {
        case .keep:
            "Current"
        case .minimal:
            "Min"
        case .medium:
            "Med"
        case .xhigh:
            "XH"
        default:
            title
        }
    }

    init?(apiValue: String?) {
        guard let apiValue else { return nil }
        self.init(rawValue: apiValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
}

enum ReasoningPreferenceStore {
    private static let key = "threadReasoningEffortByID"

    static func load() -> [String: ReasoningLevel] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let raw = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return raw.compactMapValues(ReasoningLevel.init(rawValue:))
    }

    static func save(_ values: [String: ReasoningLevel]) {
        let raw = values.mapValues(\.rawValue)
        guard let data = try? JSONEncoder().encode(raw) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

struct ReasoningLevelPicker: View {
    @Binding var level: ReasoningLevel

    var body: some View {
        Picker("Reasoning", selection: $level) {
            ForEach(ReasoningLevel.allCases) { level in
                Text(level.title).tag(level)
            }
        }
    }
}

struct ThreadListView: View {
    @ObservedObject var model: CodexPhoneModel
    var onRemoteDesktop: () -> Void = {}
    @AppStorage("gatewayURL") private var gatewayURL = ""
    @AppStorage("gatewayToken") private var gatewayToken = ""
    @State private var renamingThread: CodexThread?
    @State private var renameText = ""
    @State private var deletingThread: CodexThread?

    var body: some View {
        VStack(spacing: 0) {
            AggregateCreditBar(accounts: model.accountStatuses)

            List {
                Section {
                    Button(action: onRemoteDesktop) {
                        Label("Remote Desktop", systemImage: "desktopcomputer")
                    }
                    .accessibilityIdentifier("remoteDesktopHomeButton")
                }

                if !pinnedThreads.isEmpty {
                    Section {
                        ForEach(pinnedThreads) { thread in
                            threadRow(thread)
                        }
                    } header: {
                        Label("Pinned", systemImage: "pin.fill")
                            .font(.subheadline.weight(.semibold))
                            .textCase(nil)
                    }
                }

                ForEach(projectSections) { section in
                    Section {
                        ForEach(section.threads) { thread in
                            threadRow(thread)
                        }
                    } header: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(section.title)
                                .font(.subheadline.weight(.semibold))
                            Text(section.path)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .textCase(nil)
                    }
                }
            }
            .overlay {
                if model.threads.isEmpty && !model.isLoading {
                    ContentUnavailableView("No Threads", systemImage: "tray")
                }
            }
        }
        .alert("Rename Thread", isPresented: renameAlertBinding) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) {
                renamingThread = nil
                renameText = ""
            }
            Button("Save") {
                guard let thread = renamingThread else { return }
                let name = renameText
                renamingThread = nil
                renameText = ""
                Task {
                    await model.renameThread(thread, name: name, baseURL: gatewayURL, token: gatewayToken)
                }
            }
        }
        .confirmationDialog(
            "Delete Thread",
            isPresented: deleteDialogBinding,
            titleVisibility: .visible,
            presenting: deletingThread
        ) { thread in
            Button("Delete", role: .destructive) {
                deletingThread = nil
                Task {
                    await model.archiveThread(thread, baseURL: gatewayURL, token: gatewayToken)
                }
            }
            Button("Cancel", role: .cancel) {
                deletingThread = nil
            }
        } message: { thread in
            Text(thread.title)
        }
    }

    private var pinnedThreads: [CodexThread] {
        model.threads
            .filter(\.isPinned)
            .sorted { lhs, rhs in
                let lhsRank = lhs.pinnedRank ?? Int.max
                let rhsRank = rhs.pinnedRank ?? Int.max
                if lhsRank == rhsRank {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhsRank < rhsRank
            }
    }

    private var projectSections: [ThreadProjectSection] {
        ThreadProjectSection.groupedThreads(model.threads.filter { !$0.isPinned })
    }

    private func threadRow(_ thread: CodexThread) -> some View {
        NavigationLink {
            ChatView(model: model, thread: thread)
                .id(thread.id)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if thread.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }
                    Text(thread.title)
                        .font(.headline)
                        .lineLimit(2)
                }
                Text(thread.updatedText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                Task {
                    await model.setThreadPinned(thread, pinned: !thread.isPinned, baseURL: gatewayURL, token: gatewayToken)
                }
            } label: {
                Label(thread.isPinned ? "Unpin" : "Pin", systemImage: thread.isPinned ? "pin.slash" : "pin")
            }
            .tint(.yellow)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                deletingThread = thread
            } label: {
                Label("Delete", systemImage: "trash")
            }

            Button {
                renamingThread = thread
                renameText = thread.title
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            .tint(.blue)
        }
    }

    private var renameAlertBinding: Binding<Bool> {
        Binding(
            get: { renamingThread != nil },
            set: { isPresented in
                if !isPresented {
                    renamingThread = nil
                    renameText = ""
                }
            }
        )
    }

    private var deleteDialogBinding: Binding<Bool> {
        Binding(
            get: { deletingThread != nil },
            set: { isPresented in
                if !isPresented {
                    deletingThread = nil
                }
            }
        )
    }
}

enum NewThreadProjectMode: String, CaseIterable, Identifiable {
    case existing
    case new

    var id: String { rawValue }

    var title: String {
        switch self {
        case .existing:
            "Existing"
        case .new:
            "New"
        }
    }
}

struct NewThreadView: View {
    @ObservedObject var model: CodexPhoneModel
    let gatewayURL: String
    let gatewayToken: String
    let onCreated: (CodexThread) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var projectMode: NewThreadProjectMode = .existing
    @State private var selectedWorkspace = ""
    @State private var newProjectName = ""
    @State private var newProjectParent = ""
    @State private var prompt = ""
    @State private var reasoningLevel: ReasoningLevel = .keep

    var body: some View {
        NavigationStack {
            Form {
                Section("Project") {
                    Picker("Mode", selection: $projectMode) {
                        ForEach(NewThreadProjectMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    switch projectMode {
                    case .existing:
                        if !projects.isEmpty {
                            Picker("Project", selection: $selectedWorkspace) {
                                ForEach(projects) { project in
                                    Text(project.title)
                                        .tag(project.path)
                                }
                            }
                        } else {
                            ContentUnavailableView("No Projects", systemImage: "folder")
                        }

                        TextField("Workspace path", text: $selectedWorkspace)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                    case .new:
                        TextField("Project name", text: $newProjectName)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()

                        TextField("Parent folder", text: $newProjectParent)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        LabeledContent("Workspace path") {
                            Text(newProjectWorkspacePath.isEmpty ? "Enter a project name" : newProjectWorkspacePath)
                                .foregroundStyle(newProjectWorkspacePath.isEmpty ? .secondary : .primary)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }

                Section("First Message") {
                    TextField("Ask Codex", text: $prompt, axis: .vertical)
                        .lineLimit(4...10)
                }

                Section("Reasoning") {
                    ReasoningLevelPicker(level: $reasoningLevel)
                }
            }
            .navigationTitle("New Thread")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await createThread() }
                    } label: {
                        if model.isCreatingThread {
                            ProgressView()
                        } else {
                            Text("Create")
                        }
                    }
                    .disabled(!canCreate)
                }
            }
            .task {
                if selectedWorkspace.isEmpty {
                    selectedWorkspace = projects.first?.path ?? ""
                }
                if newProjectParent.isEmpty {
                    newProjectParent = defaultProjectParent
                }
            }
        }
    }

    private var projects: [ThreadProjectSection] {
        ThreadProjectSection.groupedThreads(model.threads)
    }

    private var canCreate: Bool {
        !model.isCreatingThread &&
        !targetWorkspace.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var targetWorkspace: String {
        switch projectMode {
        case .existing:
            selectedWorkspace
        case .new:
            newProjectWorkspacePath
        }
    }

    private var shouldCreateWorkspace: Bool {
        projectMode == .new
    }

    private var defaultProjectParent: String {
        if let firstProjectPath = projects.first?.path, firstProjectPath != "No workspace" {
            let parent = URL(fileURLWithPath: firstProjectPath, isDirectory: true).deletingLastPathComponent().path
            if !parent.isEmpty {
                return parent
            }
        }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.path ?? "/"
    }

    private var newProjectWorkspacePath: String {
        let parent = newProjectParent.trimmingCharacters(in: .whitespacesAndNewlines)
        let slug = projectSlug(newProjectName)
        guard !parent.isEmpty, !slug.isEmpty else { return "" }
        return URL(fileURLWithPath: parent, isDirectory: true)
            .appendingPathComponent(slug, isDirectory: true)
            .standardizedFileURL
            .path
    }

    private func projectSlug(_ name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9._ -]+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".- _"))
    }

    private func createThread() async {
        guard let thread = await model.createThread(
            prompt: prompt,
            cwd: targetWorkspace,
            createWorkspace: shouldCreateWorkspace,
            reasoningLevel: reasoningLevel,
            baseURL: gatewayURL,
            token: gatewayToken
        ) else {
            return
        }
        onCreated(thread)
    }
}

struct ChatView: View {
    @ObservedObject var model: CodexPhoneModel
    let thread: CodexThread
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("gatewayURL") private var gatewayURL = ""
    @AppStorage("gatewayToken") private var gatewayToken = ""
    @State private var prompt = ""
    @State private var attachments: [PendingAttachment] = []
    @State private var showingFileImporter = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var autoScrollState = ChatAutoScrollState()
    @State private var didInitialScrollToBottom = false
    @State private var isTimelineReady = false
    private let scrollBottomID = "chat-bottom-anchor"

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                AggregateCreditBar(accounts: model.accountStatuses)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(timelineMessages) { message in
                            MessageBubble(message: message, gatewayURL: gatewayURL, gatewayToken: gatewayToken)
                                .id(message.id)
                        }
                        if let job = visibleJob {
                            JobStatusView(job: job, gatewayURL: gatewayURL, gatewayToken: gatewayToken)
                                .id("job")
                        }
                        Color.clear
                            .frame(height: 1)
                            .id(scrollBottomID)
                            .onAppear {
                                autoScrollState.reachedLatest()
                            }
                    }
                    .padding()
                }
                .opacity(isTimelineReady ? 1 : 0)
                .overlay {
                    if !isTimelineReady {
                        ProgressView()
                    }
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 8)
                        .onChanged { value in
                            if value.translation.height > 8 {
                                autoScrollState.userDraggedTowardHistory()
                            }
                        }
                )
                .overlay(alignment: .bottomTrailing) {
                    if autoScrollState.hasUnseenActivity {
                        Button {
                            autoScrollState.forceFollowLatest()
                            scrollToBottomAfterLayout(proxy, animated: true)
                        } label: {
                            Image(systemName: "arrow.down.to.line.compact")
                                .font(.headline)
                        }
                        .buttonStyle(.borderedProminent)
                        .clipShape(Capsule())
                        .accessibilityLabel("Jump to latest")
                        .padding(.trailing, 16)
                        .padding(.bottom, 16)
                    }
                }
                .onChange(of: timelineMessages.count) { _, _ in
                    performInitialScrollIfNeeded(proxy)
                    scrollToBottomIfFollowing(proxy)
                }
                .onChange(of: activeJob?.status) { _, _ in
                    scrollToBottomIfFollowing(proxy)
                }
                .onChange(of: activeJob?.activityEvents.count) { _, _ in
                    scrollToBottomIfFollowing(proxy)
                }
                .onChange(of: activeJob?.updatedAt) { _, _ in
                    scrollToBottomIfFollowing(proxy)
                }
                .task(id: thread.id) {
                    didInitialScrollToBottom = false
                    isTimelineReady = false
                    autoScrollState.forceFollowLatest()
                    await model.loadThread(thread, baseURL: gatewayURL, token: gatewayToken)
                    await model.loadAccountStatus(baseURL: gatewayURL, token: gatewayToken)
                    await model.recoverActiveJob(for: thread, baseURL: gatewayURL, token: gatewayToken)
                    performInitialScrollIfNeeded(proxy)
                }

                Divider()

                VStack(spacing: 8) {
                    if !attachments.isEmpty {
                        AttachmentStrip(attachments: attachments) { attachment in
                            attachments.removeAll { $0.id == attachment.id }
                        }
                    }

                    HStack(alignment: .bottom, spacing: 10) {
                        Button {
                            showingFileImporter = true
                        } label: {
                            Image(systemName: "paperclip")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Attach Files")
                        .disabled(activeJob?.status == "running")

                        PhotosPicker(selection: $selectedPhotoItems, maxSelectionCount: max(0, 8 - attachments.count), matching: .images) {
                            Image(systemName: "photo")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Attach Photos")
                        .disabled(activeJob?.status == "running" || attachments.count >= 8)

                        if let job = activeJob, job.status == "running" {
                            Button {
                                Task {
                                    await model.stop(job: job, thread: thread, baseURL: gatewayURL, token: gatewayToken)
                                }
                            } label: {
                                Image(systemName: "stop.fill")
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                            .accessibilityLabel("Stop Turn")
                        }

                        TextField(composerPlaceholder, text: $prompt, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(1...6)

                        if let diffStats = activeDiffStats {
                            DiffStatsCounter(stats: diffStats)
                        }

                        Button {
                            let text = prompt
                            let files = attachments
                            let reasoningLevel = model.reasoningLevel(for: thread)
                            autoScrollState.forceFollowLatest()
                            scrollToBottomAfterLayout(proxy, animated: false)
                            prompt = ""
                            attachments = []
                            Task {
                                let didSend: Bool
                                if let job = activeJob, job.status == "running" {
                                    didSend = await model.steer(text: text, job: job, thread: thread, baseURL: gatewayURL, token: gatewayToken)
                                } else {
                                    didSend = await model.send(
                                        prompt: text,
                                        attachments: files,
                                        reasoningLevel: reasoningLevel,
                                        to: thread,
                                        baseURL: gatewayURL,
                                        token: gatewayToken
                                    )
                                }
                                if !didSend {
                                    prompt = text
                                    attachments = files
                                }
                            }
                        } label: {
                            Image(systemName: "paperplane.fill")
                                .font(.title3)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canSend)
                    }
                }
                .padding()
            }
        }
        .navigationTitle(thread.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ReasoningLevelPicker(level: reasoningLevelBinding)
                } label: {
                    Label(model.reasoningLevel(for: thread).shortTitle, systemImage: "brain.head.profile")
                }
                .accessibilityLabel("Reasoning Level")
                .disabled(isRunningTurn)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        await model.loadThread(thread, baseURL: gatewayURL, token: gatewayToken)
                        await model.recoverActiveJob(for: thread, baseURL: gatewayURL, token: gatewayToken)
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Refresh Thread")
            }
        }
        .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            importFiles(result)
        }
        .onChange(of: selectedPhotoItems) { _, items in
            Task {
                await importPhotos(items)
                selectedPhotoItems = []
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await model.loadThread(thread, baseURL: gatewayURL, token: gatewayToken)
                await model.loadAccountStatus(baseURL: gatewayURL, token: gatewayToken)
                await model.recoverActiveJob(for: thread, baseURL: gatewayURL, token: gatewayToken)
            }
        }
    }

    private var canSend: Bool {
        if isRunningTurn {
            guard canSteer else { return false }
            return !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
    }

    private var isRunningTurn: Bool {
        activeJob?.status == "running"
    }

    private var canSteer: Bool {
        guard let turnId = activeJob?.turnId else { return false }
        return !turnId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var composerPlaceholder: String {
        if isRunningTurn {
            return canSteer ? "Steer Codex" : "Steering unavailable for this turn"
        }
        return "Ask Codex"
    }

    private var activeJob: CodexJob? {
        model.activeJob(for: thread.id)
    }

    private var visibleJob: CodexJob? {
        guard let activeJob else { return nil }
        if activeJob.status == "running" {
            return activeJob
        }
        if activeJob.status == "failed" || activeJob.status == "canceled" {
            return activeJob.hasVisibleFailureDetails ? activeJob : nil
        }
        return nil
    }

    private var activeDiffStats: CodexDiffStats? {
        activeJob?.diffStats
    }

    private var reasoningLevelBinding: Binding<ReasoningLevel> {
        Binding(
            get: { model.reasoningLevel(for: thread) },
            set: { model.setReasoningLevel($0, for: thread.id) }
        )
    }

    private var timelineMessages: [CodexMessage] {
        model.timelineMessages(for: thread.id)
    }

    private func importFiles(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            for url in urls.prefix(8 - attachments.count) {
                let didStartAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if didStartAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                let data = try Data(contentsOf: url)
                if !canAttach(data, filename: url.lastPathComponent) {
                    continue
                }

                let mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                attachments.append(PendingAttachment(filename: url.lastPathComponent, mimeType: mimeType, data: data))
            }
        } catch {
            guard !isBenignCancellationError(error) else { return }
            model.errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func importPhotos(_ items: [PhotosPickerItem]) async {
        for (index, item) in items.prefix(8 - attachments.count).enumerated() {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    continue
                }
                let contentType = item.supportedContentTypes.first { $0.conforms(to: .image) }
                let ext = contentType?.preferredFilenameExtension ?? "jpg"
                let mimeType = contentType?.preferredMIMEType ?? "image/jpeg"
                let filename = "photo-\(Int(Date().timeIntervalSince1970))-\(index + 1).\(ext)"
                if !canAttach(data, filename: filename) {
                    continue
                }
                attachments.append(PendingAttachment(filename: filename, mimeType: mimeType, data: data))
            } catch {
                guard !isBenignCancellationError(error) else { continue }
                model.errorMessage = error.localizedDescription
            }
        }
    }

    private func canAttach(_ data: Data, filename: String) -> Bool {
        if data.count > PendingAttachment.maxBytes {
            model.errorMessage = "\(filename) is too large"
            return false
        }
        let currentSize = attachments.reduce(0) { $0 + $1.data.count }
        if currentSize + data.count > PendingAttachment.maxTotalBytes {
            model.errorMessage = "Attachments are too large"
            return false
        }
        if attachments.count >= 8 {
            model.errorMessage = "Too many attachments"
            return false
        }
        return true
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = false) {
        let action = {
            proxy.scrollTo(scrollBottomID, anchor: .bottom)
        }
        if animated {
            withAnimation(.easeOut(duration: 0.12), action)
        } else {
            action()
        }
    }

    private func scrollToBottomAfterLayout(_ proxy: ScrollViewProxy, animated: Bool = false) {
        scrollToBottom(proxy, animated: animated)
        DispatchQueue.main.async {
            scrollToBottom(proxy, animated: animated)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            scrollToBottom(proxy, animated: false)
        }
    }

    private func performInitialScrollIfNeeded(_ proxy: ScrollViewProxy) {
        guard !didInitialScrollToBottom else { return }
        didInitialScrollToBottom = true
        scrollToBottomAfterLayout(proxy, animated: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            isTimelineReady = true
        }
    }

    private func scrollToBottomIfFollowing(_ proxy: ScrollViewProxy) {
        if autoScrollState.shouldFollowLatest {
            scrollToBottomAfterLayout(proxy, animated: false)
        } else {
            autoScrollState.noteIncomingActivityWhileDetached()
        }
    }
}

struct AttachmentStrip: View {
    let attachments: [PendingAttachment]
    let onRemove: (PendingAttachment) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    HStack(spacing: 6) {
                        Image(systemName: attachment.isImage ? "photo" : "doc")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(attachment.filename)
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                            Text(attachment.sizeText)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Button {
                            onRemove(attachment)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(attachment.filename)")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }
}

struct MessageBubble: View {
    let message: CodexMessage
    let gatewayURL: String
    let gatewayToken: String
    @State private var showingSelectionSheet = false

    var body: some View {
        HStack {
            if message.role == "user" {
                Spacer(minLength: 32)
            }
            OpenableText(
                text: message.text,
                font: .body,
                gatewayURL: gatewayURL,
                gatewayToken: gatewayToken
            )
                .padding(12)
                .background(message.role == "user" ? Color.accentColor.opacity(0.15) : Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .contextMenu {
                    Button {
                        showingSelectionSheet = true
                    } label: {
                        Label("Select Text", systemImage: "selection.pin.in.out")
                    }
                    Button {
                        UIPasteboard.general.string = message.text
                    } label: {
                        Label("Copy Message", systemImage: "doc.on.doc")
                    }
                }
            if message.role != "user" {
                Spacer(minLength: 32)
            }
        }
        .sheet(isPresented: $showingSelectionSheet) {
            SelectableMessageSheet(text: message.text)
        }
    }
}

struct SelectableMessageSheet: View {
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SelectableTextView(text: text)
                .padding(.horizontal)
                .padding(.bottom)
                .navigationTitle("Select Text")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            UIPasteboard.general.string = text
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .accessibilityLabel("Copy Message")
                    }
                }
        }
    }
}

struct SelectableTextView: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = true
        textView.backgroundColor = .clear
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 0, bottom: 12, right: 0)
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        uiView.text = text
    }
}

struct OpenableText: View {
    let text: String
    var font: Font = .body
    var foregroundColor: Color = .primary
    let gatewayURL: String
    let gatewayToken: String
    @State private var previewItem: FilePreviewItem?
    @State private var localWebItem: LocalWebItem?
    @State private var openError: String?

    var body: some View {
        Text(renderedMessageAttributedString(text))
            .font(font)
            .foregroundStyle(foregroundColor)
            .textSelection(.enabled)
            .environment(\.openURL, OpenURLAction { url in
                if let path = remoteFilePath(from: url) {
                    Task {
                        await openRemoteFile(path)
                    }
                    return .handled
                }
                if isMacLocalWebURL(url) {
                    Task {
                        await openLocalWebURL(url)
                    }
                    return .handled
                }
                return .systemAction
            })
            .sheet(item: $previewItem) { item in
                FilePreviewSheet(url: item.url)
                    .presentationDragIndicator(.visible)
            }
            .sheet(item: $localWebItem) { item in
                LocalWebBrowserView(item: item)
                    .ignoresSafeArea()
            }
            .alert("File Could Not Be Opened", isPresented: Binding(
                get: { openError != nil },
                set: { if !$0 { openError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(openError ?? "")
            }
    }

    @MainActor
    private func openRemoteFile(_ path: String) async {
        do {
            let localURL = try await CodexGatewayClient().downloadRemoteFile(
                path: path,
                baseURL: gatewayURL,
                token: gatewayToken
            )
            previewItem = FilePreviewItem(url: localURL)
        } catch {
            openError = error.localizedDescription
        }
    }

    @MainActor
    private func openLocalWebURL(_ url: URL) async {
        do {
            let sessionURL = try await CodexGatewayClient().startLocalWebSession(
                url: url,
                baseURL: gatewayURL,
                token: gatewayToken
            )
            localWebItem = LocalWebItem(originalURL: url, sessionURL: sessionURL)
        } catch {
            openError = error.localizedDescription
        }
    }
}

struct FilePreviewItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct LocalWebItem: Identifiable {
    let id = UUID()
    let originalURL: URL
    let sessionURL: URL
}

struct FilePreviewSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        ZStack(alignment: .top) {
            QuickLookPreview(url: url)
                .ignoresSafeArea()

            VStack(spacing: 8) {
                Capsule()
                    .fill(.secondary.opacity(0.55))
                    .frame(width: 42, height: 5)
                    .padding(.top, 10)
                    .accessibilityHidden(true)

                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                    .padding(.trailing, 14)
                    .accessibilityLabel("Close document")
                }
            }
            .padding(.top, 4)
            .background(.ultraThinMaterial.opacity(0.85))
        }
        .offset(y: max(0, dragOffset))
        .gesture(
            DragGesture(minimumDistance: 16)
                .onChanged { value in
                    dragOffset = max(0, value.translation.height)
                }
                .onEnded { value in
                    if shouldDismissFilePreview(translation: value.translation, predictedEndTranslation: value.predictedEndTranslation) {
                        dismiss()
                    } else {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.86)) {
                            dragOffset = 0
                        }
                    }
                }
        )
    }
}

func shouldDismissFilePreview(translation: CGSize, predictedEndTranslation: CGSize) -> Bool {
    let downwardDistance = translation.height
    let predictedDownwardDistance = predictedEndTranslation.height
    let horizontalDistance = abs(translation.width)
    return (downwardDistance > 90 || predictedDownwardDistance > 150) && downwardDistance > horizontalDistance
}

struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        controller.reloadData()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}

struct LocalWebBrowserView: View {
    let item: LocalWebItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            LocalWebView(url: item.sessionURL)
                .navigationTitle(item.originalURL.absoluteString)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: item.originalURL) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Share Original URL")
                    }
                }
        }
    }
}

struct LocalWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

private let remoteFileURLScheme = "codex-phone-file"

func renderedMessageAttributedString(_ text: String) -> AttributedString {
    let options = AttributedString.MarkdownParsingOptions(
        interpretedSyntax: .inlineOnlyPreservingWhitespace,
        failurePolicy: .returnPartiallyParsedIfPossible
    )
    let attributed = (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    return linkifiedAttributedString(attributed)
}

private func linkifiedAttributedString(_ source: AttributedString) -> AttributedString {
    var attributed = source
    let text = String(attributed.characters)
    let nsText = text as NSString
    let fullRange = NSRange(location: 0, length: nsText.length)
    var linkedRanges: [NSRange] = []

    if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
        for match in detector.matches(in: text, options: [], range: fullRange) {
            guard let url = match.url,
                  let range = Range(match.range, in: text),
                  let attributedRange = attributedRange(for: range, in: attributed) else {
                continue
            }
            attributed[attributedRange].link = url
            linkedRanges.append(match.range)
        }
    }

    for fileMatch in detectedRemoteFilePathMatches(in: text, excluding: linkedRanges) {
        guard let url = remoteFilePreviewURL(path: fileMatch.path),
              let range = Range(fileMatch.range, in: text),
              let attributedRange = attributedRange(for: range, in: attributed) else {
            continue
        }
        attributed[attributedRange].link = url
    }

    return attributed
}

private func attributedRange(for range: Range<String.Index>, in attributed: AttributedString) -> Range<AttributedString.Index>? {
    guard let lower = AttributedString.Index(range.lowerBound, within: attributed),
          let upper = AttributedString.Index(range.upperBound, within: attributed) else {
        return nil
    }
    return lower..<upper
}

private func detectedRemoteFilePathMatches(in text: String, excluding linkedRanges: [NSRange]) -> [(range: NSRange, path: String)] {
    let nsText = text as NSString
    let fullRange = NSRange(location: 0, length: nsText.length)
    let pattern = #"(?<![A-Za-z0-9_])/(?:[^\s\]\)\}\"'<>`])+"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
        return []
    }

    return regex.matches(in: text, options: [], range: fullRange).compactMap { match in
        guard !linkedRanges.contains(where: { rangesOverlap($0, match.range) }) else {
            return nil
        }
        var raw = nsText.substring(with: match.range)
        while let last = raw.last, ".,;".contains(last) {
            raw.removeLast()
        }
        guard raw.count > 1 else { return nil }
        let adjustedRange = NSRange(location: match.range.location, length: (raw as NSString).length)
        return (adjustedRange, normalizedRemoteFilePath(raw))
    }
}

private func rangesOverlap(_ lhs: NSRange, _ rhs: NSRange) -> Bool {
    NSIntersectionRange(lhs, rhs).length > 0
}

private func normalizedRemoteFilePath(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: " \n\t\r\"'`"))
    return trimmed.replacingOccurrences(of: #":\d+(?::\d+)?$"#, with: "", options: .regularExpression)
}

func remoteFilePreviewURL(path: String) -> URL? {
    var components = URLComponents()
    components.scheme = remoteFileURLScheme
    components.host = "open"
    components.queryItems = [URLQueryItem(name: "path", value: path)]
    return components.url
}

func remoteFilePath(from url: URL) -> String? {
    guard url.scheme == remoteFileURLScheme,
          let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
        return macAbsoluteFilePath(from: url)
    }
    return components.queryItems?.first(where: { $0.name == "path" })?.value
}

func macAbsoluteFilePath(from url: URL) -> String? {
    if url.isFileURL {
        return normalizedRemoteFilePath(url.path)
    }

    guard url.scheme == nil else {
        return nil
    }

    let path = url.path
    guard path.hasPrefix("/") else {
        return nil
    }
    return normalizedRemoteFilePath(path)
}

func isMacLocalWebURL(_ url: URL) -> Bool {
    guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
        return false
    }
    guard let host = url.host?.lowercased() else {
        return false
    }
    return host == "localhost" || host == "127.0.0.1" || host == "::1"
}

func localWebSessionURL(path: String, baseURL: String) -> URL? {
    guard let root = GatewayEndpoint.baseURL(from: baseURL),
          var components = URLComponents(url: root, resolvingAgainstBaseURL: false) else {
        return nil
    }
    let parsedPath = URLComponents(string: path)
    components.path = parsedPath?.path ?? path
    components.queryItems = parsedPath?.queryItems
    components.fragment = nil
    return components.url
}

struct JobStatusView: View {
    let job: CodexJob
    let gatewayURL: String
    let gatewayToken: String
    @State private var expandedEventIDs: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            JobStatusHeader(job: job)

            if !job.activityEvents.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(job.activityEvents) { event in
                        JobEventRow(
                            event: event,
                            isExpanded: expandedEventIDs.contains(event.id),
                            gatewayURL: gatewayURL,
                            gatewayToken: gatewayToken
                        ) {
                            toggleExpansion(for: event)
                        }
                    }
                }
            }

            if job.status == "running" {
                RespondingIndicator()
            }

            if job.status == "failed" {
                OpenableText(
                    text: job.errorSummary,
                    font: .caption,
                    foregroundColor: .red,
                    gatewayURL: gatewayURL,
                    gatewayToken: gatewayToken
                )
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(12)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func toggleExpansion(for event: CodexJobEvent) {
        guard event.isCollapsible else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            if expandedEventIDs.contains(event.id) {
                expandedEventIDs.remove(event.id)
            } else {
                expandedEventIDs.insert(event.id)
            }
        }
    }
}

struct JobStatusHeader: View {
    let job: CodexJob

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbolName)
                .foregroundStyle(color)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
            Spacer()
        }
    }

    private var title: String {
        switch job.status {
        case "running":
            "Codex is responding"
        case "failed":
            "Codex failed"
        case "canceled":
            "Codex stopped"
        default:
            "Codex finished"
        }
    }

    private var symbolName: String {
        switch job.status {
        case "running":
            "ellipsis.message"
        case "failed":
            "xmark.octagon.fill"
        case "canceled":
            "stop.circle.fill"
        default:
            "checkmark.circle.fill"
        }
    }

    private var color: Color {
        switch job.status {
        case "failed":
            .red
        default:
            .secondary
        }
    }
}

struct JobEventRow: View {
    let event: CodexJobEvent
    let isExpanded: Bool
    let gatewayURL: String
    let gatewayToken: String
    let toggleExpansion: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbolName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(event.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(isExpanded ? nil : 2)

                    if !event.subtitle.isEmpty {
                        Text(event.subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                }

                if shouldShowBody {
                    OpenableText(
                        text: event.body,
                        font: event.kind == "message" ? .body : .caption,
                        foregroundColor: event.kind == "message" ? .primary : .secondary,
                        gatewayURL: gatewayURL,
                        gatewayToken: gatewayToken
                    )
                        .lineLimit(event.kind == "message" || isExpanded ? nil : 8)
                }
            }

            Spacer(minLength: 0)

            if event.isCollapsible {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 18, height: 18)
            }
        }
        .padding(10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture {
            if event.isCollapsible {
                toggleExpansion()
            }
        }
    }

    private var shouldShowBody: Bool {
        guard !event.body.isEmpty else { return false }
        if event.isCollapsible {
            return isExpanded
        }
        return true
    }

    private var symbolName: String {
        if event.status == "running" {
            return "circle.dotted"
        }
        if event.status == "failed" {
            return "exclamationmark.triangle.fill"
        }
        switch event.kind {
        case "message":
            return "text.bubble"
        case "tool":
            return "wrench.and.screwdriver"
        case "command":
            return "terminal"
        case "fileChange":
            return "doc.text"
        case "warning":
            return "exclamationmark.triangle"
        case "error":
            return "xmark.octagon"
        default:
            return "doc.text.magnifyingglass"
        }
    }

    private var color: Color {
        if event.status == "failed" || event.kind == "error" {
            return .red
        }
        if event.kind == "warning" {
            return .orange
        }
        if event.status == "running" {
            return .accentColor
        }
        return .secondary
    }
}

struct DiffStatsCounter: View {
    let stats: CodexDiffStats

    var body: some View {
        HStack(spacing: 4) {
            if stats.added > 0 {
                Text("+\(stats.added)")
                    .foregroundStyle(.green)
            }
            if stats.removed > 0 {
                Text("-\(stats.removed)")
                    .foregroundStyle(.red)
            }
        }
        .font(.caption2.weight(.semibold))
        .monospacedDigit()
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color(.tertiarySystemBackground))
        .clipShape(Capsule())
        .fixedSize()
    }
}

struct RespondingIndicator: View {
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Responding")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 4, height: 4)
                        .opacity(index == phase ? 1 : 0.25)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onReceive(Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                phase = (phase + 1) % 3
            }
        }
    }
}

struct SettingsView: View {
    @Binding var gatewayURL: String
    @Binding var gatewayToken: String
    @ObservedObject var model: CodexPhoneModel
    @Binding var liveActivityError: String
    @Environment(\.dismiss) private var dismiss
    @AppStorage("gatewayConnectionKind") private var gatewayConnectionKind = GatewayConnectionKind.local.rawValue
    @AppStorage("totalCreditLiveActivityEnabled") private var totalCreditLiveActivityEnabled = false
    @State private var isTestingConnection = false
    @State private var connectionMessage = ""
    @State private var lastConnectedAt: Date?
    private let client = CodexGatewayClient()

    var body: some View {
        NavigationStack {
            Form {
                Section("Gateway") {
                    Picker("Connection", selection: $gatewayConnectionKind) {
                        ForEach(GatewayConnectionKind.allCases) { kind in
                            Text(kind.title).tag(kind.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(selectedConnectionKind.helpText)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("URL", text: $gatewayURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    SecureField("Bearer token", text: $gatewayToken)
                        .textInputAutocapitalization(.never)
                }

                Section("Status") {
                    LabeledContent("Active account", value: model.activeAccount.isEmpty ? "Unknown" : model.activeAccount)
                    if let generatedAt = model.accountStatusGeneratedAt {
                        LabeledContent("Usage updated", value: Date(timeIntervalSince1970: TimeInterval(generatedAt)).formatted(date: .abbreviated, time: .shortened))
                    }
                    if let lastConnectedAt {
                        LabeledContent("Last connection", value: lastConnectedAt.formatted(date: .omitted, time: .shortened))
                    }
                    if !connectionMessage.isEmpty {
                        Text(connectionMessage)
                            .font(.caption)
                            .foregroundStyle(connectionMessage.hasPrefix("Connected") ? .green : .orange)
                    }
                }

                Section {
                    Toggle("Total Credit Live Activity", isOn: $totalCreditLiveActivityEnabled)
                        .disabled(!ActivityAuthorizationInfo().areActivitiesEnabled)

                    if !ActivityAuthorizationInfo().areActivitiesEnabled {
                        Text("Live Activities are disabled for CodePilot in iOS Settings.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if !liveActivityError.isEmpty {
                        Text(liveActivityError)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("Lock Screen")
                } footer: {
                    Text("Shows total credit across your available accounts and updates through the CodePilot gateway while the app is in the background.")
                }

                Section {
                    Button {
                        Task { await testConnection() }
                    } label: {
                        if isTestingConnection {
                            ProgressView()
                        } else {
                            Label("Test Connection", systemImage: "checkmark.shield")
                        }
                    }
                    .disabled(!canTestConnection || isTestingConnection)

                    Text("The token is stored on the Mac at ~/.codex-account-switcher/phone-gateway-token.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Connection")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var canTestConnection: Bool {
        !gatewayURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !gatewayToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var selectedConnectionKind: GatewayConnectionKind {
        GatewayConnectionKind(rawValue: gatewayConnectionKind) ?? .local
    }

    @MainActor
    private func testConnection() async {
        isTestingConnection = true
        defer { isTestingConnection = false }
        do {
            let status = try await client.accountStatus(baseURL: gatewayURL, token: gatewayToken)
            model.applyAccountStatusFromConnectionTest(status)
            lastConnectedAt = Date()
            let accountText = status.activeAccount.isEmpty ? "unknown account" : status.activeAccount
            connectionMessage = "Connected as \(accountText)."
        } catch {
            connectionMessage = connectionFailureMessage(error)
        }
    }

    private func connectionFailureMessage(_ error: Error) -> String {
        if let gatewayError = error as? GatewayError {
            switch gatewayError {
            case .invalidURL:
                return "Enter a valid gateway URL."
            case .http(let status) where status == 401 || status == 403:
                return "Invalid or expired bearer token."
            case .http(let status) where status == 502:
                return "Cloudflare reached the hostname, but the gateway is not reachable behind it."
            case .http(let status):
                return "Gateway returned HTTP \(status)."
            case .gateway(let payload):
                return GatewayErrorPresenter.recovery(for: payload)
            case .server(let message):
                return message
            case .invalidResponse:
                return "The gateway response could not be read."
            }
        }
        return error.localizedDescription
    }
}

struct AccountStatusView: View {
    @ObservedObject var model: CodexPhoneModel
    let gatewayURL: String
    let gatewayToken: String
    @Environment(\.dismiss) private var dismiss
    @State private var refreshTargetAccount: AccountUsageStatus?
    @State private var reconnectTargetServer: MCPServerStatus?
    @State private var isAddingAccount = false
    @State private var rateLimitResetTargetAccount: AccountUsageStatus?
    @State private var showRateLimitResetConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Active", value: displayValue(model.activeAccount))
                    if let generatedAt = model.accountStatusGeneratedAt {
                        LabeledContent("Updated", value: shortDate(generatedAt))
                    }
                }

                Section {
                    if model.isLoadingAccountStatus && model.accountStatuses.isEmpty {
                        HStack {
                            ProgressView()
                            Text("Loading usage")
                                .foregroundStyle(.secondary)
                        }
                    } else if model.accountStatuses.isEmpty {
                        ContentUnavailableView("No Accounts", systemImage: "person.crop.circle.badge.questionmark")
                    } else {
                        ForEach(model.accountStatuses) { account in
                            AccountStatusRow(
                                account: account,
                                switchingAccountName: model.switchingAccountName,
                                refreshingAuthAccountName: model.refreshingAuthAccountName,
                                resettingRateLimitAccountName: model.resettingRateLimitAccountName
                            ) {
                                Task {
                                    await model.switchAccount(named: account.name, baseURL: gatewayURL, token: gatewayToken)
                                }
                            } onRefreshAuth: {
                                refreshTargetAccount = account
                            } onResetRateLimit: {
                                rateLimitResetTargetAccount = account
                                showRateLimitResetConfirmation = true
                            }
                        }
                    }
                } header: {
                    Text("Accounts")
                } footer: {
                    Text("Percentages show remaining Codex usage for each account. The countdown is when that allowance is expected to refresh.")
                }

                PluginStatusSection(plugins: model.pluginStatuses, sync: model.pluginSyncStatus)

                ConnectorStatusSection(
                    servers: model.mcpServers,
                    onReconnect: { server in
                        reconnectTargetServer = server
                    }
                )
            }
            .navigationTitle("Usage")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        isAddingAccount = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(model.addingAccountName != nil || model.refreshingAuthAccountName != nil)
                    .accessibilityLabel("Add Account")

                    Button {
                        Task { await model.loadAccountStatus(baseURL: gatewayURL, token: gatewayToken) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh Usage")
                }
            }
            .refreshable {
                await model.loadAccountStatus(baseURL: gatewayURL, token: gatewayToken)
            }
            .task {
                await model.pollAccountStatus(baseURL: gatewayURL, token: gatewayToken)
            }
            .confirmationDialog(
                "Use a reset credit for \(displayValue(rateLimitResetTargetAccount?.name ?? ""))?",
                isPresented: $showRateLimitResetConfirmation,
                titleVisibility: .visible
            ) {
                Button("Use Reset Credit") {
                    let account = rateLimitResetTargetAccount
                    Task {
                        if let account {
                            await model.resetRateLimit(for: account.name, baseURL: gatewayURL, token: gatewayToken)
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This asks Codex to consume one available rate limit reset credit on that account, without switching accounts.")
            }
            .sheet(item: $refreshTargetAccount) { account in
                AccountAuthRefreshSheet(
                    model: model,
                    accountName: account.name,
                    gatewayURL: gatewayURL,
                    gatewayToken: gatewayToken
                )
                .presentationDetents([.large])
            }
            .sheet(item: $reconnectTargetServer) { server in
                MCPReconnectSheet(
                    model: model,
                    server: server,
                    gatewayURL: gatewayURL,
                    gatewayToken: gatewayToken
                )
                .presentationDetents([.large])
            }
            .sheet(isPresented: $isAddingAccount) {
                AccountAddSheet(
                    model: model,
                    gatewayURL: gatewayURL,
                    gatewayToken: gatewayToken
                )
                .presentationDetents([.large])
            }
        }
    }

    private func displayValue(_ value: String) -> String {
        value.isEmpty ? "Unknown" : value
    }

    private func shortDate(_ epoch: Int) -> String {
        Date(timeIntervalSince1970: TimeInterval(epoch)).formatted(date: .abbreviated, time: .shortened)
    }
}

struct AccountSwitcherView: View {
    @ObservedObject var model: CodexPhoneModel
    let gatewayURL: String
    let gatewayToken: String
    @Environment(\.dismiss) private var dismiss
    @State private var refreshTargetAccount: AccountUsageStatus?
    @State private var reconnectTargetServer: MCPServerStatus?
    @State private var isAddingAccount = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if model.isLoadingAccountStatus && model.accountStatuses.isEmpty {
                        HStack {
                            ProgressView()
                            Text("Loading accounts")
                                .foregroundStyle(.secondary)
                        }
                    } else if model.accountStatuses.isEmpty {
                        ContentUnavailableView("No Accounts", systemImage: "person.crop.circle.badge.questionmark")
                    } else {
                        ForEach(model.accountStatuses) { account in
                            AccountStatusRow(
                                account: account,
                                switchingAccountName: model.switchingAccountName,
                                refreshingAuthAccountName: model.refreshingAuthAccountName
                            ) {
                                Task {
                                    let didSwitch = await model.switchAccount(named: account.name, baseURL: gatewayURL, token: gatewayToken)
                                    if didSwitch {
                                        dismiss()
                                    }
                                }
                            } onRefreshAuth: {
                                refreshTargetAccount = account
                            }
                        }
                    }
                } header: {
                    Text("OpenAI Account")
                } footer: {
                    Text("Switching changes the account used for new Codex turns on the Mac. Percentages show remaining usage before each allowance refreshes.")
                }

                PluginStatusSection(plugins: model.pluginStatuses, sync: model.pluginSyncStatus)

                ConnectorStatusSection(
                    servers: model.mcpServers,
                    onReconnect: { server in
                        reconnectTargetServer = server
                    }
                )
            }
            .navigationTitle("Switch Account")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        isAddingAccount = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(model.addingAccountName != nil || model.refreshingAuthAccountName != nil)
                    .accessibilityLabel("Add Account")

                    Button {
                        Task { await model.loadAccountStatus(baseURL: gatewayURL, token: gatewayToken) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh Accounts")
                }
            }
            .refreshable {
                await model.loadAccountStatus(baseURL: gatewayURL, token: gatewayToken)
            }
            .task {
                await model.pollAccountStatus(baseURL: gatewayURL, token: gatewayToken)
            }
            .sheet(item: $refreshTargetAccount) { account in
                AccountAuthRefreshSheet(
                    model: model,
                    accountName: account.name,
                    gatewayURL: gatewayURL,
                    gatewayToken: gatewayToken
                )
                .presentationDetents([.large])
            }
            .sheet(item: $reconnectTargetServer) { server in
                MCPReconnectSheet(
                    model: model,
                    server: server,
                    gatewayURL: gatewayURL,
                    gatewayToken: gatewayToken
                )
                .presentationDetents([.large])
            }
            .sheet(isPresented: $isAddingAccount) {
                AccountAddSheet(
                    model: model,
                    gatewayURL: gatewayURL,
                    gatewayToken: gatewayToken
                )
                .presentationDetents([.large])
            }
        }
    }
}

struct PluginStatusSection: View {
    let plugins: [PluginStatus]
    let sync: PluginSyncStatus?

    var body: some View {
        if !plugins.isEmpty || sync?.hasVisibleStatus == true {
            Section {
                if let sync, sync.hasVisibleStatus {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: sync.hasWarnings ? "exclamationmark.triangle.fill" : "checkmark.seal")
                            .foregroundStyle(sync.hasWarnings ? .orange : .green)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(sync.title)
                                .font(.body.weight(.medium))
                            Text(sync.detailText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !sync.warningText.isEmpty {
                                Text(sync.warningText)
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                ForEach(plugins) { plugin in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: plugin.enabled ? "puzzlepiece.extension" : "puzzlepiece.extension.fill")
                            .foregroundStyle(plugin.enabled ? Color.secondary : Color.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(plugin.displayName)
                                .font(.body.weight(.medium))
                            Text(detailText(for: plugin))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !plugin.description.isEmpty {
                                Text(plugin.description)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("Plugins")
            } footer: {
                Text("Plugin and MCP declarations are synced from the shared Codex profiles on the Mac. OAuth connectors may still need a reconnect for the active account.")
            }
        }
    }

    private func detailText(for plugin: PluginStatus) -> String {
        var parts = [plugin.statusText]
        if !plugin.marketplace.isEmpty {
            parts.append(plugin.marketplace)
        }
        return parts.joined(separator: " · ")
    }
}

struct ConnectorStatusSection: View {
    let servers: [MCPServerStatus]
    let onReconnect: (MCPServerStatus) -> Void

    var body: some View {
        if !servers.isEmpty {
            Section {
                ForEach(servers) { server in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: iconName(for: server))
                            .foregroundStyle(server.needsLogin ? .orange : .secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(server.displayName)
                                .font(.body.weight(.medium))
                            Text(detailText(for: server))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let warning = warningText(for: server) {
                                Text(warning)
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                        Spacer(minLength: 12)
                        if server.canReconnect {
                            Button("Reconnect") {
                                onReconnect(server)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("Connector Auth")
            } footer: {
                Text("These are MCP connector login states for the active Codex profile. Some plugins do not have a connector auth flow.")
            }
        }
    }

    private func iconName(for server: MCPServerStatus) -> String {
        server.needsLogin ? "puzzlepiece.extension.fill" : "puzzlepiece.extension"
    }

    private func detailText(for server: MCPServerStatus) -> String {
        var parts = [server.statusText]
        if !server.status.isEmpty {
            parts.append(server.status)
        }
        return parts.joined(separator: " · ")
    }

    private func warningText(for server: MCPServerStatus) -> String? {
        guard server.needsLogin else { return nil }
        if let lastWarning = server.lastAuthWarningAt {
            let date = Date(timeIntervalSince1970: TimeInterval(lastWarning))
            return "Last warning \(date.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated)))"
        }
        return server.lastAuthWarningReason.isEmpty ? nil : server.lastAuthWarningReason
    }
}

struct AccountStatusRow: View {
    let account: AccountUsageStatus
    let switchingAccountName: String?
    let refreshingAuthAccountName: String?
    let resettingRateLimitAccountName: String?
    let onSwitch: (() -> Void)?
    let onRefreshAuth: (() -> Void)?
    let onResetRateLimit: (() -> Void)?

    init(
        account: AccountUsageStatus,
        switchingAccountName: String? = nil,
        refreshingAuthAccountName: String? = nil,
        resettingRateLimitAccountName: String? = nil,
        onSwitch: (() -> Void)? = nil,
        onRefreshAuth: (() -> Void)? = nil,
        onResetRateLimit: (() -> Void)? = nil
    ) {
        self.account = account
        self.switchingAccountName = switchingAccountName
        self.refreshingAuthAccountName = refreshingAuthAccountName
        self.resettingRateLimitAccountName = resettingRateLimitAccountName
        self.onSwitch = onSwitch
        self.onRefreshAuth = onRefreshAuth
        self.onResetRateLimit = onResetRateLimit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(account.name)
                    .font(.headline)
                Spacer()
                if account.isActive {
                    Label("Active", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green)
                }
                if let onRefreshAuth {
                    Button {
                        onRefreshAuth()
                    } label: {
                        if refreshingAuthAccountName == account.name {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "key")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(refreshingAuthAccountName != nil)
                    .accessibilityLabel("Refresh login for \(account.name)")
                }
                if let onResetRateLimit, (account.rateLimitResetCreditsRemaining ?? 0) > 0 {
                    Button {
                        onResetRateLimit()
                    } label: {
                        if resettingRateLimitAccountName == account.name {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.counterclockwise.circle")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(resettingRateLimitAccountName != nil)
                    .accessibilityLabel("Use reset credit for \(account.name)")
                }
                if let onSwitch, !account.isActive {
                    Button {
                        onSwitch()
                    } label: {
                        if switchingAccountName == account.name {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Use", systemImage: "arrow.triangle.2.circlepath")
                                .labelStyle(.titleAndIcon)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(switchingAccountName != nil)
                    .accessibilityLabel("Use \(account.name)")
                }
            }

            VStack(spacing: 8) {
                UsageLine(
                    title: "5-hour window",
                    subtitle: "Short-term allowance",
                    percent: account.fiveHourRemainingPercent,
                    resetAt: account.fiveHourResetsAt
                )
                UsageLine(
                    title: "Weekly window",
                    subtitle: "Long-term allowance",
                    percent: account.weeklyRemainingPercent,
                    resetAt: account.weeklyResetsAt
                )
            }

            if account.authStale {
                Label(account.authStaleText, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if !account.rateLimitError.isEmpty {
                Label(account.rateLimitError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    if let resetCredits = account.rateLimitResetCreditsRemaining {
                        usageCounter("Reset credits", resetCredits)
                    }
                    usageCounter("Limit hits", account.limitHits)
                    usageCounter("Auto switches", account.automaticSwitches)
                    usageCounter("Manual switches", account.manualSwitches)
                    if let lastRefreshAt = account.lastRefreshAt {
                        Text("Updated \(relativeTime(lastRefreshAt))")
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    if let resetCredits = account.rateLimitResetCreditsRemaining {
                        usageCounter("Reset credits", resetCredits)
                    }
                    usageCounter("Limit hits", account.limitHits)
                    usageCounter("Auto switches", account.automaticSwitches)
                    usageCounter("Manual switches", account.manualSwitches)
                    if let lastRefreshAt = account.lastRefreshAt {
                        Text("Updated \(relativeTime(lastRefreshAt))")
                    }
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func usageCounter(_ label: String, _ value: Int) -> Text {
        Text("\(label): \(value)")
    }

    private func relativeTime(_ epoch: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(epoch))
        return date.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated))
    }
}

struct UsageLine: View {
    let title: String
    let subtitle: String
    let percent: Int?
    let resetAt: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(percentText)
                        .font(.caption.weight(.medium))
                    if let resetText {
                        Text(resetText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            ProgressView(value: progressValue)
                .tint(progressTint)
                .accessibilityLabel(title)
                .accessibilityValue(accessibilityValue)
        }
    }

    private var percentText: String {
        guard let percent else { return "Not reported" }
        return "\(percent)% left"
    }

    private var accessibilityValue: String {
        guard let resetText else { return percentText }
        return "\(percentText), \(resetText)"
    }

    private var progressValue: Double {
        Double(percent ?? 0) / 100
    }

    private var progressTint: Color {
        guard let percent else { return .secondary }
        if percent <= 10 {
            return .red
        }
        if percent <= 30 {
            return .orange
        }
        return .green
    }

    private var resetText: String? {
        guard let resetAt else { return nil }
        let remaining = resetAt - Int(Date().timeIntervalSince1970)
        if remaining <= 0 {
            return "Refresh due"
        }
        return "Refreshes in \(durationText(remaining))"
    }

    private func durationText(_ seconds: Int) -> String {
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 {
            return hours > 0 ? "\(days)d \(hours)h" : "\(days)d"
        }
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(max(1, minutes))m"
    }
}

struct AggregateCreditBar: View {
    let accounts: [AccountUsageStatus]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            let status = AggregateCreditStatus(accounts: accounts, now: timeline.date)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Label(status.title, systemImage: status.systemImage)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(status.trailingText)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                ProgressView(value: status.progress)
                    .tint(status.tint)
                    .accessibilityLabel("Total credit")
                    .accessibilityValue(status.accessibilityValue)
            }
            .padding(.horizontal, 16)
            .padding(.top, 5)
            .padding(.bottom, 6)
            .background(.bar)
        }
    }
}

struct AggregateCreditStatus {
    let title: String
    let trailingText: String
    let progress: Double
    let tint: Color
    let systemImage: String

    var accessibilityValue: String {
        "\(title), \(trailingText)"
    }

    init(accounts: [AccountUsageStatus], now: Date) {
        let state = TotalCreditStatus(accounts: accounts, now: now).activityState
        progress = state.progress

        switch state.kind {
        case .available:
            title = "\(state.percent ?? 0)% total credit"
            trailingText = "\(state.usableAccountCount)/\(state.reportedAccountCount) accounts usable"
            systemImage = "bolt.circle"
            if state.progress <= 0.10 {
                tint = .red
            } else if state.progress <= 0.30 {
                tint = .orange
            } else {
                tint = .green
            }
        case .refilling:
            let nowEpoch = Int(now.timeIntervalSince1970)
            let remainingSeconds = max(0, (state.nextRefreshAt ?? nowEpoch) - nowEpoch)
            title = "Refilling credit"
            trailingText = "\(state.refreshLabel ?? "Credit") in \(Self.durationText(remainingSeconds))"
            tint = .blue
            systemImage = "clock.arrow.circlepath"
        case .authenticationRequired:
            title = "Auth refresh needed"
            trailingText = "\(accounts.count) account\(accounts.count == 1 ? "" : "s") unavailable"
            tint = .orange
            systemImage = "key.fill"
        case .unavailable:
            title = "Credit unavailable"
            trailingText = accounts.isEmpty ? "Loading usage" : "No reset time reported"
            tint = .secondary
            systemImage = "bolt.slash"
        }
    }

    private static func durationText(_ seconds: Int) -> String {
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 {
            return hours > 0 ? "\(days)d \(hours)h" : "\(days)d"
        }
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(max(1, minutes))m"
    }
}

struct AccountCreditBucket {
    let accountName: String
    let label: String
    let remainingPercent: Int?
    let resetAt: Int?
    let windowMins: Int?
    let authStale: Bool

    init?(account: AccountUsageStatus) {
        accountName = account.name
        authStale = account.authStale

        let windows = [
            CreditWindow(
                label: "5h",
                remainingPercent: account.fiveHourRemainingPercent,
                resetAt: account.fiveHourResetsAt,
                windowMins: account.fiveHourWindowMins
            ),
            CreditWindow(
                label: "weekly",
                remainingPercent: account.weeklyRemainingPercent,
                resetAt: account.weeklyResetsAt,
                windowMins: account.weeklyWindowMins
            )
        ].filter { $0.remainingPercent != nil || $0.resetAt != nil }

        guard !windows.isEmpty else {
            return nil
        }

        let knownRemaining = windows.compactMap(\.remainingPercent).map { max(0, min(100, $0)) }
        remainingPercent = knownRemaining.min()

        if let effectiveRemaining = remainingPercent, effectiveRemaining > 0 {
            let displayWindow = windows.first { $0.remainingPercent == effectiveRemaining }
                ?? windows.first
            label = displayWindow?.label ?? "credit"
            resetAt = nil
            windowMins = displayWindow?.windowMins
            return
        }

        let depletedWindows = windows.filter { window in
            guard let remaining = window.remainingPercent else { return false }
            return remaining <= 0 && window.resetAt != nil
        }
        let limitingWindow = depletedWindows.max { left, right in
            (left.resetAt ?? 0) < (right.resetAt ?? 0)
        } ?? windows.first

        label = limitingWindow?.label ?? "credit"
        resetAt = limitingWindow?.resetAt
        windowMins = limitingWindow?.windowMins
    }
}

private struct CreditWindow {
    let label: String
    let remainingPercent: Int?
    let resetAt: Int?
    let windowMins: Int?
}

struct SignupURL: Identifiable {
    let id: String
    let url: URL

    static let openAI = SignupURL(
        id: "openai-signup",
        url: URL(string: "https://chatgpt.com/auth/login")!
    )
}

struct SafariSignupView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = false
        let controller = SFSafariViewController(url: url, configuration: configuration)
        controller.dismissButtonStyle = .done
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

struct AccountAuthRefreshSheet: View {
    @ObservedObject var model: CodexPhoneModel
    let accountName: String
    let gatewayURL: String
    let gatewayToken: String
    @Environment(\.dismiss) private var dismiss
    @State private var session: RemoteAccountLoginSession?
    @State private var phase = RemoteLoginPhase.idle
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .idle, .starting:
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Starting secure login")
                            .font(.headline)
                        Text("The Mac is preparing a temporary Codex login for \(accountName).")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                case .authenticating:
                    if let authURL {
                        RemoteLoginAuthenticationView(
                            url: authURL,
                            title: "Continue in OpenAI",
                            message: "Use iOS Passwords and verification-code autofill when they are offered.",
                            prefersEphemeralWebBrowserSession: false
                        ) { callbackURL in
                            Task {
                                await complete(callbackURL: callbackURL.absoluteString)
                            }
                        } onFailure: { message in
                            errorMessage = message
                            phase = .failed
                        }
                    } else {
                        ContentUnavailableView("Login URL Missing", systemImage: "exclamationmark.triangle")
                    }
                case .completing:
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Finishing login")
                            .font(.headline)
                        Text("Codex is saving the refreshed account auth on the Mac.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                case .failed:
                    ContentUnavailableView {
                        Label("Login Failed", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(errorMessage ?? "The account login could not be refreshed.")
                    } actions: {
                        Button("Try Again") {
                            Task {
                                await start()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Refresh \(accountName)")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(phase == .starting || phase == .authenticating || phase == .completing)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        Task {
                            await cancel()
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .disabled(phase != .failed)
                }
            }
            .task {
                await start()
            }
        }
    }

    private var authURL: URL? {
        guard let session else { return nil }
        return URL(string: session.authUrl)
    }

    private func start() async {
        guard phase == .idle || phase == .failed else { return }
        phase = .starting
        errorMessage = nil
        if let existingSessionID = session?.sessionId {
            await model.cancelRemoteAccountLogin(sessionID: existingSessionID, baseURL: gatewayURL, token: gatewayToken)
            session = nil
        }
        guard let newSession = await model.startRemoteAccountLogin(
            named: accountName,
            baseURL: gatewayURL,
            token: gatewayToken
        ) else {
            errorMessage = model.errorMessage
            phase = .failed
            return
        }
        session = newSession
        phase = .authenticating
    }

    private func complete(callbackURL: String) async {
        guard phase == .authenticating, let session else { return }
        phase = .completing
        let didComplete = await model.completeRemoteAccountLogin(
            sessionID: session.sessionId,
            callbackURL: callbackURL,
            baseURL: gatewayURL,
            token: gatewayToken
        )
        if didComplete {
            dismiss()
        } else {
            errorMessage = model.errorMessage
            phase = .failed
        }
    }

    private func cancel() async {
        guard let session else { return }
        await model.cancelRemoteAccountLogin(sessionID: session.sessionId, baseURL: gatewayURL, token: gatewayToken)
    }
}

struct MCPReconnectSheet: View {
    @ObservedObject var model: CodexPhoneModel
    let server: MCPServerStatus
    let gatewayURL: String
    let gatewayToken: String
    @Environment(\.dismiss) private var dismiss
    @State private var session: RemoteAccountLoginSession?
    @State private var phase = RemoteLoginPhase.idle
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .idle, .starting:
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Starting connector login")
                            .font(.headline)
                        Text("The Mac is preparing a Codex MCP login for \(server.displayName).")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                case .authenticating:
                    if let authURL {
                        RemoteLoginAuthenticationView(
                            url: authURL,
                            title: "Continue in \(server.displayName)",
                            message: "Finish the connector sign-in to reconnect it for the active Codex profile.",
                            prefersEphemeralWebBrowserSession: true
                        ) { callbackURL in
                            Task {
                                await complete(callbackURL: callbackURL.absoluteString)
                            }
                        } onFailure: { message in
                            errorMessage = message
                            phase = .failed
                        }
                    } else {
                        ContentUnavailableView("Login URL Missing", systemImage: "exclamationmark.triangle")
                    }
                case .completing:
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Finishing reconnect")
                            .font(.headline)
                        Text("Codex is saving the connector login on the Mac.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                case .failed:
                    ContentUnavailableView {
                        Label("Reconnect Failed", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(errorMessage ?? "The connector could not be reconnected.")
                    } actions: {
                        Button("Try Again") {
                            Task {
                                await start()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Reconnect \(server.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(phase == .starting || phase == .authenticating || phase == .completing)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        Task {
                            await cancel()
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .disabled(phase != .failed)
                }
            }
            .task {
                await start()
            }
        }
    }

    private var authURL: URL? {
        guard let session else { return nil }
        return URL(string: session.authUrl)
    }

    private func start() async {
        guard phase == .idle || phase == .failed else { return }
        phase = .starting
        errorMessage = nil
        if let existingSessionID = session?.sessionId {
            await model.cancelRemoteMCPLogin(sessionID: existingSessionID, baseURL: gatewayURL, token: gatewayToken)
            session = nil
        }
        guard let newSession = await model.startRemoteMCPLogin(
            named: server.name,
            baseURL: gatewayURL,
            token: gatewayToken
        ) else {
            errorMessage = model.errorMessage
            phase = .failed
            return
        }
        session = newSession
        phase = .authenticating
    }

    private func complete(callbackURL: String) async {
        guard phase == .authenticating, let session else { return }
        phase = .completing
        let didComplete = await model.completeRemoteMCPLogin(
            sessionID: session.sessionId,
            callbackURL: callbackURL,
            baseURL: gatewayURL,
            token: gatewayToken
        )
        if didComplete {
            dismiss()
        } else {
            errorMessage = model.errorMessage
            phase = .failed
        }
    }

    private func cancel() async {
        guard let session else { return }
        await model.cancelRemoteMCPLogin(sessionID: session.sessionId, baseURL: gatewayURL, token: gatewayToken)
    }
}

struct AccountAddSheet: View {
    @ObservedObject var model: CodexPhoneModel
    let gatewayURL: String
    let gatewayToken: String
    @Environment(\.dismiss) private var dismiss
    @State private var accountName = ""
    @State private var submittedAccountName = ""
    @State private var session: RemoteAccountLoginSession?
    @State private var phase = RemoteLoginPhase.idle
    @State private var errorMessage: String?
    @State private var signupURL: SignupURL?
    @FocusState private var isNameFocused: Bool

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .idle:
                    Form {
                        Section {
                            TextField("Account name", text: $accountName)
                                .textInputAutocapitalization(.words)
                                .autocorrectionDisabled()
                                .focused($isNameFocused)
                                .submitLabel(.continue)
                                .onSubmit {
                                    Task { await start() }
                                }
                        } footer: {
                            Text("The account is saved as a new tracked profile on the Mac. It will not become the active account automatically.")
                        }

                        Section {
                            Button {
                                signupURL = SignupURL.openAI
                            } label: {
                                Label("Create OpenAI Account", systemImage: "safari")
                            }
                        } footer: {
                            Text("Use Continue with Apple to choose Hide My Email. If you sign up with email, iOS may offer a strong password. OpenAI controls any verification prompts.")
                        }
                    }
                case .starting:
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Starting account login")
                            .font(.headline)
                        Text("The Mac is preparing a temporary Codex login for \(displayAccountName).")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                case .authenticating:
                    if let authURL {
                        RemoteLoginAuthenticationView(
                            url: authURL,
                            title: "Continue in OpenAI",
                            message: "Use iOS Passwords and verification-code autofill when they are offered.",
                            prefersEphemeralWebBrowserSession: false
                        ) { callbackURL in
                            Task {
                                await complete(callbackURL: callbackURL.absoluteString)
                            }
                        } onFailure: { message in
                            errorMessage = message
                            phase = .failed
                        }
                    } else {
                        ContentUnavailableView("Login URL Missing", systemImage: "exclamationmark.triangle")
                    }
                case .completing:
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Saving account")
                            .font(.headline)
                        Text("Codex is saving \(displayAccountName) as a tracked account on the Mac.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                case .failed:
                    ContentUnavailableView {
                        Label("Login Failed", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(errorMessage ?? "The account could not be added.")
                    } actions: {
                        Button("Try Again") {
                            phase = .idle
                            errorMessage = nil
                        }
                    }
                }
            }
            .navigationTitle("Add Account")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(phase == .starting || phase == .authenticating || phase == .completing)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        Task {
                            await cancel()
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if phase == .idle {
                        Button("Continue") {
                            Task { await start() }
                        }
                        .disabled(trimmedAccountName.isEmpty || model.addingAccountName != nil)
                    } else {
                        Button("Done") { dismiss() }
                            .disabled(phase != .failed)
                    }
                }
            }
            .task {
                isNameFocused = true
            }
            .sheet(item: $signupURL) { signup in
                SafariSignupView(url: signup.url)
                    .ignoresSafeArea()
            }
        }
    }

    private var trimmedAccountName: String {
        accountName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var displayAccountName: String {
        submittedAccountName.isEmpty ? trimmedAccountName : submittedAccountName
    }

    private var authURL: URL? {
        guard let session else { return nil }
        return URL(string: session.authUrl)
    }

    private func start() async {
        let name = trimmedAccountName
        guard !name.isEmpty, phase == .idle || phase == .failed else { return }
        phase = .starting
        errorMessage = nil
        submittedAccountName = name
        if let existingSessionID = session?.sessionId {
            await model.cancelRemoteNewAccountLogin(sessionID: existingSessionID, baseURL: gatewayURL, token: gatewayToken)
            session = nil
        }
        guard let newSession = await model.startRemoteNewAccountLogin(
            named: name,
            baseURL: gatewayURL,
            token: gatewayToken
        ) else {
            errorMessage = model.errorMessage
            phase = .failed
            return
        }
        submittedAccountName = newSession.accountName
        session = newSession
        phase = .authenticating
    }

    private func complete(callbackURL: String) async {
        guard phase == .authenticating, let session else { return }
        phase = .completing
        let didComplete = await model.completeRemoteNewAccountLogin(
            sessionID: session.sessionId,
            callbackURL: callbackURL,
            baseURL: gatewayURL,
            token: gatewayToken
        )
        if didComplete {
            dismiss()
        } else {
            errorMessage = model.errorMessage
            phase = .failed
        }
    }

    private func cancel() async {
        guard let session else { return }
        await model.cancelRemoteNewAccountLogin(sessionID: session.sessionId, baseURL: gatewayURL, token: gatewayToken)
    }
}

enum RemoteLoginPhase: Equatable {
    case idle
    case starting
    case authenticating
    case completing
    case failed
}

struct RemoteLoginAuthenticationView: View {
    let url: URL
    let title: String
    let message: String
    let prefersEphemeralWebBrowserSession: Bool
    let onCallback: (URL) -> Void
    let onFailure: (String) -> Void

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text(title)
                .font(.headline)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .background(
            RemoteLoginAuthenticationController(
                url: url,
                prefersEphemeralWebBrowserSession: prefersEphemeralWebBrowserSession,
                onCallback: onCallback,
                onFailure: onFailure
            )
            .frame(width: 0, height: 0)
        )
    }
}

struct RemoteLoginAuthenticationController: UIViewControllerRepresentable {
    let url: URL
    let prefersEphemeralWebBrowserSession: Bool
    let onCallback: (URL) -> Void
    let onFailure: (String) -> Void

    func makeUIViewController(context: Context) -> RemoteLoginAuthenticationViewController {
        RemoteLoginAuthenticationViewController(
            url: url,
            prefersEphemeralWebBrowserSession: prefersEphemeralWebBrowserSession,
            onCallback: onCallback,
            onFailure: onFailure
        )
    }

    func updateUIViewController(_ controller: RemoteLoginAuthenticationViewController, context: Context) {}
}

final class RemoteLoginAuthenticationViewController: UIViewController, ASWebAuthenticationPresentationContextProviding {
    private let url: URL
    private let prefersEphemeralWebBrowserSession: Bool
    private let onCallback: (URL) -> Void
    private let onFailure: (String) -> Void
    private var session: ASWebAuthenticationSession?
    private var callbackServer: LoopbackCallbackServer?
    private var didStart = false
    private var didComplete = false

    init(
        url: URL,
        prefersEphemeralWebBrowserSession: Bool,
        onCallback: @escaping (URL) -> Void,
        onFailure: @escaping (String) -> Void
    ) {
        self.url = url
        self.prefersEphemeralWebBrowserSession = prefersEphemeralWebBrowserSession
        self.onCallback = onCallback
        self.onFailure = onFailure
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startIfNeeded()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || navigationController?.isBeingDismissed == true {
            cleanup()
        }
    }

    private func startIfNeeded() {
        guard !didStart else { return }
        didStart = true

        guard let redirectURL = Self.redirectURL(from: url),
              let port = redirectURL.port,
              let expectedState = Self.state(from: url),
              Self.isCodexLoopbackCallback(redirectURL) else {
            onFailure("Login callback URL could not be prepared.")
            return
        }

        do {
            let server = try LoopbackCallbackServer(
                port: UInt16(port),
                expectedPath: redirectURL.path,
                expectedState: expectedState
            ) { [weak self] callbackURL in
                DispatchQueue.main.async {
                    guard let self, !self.didComplete else { return }
                    self.didComplete = true
                    self.cleanup()
                    self.onCallback(callbackURL)
                }
            }
            callbackServer = server
            server.start()
        } catch {
            onFailure("Login callback listener could not start: \(error.localizedDescription)")
            return
        }

        let authSession = ASWebAuthenticationSession(url: url, callbackURLScheme: nil) { [weak self] _, error in
            DispatchQueue.main.async {
                guard let self, !self.didComplete else { return }
                self.cleanup()
                if let authError = error as? ASWebAuthenticationSessionError,
                   authError.code == .canceledLogin {
                    self.onFailure("Login was canceled.")
                    return
                }
                self.onFailure(error?.localizedDescription ?? "Login did not complete.")
            }
        }
        authSession.presentationContextProvider = self
        authSession.prefersEphemeralWebBrowserSession = prefersEphemeralWebBrowserSession

        if authSession.start() {
            session = authSession
        } else {
            cleanup()
            onFailure("Login could not be started.")
        }
    }

    private func cleanup() {
        session?.cancel()
        session = nil
        callbackServer?.stop()
        callbackServer = nil
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        view.window ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }

    private static func redirectURL(from authURL: URL) -> URL? {
        URLComponents(url: authURL, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == "redirect_uri" }?
            .value
            .flatMap(URL.init(string:))
    }

    private static func state(from authURL: URL) -> String? {
        URLComponents(url: authURL, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == "state" }?
            .value
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    private static func isCodexLoopbackCallback(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(),
              host == "localhost" || host == "127.0.0.1",
              !url.path.isEmpty else {
            return false
        }
        return url.scheme?.lowercased() == "http"
    }
}

final class LoopbackCallbackServer {
    private let port: UInt16
    private let expectedPath: String
    private let expectedState: String
    private let onCallback: (URL) -> Void
    private let queue = DispatchQueue(label: "codexphone.loopback-callback")
    private var listener: NWListener?
    private var didComplete = false

    init(
        port: UInt16,
        expectedPath: String,
        expectedState: String,
        onCallback: @escaping (URL) -> Void
    ) throws {
        self.port = port
        self.expectedPath = expectedPath.isEmpty ? "/auth/callback" : expectedPath
        self.expectedState = expectedState
        self.onCallback = onCallback
        let nwPort = NWEndpoint.Port(rawValue: port)!
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: nwPort)
        listener = try NWListener(using: parameters)
        listener?.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
    }

    func start() {
        listener?.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self else {
                connection.cancel()
                return
            }
            guard let data,
                  let request = String(data: data, encoding: .utf8),
                  let callbackURL = loopbackCallbackURL(
                    from: request,
                    port: self.port,
                    expectedPath: self.expectedPath,
                    expectedState: self.expectedState
                  ) else {
                self.respond(to: connection, status: "400 Bad Request", body: "Invalid Codex callback.")
                return
            }
            self.respond(to: connection, status: "200 OK", body: "Codex Phone received the login callback. You can return to the app.")
            guard !self.didComplete else { return }
            self.didComplete = true
            self.onCallback(callbackURL)
        }
    }

    private func respond(to connection: NWConnection, status: String, body: String) {
        let response = """
        HTTP/1.1 \(status)\r
        Content-Type: text/plain; charset=utf-8\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

func loopbackCallbackURL(
    from request: String,
    port: UInt16,
    expectedPath: String,
    expectedState: String
) -> URL? {
    guard let requestLine = request.split(separator: "\r\n", maxSplits: 1, omittingEmptySubsequences: false).first else {
        return nil
    }
    let parts = requestLine.split(separator: " ")
    guard parts.count == 3, parts[0] == "GET" else { return nil }
    let requestTarget = String(parts[1])
    guard requestTarget.hasPrefix("/"),
          let callbackURL = URL(string: "http://127.0.0.1:\(port)\(requestTarget)"),
          let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
          components.path == expectedPath,
          components.queryItems?.filter({ $0.name == "state" }).map(\.value) == [expectedState] else {
        return nil
    }
    return callbackURL
}

@MainActor
final class CodexPhoneModel: ObservableObject {
    @Published var threads: [CodexThread] = []
    @Published var activeAccount = ""
    @Published var accountStatuses: [AccountUsageStatus] = []
    @Published var pluginStatuses: [PluginStatus] = []
    @Published var mcpServers: [MCPServerStatus] = []
    @Published var pluginSyncStatus: PluginSyncStatus?
    @Published var accountStatusGeneratedAt: Int?
    @Published private var messagesByThreadID: [String: [CodexMessage]] = [:]
    @Published private var activeJobsByThreadID: [String: CodexJob] = [:]
    @Published private var pendingUserMessagesByThreadID: [String: CodexMessage] = [:]
    @Published private var queuedPromptsByThreadID = QueuedPromptStore.load()
    @Published private var reasoningEffortByThreadID = ReasoningPreferenceStore.load()
    @Published var isLoading = false
    @Published var isLoadingAccountStatus = false
    @Published var isCreatingThread = false
    @Published var switchingAccountName: String?
    @Published var refreshingAuthAccountName: String?
    @Published var addingAccountName: String?
    @Published var resettingRateLimitAccountName: String?
    @Published var errorMessage: String?

    private var pollingJobIDs: Set<String> = []
    private var jobEventCursorsByJobID: [String: Int] = [:]
    private var submittedPromptsByJobID: [String: QueuedPrompt] = [:]
    private let client = CodexGatewayClient()
    private let turnCompletionNotifier = TurnCompletionNotifier()
    private var turnNotificationTracker = TurnCompletionNotificationTracker()

    func loadThreads(baseURL: String, token: String) async {
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await client.threads(baseURL: baseURL, token: token)
            activeAccount = response.activeAccount
            threads = response.threads
        } catch {
            report(error)
        }
    }

    func loadThread(_ thread: CodexThread, baseURL: String, token: String) async {
        do {
            let response = try await client.thread(id: thread.id, baseURL: baseURL, token: token)
            activeAccount = response.activeAccount
            if let messages = response.thread.messages {
                if !messages.isEmpty || (messagesByThreadID[thread.id] ?? []).isEmpty {
                    messagesByThreadID[thread.id] = messages
                }
            }
        } catch {
            report(error)
        }
    }

    func recoverActiveJob(for thread: CodexThread, baseURL: String, token: String) async {
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            let response = try await client.activeJob(threadID: thread.id, baseURL: baseURL, token: token)
            applyGatewayState(response)
            guard let job = response.job else {
                if let previousJob = activeJobsByThreadID[thread.id], previousJob.status == "running" {
                    if await recoverCompletedJob(previousJob, thread: thread, baseURL: baseURL, token: token) {
                        return
                    }
                    activeJobsByThreadID[thread.id] = nil
                }
                return
            }
            setActiveJob(job, fallbackThreadID: thread.id)
            if pendingUserMessagesByThreadID[thread.id] == nil, let promptText = job.promptText, !promptText.isEmpty {
                pendingUserMessagesByThreadID[thread.id] = CodexMessage(
                    id: "pending-\(job.id)",
                    role: "user",
                    text: promptText,
                    timestamp: nil
                )
            }
            startPolling(jobID: job.id, thread: thread, baseURL: baseURL, token: token)
        } catch {
            report(error)
        }
    }

    func renameThread(_ thread: CodexThread, name: String, baseURL: String, token: String) async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        do {
            try await client.renameThread(threadID: thread.id, name: trimmedName, baseURL: baseURL, token: token)
            await loadThreads(baseURL: baseURL, token: token)
        } catch {
            report(error)
        }
    }

    func archiveThread(_ thread: CodexThread, baseURL: String, token: String) async {
        do {
            try await client.archiveThread(threadID: thread.id, baseURL: baseURL, token: token)
            threads.removeAll { $0.id == thread.id }
            await loadThreads(baseURL: baseURL, token: token)
        } catch {
            report(error)
        }
    }

    func setThreadPinned(_ thread: CodexThread, pinned: Bool, baseURL: String, token: String) async {
        do {
            try await client.setThreadPinned(threadID: thread.id, pinned: pinned, baseURL: baseURL, token: token)
            await loadThreads(baseURL: baseURL, token: token)
        } catch {
            report(error)
        }
    }

    func loadAccountStatus(baseURL: String, token: String) async {
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !isLoadingAccountStatus else { return }
        isLoadingAccountStatus = true
        defer { isLoadingAccountStatus = false }
        do {
            let response = try await client.accountStatus(baseURL: baseURL, token: token)
            applyAccountStatus(response)
            await flushQueuedPromptsIfPossible(baseURL: baseURL, token: token)
        } catch {
            report(error)
        }
    }

    func pollAccountStatus(baseURL: String, token: String) async {
        await loadAccountStatus(baseURL: baseURL, token: token)

        while !Task.isCancelled {
            do {
                try await Task.sleep(nanoseconds: 30_000_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await loadAccountStatus(baseURL: baseURL, token: token)
        }
    }

    func switchAccount(named name: String, baseURL: String, token: String) async -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return false }
        guard switchingAccountName == nil else { return false }
        switchingAccountName = trimmedName
        defer { switchingAccountName = nil }
        do {
            let response = try await client.switchAccount(name: trimmedName, baseURL: baseURL, token: token)
            applyAccountStatus(response)
            await loadThreads(baseURL: baseURL, token: token)
            await flushQueuedPromptsIfPossible(baseURL: baseURL, token: token)
            return true
        } catch {
            report(error)
            return false
        }
    }

    func resetRateLimit(for name: String, baseURL: String, token: String) async -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard !trimmedName.isEmpty else { return false }
        guard resettingRateLimitAccountName == nil else { return false }
        resettingRateLimitAccountName = trimmedName
        defer { resettingRateLimitAccountName = nil }
        do {
            let response = try await client.consumeRateLimitResetCredit(accountName: trimmedName, baseURL: baseURL, token: token)
            applyAccountStatus(response)
            await flushQueuedPromptsIfPossible(baseURL: baseURL, token: token)
            errorMessage = "Rate limit reset requested for \(trimmedName)."
            return true
        } catch {
            report(error)
            return false
        }
    }

    func refreshAccountAuth(named name: String, accessToken: String, baseURL: String, token: String) async -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAccessToken = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedAccessToken.isEmpty else { return false }
        guard refreshingAuthAccountName == nil else { return false }
        refreshingAuthAccountName = trimmedName
        defer { refreshingAuthAccountName = nil }
        do {
            let response = try await client.refreshAccountAuth(
                name: trimmedName,
                accessToken: trimmedAccessToken,
                baseURL: baseURL,
                token: token
            )
            applyAccountStatus(response)
            await loadThreads(baseURL: baseURL, token: token)
            await flushQueuedPromptsIfPossible(baseURL: baseURL, token: token)
            return true
        } catch {
            report(error)
            return false
        }
    }

    func startRemoteAccountLogin(named name: String, baseURL: String, token: String) async -> RemoteAccountLoginSession? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }
        guard refreshingAuthAccountName == nil else { return nil }
        refreshingAuthAccountName = trimmedName
        do {
            let session = try await client.startRemoteAccountLogin(name: trimmedName, baseURL: baseURL, token: token)
            return session
        } catch {
            refreshingAuthAccountName = nil
            report(error)
            return nil
        }
    }

    func startRemoteNewAccountLogin(named name: String, baseURL: String, token: String) async -> RemoteAccountLoginSession? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }
        guard addingAccountName == nil else { return nil }
        addingAccountName = trimmedName
        do {
            let session = try await client.startRemoteNewAccountLogin(name: trimmedName, baseURL: baseURL, token: token)
            addingAccountName = session.accountName
            return session
        } catch {
            addingAccountName = nil
            report(error)
            return nil
        }
    }

    func completeRemoteAccountLogin(sessionID: String, callbackURL: String, baseURL: String, token: String) async -> Bool {
        do {
            let response = try await client.completeRemoteAccountLogin(
                sessionID: sessionID,
                callbackURL: callbackURL,
                baseURL: baseURL,
                token: token
            )
            refreshingAuthAccountName = nil
            applyAccountStatus(response)
            await loadThreads(baseURL: baseURL, token: token)
            await flushQueuedPromptsIfPossible(baseURL: baseURL, token: token)
            return true
        } catch {
            refreshingAuthAccountName = nil
            report(error)
            return false
        }
    }

    func completeRemoteNewAccountLogin(sessionID: String, callbackURL: String, baseURL: String, token: String) async -> Bool {
        do {
            let response = try await client.completeRemoteAccountLogin(
                sessionID: sessionID,
                callbackURL: callbackURL,
                baseURL: baseURL,
                token: token
            )
            addingAccountName = nil
            applyAccountStatus(response)
            await loadThreads(baseURL: baseURL, token: token)
            await flushQueuedPromptsIfPossible(baseURL: baseURL, token: token)
            return true
        } catch {
            addingAccountName = nil
            report(error)
            return false
        }
    }

    func cancelRemoteAccountLogin(sessionID: String, baseURL: String, token: String) async {
        do {
            try await client.cancelRemoteAccountLogin(sessionID: sessionID, baseURL: baseURL, token: token)
        } catch {
            report(error)
        }
        refreshingAuthAccountName = nil
    }

    func startRemoteMCPLogin(named name: String, baseURL: String, token: String) async -> RemoteAccountLoginSession? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }
        do {
            return try await client.startRemoteMCPLogin(name: trimmedName, baseURL: baseURL, token: token)
        } catch {
            report(error)
            return nil
        }
    }

    func completeRemoteMCPLogin(sessionID: String, callbackURL: String, baseURL: String, token: String) async -> Bool {
        do {
            let response = try await client.completeRemoteMCPLogin(
                sessionID: sessionID,
                callbackURL: callbackURL,
                baseURL: baseURL,
                token: token
            )
            applyAccountStatus(response)
            return true
        } catch {
            report(error)
            return false
        }
    }

    func cancelRemoteMCPLogin(sessionID: String, baseURL: String, token: String) async {
        do {
            try await client.cancelRemoteMCPLogin(sessionID: sessionID, baseURL: baseURL, token: token)
        } catch {
            report(error)
        }
    }

    func cancelRemoteNewAccountLogin(sessionID: String, baseURL: String, token: String) async {
        do {
            try await client.cancelRemoteAccountLogin(sessionID: sessionID, baseURL: baseURL, token: token)
        } catch {
            report(error)
        }
        addingAccountName = nil
    }

    func timelineMessages(for threadID: String) -> [CodexMessage] {
        var messages = messagesByThreadID[threadID] ?? []
        if let queuedPrompt = queuedPromptsByThreadID[threadID],
           !messages.contains(where: { $0.role == "user" && $0.text == queuedPrompt.displayText }) {
            messages.append(CodexMessage(
                id: "queued-\(queuedPrompt.id.uuidString)",
                role: "user",
                text: "Queued until account usage is available\n\n\(queuedPrompt.displayText)",
                timestamp: nil
            ))
        }
        guard let pendingUserMessage = pendingUserMessagesByThreadID[threadID] else {
            return messages
        }
        if messages.contains(where: { $0.role == pendingUserMessage.role && $0.text == pendingUserMessage.text }) {
            return messages
        }
        return messages + [pendingUserMessage]
    }

    func activeJob(for threadID: String) -> CodexJob? {
        activeJobsByThreadID[threadID]
    }

    func reasoningLevel(for thread: CodexThread) -> ReasoningLevel {
        if let stored = reasoningEffortByThreadID[thread.id] {
            return stored
        }
        return ReasoningLevel(apiValue: thread.reasoningEffort) ?? .keep
    }

    func setReasoningLevel(_ level: ReasoningLevel, for threadID: String) {
        reasoningEffortByThreadID[threadID] = level
        ReasoningPreferenceStore.save(reasoningEffortByThreadID)
    }

    func send(
        prompt: String,
        attachments: [PendingAttachment],
        reasoningLevel: ReasoningLevel,
        to thread: CodexThread,
        baseURL: String,
        token: String
    ) async -> Bool {
        if accountStatuses.isEmpty {
            await refreshAccountStatusForQueueDecision(baseURL: baseURL, token: token)
        }
        if shouldQueuePromptBeforeSending() {
            queuePrompt(prompt: prompt, attachments: attachments, reasoningLevel: reasoningLevel, threadID: thread.id)
            return true
        }

        return await sendNow(
            prompt: prompt,
            attachments: attachments,
            reasoningLevel: reasoningLevel,
            to: thread,
            baseURL: baseURL,
            token: token,
            requeueOnAccountUnavailable: true
        )
    }

    private func sendNow(
        prompt: String,
        attachments: [PendingAttachment],
        reasoningLevel: ReasoningLevel,
        to thread: CodexThread,
        baseURL: String,
        token: String,
        requeueOnAccountUnavailable: Bool
    ) async -> Bool {
        pendingUserMessagesByThreadID[thread.id] = CodexMessage(
            id: "pending-\(UUID().uuidString)",
            role: "user",
            text: outgoingMessageText(prompt: prompt, attachments: attachments),
            timestamp: nil
        )

        do {
            let response = try await client.send(
                prompt: prompt,
                attachments: attachments,
                reasoningEffort: reasoningLevel.apiValue,
                threadID: thread.id,
                baseURL: baseURL,
                token: token
            )
            applyGatewayState(response)
            submittedPromptsByJobID[response.job.id] = QueuedPrompt(
                threadID: thread.id,
                prompt: prompt,
                attachments: attachments.map(QueuedAttachment.init),
                reasoningLevel: reasoningLevel
            )
            setActiveJob(response.job, fallbackThreadID: thread.id)
            startPolling(jobID: response.job.id, thread: thread, baseURL: baseURL, token: token)
            return true
        } catch {
            pendingUserMessagesByThreadID[thread.id] = nil
            if requeueOnAccountUnavailable, isAccountUnavailableError(error) {
                queuePrompt(prompt: prompt, attachments: attachments, reasoningLevel: reasoningLevel, threadID: thread.id)
                return true
            }
            report(error)
            return false
        }
    }

    func steer(text: String, job: CodexJob, thread: CodexThread, baseURL: String, token: String) async -> Bool {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return false }
        do {
            let response = try await client.steer(text: trimmedText, jobID: job.id, threadID: thread.id, baseURL: baseURL, token: token)
            applyGatewayState(response)
            setActiveJob(response.job, fallbackThreadID: thread.id)
            return true
        } catch {
            report(error)
            return false
        }
    }

    func stop(job: CodexJob, thread: CodexThread, baseURL: String, token: String) async {
        do {
            let response = try await client.stop(jobID: job.id, threadID: thread.id, baseURL: baseURL, token: token)
            applyGatewayState(response)
            setActiveJob(response.job, fallbackThreadID: thread.id)
        } catch {
            report(error)
        }
    }

    func createThread(prompt: String, cwd: String, createWorkspace: Bool = false, reasoningLevel: ReasoningLevel, baseURL: String, token: String) async -> CodexThread? {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCWD = cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty, !trimmedCWD.isEmpty else { return nil }
        isCreatingThread = true
        defer { isCreatingThread = false }

        do {
            let response = try await client.createThread(
                prompt: trimmedPrompt,
                cwd: trimmedCWD,
                createWorkspace: createWorkspace,
                reasoningEffort: reasoningLevel.apiValue,
                baseURL: baseURL,
                token: token
            )
            applyGatewayState(response)
            setActiveJob(response.job, fallbackThreadID: "")
            return await waitForCreatedThread(
                jobID: response.job.id,
                prompt: trimmedPrompt,
                cwd: trimmedCWD,
                reasoningLevel: reasoningLevel,
                baseURL: baseURL,
                token: token
            )
        } catch {
            report(error)
            return nil
        }
    }

    private func waitForCreatedThread(
        jobID: String,
        prompt: String,
        cwd: String,
        reasoningLevel: ReasoningLevel,
        baseURL: String,
        token: String
    ) async -> CodexThread? {
        while true {
            try? await Task.sleep(for: .seconds(1))
            do {
                let response = try await client.job(id: jobID, baseURL: baseURL, token: token)
                applyGatewayState(response)
                setActiveJob(response.job, fallbackThreadID: "")

                if !response.job.threadId.isEmpty {
                    let threadID = response.job.threadId
                    activeJobsByThreadID[""] = nil
                    if reasoningLevel != .keep {
                        setReasoningLevel(reasoningLevel, for: threadID)
                    }
                    setActiveJob(response.job, fallbackThreadID: threadID)
                    pendingUserMessagesByThreadID[threadID] = CodexMessage(
                        id: "pending-\(UUID().uuidString)",
                        role: "user",
                        text: prompt,
                        timestamp: nil
                    )
                    await loadThreads(baseURL: baseURL, token: token)
                    let thread = threads.first { $0.id == threadID } ?? CodexThread.newThreadStub(id: threadID, cwd: cwd)
                    startPolling(jobID: jobID, thread: thread, baseURL: baseURL, token: token)
                    return thread
                }

                if response.job.status != "running" {
                    if let error = response.job.error, !error.isEmpty {
                        errorMessage = response.job.errorSummary
                    } else {
                        errorMessage = "Codex did not create a thread"
                    }
                    return nil
                }
            } catch {
                if isMissingJobError(error) {
                    activeJobsByThreadID[""] = nil
                    return nil
                }
                report(error)
                return nil
            }
        }
    }

    private func startPolling(jobID: String, thread: CodexThread, baseURL: String, token: String) {
        guard !pollingJobIDs.contains(jobID) else { return }
        pollingJobIDs.insert(jobID)
        Task {
            await poll(jobID: jobID, thread: thread, baseURL: baseURL, token: token)
        }
    }

    private func poll(jobID: String, thread: CodexThread, baseURL: String, token: String) async {
        defer {
            pollingJobIDs.remove(jobID)
        }
        var missingJobAttempts = 0
        var transientNetworkAttempts = 0
        while true {
            try? await Task.sleep(for: .seconds(2))
            do {
                let response = try await client.job(
                    id: jobID,
                    afterEventSeq: jobEventCursorsByJobID[jobID],
                    baseURL: baseURL,
                    token: token
                )
                applyGatewayState(response)
                missingJobAttempts = 0
                transientNetworkAttempts = 0
                let currentThreadID = response.job.threadId.isEmpty ? thread.id : response.job.threadId
                setActiveJob(response.job, fallbackThreadID: currentThreadID, mergeEvents: true)
                if response.job.status != "running" {
                    let currentThread = currentThreadID == thread.id ? thread : CodexThread.newThreadStub(id: currentThreadID, cwd: thread.cwd)
                    await loadThread(currentThread, baseURL: baseURL, token: token)
                    pendingUserMessagesByThreadID[currentThreadID] = nil
                    if response.job.status == "failed",
                       isAccountUnavailableMessage(response.job.errorSummary),
                       let queuedPrompt = submittedPromptsByJobID[response.job.id] {
                        queuedPromptsByThreadID[currentThreadID] = queuedPrompt
                        QueuedPromptStore.save(queuedPromptsByThreadID)
                        errorMessage = "Prompt queued. It will be sent when the active account has fresh auth and usage available."
                    }
                    submittedPromptsByJobID[response.job.id] = nil
                    if response.job.isTerminal {
                        activeJobsByThreadID[currentThreadID] = nil
                    }
                    return
                }
            } catch {
                if isTransientNetworkError(error) {
                    transientNetworkAttempts += 1
                    let delay = min(10, 2 + transientNetworkAttempts)
                    try? await Task.sleep(for: .seconds(delay))
                    continue
                }
                if isMissingJobError(error) {
                    missingJobAttempts += 1
                    if await recoverPollingJob(for: thread, baseURL: baseURL, token: token) {
                        missingJobAttempts = 0
                        continue
                    }
                    if missingJobAttempts < 5 {
                        continue
                    }
                    await loadThread(thread, baseURL: baseURL, token: token)
                    clearMissingJob(jobID: jobID, fallbackThreadID: thread.id)
                    errorMessage = "Live stream disconnected. Loaded the latest saved messages."
                    return
                }
                report(error)
                return
            }
        }
    }

    private func recoverPollingJob(for thread: CodexThread, baseURL: String, token: String) async -> Bool {
        do {
            let response = try await client.activeJob(threadID: thread.id, baseURL: baseURL, token: token)
            applyGatewayState(response)
            guard let job = response.job else {
                return false
            }
            setActiveJob(job, fallbackThreadID: thread.id)
            return job.status == "running"
        } catch {
            return false
        }
    }

    private func recoverCompletedJob(_ previousJob: CodexJob, thread: CodexThread, baseURL: String, token: String) async -> Bool {
        do {
            let response = try await client.job(id: previousJob.id, baseURL: baseURL, token: token)
            applyGatewayState(response)
            let currentThreadID = response.job.threadId.isEmpty ? thread.id : response.job.threadId
            setActiveJob(response.job, fallbackThreadID: currentThreadID)
            if response.job.status == "running" {
                startPolling(jobID: response.job.id, thread: thread, baseURL: baseURL, token: token)
                return true
            }

            let currentThread = currentThreadID == thread.id ? thread : CodexThread.newThreadStub(id: currentThreadID, cwd: thread.cwd)
            await loadThread(currentThread, baseURL: baseURL, token: token)
            pendingUserMessagesByThreadID[currentThreadID] = nil
            if response.job.status == "failed",
               isAccountUnavailableMessage(response.job.errorSummary),
               let queuedPrompt = submittedPromptsByJobID[response.job.id] {
                queuedPromptsByThreadID[currentThreadID] = queuedPrompt
                QueuedPromptStore.save(queuedPromptsByThreadID)
                errorMessage = "Prompt queued. It will be sent when the active account has fresh auth and usage available."
            }
            submittedPromptsByJobID[response.job.id] = nil
            if response.job.isTerminal {
                activeJobsByThreadID[currentThreadID] = nil
            }
            return true
        } catch {
            return false
        }
    }

    private func report(_ error: Error) {
        guard !isBenignCancellationError(error) else { return }
        guard !isMissingJobError(error) else { return }
        errorMessage = GatewayErrorPresenter.message(for: error)
    }

    private func refreshAccountStatusForQueueDecision(baseURL: String, token: String) async {
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            let response = try await client.accountStatus(baseURL: baseURL, token: token)
            applyAccountStatus(response)
        } catch {
            report(error)
        }
    }

    private func queuePrompt(prompt: String, attachments: [PendingAttachment], reasoningLevel: ReasoningLevel, threadID: String) {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty || !attachments.isEmpty else { return }
        let queuedPrompt = QueuedPrompt(
            threadID: threadID,
            prompt: prompt,
            attachments: attachments.map(QueuedAttachment.init),
            reasoningLevel: reasoningLevel
        )
        queuedPromptsByThreadID[threadID] = queuedPrompt
        QueuedPromptStore.save(queuedPromptsByThreadID)
        pendingUserMessagesByThreadID[threadID] = nil
        errorMessage = "Prompt queued. It will be sent when the active account has fresh auth and usage available."
    }

    private func flushQueuedPromptsIfPossible(baseURL: String, token: String) async {
        guard usableActiveAccount != nil else { return }
        let queuedItems = queuedPromptsByThreadID.values.sorted { $0.createdAt < $1.createdAt }
        for queuedPrompt in queuedItems {
            guard activeJobsByThreadID[queuedPrompt.threadID]?.status != "running" else { continue }
            guard let thread = threads.first(where: { $0.id == queuedPrompt.threadID }) else { continue }
            queuedPromptsByThreadID[queuedPrompt.threadID] = nil
            QueuedPromptStore.save(queuedPromptsByThreadID)
            let didSend = await sendNow(
                prompt: queuedPrompt.prompt,
                attachments: queuedPrompt.pendingAttachments,
                reasoningLevel: queuedPrompt.reasoningLevel,
                to: thread,
                baseURL: baseURL,
                token: token,
                requeueOnAccountUnavailable: true
            )
            if !didSend {
                queuedPromptsByThreadID[queuedPrompt.threadID] = queuedPrompt
                QueuedPromptStore.save(queuedPromptsByThreadID)
                return
            }
        }
    }

    private func shouldQueuePromptBeforeSending() -> Bool {
        guard !accountStatuses.isEmpty else { return false }
        return usableActiveAccount == nil
    }

    private var usableActiveAccount: AccountUsageStatus? {
        accountStatuses.first { $0.isActive && $0.isUsableForNewTurn }
    }

    private func isAccountUnavailableError(_ error: Error) -> Bool {
        guard let gatewayError = error as? GatewayError else { return false }
        switch gatewayError {
        case .gateway(let payload):
            return payload.code == "auth_stale" || payload.code == "account_unavailable" || isAccountUnavailableMessage(payload.message)
        case .server(let message):
            return isAccountUnavailableMessage(message)
        default:
            return false
        }
    }

    private func isAccountUnavailableMessage(_ message: String) -> Bool {
        let normalized = message.lowercased()
        return normalized.contains("usage limit")
            || normalized.contains("rate limit")
            || normalized.contains("auth is stale")
            || normalized.contains("auth needs refresh")
            || normalized.contains("authentication")
            || normalized.contains("token")
            || normalized.contains("refresh the")
            || normalized.contains("login before starting")
            || normalized.contains("quota")
            || normalized.contains("429")
    }

    private func clearMissingJob(jobID: String, fallbackThreadID: String) {
        let threadID = activeJobsByThreadID.first { $0.value.id == jobID }?.key ?? fallbackThreadID
        activeJobsByThreadID[threadID] = nil
        pendingUserMessagesByThreadID[threadID] = nil
    }

    private func isMissingJobError(_ error: Error) -> Bool {
        if let gatewayError = error as? GatewayError {
            switch gatewayError {
            case .http(let status):
                return status == 404
            case .gateway(let payload):
                return payload.code == "job_not_found"
            case .server(let message):
                return message == "Job not found"
            default:
                return false
            }
        }
        return false
    }

    private func applyGatewayState(_ response: JobResponse) {
        if let active = response.activeAccount, !active.isEmpty {
            activeAccount = active
        }
    }

    private func applyGatewayState(_ response: ActiveJobResponse) {
        if let active = response.activeAccount, !active.isEmpty {
            activeAccount = active
        }
    }

    private func applyAccountStatus(_ response: AccountStatusResponse) {
        activeAccount = response.activeAccount
        accountStatuses = response.accounts
        pluginStatuses = response.plugins ?? []
        mcpServers = response.mcpServers ?? []
        pluginSyncStatus = response.pluginSync
        accountStatusGeneratedAt = response.generatedAt
    }

    func applyAccountStatusFromConnectionTest(_ response: AccountStatusResponse) {
        applyAccountStatus(response)
    }

    private func setActiveJob(_ job: CodexJob, fallbackThreadID: String, mergeEvents: Bool = false) {
        let threadID = job.threadId.isEmpty ? fallbackThreadID : job.threadId
        let previousStatus = activeJobsByThreadID[threadID]?.status
        let storedJob = mergeEvents ? job.mergingEvents(from: activeJobsByThreadID[threadID]) : job
        activeJobsByThreadID[threadID] = storedJob
        updateEventCursor(for: storedJob)
        if job.status == "running", previousStatus != "running" {
            Task {
                await turnCompletionNotifier.requestAuthorizationIfNeeded()
            }
        }
        if let notification = turnNotificationTracker.notification(
            for: job,
            previousStatus: previousStatus,
            serverNotificationSentAt: storedJob.completionNotificationSentAt,
            threadTitle: notificationThreadTitle(for: threadID)
        ) {
            Task {
                await turnCompletionNotifier.deliver(notification)
            }
        }
    }

    private func updateEventCursor(for job: CodexJob) {
        let eventCursor = job.events?.compactMap(\.eventSeq).max() ?? 0
        let cursor = max(job.eventCursor ?? 0, eventCursor)
        if cursor > 0 {
            jobEventCursorsByJobID[job.id] = cursor
        }
        if job.status != "running" {
            jobEventCursorsByJobID[job.id] = nil
        }
    }

    private func notificationThreadTitle(for threadID: String) -> String {
        let title = threads.first { $0.id == threadID }?.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let title, !title.isEmpty {
            return title
        }
        return "Codex thread"
    }

    private func outgoingMessageText(prompt: String, attachments: [PendingAttachment]) -> String {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !attachments.isEmpty else {
            return trimmedPrompt
        }

        let attachmentNames = attachments.map(\.filename).joined(separator: ", ")
        if trimmedPrompt.isEmpty {
            return "Attached: \(attachmentNames)"
        }
        return "\(trimmedPrompt)\n\nAttached: \(attachmentNames)"
    }
}

struct CodexGatewayClient {
    func threads(baseURL: String, token: String) async throws -> ThreadsResponse {
        try await get("/api/threads", baseURL: baseURL, token: token)
    }

    func accountStatus(baseURL: String, token: String) async throws -> AccountStatusResponse {
        try await get("/api/accounts", baseURL: baseURL, token: token)
    }

    func switchAccount(name: String, baseURL: String, token: String) async throws -> AccountStatusResponse {
        try await request(
            "/api/accounts/switch",
            method: "POST",
            body: SwitchAccountRequest(name: name),
            baseURL: baseURL,
            token: token
        )
    }

    func consumeRateLimitResetCredit(accountName: String, baseURL: String, token: String) async throws -> AccountStatusResponse {
        try await request(
            "/api/accounts/rate-limit-reset",
            method: "POST",
            body: RateLimitResetRequest(name: accountName),
            baseURL: baseURL,
            token: token
        )
    }

    func refreshAccountAuth(name: String, accessToken: String, baseURL: String, token: String) async throws -> AccountStatusResponse {
        try await request(
            "/api/accounts/auth/refresh",
            method: "POST",
            body: RefreshAccountAuthRequest(name: name, accessToken: accessToken),
            baseURL: baseURL,
            token: token
        )
    }

    func startRemoteAccountLogin(name: String, baseURL: String, token: String) async throws -> RemoteAccountLoginSession {
        try await request(
            "/api/accounts/auth/login/start",
            method: "POST",
            body: StartRemoteAccountLoginRequest(name: name),
            baseURL: baseURL,
            token: token
        )
    }

    func startRemoteNewAccountLogin(name: String, baseURL: String, token: String) async throws -> RemoteAccountLoginSession {
        try await request(
            "/api/accounts/auth/login/add/start",
            method: "POST",
            body: StartRemoteAccountLoginRequest(name: name),
            baseURL: baseURL,
            token: token
        )
    }

    func completeRemoteAccountLogin(sessionID: String, callbackURL: String, baseURL: String, token: String) async throws -> AccountStatusResponse {
        try await request(
            "/api/accounts/auth/login/callback",
            method: "POST",
            body: CompleteRemoteAccountLoginRequest(sessionId: sessionID, callbackURL: callbackURL),
            baseURL: baseURL,
            token: token
        )
    }

    func cancelRemoteAccountLogin(sessionID: String, baseURL: String, token: String) async throws {
        let _: OKResponse = try await request(
            "/api/accounts/auth/login/cancel",
            method: "POST",
            body: CancelRemoteAccountLoginRequest(sessionId: sessionID),
            baseURL: baseURL,
            token: token
        )
    }

    func startRemoteMCPLogin(name: String, baseURL: String, token: String) async throws -> RemoteAccountLoginSession {
        try await request(
            "/api/mcp/login/start",
            method: "POST",
            body: MCPLoginRequest(name: name),
            baseURL: baseURL,
            token: token
        )
    }

    func completeRemoteMCPLogin(sessionID: String, callbackURL: String, baseURL: String, token: String) async throws -> AccountStatusResponse {
        try await request(
            "/api/mcp/login/callback",
            method: "POST",
            body: CompleteRemoteAccountLoginRequest(sessionId: sessionID, callbackURL: callbackURL),
            baseURL: baseURL,
            token: token
        )
    }

    func cancelRemoteMCPLogin(sessionID: String, baseURL: String, token: String) async throws {
        let _: OKResponse = try await request(
            "/api/mcp/login/cancel",
            method: "POST",
            body: CancelRemoteAccountLoginRequest(sessionId: sessionID),
            baseURL: baseURL,
            token: token
        )
    }

    func thread(id: String, baseURL: String, token: String) async throws -> ThreadResponse {
        try await get("/api/threads/\(id)", baseURL: baseURL, token: token)
    }

    func job(id: String, afterEventSeq: Int? = nil, baseURL: String, token: String) async throws -> JobResponse {
        if let afterEventSeq {
            return try await get("/api/jobs/\(id)?afterEventSeq=\(afterEventSeq)", baseURL: baseURL, token: token)
        }
        return try await get("/api/jobs/\(id)", baseURL: baseURL, token: token)
    }

    func activeJob(threadID: String, baseURL: String, token: String) async throws -> ActiveJobResponse {
        let encodedThreadID = threadID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? threadID
        return try await get("/api/jobs/active?threadId=\(encodedThreadID)", baseURL: baseURL, token: token)
    }

    func send(
        prompt: String,
        attachments: [PendingAttachment],
        reasoningEffort: String?,
        threadID: String,
        baseURL: String,
        token: String
    ) async throws -> JobResponse {
        try await request(
            "/api/threads/\(threadID)/turns",
            method: "POST",
            body: TurnRequest(
                prompt: prompt,
                attachments: attachments.map(GatewayAttachment.init),
                reasoningEffort: reasoningEffort
            ),
            baseURL: baseURL,
            token: token
        )
    }

    func steer(text: String, jobID: String, threadID: String, baseURL: String, token: String) async throws -> JobResponse {
        try await request(
            "/api/threads/\(threadID)/steer",
            method: "POST",
            body: SteerRequest(jobId: jobID, text: text),
            baseURL: baseURL,
            token: token
        )
    }

    func stop(jobID: String, threadID: String, baseURL: String, token: String) async throws -> JobResponse {
        try await request(
            "/api/threads/\(threadID)/stop",
            method: "POST",
            body: StopTurnRequest(jobId: jobID),
            baseURL: baseURL,
            token: token
        )
    }

    func createThread(prompt: String, cwd: String, createWorkspace: Bool = false, reasoningEffort: String?, baseURL: String, token: String) async throws -> JobResponse {
        try await request(
            "/api/threads",
            method: "POST",
            body: NewThreadRequest(prompt: prompt, cwd: cwd, attachments: [], createWorkspace: createWorkspace, reasoningEffort: reasoningEffort),
            baseURL: baseURL,
            token: token
        )
    }

    func renameThread(threadID: String, name: String, baseURL: String, token: String) async throws {
        let _: OKResponse = try await request(
            "/api/threads/\(threadID)/rename",
            method: "POST",
            body: RenameThreadRequest(name: name),
            baseURL: baseURL,
            token: token
        )
    }

    func archiveThread(threadID: String, baseURL: String, token: String) async throws {
        let _: OKResponse = try await request(
            "/api/threads/\(threadID)/archive",
            method: "POST",
            body: Optional<[String: String]>.none,
            baseURL: baseURL,
            token: token
        )
    }

    func setThreadPinned(threadID: String, pinned: Bool, baseURL: String, token: String) async throws {
        let _: OKResponse = try await request(
            "/api/threads/\(threadID)/pin",
            method: "POST",
            body: PinThreadRequest(pinned: pinned),
            baseURL: baseURL,
            token: token
        )
    }

    func downloadRemoteFile(path: String, baseURL: String, token: String) async throws -> URL {
        guard let root = URL(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw GatewayError.invalidURL
        }
        guard var components = URLComponents(url: root, resolvingAgainstBaseURL: false) else {
            throw GatewayError.invalidURL
        }
        components.path = "/api/files/download"
        components.queryItems = [URLQueryItem(name: "path", value: path)]
        guard let url = components.url else {
            throw GatewayError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 120
        request.setValue("Bearer \(token.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")

        let (temporaryURL, response) = try await GatewayURLSession.shared.download(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GatewayError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw GatewayError.http(http.statusCode)
        }

        let fileManager = FileManager.default
        let previewDirectory = fileManager.temporaryDirectory.appendingPathComponent("codex-phone-previews", isDirectory: true)
        try fileManager.createDirectory(at: previewDirectory, withIntermediateDirectories: true)
        let fallbackFilename = URL(fileURLWithPath: path).lastPathComponent.isEmpty ? "Codex File" : URL(fileURLWithPath: path).lastPathComponent
        let filename = response.suggestedFilename ?? fallbackFilename
        let destination = previewDirectory.appendingPathComponent("\(UUID().uuidString)-\(filename)")
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: temporaryURL, to: destination)
        return destination
    }

    func startLocalWebSession(url: URL, baseURL: String, token: String) async throws -> URL {
        let response: LocalWebSessionResponse = try await request(
            "/api/local-web/sessions",
            method: "POST",
            body: LocalWebSessionRequest(url: url.absoluteString),
            baseURL: baseURL,
            token: token
        )
        guard let sessionURL = localWebSessionURL(path: response.path, baseURL: baseURL) else {
            throw GatewayError.invalidResponse
        }
        return sessionURL
    }

    private func get<T: Decodable>(_ path: String, baseURL: String, token: String) async throws -> T {
        try await request(path, method: "GET", body: Optional<[String: String]>.none, baseURL: baseURL, token: token)
    }

    private func request<T: Decodable, Body: Encodable>(
        _ path: String,
        method: String,
        body: Body?,
        baseURL: String,
        token: String
    ) async throws -> T {
        guard let root = GatewayEndpoint.baseURL(from: baseURL) else {
            throw GatewayError.invalidURL
        }
        guard let url = URL(string: path, relativeTo: root)?.absoluteURL else {
            throw GatewayError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = method == "GET" ? 30 : 120
        request.setValue("Bearer \(token.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        var attempt = 0
        while true {
            do {
                let (data, response) = try await GatewayURLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw GatewayError.invalidResponse
                }
                guard (200..<300).contains(http.statusCode) else {
                    if let payload = try? JSONDecoder().decode(GatewayErrorPayload.self, from: data) {
                        throw GatewayError.gateway(payload.error)
                    }
                    if let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) {
                        throw GatewayError.server(envelope.error)
                    }
                    throw GatewayError.http(http.statusCode)
                }
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                if method == "GET", !Task.isCancelled, isTransientNetworkError(error), attempt < 3 {
                    attempt += 1
                    try await Task.sleep(for: .seconds(attempt))
                    continue
                }
                throw error
            }
        }
    }
}

struct ThreadsResponse: Decodable {
    let activeAccount: String
    let threads: [CodexThread]
}

struct ThreadResponse: Decodable {
    let activeAccount: String
    let thread: CodexThread
}

struct JobResponse: Decodable {
    let activeAccount: String?
    let appServerAuth: AppServerAuthStatus?
    let job: CodexJob
}

struct ActiveJobResponse: Decodable {
    let activeAccount: String?
    let appServerAuth: AppServerAuthStatus?
    let job: CodexJob?
}

struct OKResponse: Decodable {
    let ok: Bool
}

struct AccountStatusResponse: Decodable {
    let generatedAt: Int
    let activeAccount: String
    let appServerAuth: AppServerAuthStatus?
    let plugins: [PluginStatus]?
    let mcpServers: [MCPServerStatus]?
    let pluginSync: PluginSyncStatus?
    let accounts: [AccountUsageStatus]
}

struct AppServerAuthStatus: Decodable, Hashable {
    let clientRunning: Bool
    let inSync: Bool
    let restartDeferred: Bool
}

struct TurnRequest: Encodable {
    let prompt: String
    let attachments: [GatewayAttachment]
    let reasoningEffort: String?
}

struct SteerRequest: Encodable {
    let jobId: String
    let text: String
}

struct StopTurnRequest: Encodable {
    let jobId: String
}

struct NewThreadRequest: Encodable {
    let prompt: String
    let cwd: String
    let attachments: [GatewayAttachment]
    let createWorkspace: Bool
    let reasoningEffort: String?
}

struct SwitchAccountRequest: Encodable {
    let name: String
}

struct RateLimitResetRequest: Encodable {
    let name: String
}

struct RefreshAccountAuthRequest: Encodable {
    let name: String
    let accessToken: String
}

struct RemoteAccountLoginSession: Decodable {
    let sessionId: String
    let accountName: String
    let status: String
    let authUrl: String
    let createdAt: Int
}

struct StartRemoteAccountLoginRequest: Encodable {
    let name: String
}

struct CompleteRemoteAccountLoginRequest: Encodable {
    let sessionId: String
    let callbackURL: String
}

struct PluginStatus: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let marketplace: String
    let displayName: String
    let enabled: Bool
    let installed: Bool
    let status: String
    let description: String

    var statusText: String {
        if !enabled {
            return "Disabled"
        }
        if !installed {
            return "Configured, not cached"
        }
        return "Enabled"
    }
}

struct PluginSyncStatus: Decodable, Hashable {
    let source: String
    let target: String
    let repairedAt: Int
    let sourceAvailable: Bool
    let addedPlugins: [String]
    let addedMcpServers: [String]
    let missingConnectorEnvVars: [String]

    var hasVisibleStatus: Bool {
        !sourceAvailable || !addedPlugins.isEmpty || !addedMcpServers.isEmpty || !missingConnectorEnvVars.isEmpty
    }

    var hasWarnings: Bool {
        !sourceAvailable || !missingConnectorEnvVars.isEmpty
    }

    var title: String {
        if !sourceAvailable {
            return "Plugin sync source missing"
        }
        if !addedPlugins.isEmpty || !addedMcpServers.isEmpty {
            return "Plugin config repaired"
        }
        if !missingConnectorEnvVars.isEmpty {
            return "Connector token missing"
        }
        return "Plugin config synced"
    }

    var detailText: String {
        if !addedPlugins.isEmpty || !addedMcpServers.isEmpty {
            let pluginText = addedPlugins.isEmpty ? nil : "\(addedPlugins.count) plugin\(addedPlugins.count == 1 ? "" : "s")"
            let serverText = addedMcpServers.isEmpty ? nil : "\(addedMcpServers.count) connector\(addedMcpServers.count == 1 ? "" : "s")"
            return [pluginText, serverText].compactMap { $0 }.joined(separator: " and ") + " added to the desktop profile."
        }
        if !sourceAvailable {
            return "The mobile Codex profile config was not found on the Mac."
        }
        return "The desktop profile has the shared plugin and connector declarations."
    }

    var warningText: String {
        if missingConnectorEnvVars.isEmpty {
            return ""
        }
        return "Missing gateway env: " + missingConnectorEnvVars.joined(separator: ", ")
    }
}

struct MCPServerStatus: Decodable, Identifiable, Hashable {
    var id: String { name }

    let name: String
    let displayName: String
    let status: String
    let auth: String
    let needsLogin: Bool
    let canReconnect: Bool
    let lastAuthWarningAt: Int?
    let lastAuthWarningReason: String

    var statusText: String {
        if needsLogin {
            return "Needs reconnect"
        }
        if !auth.isEmpty {
            return auth
        }
        return status.isEmpty ? "Unknown" : status
    }
}

struct MCPLoginRequest: Encodable {
    let name: String
}

struct CancelRemoteAccountLoginRequest: Encodable {
    let sessionId: String
}

struct NotificationDeviceRegistrationRequest: Encodable {
    let token: String
    let environment: String
    let bundleId: String
    let platform: String
}

struct RenameThreadRequest: Encodable {
    let name: String
}

struct PinThreadRequest: Encodable {
    let pinned: Bool
}

struct LocalWebSessionRequest: Encodable {
    let url: String
}

struct LocalWebSessionResponse: Decodable {
    let sessionId: String
    let path: String
    let targetOrigin: String
    let expiresAt: Int
}

struct QueuedPrompt: Codable, Identifiable, Hashable {
    let id: UUID
    let threadID: String
    let prompt: String
    let attachments: [QueuedAttachment]
    let reasoningLevel: ReasoningLevel
    let createdAt: Int

    init(
        id: UUID = UUID(),
        threadID: String,
        prompt: String,
        attachments: [QueuedAttachment],
        reasoningLevel: ReasoningLevel,
        createdAt: Int = Int(Date().timeIntervalSince1970)
    ) {
        self.id = id
        self.threadID = threadID
        self.prompt = prompt
        self.attachments = attachments
        self.reasoningLevel = reasoningLevel
        self.createdAt = createdAt
    }

    var pendingAttachments: [PendingAttachment] {
        attachments.map(\.pendingAttachment)
    }

    var displayText: String {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !attachments.isEmpty else {
            return trimmedPrompt
        }
        let attachmentNames = attachments.map(\.filename).joined(separator: ", ")
        if trimmedPrompt.isEmpty {
            return "Attached: \(attachmentNames)"
        }
        return "\(trimmedPrompt)\n\nAttached: \(attachmentNames)"
    }
}

struct QueuedAttachment: Codable, Hashable {
    let filename: String
    let mimeType: String
    let data: Data

    init(_ attachment: PendingAttachment) {
        filename = attachment.filename
        mimeType = attachment.mimeType
        data = attachment.data
    }

    var pendingAttachment: PendingAttachment {
        PendingAttachment(filename: filename, mimeType: mimeType, data: data)
    }
}

enum QueuedPromptStore {
    private static var url: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return directory
            .appendingPathComponent("CodexPhone", isDirectory: true)
            .appendingPathComponent("queued-prompts.json")
    }

    static func load() -> [String: QueuedPrompt] {
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([String: QueuedPrompt].self, from: data)
        } catch {
            return [:]
        }
    }

    static func save(_ queuedPrompts: [String: QueuedPrompt]) {
        do {
            let fileURL = url
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(queuedPrompts)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            assertionFailure("Could not save queued prompts: \(error)")
        }
    }
}

struct PendingAttachment: Identifiable, Hashable {
    static let maxBytes = 25 * 1024 * 1024
    static let maxTotalBytes = 50 * 1024 * 1024

    let id = UUID()
    let filename: String
    let mimeType: String
    let data: Data

    var isImage: Bool {
        mimeType.hasPrefix("image/")
    }

    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
    }
}

struct GatewayAttachment: Encodable {
    let filename: String
    let mimeType: String
    let dataBase64: String

    init(_ attachment: PendingAttachment) {
        filename = attachment.filename
        mimeType = attachment.mimeType
        dataBase64 = attachment.data.base64EncodedString()
    }
}

struct ErrorEnvelope: Decodable {
    let error: String
}

struct GatewayErrorPayload: Decodable, Equatable {
    struct ErrorBody: Decodable, Equatable {
        let code: String
        let message: String
        let recovery: String
    }

    let error: ErrorBody
}

enum GatewayErrorPresenter {
    static func title(for error: GatewayErrorPayload.ErrorBody) -> String {
        error.message
    }

    static func recovery(for error: GatewayErrorPayload.ErrorBody) -> String {
        error.recovery
    }

    static func message(for error: Error) -> String {
        if let gatewayError = error as? GatewayError {
            switch gatewayError {
            case .gateway(let payload):
                return recovery(for: payload)
            default:
                return gatewayError.localizedDescription
            }
        }
        return error.localizedDescription
    }
}

struct CodexThread: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let cwd: String
    let rolloutPath: String
    let updatedAt: Int
    let createdAt: Int
    let source: String?
    let threadSource: String?
    let reasoningEffort: String?
    let messages: [CodexMessage]?
    let pinned: Bool?
    let pinnedRank: Int?

    var updatedText: String {
        Date(timeIntervalSince1970: TimeInterval(updatedAt)).formatted(date: .abbreviated, time: .shortened)
    }

    var isPinned: Bool {
        pinned == true
    }

    static func newThreadStub(id: String, cwd: String) -> CodexThread {
        let now = Int(Date().timeIntervalSince1970)
        return CodexThread(
            id: id,
            title: "New Thread",
            cwd: cwd,
            rolloutPath: "",
            updatedAt: now,
            createdAt: now,
            source: nil,
            threadSource: nil,
            reasoningEffort: nil,
            messages: nil,
            pinned: false,
            pinnedRank: nil
        )
    }
}

struct CodexMessage: Decodable, Identifiable, Hashable {
    let id: String
    let role: String
    let text: String
    let timestamp: String?
}

struct CodexJob: Decodable, Identifiable, Hashable {
    let id: String
    let threadId: String
    let turnId: String?
    let status: String
    let createdAt: Int
    let updatedAt: Int
    let output: String
    let lastMessage: String
    let error: String?
    let reasoningEffort: String?
    let promptText: String?
    let attachments: [CodexJobAttachment]?
    let events: [CodexJobEvent]?
    let eventCursor: Int?
    let completionNotificationSentAt: Int?

    var isTerminal: Bool {
        status != "running"
    }

    var hasVisibleFailureDetails: Bool {
        if status == "failed" {
            return !(error ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if status == "canceled" {
            return activityEvents.contains { $0.kind == "error" || $0.status == "failed" }
        }
        return false
    }

    var activityEvents: [CodexJobEvent] {
        (events ?? []).filter { $0.isDisplayable }
    }

    var diffStats: CodexDiffStats? {
        let allEvents = events ?? []
        if let cumulative = allEvents.last(where: { $0.rawType == "turn/diff/updated" })?.apiDiffStats, !cumulative.isEmpty {
            return cumulative
        }

        let totals = allEvents.reduce(CodexDiffStats(added: 0, removed: 0)) { partialResult, event in
            guard let stats = event.apiDiffStats else {
                return partialResult
            }
            return CodexDiffStats(
                added: partialResult.added + stats.added,
                removed: partialResult.removed + stats.removed
            )
        }
        return totals.isEmpty ? nil : totals
    }

    var errorSummary: String {
        guard let error, !error.isEmpty else {
            return "Codex failed"
        }
        return error.components(separatedBy: "\n\n").first ?? error
    }

    func mergingEvents(from previous: CodexJob?) -> CodexJob {
        guard let previous else {
            return self
        }
        var mergedEvents = previous.events ?? []
        for event in events ?? [] {
            if let index = mergedEvents.firstIndex(where: { $0.id == event.id }) {
                mergedEvents[index] = event
            } else {
                mergedEvents.append(event)
            }
        }
        if mergedEvents.count > 80 {
            mergedEvents.removeFirst(mergedEvents.count - 80)
        }
        let cursor = max(eventCursor ?? 0, previous.eventCursor ?? 0, mergedEvents.compactMap(\.eventSeq).max() ?? 0)
        return CodexJob(
            id: id,
            threadId: threadId,
            turnId: turnId,
            status: status,
            createdAt: createdAt,
            updatedAt: updatedAt,
            output: output,
            lastMessage: lastMessage,
            error: error,
            reasoningEffort: reasoningEffort,
            promptText: promptText,
            attachments: attachments,
            events: mergedEvents,
            eventCursor: cursor,
            completionNotificationSentAt: completionNotificationSentAt ?? previous.completionNotificationSentAt
        )
    }
}

struct CodexJobEvent: Decodable, Identifiable, Hashable {
    let id: String
    let kind: String
    let status: String
    let title: String
    let subtitle: String
    let body: String
    let timestamp: Int
    let rawType: String
    let eventSeq: Int?
    let diffStats: CodexDiffStats?

    var isCollapsible: Bool {
        kind == "tool" || kind == "command" || kind == "fileChange"
    }

    var apiDiffStats: CodexDiffStats? {
        if let diffStats {
            return diffStats
        }
        if rawType == "turn/diff/updated" {
            return CodexDiffStats.fromDiffEventBody(body)
        }
        if kind == "fileChange" || title == "Filechange" {
            return CodexDiffStats.fromFileChangeEventBody(body)
        }
        return nil
    }

    var isDisplayable: Bool {
        if rawType == "turn/diff/updated" {
            return false
        }
        if rawType == "item/agentMessage/delta" && kind != "message" {
            return false
        }
        if rawType.hasSuffix("/outputDelta") || rawType == "thread/tokenUsage/updated" || rawType == "thread/status/changed" {
            return false
        }
        if title == "Delta" || title == "Outputdelta" || title == "Updated" || title == "Changed" || title == "Started" || title == "Completed" {
            return kind != "context"
        }
        if title == "Reasoning" && body.contains("\"content\": []") && body.contains("\"summary\": []") {
            return false
        }
        return true
    }
}

struct CodexDiffStats: Decodable, Hashable {
    let added: Int
    let removed: Int

    var isEmpty: Bool {
        added == 0 && removed == 0
    }

    static func fromDiffEventBody(_ body: String) -> CodexDiffStats? {
        guard
            let payload = jsonObject(from: body),
            let diff = payload["diff"] as? String
        else {
            return nil
        }
        return fromUnifiedDiff(diff)
    }

    static func fromFileChangeEventBody(_ body: String) -> CodexDiffStats? {
        guard
            let payload = jsonObject(from: body),
            let changes = payload["changes"] as? [[String: Any]]
        else {
            return nil
        }

        let totals = changes.reduce(CodexDiffStats(added: 0, removed: 0)) { partialResult, change in
            guard let diff = change["diff"] as? String else {
                return partialResult
            }
            let stats = fromUnifiedDiff(diff)
            return CodexDiffStats(
                added: partialResult.added + stats.added,
                removed: partialResult.removed + stats.removed
            )
        }
        return totals.isEmpty ? nil : totals
    }

    static func fromUnifiedDiff(_ diff: String) -> CodexDiffStats {
        var added = 0
        var removed = 0

        for line in diff.components(separatedBy: .newlines) {
            if line.hasPrefix("+++") || line.hasPrefix("---") {
                continue
            }
            if line.hasPrefix("+") {
                added += 1
            } else if line.hasPrefix("-") {
                removed += 1
            }
        }

        return CodexDiffStats(added: added, removed: removed)
    }

    private static func jsonObject(from body: String) -> [String: Any]? {
        guard let data = body.data(using: .utf8) else {
            return nil
        }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

struct TurnCompletionNotification: Equatable {
    let identifier: String
    let title: String
    let body: String
    let threadID: String
    let jobID: String
}

struct TurnCompletionNotificationTracker {
    private var deliveredJobIDs: Set<String> = []

    mutating func notification(
        for job: CodexJob,
        previousStatus: String?,
        serverNotificationSentAt: Int?,
        threadTitle: String
    ) -> TurnCompletionNotification? {
        if serverNotificationSentAt != nil {
            deliveredJobIDs.insert(job.id)
            return nil
        }

        guard previousStatus == "running",
              job.status != "running",
              !deliveredJobIDs.contains(job.id) else {
            return nil
        }

        deliveredJobIDs.insert(job.id)
        let cleanThreadTitle = threadTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayThreadTitle = cleanThreadTitle.isEmpty ? "Codex thread" : cleanThreadTitle

        if job.status == "failed" {
            return TurnCompletionNotification(
                identifier: "turn-failed-\(job.id)",
                title: "Codex failed",
                body: "\(displayThreadTitle): \(job.errorSummary)",
                threadID: job.threadId,
                jobID: job.id
            )
        }

        return TurnCompletionNotification(
            identifier: "turn-finished-\(job.id)",
            title: "Codex finished",
            body: "Turn finished in \(displayThreadTitle).",
            threadID: job.threadId,
            jobID: job.id
        )
    }
}

@MainActor
final class TurnCompletionNotifier {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func requestAuthorizationIfNeeded() async {
        if await isAuthorizedOrCanRequest() {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    func deliver(_ notification: TurnCompletionNotification) async {
        guard await isAuthorizedOrCanRequest() else { return }
        UIApplication.shared.registerForRemoteNotifications()

        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        content.userInfo = [
            "threadId": notification.threadID,
            "jobId": notification.jobID
        ]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: notification.identifier,
            content: content,
            trigger: trigger
        )

        try? await center.add(request)
    }

    private func isAuthorizedOrCanRequest() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) == true
        case .denied:
            return false
        @unknown default:
            return false
        }
    }
}

struct CodexJobAttachment: Decodable, Identifiable, Hashable {
    var id: String { path }
    let filename: String
    let mimeType: String
    let size: Int
    let path: String
    let isImage: Bool
}

struct AccountUsageStatus: Decodable, Identifiable, Hashable {
    var id: String { name }

    let name: String
    let isActive: Bool
    let fiveHourRemainingPercent: Int?
    let fiveHourUsedPercent: Int?
    let fiveHourWindowMins: Int?
    let fiveHourResetsAt: Int?
    let weeklyRemainingPercent: Int?
    let weeklyUsedPercent: Int?
    let weeklyWindowMins: Int?
    let weeklyResetsAt: Int?
    let rateLimitResetCreditsRemaining: Int?
    let lastRefreshAt: Int?
    let lastUsedAt: Int?
    let lastLimitAt: Int?
    let lastSwitchAt: Int?
    let turnEvents: Int
    let limitHits: Int
    let manualSwitches: Int
    let automaticSwitches: Int
    let rateLimitError: String
    let authStale: Bool
    let authStaleAt: Int?
    let authStaleReason: String

    var authStaleText: String {
        authStaleReason.isEmpty ? "Auth needs refresh" : "Auth needs refresh: \(authStaleReason)"
    }

    var isUsableForNewTurn: Bool {
        guard !authStale else { return false }
        let fiveHourRemaining = fiveHourRemainingPercent ?? 0
        let weeklyRemaining = weeklyRemainingPercent ?? 0
        return fiveHourRemaining > 0 || weeklyRemaining > 0
    }
}

enum GatewayError: LocalizedError {
    case invalidURL
    case invalidResponse
    case http(Int)
    case server(String)
    case gateway(GatewayErrorPayload.ErrorBody)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Invalid gateway URL"
        case .invalidResponse:
            "Invalid gateway response"
        case .http(let status):
            "Gateway returned HTTP \(status)"
        case .server(let message):
            message
        case .gateway(let payload):
            GatewayErrorPresenter.recovery(for: payload)
        }
    }
}

private func isTransientNetworkError(_ error: Error) -> Bool {
    if error is CancellationError {
        return false
    }
    let urlError: URLError?
    if let error = error as? URLError {
        urlError = error
    } else {
        let nsError = error as NSError
        urlError = nsError.domain == NSURLErrorDomain ? URLError(URLError.Code(rawValue: nsError.code)) : nil
    }
    guard let urlError else {
        return false
    }
    switch urlError.code {
    case .networkConnectionLost,
         .timedOut,
         .cannotFindHost,
         .cannotConnectToHost,
         .dnsLookupFailed,
         .notConnectedToInternet,
         .secureConnectionFailed,
         .internationalRoamingOff,
         .callIsActive,
         .dataNotAllowed:
        return true
    default:
        return false
    }
}

private func isBenignCancellationError(_ error: Error) -> Bool {
    if error is CancellationError {
        return true
    }
    if let error = error as? URLError {
        return error.code == .cancelled
    }
    let nsError = error as NSError
    if nsError.domain == NSURLErrorDomain, nsError.code == URLError.cancelled.rawValue {
        return true
    }
    let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return message == "cancelled" || message == "canceled" || message == "cancelled." || message == "canceled."
}
