import AppKit
import CryptoKit
import Darwin
import Foundation

struct Settings {
    let codexDir: URL
    let appDir: URL
    let accountsDir: URL
    let backupsDir: URL
    let usageFile: URL
    let logsDatabase: URL
    let activeAuth: URL
    let loginBackupAuth: URL
    let pendingLoginReplacementMarker: URL
    let activeAccountMarker: URL
    let phoneGatewayToken: URL
    let phoneGatewayBaseURL: URL
    let appServerControlSocket: URL
    let pollInterval: TimeInterval
    let idleGrace: TimeInterval
    let rateLimitRefreshInterval: TimeInterval

    static func load() -> Settings {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let codexDir = home.appendingPathComponent(".codex", isDirectory: true)
        let appDir = home.appendingPathComponent(".codex-account-switcher", isDirectory: true)
        return Settings(
            codexDir: codexDir,
            appDir: appDir,
            accountsDir: appDir.appendingPathComponent("accounts", isDirectory: true),
            backupsDir: appDir.appendingPathComponent("backups", isDirectory: true),
            usageFile: appDir.appendingPathComponent("usage.json"),
            logsDatabase: codexDir.appendingPathComponent("logs_2.sqlite"),
            activeAuth: codexDir.appendingPathComponent("auth.json"),
            loginBackupAuth: appDir.appendingPathComponent("pending-login-auth.json"),
            pendingLoginReplacementMarker: appDir.appendingPathComponent("pending-login-replacement.txt"),
            activeAccountMarker: appDir.appendingPathComponent("active-account.txt"),
            phoneGatewayToken: appDir.appendingPathComponent("phone-gateway-token"),
            phoneGatewayBaseURL: URL(string: "http://127.0.0.1:18790")!,
            appServerControlSocket: codexDir
                .appendingPathComponent("app-server-control", isDirectory: true)
                .appendingPathComponent("app-server-control.sock"),
            pollInterval: 5,
            idleGrace: 20,
            rateLimitRefreshInterval: 60
        )
    }
}

enum PollingTimerFactory {
    static func scheduleCommonModeTimer(
        interval: TimeInterval,
        repeats: Bool,
        handler: @escaping (Timer) -> Void
    ) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: repeats, block: handler)
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .eventTracking)
        return timer
    }
}

enum CodePilotHostServicesManager {
    private static let fileManager = FileManager.default
    private static let home = FileManager.default.homeDirectoryForCurrentUser
    private static let launchAgents = home.appendingPathComponent("Library/LaunchAgents", isDirectory: true)
    private static let logs = home.appendingPathComponent("Library/Logs", isDirectory: true)
    private static let appDir = home.appendingPathComponent(".codex-account-switcher", isDirectory: true)
    private static let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)

    static func ensureConfiguredOnLaunch() {
        DispatchQueue.global(qos: .utility).async {
            do {
                try fileManager.createDirectory(at: launchAgents, withIntermediateDirectories: true)
                try fileManager.createDirectory(at: logs, withIntermediateDirectories: true)
                ensurePreferredCodexCLI()
                unloadAndRemoveLegacyLaunchAgents()
                try installGatewayLaunchAgent()
                try installCloudflaredLaunchAgentIfConfigured()
                try installAgentSchedulerLaunchAgent()
            } catch {
                NSLog("CodePilot host service setup failed: \(error.localizedDescription)")
            }
        }
    }

    private static func preferredCodexURL() -> URL? {
        let candidates = [
            URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex"),
            URL(fileURLWithPath: "/Applications/Codex.app/Contents/Resources/codex")
        ]
        return candidates.first { fileManager.isExecutableFile(atPath: $0.path) }
    }

    private static func ensurePreferredCodexCLI() {
        guard let preferred = preferredCodexURL() else { return }
        let localBin = home.appendingPathComponent(".local/bin", isDirectory: true)
        let target = localBin.appendingPathComponent("codex")
        do {
            try fileManager.createDirectory(at: localBin, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: target.path) {
                try fileManager.removeItem(at: target)
            }
            try fileManager.createSymbolicLink(at: target, withDestinationURL: preferred)
        } catch {
            NSLog("CodePilot could not normalize Codex CLI path: \(error.localizedDescription)")
        }
    }

    private static func unloadAndRemoveLegacyLaunchAgents() {
        let legacyLabels = ProcessInfo.processInfo.environment["CODEPILOT_LEGACY_LAUNCHD_LABELS"]?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
        legacyLabels.forEach { label in
            let plist = launchAgents.appendingPathComponent("\(label).plist")
            runLaunchctl(["unload", plist.path])
            try? fileManager.removeItem(at: plist)
        }
    }

    private static func installGatewayLaunchAgent() throws {
        let gateway = bundledResource("gateway/codex_phone_gateway.py")
            ?? repoRoot.appendingPathComponent("gateway/codex_phone_gateway.py")
        guard fileManager.fileExists(atPath: gateway.path) else { return }

        let env = [
            "CODEX_PHONE_APNS_CERT_PATH": appDir.appendingPathComponent("apns/codexphone-apns-cert.pem").path,
            "CODEX_PHONE_APNS_CERT_KEY_PATH": appDir.appendingPathComponent("apns/codexphone-apns-private.key").path,
            "CODEX_PHONE_APNS_TOPIC": "io.codepilot.iOS"
        ]
        try writeLaunchAgent(
            label: "io.codepilot.phone-gateway",
            programArguments: [
                pythonPath(),
                gateway.path,
                "--host",
                "127.0.0.1",
                "--port",
                "18790"
            ],
            workingDirectory: gateway.deletingLastPathComponent().deletingLastPathComponent().path,
            stdout: logs.appendingPathComponent("codex-phone-gateway.out.log").path,
            stderr: logs.appendingPathComponent("codex-phone-gateway.err.log").path,
            environment: env,
            keepAlive: true,
            startInterval: nil
        )
    }

    private static func installCloudflaredLaunchAgentIfConfigured() throws {
        guard let cloudflared = executable(named: "cloudflared") ?? executable(at: "/opt/homebrew/bin/cloudflared") ?? executable(at: "/usr/local/bin/cloudflared") else {
            return
        }
        let modern = home.appendingPathComponent(".cloudflared/codepilot-config.yaml")
        let legacy = home.appendingPathComponent(".cloudflared/codex-phone-config.yaml")
        let config = fileManager.fileExists(atPath: modern.path) ? modern : legacy
        guard fileManager.fileExists(atPath: config.path) else { return }

        try writeLaunchAgent(
            label: "io.codepilot.phone-cloudflared",
            programArguments: [cloudflared.path, "tunnel", "--config", config.path, "run"],
            workingDirectory: repoRoot.path,
            stdout: logs.appendingPathComponent("codex-phone-cloudflared.out.log").path,
            stderr: logs.appendingPathComponent("codex-phone-cloudflared.err.log").path,
            environment: [:],
            keepAlive: true,
            startInterval: nil
        )
    }

    private static func installAgentSchedulerLaunchAgent() throws {
        let scheduler = bundledResource("scripts/codepilot-agent-scheduler.sh")
            ?? repoRoot.appendingPathComponent("scripts/codepilot-agent-scheduler.sh")
        guard fileManager.fileExists(atPath: scheduler.path) else { return }
        let threadIDFile = appDir.appendingPathComponent("agents/thread-id")
        guard let threadID = try? String(contentsOf: threadIDFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !threadID.isEmpty else {
            return
        }
        let codex = preferredCodexURL()?.path ?? executable(named: "codex")?.path ?? "codex"
        try writeLaunchAgent(
            label: "io.codepilot.agents.scheduler",
            programArguments: [scheduler.path],
            workingDirectory: repoRoot.path,
            stdout: logs.appendingPathComponent("CodePilotAgents/scheduler.launchd.out.log").path,
            stderr: logs.appendingPathComponent("CodePilotAgents/scheduler.launchd.err.log").path,
            environment: [
                "CODEPILOT_REPO_ROOT": repoRoot.path,
                "CODEPILOT_AGENT_ENABLED": "1",
                "CODEPILOT_AGENT_CONTINUOUS": "1",
                "CODEPILOT_AGENT_PUBLIC_AUTONOMY": "launch",
                "CODEPILOT_AGENT_MODEL": "gpt-5.6-sol",
                "CODEPILOT_AGENT_REASONING_EFFORT": "medium",
                "CODEPILOT_CODEX_BIN": codex,
                "CODEPILOT_AGENT_THREAD_ID": threadID
            ],
            keepAlive: false,
            startInterval: 60
        )
    }

    private static func writeLaunchAgent(
        label: String,
        programArguments: [String],
        workingDirectory: String,
        stdout: String,
        stderr: String,
        environment: [String: String],
        keepAlive: Bool,
        startInterval: Int?
    ) throws {
        try fileManager.createDirectory(at: URL(fileURLWithPath: stdout).deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: URL(fileURLWithPath: stderr).deletingLastPathComponent(), withIntermediateDirectories: true)
        let plist = launchAgents.appendingPathComponent("\(label).plist")
        var payload: [String: Any] = [
            "Label": label,
            "ProgramArguments": programArguments,
            "RunAtLoad": true,
            "WorkingDirectory": workingDirectory,
            "StandardOutPath": stdout,
            "StandardErrorPath": stderr,
            "EnvironmentVariables": environment
        ]
        if keepAlive {
            payload["KeepAlive"] = true
        }
        if let startInterval {
            payload["StartInterval"] = startInterval
        }
        let data = try PropertyListSerialization.data(fromPropertyList: payload, format: .xml, options: 0)
        try data.write(to: plist, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: plist.path)
        runLaunchctl(["unload", plist.path])
        runLaunchctl(["load", plist.path])
    }

    private static func bundledResource(_ relativePath: String) -> URL? {
        guard let resourceURL = Bundle.main.resourceURL else { return nil }
        let url = resourceURL.appendingPathComponent(relativePath)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    private static func pythonPath() -> String {
        executable(at: "/usr/local/bin/python3")?.path
            ?? executable(at: "/Library/Frameworks/Python.framework/Versions/3.13/bin/python3")?.path
            ?? "/usr/bin/python3"
    }

    private static func executable(named name: String) -> URL? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]
        process.standardOutput = pipe
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let path = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let path, !path.isEmpty else { return nil }
        return executable(at: path)
    }

    private static func executable(at path: String) -> URL? {
        fileManager.isExecutableFile(atPath: path) ? URL(fileURLWithPath: path) : nil
    }

    @discardableResult
    private static func runLaunchctl(_ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return 1
        }
    }
}

enum AuthStaleClassifier {
    static func isStaleAuthMessage(_ message: String) -> Bool {
        let lower = message.lowercased()
        let markers = [
            "token_invalidated",
            "token_revoked",
            "token_expired",
            "invalidated oauth token",
            "authentication token is expired",
            "refresh_token_reused",
            "refresh token has already been used",
            "refresh token was already used",
            "please try signing in again",
            "please log out and sign in again",
            "no access token",
            "missing access token"
        ]
        return markers.contains { lower.contains($0) }
    }
}

struct AccountProfile: Equatable {
    let name: String
    let authFile: URL
}

struct AccountUsage: Codable {
    var turnEvents = 0
    var estimatedBytes = 0
    var limitHits = 0
    var manualSwitches = 0
    var automaticSwitches = 0
    var lastUsedAt: Date?
    var lastLimitAt: Date?
    var lastSwitchAt: Date?
    var dailyLimitRemainingPercent: Int?
    var dailyLimitUsedPercent: Int?
    var dailyLimitWindowMins: Int?
    var dailyLimitResetsAt: Date?
    var weeklyLimitRemainingPercent: Int?
    var weeklyLimitUsedPercent: Int?
    var weeklyLimitWindowMins: Int?
    var weeklyLimitResetsAt: Date?
    var rateLimitResetCreditsRemaining: Int?
    var lastRateLimitRefreshAt: Date?
    var rateLimitError: String?
    var authStaleAt: Date?
    var authStaleReason: String?
}

struct LimitWindowSummary {
    let remainingPercent: Int
    let usedPercent: Int
    let windowDurationMins: Int?
    let resetsAt: Date?
}

struct RateLimitSummary {
    let daily: LimitWindowSummary?
    let weekly: LimitWindowSummary?
    let resetCreditsRemaining: Int?
}

private struct AutomaticSwitchCandidate {
    let profile: AccountProfile
    let score: Int?
    let refreshesAt: Date?
    let windowLabel: String
    let selectionDescription: String
}

private enum AccountExhaustionState: Equatable {
    case exhausted
    case available
    case unknown
}

private enum RefreshCountdownStyle {
    case fiveHour
    case weekly
}

private func durationUntilRefresh(_ date: Date, style: RefreshCountdownStyle) -> String {
    let seconds = max(0, date.timeIntervalSinceNow)

    switch style {
    case .fiveHour:
        let totalMinutes = max(0, Int(ceil(seconds / 60)))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    case .weekly:
        guard seconds > 0 else { return "0d" }
        let days = Int(seconds / 86_400)
        return days == 0 ? "<1d" : "\(days)d"
    }
}

final class CodexAccountSwitcher {
    private let settings = Settings.load()
    private let fileManager = FileManager.default
    private(set) var isPaused = false
    private(set) var statusMessage = "Starting"
    private(set) var loginCapturePending = false
    private(set) var loginReplacementAccountName: String?
    private var lastLogID = 0
    private var pendingSwitchReason: String?
    private var pendingSwitchRequiresExhaustedActive = false
    private var lastTurnActivity = Date.distantPast
    private var activeTurnTracker = ActiveTurnTracker()
    private var usageByAccount: [String: AccountUsage] = [:]
    private var timer: Timer?
    private var pollInFlight = false
    private var rateLimitRefreshInFlight = false
    private var lastDesktopProjectIndexRepairAt = Date.distantPast
    private var lastRateLimitRefreshAttemptAt = Date.distantPast
    var onChange: (() -> Void)?

    init() {
        createFolders()
        usageByAccount = loadUsage()
        lastLogID = latestLogID()
        activeTurnTracker = seedActiveTurnTracker()
        lastTurnActivity = Date()
        recoverPendingLoginCapture()
        markAccountUsed(activeAccountName())
    }

    func start() {
        tick()
        timer = PollingTimerFactory.scheduleCommonModeTimer(interval: settings.pollInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func togglePaused() {
        isPaused.toggle()
        statusMessage = isPaused ? "Paused" : "Monitoring"
        onChange?()
    }

    func profiles() -> [AccountProfile] {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: settings.accountsDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return entries.compactMap { url in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true else { return nil }
            let authFile = url.appendingPathComponent("auth.json")
            guard fileManager.fileExists(atPath: authFile.path) else { return nil }
            return AccountProfile(name: url.lastPathComponent, authFile: authFile)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func usage(for accountName: String) -> AccountUsage {
        if let usage = usageByAccount[accountName] {
            return usage
        }
        let folded = accountName.lowercased()
        return usageByAccount.first { $0.key.lowercased() == folded }?.value ?? AccountUsage()
    }

    func staleAuthProfiles() -> [AccountProfile] {
        profiles().filter { isAuthStale(usage(for: $0.name)) }
    }

    func authStaleReason(for accountName: String) -> String? {
        let usage = usage(for: accountName)
        if let reason = usage.authStaleReason, !reason.isEmpty {
            return reason
        }
        if let error = usage.rateLimitError, Self.isStaleAuthMessage(error) {
            return error
        }
        return nil
    }

    func activeAccountName() -> String {
        let marker = (try? String(contentsOf: settings.activeAccountMarker, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines))
            .flatMap { $0.isEmpty ? nil : $0 }

        let activeHash = sha256(settings.activeAuth)
        let allProfiles = profiles()

        if let activeHash {
            if let marker,
               let markerProfile = allProfiles.first(where: { $0.name == marker }),
               sha256(markerProfile.authFile) == activeHash {
                return marker
            }

            if let matchingProfile = allProfiles.first(where: { sha256($0.authFile) == activeHash }) {
                return matchingProfile.name
            }
        }

        return marker ?? "unknown"
    }

    func openAccountsFolder() {
        NSWorkspace.shared.open(settings.accountsDir)
    }

    func switchNow() {
        do {
            try switchToNextAccount(reason: "manual switch", isAutomatic: false)
        } catch SwitchError.activeTurnsRunning(let count) {
            let suffix = count == 1 ? "" : "s"
            statusMessage = "Switch blocked: \(count) active turn\(suffix)"
        } catch {
            statusMessage = "Switch failed: \(error.localizedDescription)"
        }
        onChange?()
    }

    func switchToAccount(named name: String) {
        do {
            let allProfiles = profiles()
            guard let profile = allProfiles.first(where: { $0.name == name }) else {
                throw SwitchError.missingProfile(name)
            }
            try switchToAccount(profile, reason: "manual profile switch", isAutomatic: false)
        } catch SwitchError.activeTurnsRunning(let count) {
            let suffix = count == 1 ? "" : "s"
            statusMessage = "Switch blocked: \(count) active turn\(suffix)"
        } catch {
            statusMessage = "Switch failed: \(error.localizedDescription)"
        }
        onChange?()
    }

    func refreshCodexProjectList() {
        do {
            try repairDesktopProjectIndex()
            let relaunch = relaunchCodexAppIfRunning(repairProjectStateBeforeOpen: true)
            switch relaunch {
            case .relaunched:
                statusMessage = "Refreshed projects; relaunching Codex"
            case .blocked:
                statusMessage = "Refreshed projects; Codex turn still running"
            case .notRunning:
                statusMessage = "Refreshed Codex projects"
            }
        } catch {
            statusMessage = "Project refresh failed: \(error.localizedDescription)"
        }
        onChange?()
    }

    func beginManualLogin() {
        beginManualLogin(replacingAccount: nil)
    }

    func beginProfileLoginRefresh(named name: String) {
        beginManualLogin(replacingAccount: name)
    }

    private func beginManualLogin(replacingAccount replacementName: String?) {
        do {
            guard !loginCapturePending else {
                statusMessage = "Login capture already pending"
                onChange?()
                return
            }
            if let replacementName,
               !profiles().contains(where: { $0.name == replacementName }) {
                throw SwitchError.missingProfile(replacementName)
            }
            try backupActiveAuth()
            if fileManager.fileExists(atPath: settings.activeAuth.path) {
                if fileManager.fileExists(atPath: settings.loginBackupAuth.path) {
                    try fileManager.removeItem(at: settings.loginBackupAuth)
                }
                try fileManager.copyItem(at: settings.activeAuth, to: settings.loginBackupAuth)
                try fileManager.removeItem(at: settings.activeAuth)
            }
            loginCapturePending = true
            loginReplacementAccountName = replacementName
            if let replacementName {
                try replacementName.write(to: settings.pendingLoginReplacementMarker, atomically: true, encoding: .utf8)
            } else if fileManager.fileExists(atPath: settings.pendingLoginReplacementMarker.path) {
                try fileManager.removeItem(at: settings.pendingLoginReplacementMarker)
            }
            isPaused = true
            if let replacementName {
                statusMessage = "Login started for \(replacementName); save when Codex finishes"
            } else {
                statusMessage = "Login started; save it when Codex finishes"
            }
            openCodexLogin()
        } catch {
            statusMessage = "Login setup failed: \(error.localizedDescription)"
        }
        onChange?()
    }

    func saveLoggedInAccount(named rawName: String) {
        let replacementName = loginReplacementAccountName
        let name = replacementName ?? sanitizedProfileName(rawName)
        do {
            guard !name.isEmpty else { throw SwitchError.invalidProfileName }
            guard fileManager.fileExists(atPath: settings.activeAuth.path) else {
                throw SwitchError.noActiveAuth
            }
            let profileDir = settings.accountsDir.appendingPathComponent(name, isDirectory: true)
            let authFile = profileDir.appendingPathComponent("auth.json")
            if replacementName == nil, fileManager.fileExists(atPath: authFile.path) {
                throw SwitchError.profileExists(name)
            }

            try fileManager.createDirectory(at: profileDir, withIntermediateDirectories: true)
            try installAuth(from: settings.activeAuth, to: authFile)

            let markedActive = activeAccountMarkerName()
            let shouldRestorePreviousActive = replacementName != nil && markedActive != name
            if shouldRestorePreviousActive {
                if let markedActive,
                   let restoreProfile = profiles().first(where: { $0.name == markedActive }) {
                    try installAuth(from: restoreProfile.authFile, to: settings.activeAuth)
                } else if fileManager.fileExists(atPath: settings.loginBackupAuth.path) {
                    try installAuth(from: settings.loginBackupAuth, to: settings.activeAuth)
                }
            } else {
                try name.write(to: settings.activeAccountMarker, atomically: true, encoding: .utf8)
            }

            if fileManager.fileExists(atPath: settings.loginBackupAuth.path) {
                try? fileManager.removeItem(at: settings.loginBackupAuth)
            }
            if fileManager.fileExists(atPath: settings.pendingLoginReplacementMarker.path) {
                try? fileManager.removeItem(at: settings.pendingLoginReplacementMarker)
            }
            var usage = usageByAccount[name, default: AccountUsage()]
            usage.lastUsedAt = Date()
            usage.rateLimitError = nil
            usage.authStaleAt = nil
            usage.authStaleReason = nil
            usageByAccount[name] = usage
            saveUsage()
            lastRateLimitRefreshAttemptAt = .distantPast
            loginCapturePending = false
            loginReplacementAccountName = nil
            isPaused = false
            let relaunch = relaunchCodexAppIfRunning()
            if replacementName != nil {
                switch relaunch {
                case .relaunched:
                    statusMessage = "Refreshed \(name); relaunching Codex"
                case .blocked:
                    statusMessage = "Refreshed \(name); Codex turn still running"
                case .notRunning:
                    statusMessage = "Refreshed login for \(name)"
                }
                appendAudit("Refreshed logged-in account \(name)")
            } else {
                switch relaunch {
                case .relaunched:
                    statusMessage = "Saved \(name); relaunching Codex"
                case .blocked:
                    statusMessage = "Saved \(name); Codex turn still running"
                case .notRunning:
                    statusMessage = "Saved and tracking \(name)"
                }
                appendAudit("Saved logged-in account \(name)")
            }
        } catch {
            statusMessage = "Save failed: \(error.localizedDescription)"
        }
        onChange?()
    }

    func cancelManualLogin() {
        if !fileManager.fileExists(atPath: settings.activeAuth.path),
           fileManager.fileExists(atPath: settings.loginBackupAuth.path) {
            try? fileManager.copyItem(at: settings.loginBackupAuth, to: settings.activeAuth)
        }
        if fileManager.fileExists(atPath: settings.loginBackupAuth.path) {
            try? fileManager.removeItem(at: settings.loginBackupAuth)
        }
        if fileManager.fileExists(atPath: settings.pendingLoginReplacementMarker.path) {
            try? fileManager.removeItem(at: settings.pendingLoginReplacementMarker)
        }
        loginCapturePending = false
        loginReplacementAccountName = nil
        isPaused = false
        statusMessage = "Login capture cancelled"
        onChange?()
    }

    private func activeAccountMarkerName() -> String? {
        let marker = (try? String(contentsOf: settings.activeAccountMarker, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let marker, !marker.isEmpty else { return nil }
        return marker
    }

    private func installAuth(from source: URL, to destination: URL) throws {
        let temporary = destination
            .deletingLastPathComponent()
            .appendingPathComponent(".auth.json.codex-account-switcher.tmp")
        if fileManager.fileExists(atPath: temporary.path) {
            try fileManager.removeItem(at: temporary)
        }
        try fileManager.copyItem(at: source, to: temporary)
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try fileManager.moveItem(at: temporary, to: destination)
        }
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
    }

    private func tick() {
        if completePendingReplacementLoginIfReady() {
            onChange?()
            return
        }

        guard !isPaused else {
            onChange?()
            return
        }

        startLogPollIfNeeded()
        startRateLimitRefreshIfNeeded()
        repairDesktopProjectIndexIfNeeded()
        processPendingSwitchIfNeeded()
        onChange?()
    }

    @discardableResult
    private func completePendingReplacementLoginIfReady() -> Bool {
        guard loginCapturePending,
              let replacementName = loginReplacementAccountName,
              fileManager.fileExists(atPath: settings.activeAuth.path) else {
            return false
        }

        let activeHash = sha256(settings.activeAuth)
        let backupHash = sha256(settings.loginBackupAuth)
        guard activeHash != nil, activeHash != backupHash else {
            return false
        }

        saveLoggedInAccount(named: replacementName)
        return true
    }

    private func repairDesktopProjectIndexIfNeeded(force: Bool = false) {
        guard force || Date().timeIntervalSince(lastDesktopProjectIndexRepairAt) >= 10 else { return }

        do {
            try repairDesktopProjectIndex()
            lastDesktopProjectIndexRepairAt = Date()
        } catch {
            statusMessage = "Project index repair failed: \(error.localizedDescription)"
        }
    }

    private func repairDesktopProjectIndex() throws {
        try syncThreadNamesFromSessionIndexes()
        try backfillProjectRootsFromStateDatabase(
            database: settings.codexDir.appendingPathComponent("state_5.sqlite"),
            globalState: settings.codexDir.appendingPathComponent(".codex-global-state.json")
        )
    }

    private func startLogPollIfNeeded() {
        guard !pollInFlight else { return }

        pollInFlight = true
        let afterLogID = lastLogID
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let events = self.readLogEvents(after: afterLogID)
            DispatchQueue.main.async {
                self.pollInFlight = false
                self.applyLogEvents(events)
                self.processPendingSwitchIfNeeded()
                self.onChange?()
            }
        }
    }

    private func startRateLimitRefreshIfNeeded(force: Bool = false) {
        guard !rateLimitRefreshInFlight else { return }
        guard force || Date().timeIntervalSince(lastRateLimitRefreshAttemptAt) >= settings.rateLimitRefreshInterval else { return }

        let trackedProfiles = profiles()
        guard !trackedProfiles.isEmpty else { return }

        rateLimitRefreshInFlight = true
        lastRateLimitRefreshAttemptAt = Date()

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let results = trackedProfiles.map { profile in
                (
                    name: profile.name,
                    result: Result { try CodexUsageAPIClient(authFile: profile.authFile).readRateLimits() }
                )
            }

            DispatchQueue.main.async {
                self?.rateLimitRefreshInFlight = false
                for result in results {
                    self?.recordRateLimitRefresh(result.result, for: result.name)
                }
                self?.processPendingSwitchIfNeeded()
                self?.onChange?()
            }
        }
    }

    private func recordRateLimitRefresh(_ result: Result<RateLimitSummary, Error>, for accountName: String) {
        guard accountName != "unknown" else { return }

        var usage = usageByAccount[accountName, default: AccountUsage()]
        usage.lastRateLimitRefreshAt = Date()

        switch result {
        case .success(let summary):
            usage.rateLimitError = nil
            usage.authStaleAt = nil
            usage.authStaleReason = nil
            usage.dailyLimitRemainingPercent = summary.daily?.remainingPercent
            usage.dailyLimitUsedPercent = summary.daily?.usedPercent
            usage.dailyLimitWindowMins = summary.daily?.windowDurationMins
            usage.dailyLimitResetsAt = summary.daily?.resetsAt
            usage.weeklyLimitRemainingPercent = summary.weekly?.remainingPercent
            usage.weeklyLimitUsedPercent = summary.weekly?.usedPercent
            usage.weeklyLimitWindowMins = summary.weekly?.windowDurationMins
            usage.weeklyLimitResetsAt = summary.weekly?.resetsAt
            usage.rateLimitResetCreditsRemaining = summary.resetCreditsRemaining
        case .failure(let error):
            let message = Self.singleLine(error.localizedDescription, limit: 300)
            usage.rateLimitError = message
            if Self.isStaleAuthError(error) || Self.isStaleAuthMessage(message) {
                usage.authStaleAt = Date()
                usage.authStaleReason = message
            }
        }

        usageByAccount[accountName] = usage
        saveUsage()
    }

    private static func singleLine(_ message: String, limit: Int) -> String {
        let collapsed = message.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        return String(collapsed.prefix(limit))
    }

    private func isAuthStale(_ usage: AccountUsage) -> Bool {
        if usage.authStaleAt != nil {
            return true
        }
        if let error = usage.rateLimitError {
            return Self.isStaleAuthMessage(error)
        }
        return false
    }

    private static func isStaleAuthError(_ error: Error) -> Bool {
        guard let usageError = error as? CodexUsageAPIClientError else {
            return AuthStaleClassifier.isStaleAuthMessage(error.localizedDescription)
        }

        switch usageError {
        case .missingAccessToken:
            return true
        case .httpStatus(let status, let body):
            return status == 401 && AuthStaleClassifier.isStaleAuthMessage(body)
        case .missingRateLimit, .invalidResponse, .timeout:
            return false
        }
    }

    private static func isStaleAuthMessage(_ message: String) -> Bool {
        AuthStaleClassifier.isStaleAuthMessage(message)
    }

    private func applyTurnTracking(from events: [LogEvent]) {
        guard !events.isEmpty else { return }
        lastLogID = max(lastLogID, events.map(\.id).max() ?? lastLogID)

        let active = activeAccountName()
        let turnEvents = events.filter { $0.isTurnActivity }
        if !turnEvents.isEmpty {
            lastTurnActivity = Date()
            recordTurnActivity(for: active, events: turnEvents)
        }
        for event in events {
            activeTurnTracker.apply(event)
        }
        activeTurnTracker.pruneStaleTurns(now: Date())
    }

    private func applyLogEvents(_ events: [LogEvent]) {
        guard !events.isEmpty else { return }
        let active = activeAccountName()
        applyTurnTracking(from: events)
        if events.contains(where: { $0.isTerminalTurnActivity || $0.clearsThreadTurns }),
           activeTurnTracker.activeTurnCount == 0 {
            persistActiveAuthToProfile(context: "after turn finished")
        }

        if pendingSwitchReason == nil, let exhausted = events.first(where: { $0.isTokenExhaustion }) {
            pendingSwitchReason = exhausted.summary
            pendingSwitchRequiresExhaustedActive = false
            recordLimitHit(for: active)
            statusMessage = "Limit detected; waiting for Codex to finish"
            appendAudit("Queued automatic switch for \(active): \(Self.singleLine(exhausted.summary, limit: 180))")
            startRateLimitRefreshIfNeeded(force: true)
        }
    }

    private func persistActiveAuthToProfile(context: String) {
        do {
            let didSync = try AuthProfileSynchronizer.syncActiveAuthToProfile(
                activeAuth: settings.activeAuth,
                activeAccountMarker: settings.activeAccountMarker,
                accountsDir: settings.accountsDir,
                fileManager: fileManager
            )
            if didSync {
                appendAudit("Synced active auth to profile \(context)")
            }
        } catch {
            appendAudit("Skipped active auth sync \(context): \(error.localizedDescription)")
        }
    }

    private func processPendingSwitchIfNeeded() {
        updatePendingSwitchFromUsage()

        guard let reason = pendingSwitchReason else {
            statusMessage = "Monitoring"
            return
        }

        let active = activeAccountName()
        let activeUsage = usage(for: active)
        switch exhaustionState(for: activeUsage) {
        case .available:
            if pendingSwitchRequiresExhaustedActive || usageDecisionIsFresh(activeUsage) {
                clearPendingSwitch()
                statusMessage = "Monitoring"
                return
            }
            startRateLimitRefreshIfNeeded(force: true)
            statusMessage = "Refreshing usage before switch"
            return
        case .unknown:
            if pendingSwitchRequiresExhaustedActive {
                startRateLimitRefreshIfNeeded(force: true)
                statusMessage = "Waiting for usage before switch"
                return
            }
            if !usageDecisionIsFresh(activeUsage) {
                startRateLimitRefreshIfNeeded(force: true)
                statusMessage = "Refreshing usage before switch"
                return
            }
        case .exhausted:
            break
        }

        let activeTurnBlockers = automaticSwitchTurnBlockers()
        guard activeTurnBlockers.isEmpty else {
            lastTurnActivity = Date()
            let suffix = activeTurnBlockers.count == 1 ? "" : "s"
            statusMessage = "Waiting for \(activeTurnBlockers.count) active turn\(suffix) to finish"
            return
        }

        let quietFor = Date().timeIntervalSince(lastTurnActivity)
        guard quietFor >= settings.idleGrace else {
            statusMessage = "Waiting for idle: \(Int(settings.idleGrace - quietFor))s"
            return
        }

        do {
            let didSwitch = try switchToBestAvailableAccount(reason: reason, isAutomatic: true)
            if didSwitch {
                clearPendingSwitch()
            }
        } catch SwitchError.activeTurnsRunning(let count) {
            let suffix = count == 1 ? "" : "s"
            statusMessage = "Waiting for \(count) active turn\(suffix) to finish"
        } catch SwitchError.noUsableProfiles {
            statusMessage = "No account with known usage or refresh time"
        } catch {
            statusMessage = "Switch failed: \(error.localizedDescription)"
        }
    }

    private func updatePendingSwitchFromUsage() {
        guard pendingSwitchReason == nil else { return }

        let active = activeAccountName()
        guard active != "unknown" else { return }
        guard exhaustionState(for: usage(for: active)) == .exhausted else { return }

        pendingSwitchReason = "\(active) has 0% remaining"
        pendingSwitchRequiresExhaustedActive = true
        recordLimitHit(for: active)
        statusMessage = "Usage exhausted; waiting for Codex to finish"
        appendAudit("Queued automatic switch for \(active): 0% remaining")
    }

    private func clearPendingSwitch() {
        pendingSwitchReason = nil
        pendingSwitchRequiresExhaustedActive = false
    }

    private func automaticSwitchTurnBlockers() -> [String] {
        refreshActiveTurnTrackerFromLogs()
        activeTurnTracker.pruneStaleTurns(now: Date())
        return codexQuitBlockers(refreshFromLogs: false)
    }

    private func codexQuitBlockers(refreshFromLogs: Bool = true) -> [String] {
        if refreshFromLogs {
            refreshActiveTurnTrackerFromLogs()
        }
        activeTurnTracker.pruneStaleTurns(now: Date())
        return CodexQuitGuard.blockers(
            activeTurnDescriptions: activeTurnTracker.activeTurnDescriptions,
            phoneGatewayJobDescriptions: phoneGatewayJobDescriptions()
        )
    }

    private func refreshActiveTurnTrackerFromLogs() {
        let events = readLogEvents(after: lastLogID)
        applyTurnTracking(from: events)
    }

    private func activeCodexQuitBlockersDescription(_ blockers: [String]) -> String {
        blockers.joined(separator: ", ")
    }

    private func phoneGatewayJobDescriptions() -> [String] {
        runningPhoneGatewayJobs().map { job in
            let thread = job.threadID.isEmpty ? "new-thread" : job.threadID
            return "phone:\(thread)/\(job.id)"
        }
    }

    private func exhaustionState(for usage: AccountUsage) -> AccountExhaustionState {
        let knownWindows = [usage.dailyLimitRemainingPercent, usage.weeklyLimitRemainingPercent].compactMap { $0 }
        guard !knownWindows.isEmpty else {
            return .unknown
        }

        if knownWindows.contains(where: { $0 <= 0 }) {
            return .exhausted
        }

        return .available
    }

    private func usageDecisionIsFresh(_ usage: AccountUsage) -> Bool {
        guard let refreshedAt = usage.lastRateLimitRefreshAt else { return false }
        return Date().timeIntervalSince(refreshedAt) <= settings.rateLimitRefreshInterval * 2
    }

    private func automaticSwitchScore(for usage: AccountUsage) -> (score: Int, windowLabel: String)? {
        if let fiveHourRemaining = usage.dailyLimitRemainingPercent {
            return (max(0, min(100, fiveHourRemaining)), "5h")
        }

        if let weeklyRemaining = usage.weeklyLimitRemainingPercent {
            return (max(0, min(100, weeklyRemaining)), "weekly")
        }

        return nil
    }

    private func bestAutomaticSwitchCandidate(excluding activeName: String) -> AutomaticSwitchCandidate? {
        let activeAuthHash = sha256(settings.activeAuth)
        let allProfiles = profiles()
        let usageCandidates = allProfiles.compactMap { profile -> AutomaticSwitchCandidate? in
            guard profile.name != activeName else { return nil }
            if let activeAuthHash, sha256(profile.authFile) == activeAuthHash {
                return nil
            }

            let usage = usage(for: profile.name)
            guard !isAuthStale(usage) else { return nil }
            guard exhaustionState(for: usage) == .available,
                  let score = automaticSwitchScore(for: usage),
                  score.score > 0 else {
                return nil
            }

            return AutomaticSwitchCandidate(
                profile: profile,
                score: score.score,
                refreshesAt: nil,
                windowLabel: score.windowLabel,
                selectionDescription: "\(score.score)% \(score.windowLabel) remaining"
            )
        }

        if let bestUsageCandidate = usageCandidates.sorted(by: usageCandidateSort).first {
            return bestUsageCandidate
        }

        let refreshCandidates = allProfiles.compactMap { profile -> AutomaticSwitchCandidate? in
            if profile.name != activeName,
               let activeAuthHash,
               sha256(profile.authFile) == activeAuthHash {
                return nil
            }

            let usage = usage(for: profile.name)
            guard !isAuthStale(usage),
                  let refresh = nextUsableRefresh(for: usage) else {
                return nil
            }

            return AutomaticSwitchCandidate(
                profile: profile,
                score: nil,
                refreshesAt: refresh.date,
                windowLabel: refresh.windowLabel,
                selectionDescription: "\(refresh.windowLabel) refreshes in \(durationUntilRefresh(refresh.date, style: refresh.style))"
            )
        }

        return refreshCandidates.sorted { left, right in
            let leftDate = left.refreshesAt ?? .distantFuture
            let rightDate = right.refreshesAt ?? .distantFuture
            if abs(leftDate.timeIntervalSince(rightDate)) > 1 {
                return leftDate < rightDate
            }
            if left.profile.name == activeName {
                return true
            }
            if right.profile.name == activeName {
                return false
            }
            return left.profile.name.localizedStandardCompare(right.profile.name) == .orderedAscending
        }.first
    }

    private func usageCandidateSort(_ left: AutomaticSwitchCandidate, _ right: AutomaticSwitchCandidate) -> Bool {
        let leftScore = left.score ?? 0
        let rightScore = right.score ?? 0
        if leftScore != rightScore {
            return leftScore > rightScore
        }

        return left.profile.name.localizedStandardCompare(right.profile.name) == .orderedAscending
    }

    private func nextUsableRefresh(for usage: AccountUsage) -> (date: Date, windowLabel: String, style: RefreshCountdownStyle)? {
        var depletedWindows: [(date: Date, windowLabel: String, style: RefreshCountdownStyle)] = []

        if let fiveHourRemaining = usage.dailyLimitRemainingPercent,
           fiveHourRemaining <= 0,
           let refresh = usage.dailyLimitResetsAt {
            depletedWindows.append((refresh, "5h", .fiveHour))
        }

        if let weeklyRemaining = usage.weeklyLimitRemainingPercent,
           weeklyRemaining <= 0,
           let refresh = usage.weeklyLimitResetsAt {
            depletedWindows.append((refresh, "weekly", .weekly))
        }

        guard !depletedWindows.isEmpty else { return nil }

        return depletedWindows.max { left, right in
            left.date < right.date
        }
    }

    private func createFolders() {
        try? fileManager.createDirectory(at: settings.accountsDir, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: settings.backupsDir, withIntermediateDirectories: true)
    }

    private func recoverPendingLoginCapture() {
        guard fileManager.fileExists(atPath: settings.loginBackupAuth.path) else { return }
        loginCapturePending = true
        isPaused = true
        loginReplacementAccountName = pendingLoginReplacementName()
        if let replacement = loginReplacementAccountName {
            statusMessage = "Login pending for \(replacement)"
        } else {
            statusMessage = "Login capture pending"
        }
    }

    private func pendingLoginReplacementName() -> String? {
        let value = (try? String(contentsOf: settings.pendingLoginReplacementMarker, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private func backfillProjectRootsFromStateDatabase(database: URL, globalState: URL) throws {
        let query = """
        select cwd
        from threads
        where archived = 0 and trim(cwd) != '' and cwd like '/%'
        group by cwd
        order by max(coalesce(updated_at_ms, updated_at * 1000, 0)) desc
        limit 200;
        """
        let roots = sqlite(database: database, arguments: [query])
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { Self.isAbsolutePath($0) }
        guard !roots.isEmpty else { return }

        var object: [String: Any] = [:]
        if let data = try? Data(contentsOf: globalState),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            object = existing
        }

        let active = object["active-workspace-roots"] as? [String] ?? []
        object["active-workspace-roots"] = orderedUnion(active.filter(Self.isAbsolutePath) + roots)

        let saved = object["electron-saved-workspace-roots"] as? [String] ?? []
        object["electron-saved-workspace-roots"] = orderedUnion(saved.filter(Self.isAbsolutePath) + roots)

        let order = object["project-order"] as? [String] ?? []
        object["project-order"] = orderedUnion(roots + order.filter { $0 != "5000" })

        var labels = object["electron-workspace-root-labels"] as? [String: Any] ?? [:]
        labels = labels.filter { Self.isAbsolutePath($0.key) }
        for root in roots where labels[root] == nil {
            labels[root] = URL(fileURLWithPath: root).lastPathComponent
        }
        object["electron-workspace-root-labels"] = labels

        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try fileManager.createDirectory(at: globalState.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: globalState, options: .atomic)
    }

    private static func isAbsolutePath(_ value: String) -> Bool {
        value.hasPrefix("/")
    }

    private func orderedUnion(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { value in
            guard !value.isEmpty else { return false }
            return seen.insert(value).inserted
        }
    }

    private func syncThreadNamesFromSessionIndexes() throws {
        try applySessionIndexThreadNames(
            index: settings.codexDir.appendingPathComponent("session_index.jsonl"),
            database: settings.codexDir.appendingPathComponent("state_5.sqlite")
        )
    }

    private func applySessionIndexThreadNames(index: URL, database: URL) throws {
        guard fileManager.fileExists(atPath: database.path) else { return }
        let names = sessionIndexThreadNames(index)
        guard !names.isEmpty else { return }

        let updates = names.map { id, name in
            """
            UPDATE threads
            SET title = '\(Self.sqlString(name))'
            WHERE id = '\(Self.sqlString(id))';
            """
        }
        let sql = """
        BEGIN;
        \(updates.joined(separator: "\n"))
        COMMIT;
        """
        _ = sqlite(database: database, arguments: [sql])
    }

    private func sessionIndexThreadNames(_ index: URL) -> [String: String] {
        guard let text = try? String(contentsOf: index, encoding: .utf8) else { return [:] }

        var names: [String: String] = [:]
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = String(rawLine).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = object["id"] as? String,
                  let rawName = object["thread_name"] as? String else {
                continue
            }

            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, !name.isEmpty else { continue }
            names[id] = name
        }
        return names
    }

    private static func sqlString(_ raw: String) -> String {
        raw.replacingOccurrences(of: "'", with: "''")
    }

    private func latestLogID() -> Int {
        let output = sqlite(["select coalesce(max(id), 0) from logs;"])
        return Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    private func seedActiveTurnTracker() -> ActiveTurnTracker {
        var tracker = ActiveTurnTracker()
        for event in readRecentTurnLogEvents(limit: 6_000) {
            tracker.apply(event)
        }
        tracker.pruneStaleTurns(now: Date())
        return tracker
    }

    private func readRecentTurnLogEvents(limit: Int) -> [LogEvent] {
        let query = """
        select id || char(31) || ts || char(31) || coalesce(target,'') || char(31) || replace(replace(substr(coalesce(feedback_log_body,''), 1, 2000), char(10), ' '), char(13), ' ') || char(31) || estimated_bytes
        from (
            select id, ts, target, feedback_log_body, estimated_bytes
            from logs
            where lower(coalesce(target,'') || ' ' || coalesce(feedback_log_body,'')) like '%turn%'
               or lower(coalesce(target,'') || ' ' || coalesce(feedback_log_body,'')) like '%agent loop exited%'
               or lower(coalesce(target,'') || ' ' || coalesce(feedback_log_body,'')) like '%thread/status/changed%'
            order by id desc
            limit \(limit)
        )
        order by id asc;
        """
        return parseLogEvents(sqlite([query]))
    }

    private func readLogEvents(after logID: Int) -> [LogEvent] {
        let query = """
        select id || char(31) || ts || char(31) || coalesce(target,'') || char(31) || replace(replace(substr(coalesce(feedback_log_body,''), 1, 2000), char(10), ' '), char(13), ' ') || char(31) || estimated_bytes
        from logs
        where id > \(logID)
        order by id asc
        limit 500;
        """
        return parseLogEvents(sqlite([query]))
    }

    private func parseLogEvents(_ output: String) -> [LogEvent] {
        guard !output.isEmpty else { return [] }

        var events: [LogEvent] = []
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: "\u{1F}", maxSplits: 4, omittingEmptySubsequences: false)
            guard parts.count == 5, let id = Int(parts[0]) else { continue }
            let timestampSeconds = TimeInterval(Int(parts[1]) ?? 0)
            events.append(LogEvent(
                id: id,
                timestamp: timestampSeconds > 0 ? Date(timeIntervalSince1970: timestampSeconds) : Date(),
                target: String(parts[2]),
                body: String(parts[3]),
                estimatedBytes: Int(parts[4]) ?? 0
            ))
        }
        return events
    }

    private func sqlite(_ arguments: [String]) -> String {
        sqlite(database: settings.logsDatabase, arguments: arguments)
    }

    private func sqlite(database: URL, arguments: [String]) -> String {
        guard fileManager.fileExists(atPath: database.path) else { return "" }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-cmd", ".timeout 5000", database.path] + arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }

    private func runningPhoneGatewayJobs() -> [PhoneGatewayJob] {
        guard let token = try? String(contentsOf: settings.phoneGatewayToken, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else {
            return []
        }

        let url = settings.phoneGatewayBaseURL.appendingPathComponent("api/jobs/active")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 1.5
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<Data, Error>?
        URLSession.shared.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }

            if let error {
                result = .failure(error)
                return
            }

            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let data else {
                result = .success(Data())
                return
            }

            result = .success(data)
        }.resume()

        guard semaphore.wait(timeout: .now() + 2) == .success,
              let data = try? result?.get(),
              !data.isEmpty,
              let response = try? JSONDecoder().decode(PhoneGatewayActiveJobsResponse.self, from: data) else {
            return []
        }

        if let jobs = response.jobs {
            return jobs.filter { $0.status == "running" }
        }
        if let job = response.job, job.status == "running" {
            return [job]
        }
        return []
    }

    @discardableResult
    private func switchToBestAvailableAccount(reason: String, isAutomatic: Bool) throws -> Bool {
        let active = activeAccountName()
        guard !profiles().isEmpty else {
            throw SwitchError.noProfiles(settings.accountsDir.path)
        }

        guard let candidate = bestAutomaticSwitchCandidate(excluding: active) else {
            throw SwitchError.noUsableProfiles
        }

        if candidate.profile.name == active || sha256(candidate.profile.authFile) == sha256(settings.activeAuth) {
            statusMessage = "Waiting on \(active): \(candidate.selectionDescription)"
            return false
        }

        let switchReason = "\(reason); selected \(candidate.profile.name) because \(candidate.selectionDescription)"
        try switchToAccount(candidate.profile, reason: switchReason, isAutomatic: isAutomatic)
        return true
    }

    private func switchToNextAccount(reason: String, isAutomatic: Bool) throws {
        let allProfiles = profiles()
        guard !allProfiles.isEmpty else {
            throw SwitchError.noProfiles(settings.accountsDir.path)
        }

        let active = activeAccountName()
        let orderedProfiles: [AccountProfile]
        if let index = allProfiles.firstIndex(where: { $0.name == active }) {
            orderedProfiles = Array(allProfiles[(index + 1)...]) + Array(allProfiles[..<index])
        } else {
            orderedProfiles = allProfiles
        }
        guard let next = orderedProfiles.first(where: { authStaleReason(for: $0.name) == nil }) else {
            throw SwitchError.noUsableProfiles
        }

        try switchToAccount(next, reason: reason, isAutomatic: isAutomatic)
    }

    private func switchToAccount(_ next: AccountProfile, reason: String, isAutomatic: Bool) throws {
        if next.name == activeAccountName() {
            statusMessage = "Already using \(next.name)"
            return
        }

        if let staleReason = authStaleReason(for: next.name) {
            throw SwitchError.authStale(next.name, staleReason)
        }

        let blockers = codexQuitBlockers()
        guard blockers.isEmpty else {
            appendAudit("Blocked switch to \(next.name) while active turns were running: \(activeCodexQuitBlockersDescription(blockers))")
            throw SwitchError.activeTurnsRunning(blockers.count)
        }

        persistActiveAuthToProfile(context: "before switching to \(next.name)")
        try backupActiveAuth()
        let temporary = settings.activeAuth.deletingLastPathComponent()
            .appendingPathComponent(".auth.json.codex-account-switcher.tmp")
        if fileManager.fileExists(atPath: temporary.path) {
            try fileManager.removeItem(at: temporary)
        }
        try fileManager.copyItem(at: next.authFile, to: temporary)
        if fileManager.fileExists(atPath: settings.activeAuth.path) {
            _ = try fileManager.replaceItemAt(settings.activeAuth, withItemAt: temporary)
        } else {
            try fileManager.moveItem(at: temporary, to: settings.activeAuth)
        }
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: settings.activeAuth.path)
        guard sha256(settings.activeAuth) == sha256(next.authFile) else {
            throw SwitchError.authInstallVerificationFailed
        }

        try next.name.write(to: settings.activeAccountMarker, atomically: true, encoding: .utf8)
        recordSwitch(to: next.name, isAutomatic: isAutomatic)
        if !isAutomatic {
            clearPendingSwitch()
        }
        let relaunch = relaunchCodexAppIfRunning()
        switch relaunch {
        case .relaunched:
            statusMessage = "Switched to \(next.name); relaunching Codex"
        case .blocked:
            statusMessage = "Switched to \(next.name); Codex turn still running"
        case .notRunning:
            statusMessage = "Switched to \(next.name)"
        }
        appendAudit("Switched to \(next.name) after: \(reason)")
    }

    private func backupActiveAuth() throws {
        guard fileManager.fileExists(atPath: settings.activeAuth.path) else { return }
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let active = activeAccountName().replacingOccurrences(of: "/", with: "_")
        let backup = settings.backupsDir.appendingPathComponent("\(stamp)-\(active)-auth.json")
        try fileManager.copyItem(at: settings.activeAuth, to: backup)
    }

    private func appendAudit(_ line: String) {
        let audit = settings.appDir.appendingPathComponent("switches.log")
        let entry = "\(ISO8601DateFormatter().string(from: Date())) \(line)\n"
        if let handle = try? FileHandle(forWritingTo: audit) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(entry.utf8))
            try? handle.close()
        } else {
            try? entry.write(to: audit, atomically: true, encoding: .utf8)
        }
    }

    private func sha256(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func loadUsage() -> [String: AccountUsage] {
        guard let data = try? Data(contentsOf: settings.usageFile) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([String: AccountUsage].self, from: data)) ?? [:]
    }

    private func saveUsage() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(usageByAccount) else { return }
        try? data.write(to: settings.usageFile, options: .atomic)
    }

    private func markAccountUsed(_ accountName: String) {
        guard accountName != "unknown" else { return }
        usageByAccount[accountName, default: AccountUsage()].lastUsedAt = Date()
        saveUsage()
    }

    private func recordTurnActivity(for accountName: String, events: [LogEvent]) {
        guard accountName != "unknown" else { return }
        var usage = usageByAccount[accountName, default: AccountUsage()]
        usage.turnEvents += events.count
        usage.estimatedBytes += events.reduce(0) { $0 + $1.estimatedBytes }
        usage.lastUsedAt = Date()
        usageByAccount[accountName] = usage
        saveUsage()
    }

    private func recordLimitHit(for accountName: String) {
        guard accountName != "unknown" else { return }
        var usage = usageByAccount[accountName, default: AccountUsage()]
        usage.limitHits += 1
        usage.lastLimitAt = Date()
        usageByAccount[accountName] = usage
        saveUsage()
    }

    private func recordSwitch(to accountName: String, isAutomatic: Bool) {
        var usage = usageByAccount[accountName, default: AccountUsage()]
        if isAutomatic {
            usage.automaticSwitches += 1
        } else {
            usage.manualSwitches += 1
        }
        usage.lastSwitchAt = Date()
        usage.lastUsedAt = Date()
        usageByAccount[accountName] = usage
        saveUsage()
        lastRateLimitRefreshAttemptAt = .distantPast
    }

    private func sanitizedProfileName(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: CharacterSet(charactersIn: "/:\\"))
            .joined(separator: "-")
    }

    private func openCodexLogin() {
        let script = """
        tell application "Terminal"
            activate
            do script "codex login"
        end tell
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
    }

    @discardableResult
    private func relaunchCodexAppIfRunning(repairProjectStateBeforeOpen: Bool = false) -> CodexRelaunchResult {
        let bundleIdentifier = "com.openai.codex"
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        guard !runningApps.isEmpty else { return .notRunning }

        let blockers = codexQuitBlockers()
        guard blockers.isEmpty else {
            appendAudit("Blocked Codex relaunch while active turns were running: \(activeCodexQuitBlockersDescription(blockers))")
            return .blocked(blockers)
        }

        for app in runningApps {
            app.terminate()
        }

        DispatchQueue.global(qos: .utility).async {
            let deadline = Date().addingTimeInterval(6)
            while Date() < deadline,
                  !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty {
                Thread.sleep(forTimeInterval: 0.25)
            }

            if repairProjectStateBeforeOpen {
                try? self.repairDesktopProjectIndex()
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-b", bundleIdentifier]
            try? process.run()
        }

        return .relaunched
    }
}

private enum CodexRelaunchResult: Equatable {
    case notRunning
    case blocked([String])
    case relaunched
}

struct ActiveTurn: Equatable {
    let threadID: String
    let turnID: String
    var lastActivityAt: Date

    var description: String {
        "\(threadID)/\(turnID)"
    }
}

struct ActiveTurnTracker {
    private var activeTurnsByID: [String: ActiveTurn] = [:]
    private let staleTurnInterval: TimeInterval = 6 * 60 * 60

    var activeTurnCount: Int {
        activeTurnsByID.count
    }

    var activeTurnDescriptions: [String] {
        activeTurnsByID.values.map(\.description).sorted()
    }

    mutating func apply(_ event: LogEvent) {
        if let threadID = event.threadID, event.clearsThreadTurns {
            activeTurnsByID = activeTurnsByID.filter { _, turn in
                turn.threadID != threadID
            }
            return
        }

        guard let turnID = event.turnID else { return }

        if event.isTerminalTurnActivity {
            activeTurnsByID.removeValue(forKey: turnID)
            return
        }

        guard event.isTurnActivity, let threadID = event.threadID else { return }

        activeTurnsByID[turnID] = ActiveTurn(
            threadID: threadID,
            turnID: turnID,
            lastActivityAt: event.timestamp
        )
    }

    mutating func pruneStaleTurns(now: Date) {
        activeTurnsByID = activeTurnsByID.filter { _, turn in
            now.timeIntervalSince(turn.lastActivityAt) <= staleTurnInterval
        }
    }
}

struct CodexQuitGuard {
    static func blockers(
        activeTurnDescriptions: [String],
        phoneGatewayJobDescriptions: [String]
    ) -> [String] {
        Array(Set(activeTurnDescriptions + phoneGatewayJobDescriptions)).sorted()
    }
}

enum AuthProfileSynchronizer {
    @discardableResult
    static func syncActiveAuthToProfile(
        activeAuth: URL,
        activeAccountMarker: URL,
        accountsDir: URL,
        fileManager: FileManager = .default
    ) throws -> Bool {
        guard fileManager.fileExists(atPath: activeAuth.path) else { return false }
        guard let accountName = try? String(contentsOf: activeAccountMarker, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !accountName.isEmpty,
              accountName != "unknown" else {
            return false
        }

        let profileAuth = accountsDir
            .appendingPathComponent(accountName, isDirectory: true)
            .appendingPathComponent("auth.json")
        guard fileManager.fileExists(atPath: profileAuth.path) else { return false }

        return try withAuthFileLock(near: activeAccountMarker, fileManager: fileManager) {
            let activeData = try Data(contentsOf: activeAuth)
            let profileData = try Data(contentsOf: profileAuth)
            guard activeData != profileData else { return false }

            let decoder = JSONDecoder()
            let activeSnapshot = try decoder.decode(AuthFileSnapshot.self, from: activeData)
            let profileSnapshot = try decoder.decode(AuthFileSnapshot.self, from: profileData)
            let activeAccountID = activeSnapshot.tokens?.accountID ?? ""
            let profileAccountID = profileSnapshot.tokens?.accountID ?? ""
            if !activeAccountID.isEmpty, !profileAccountID.isEmpty, activeAccountID != profileAccountID {
                return false
            }

            if let activeRefresh = activeSnapshot.lastRefreshDate,
               let profileRefresh = profileSnapshot.lastRefreshDate,
               activeRefresh < profileRefresh {
                return false
            }

            try installAuth(from: activeAuth, to: profileAuth, fileManager: fileManager)
            return true
        }
    }

    private static func withAuthFileLock<T>(
        near marker: URL,
        fileManager: FileManager,
        body: () throws -> T
    ) throws -> T {
        let lockURL = marker.deletingLastPathComponent().appendingPathComponent("auth-files.lock")
        fileManager.createFile(atPath: lockURL.path, contents: nil)
        let fd = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw POSIXError(.EIO) }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw POSIXError(.EIO) }
        defer { flock(fd, LOCK_UN) }
        return try body()
    }

    private static func installAuth(
        from source: URL,
        to destination: URL,
        fileManager: FileManager
    ) throws {
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let temporary = destination
            .deletingLastPathComponent()
            .appendingPathComponent(".auth.json.codex-account-switcher.tmp")
        if fileManager.fileExists(atPath: temporary.path) {
            try fileManager.removeItem(at: temporary)
        }
        try fileManager.copyItem(at: source, to: temporary)
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try fileManager.moveItem(at: temporary, to: destination)
        }
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
    }
}

private struct AuthFileSnapshot: Decodable {
    let lastRefresh: String?
    let tokens: AuthFileSnapshotTokens?

    var lastRefreshDate: Date? {
        guard let lastRefresh else { return nil }
        return ISO8601DateFormatter().date(from: lastRefresh)
    }

    enum CodingKeys: String, CodingKey {
        case lastRefresh = "last_refresh"
        case tokens
    }
}

private struct AuthFileSnapshotTokens: Decodable {
    let accountID: String?

    enum CodingKeys: String, CodingKey {
        case accountID = "account_id"
    }
}

private struct PhoneGatewayActiveJobsResponse: Decodable {
    let job: PhoneGatewayJob?
    let jobs: [PhoneGatewayJob]?
}

private struct PhoneGatewayJob: Decodable {
    let id: String
    let threadID: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case id
        case threadID = "threadId"
        case status
    }
}

struct LogEvent {
    let id: Int
    let timestamp: Date
    let target: String
    let body: String
    let estimatedBytes: Int

    var combined: String { "\(target)\n\(body)" }
    var normalizedCombined: String {
        combined.replacingOccurrences(of: "\\\"", with: "\"")
    }

    var isTurnActivity: Bool {
        let lower = normalizedCombined.lowercased()
        return lower.contains(":turn")
            || lower.contains("\"type\":\"response.")
            || lower.contains("submission_dispatch")
            || lower.contains("op.dispatch")
    }

    var isTerminalTurnActivity: Bool {
        let lower = normalizedCombined.lowercased()
        if lower.contains("turn error") {
            return true
        }
        if lower.contains(#""type":"turn.completed""#)
            || lower.contains(#""type":"turn.failed""#)
            || lower.contains(#""type":"turn.error""#) {
            return true
        }
        return false
    }

    var clearsThreadTurns: Bool {
        let lower = normalizedCombined.lowercased()
        return lower.contains("agent loop exited")
            || (lower.contains("thread/status/changed") && lower.contains(#""type":"idle""#))
    }

    var threadID: String? {
        Self.firstIdentifier(in: normalizedCombined, patterns: [
            #"thread\.id=([A-Za-z0-9_.-]+)"#,
            #"thread_id=([A-Za-z0-9_.-]+)"#,
            #""threadId"\s*:\s*"([^"]+)""#,
            #""thread_id"\s*:\s*"([^"]+)""#
        ])
    }

    var turnID: String? {
        Self.firstIdentifier(in: normalizedCombined, patterns: [
            #"turn\.id=([A-Za-z0-9_.-]+)"#,
            #"turn_id=([A-Za-z0-9_.-]+)"#,
            #""turnId"\s*:\s*"([^"]+)""#,
            #""turn_id"\s*:\s*"([^"]+)""#
        ])
    }

    var isTokenExhaustion: Bool {
        let lower = combined.lowercased()
        let phrases = [
            "rate limit",
            "rate_limit",
            "usage limit",
            "quota exceeded",
            "token limit",
            "tokens have run out",
            "tokens ran out",
            "out of tokens",
            "insufficient quota",
            "you have reached your limit"
        ]
        return phrases.contains { lower.contains($0) }
    }

    var summary: String {
        let text = body.isEmpty ? target : body
        return String(text.prefix(180))
    }

    private static func firstIdentifier(in text: String, patterns: [String]) -> String? {
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = regex.firstMatch(in: text, range: range),
                  match.numberOfRanges > 1,
                  let identifierRange = Range(match.range(at: 1), in: text) else {
                continue
            }
            let value = String(text[identifierRange])
            if !value.isEmpty {
                return value
            }
        }
        return nil
    }
}

private final class CodexUsageAPIClient {
    private let authFile: URL

    init(authFile: URL) {
        self.authFile = authFile
    }

    func readRateLimits() throws -> RateLimitSummary {
        let accessToken = try readAccessToken()
        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("codex-account-switcher/0.1.0", forHTTPHeaderField: "User-Agent")

        let data = try Self.perform(request)
        let response = try JSONDecoder().decode(WhamUsageResponse.self, from: data)
        guard let rateLimit = response.rateLimit else {
            throw CodexUsageAPIClientError.missingRateLimit
        }

        return Self.summary(
            from: rateLimit,
            resetCreditsRemaining: response.rateLimitResetCredits?.availableCount
        )
    }

    private func readAccessToken() throws -> String {
        let data = try Data(contentsOf: authFile)
        let auth = try JSONDecoder().decode(CodexAuthFile.self, from: data)
        guard let token = auth.tokens?.accessToken, !token.isEmpty else {
            throw CodexUsageAPIClientError.missingAccessToken
        }
        return token
    }

    private static func perform(_ request: URLRequest) throws -> Data {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<Data, Error>!

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }

            if let error {
                result = .failure(error)
                return
            }

            guard let http = response as? HTTPURLResponse else {
                result = .failure(CodexUsageAPIClientError.invalidResponse)
                return
            }

            let body = data ?? Data()
            guard (200..<300).contains(http.statusCode) else {
                let message = String(data: body.prefix(500), encoding: .utf8) ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
                result = .failure(CodexUsageAPIClientError.httpStatus(http.statusCode, message))
                return
            }

            result = .success(body)
        }
        task.resume()

        if semaphore.wait(timeout: .now() + 15) == .timedOut {
            task.cancel()
            throw CodexUsageAPIClientError.timeout
        }

        return try result.get()
    }

    private static func summary(from rateLimit: WhamRateLimit, resetCreditsRemaining: Int?) -> RateLimitSummary {
        let primary = rateLimit.primaryWindow.map(windowSummary)
        let secondary = rateLimit.secondaryWindow.map(windowSummary)

        let primaryWindowMinutes = rateLimit.primaryWindow?.windowDurationMins
        let secondaryWindowMinutes = rateLimit.secondaryWindow?.windowDurationMins

        let weekly: LimitWindowSummary?
        if let secondary, (secondaryWindowMinutes ?? 0) >= 10_080 {
            weekly = secondary
        } else if let primary, (primaryWindowMinutes ?? 0) >= 10_080 {
            weekly = primary
        } else {
            weekly = secondary
        }

        let daily: LimitWindowSummary?
        if let primary, primaryWindowMinutes != nil, primaryWindowMinutes! < 10_080 {
            daily = primary
        } else if let secondary, secondaryWindowMinutes != nil, secondaryWindowMinutes! < 10_080 {
            daily = secondary
        } else {
            daily = nil
        }

        return RateLimitSummary(
            daily: daily,
            weekly: weekly,
            resetCreditsRemaining: resetCreditsRemaining
        )
    }

    private static func windowSummary(_ window: WhamRateLimitWindow) -> LimitWindowSummary {
        let used = max(0, min(100, window.usedPercent))
        return LimitWindowSummary(
            remainingPercent: max(0, min(100, 100 - used)),
            usedPercent: used,
            windowDurationMins: window.windowDurationMins,
            resetsAt: window.resetAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        )
    }
}

private struct CodexAuthFile: Decodable {
    let tokens: CodexAuthTokens?
}

private struct CodexAuthTokens: Decodable {
    let accessToken: String?
    let accountID: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case accountID = "account_id"
    }
}

private struct WhamUsageResponse: Decodable {
    let rateLimit: WhamRateLimit?
    let rateLimitResetCredits: WhamRateLimitResetCredits?

    enum CodingKeys: String, CodingKey {
        case rateLimit = "rate_limit"
        case rateLimitResetCredits = "rate_limit_reset_credits"
    }
}

private struct WhamRateLimitResetCredits: Decodable {
    let availableCount: Int?

    enum CodingKeys: String, CodingKey {
        case availableCount = "available_count"
    }
}

private struct WhamRateLimit: Decodable {
    let primaryWindow: WhamRateLimitWindow?
    let secondaryWindow: WhamRateLimitWindow?

    enum CodingKeys: String, CodingKey {
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
    }
}

private struct WhamRateLimitWindow: Decodable {
    let usedPercent: Int
    let limitWindowSeconds: Int?
    let resetAt: Int?

    var windowDurationMins: Int? {
        guard let limitWindowSeconds else { return nil }
        return limitWindowSeconds / 60
    }

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case limitWindowSeconds = "limit_window_seconds"
        case resetAt = "reset_at"
    }
}

private enum CodexUsageAPIClientError: LocalizedError {
    case missingAccessToken
    case missingRateLimit
    case invalidResponse
    case httpStatus(Int, String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .missingAccessToken:
            return "Profile auth.json has no access token"
        case .missingRateLimit:
            return "Codex usage response did not include rate limits"
        case .invalidResponse:
            return "Codex usage response was not HTTP"
        case .httpStatus(let status, let body):
            return "Codex usage request failed with HTTP \(status): \(body)"
        case .timeout:
            return "Timed out reading Codex usage"
        }
    }
}

private final class CodexAppServerClient {
    private let socketPath: String

    init(socketPath: String) {
        self.socketPath = socketPath
    }

    func readRateLimits() throws -> RateLimitSummary {
        let connection = try UnixWebSocketConnection(socketPath: socketPath)
        defer { connection.close() }

        try connection.sendJSON([
            "id": 1,
            "method": "initialize",
            "params": [
                "clientInfo": [
                    "name": "codex-account-switcher",
                    "title": "Codex Account Switcher",
                    "version": "0.1.0"
                ],
                "capabilities": [
                    "experimentalApi": false,
                    "requestAttestation": false,
                    "optOutNotificationMethods": [
                        "thread/started",
                        "thread/status/changed",
                        "thread/tokenUsage/updated",
                        "turn/started",
                        "turn/completed"
                    ]
                ]
            ]
        ])
        _ = try connection.readResponseData(id: 1)

        try connection.sendJSON(["method": "initialized"])
        try connection.sendJSON([
            "id": 2,
            "method": "account/rateLimits/read"
        ])

        let data = try connection.readResponseData(id: 2)
        let envelope = try JSONDecoder().decode(RateLimitsEnvelope.self, from: data)
        if let error = envelope.error {
            throw CodexAppServerClientError.server(error.message)
        }
        guard let response = envelope.result else {
            throw CodexAppServerClientError.missingResult
        }
        return Self.summary(from: response)
    }

    private static func summary(from response: CodexRateLimitsResponse) -> RateLimitSummary {
        let snapshot = preferredSnapshot(from: response)
        let windows = [snapshot.primary, snapshot.secondary].compactMap { $0 }

        let weeklySource = windows.first { ($0.windowDurationMins ?? 0) >= 10_080 }
            ?? snapshot.secondary

        let dailySource = windows.first { $0.windowDurationMins == 1_440 }
            ?? ((snapshot.primary != nil && snapshot.primary != weeklySource) ? snapshot.primary : nil)
            ?? windows.filter { $0 != weeklySource }.min { duration($0) < duration($1) }

        return RateLimitSummary(
            daily: dailySource.map(windowSummary),
            weekly: weeklySource.map(windowSummary),
            resetCreditsRemaining: response.rateLimitResetCredits?.availableCount
        )
    }

    private static func preferredSnapshot(from response: CodexRateLimitsResponse) -> CodexRateLimitSnapshot {
        guard let byLimitID = response.rateLimitsByLimitId, !byLimitID.isEmpty else {
            return response.rateLimits
        }

        if let codex = byLimitID["codex"] {
            return codex
        }

        let sortedKeys = byLimitID.keys.sorted()
        if let key = sortedKeys.first(where: { key in
            let snapshot = byLimitID[key]
            return snapshot?.limitName == nil || snapshot?.limitId == nil
        }), let snapshot = byLimitID[key] {
            return snapshot
        }

        if let key = sortedKeys.first, let snapshot = byLimitID[key] {
            return snapshot
        }

        return response.rateLimits
    }

    private static func windowSummary(_ window: CodexRateLimitWindow) -> LimitWindowSummary {
        let used = max(0, min(100, window.usedPercent))
        return LimitWindowSummary(
            remainingPercent: max(0, min(100, 100 - used)),
            usedPercent: used,
            windowDurationMins: window.windowDurationMins,
            resetsAt: resetDate(from: window.resetsAt)
        )
    }

    private static func duration(_ window: CodexRateLimitWindow) -> Int {
        window.windowDurationMins ?? Int.max
    }

    private static func resetDate(from unixValue: Int?) -> Date? {
        guard let unixValue else { return nil }
        let seconds = TimeInterval(unixValue)
        if unixValue > 10_000_000_000 {
            return Date(timeIntervalSince1970: seconds / 1_000)
        }
        return Date(timeIntervalSince1970: seconds)
    }
}

private final class UnixWebSocketConnection {
    private let fd: Int32

    init(socketPath: String) throws {
        fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw CodexAppServerClientError.socket("Could not create socket")
        }

        do {
            try Self.setTimeouts(fd: fd)
            try Self.connect(fd: fd, socketPath: socketPath)
            try Self.performHandshake(fd: fd)
        } catch {
            Darwin.close(fd)
            throw error
        }
    }

    func close() {
        Darwin.close(fd)
    }

    func sendJSON(_ object: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: object)
        try sendFrame(opcode: 0x1, payload: data)
    }

    func readResponseData(id: Int) throws -> Data {
        for _ in 0..<30 {
            let frame = try readFrame()

            switch frame.opcode {
            case 0x1:
                guard let object = try JSONSerialization.jsonObject(with: frame.payload) as? [String: Any] else {
                    continue
                }
                guard let responseID = object["id"] as? NSNumber, responseID.intValue == id else {
                    continue
                }
                if let error = object["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    throw CodexAppServerClientError.server(message)
                }
                return frame.payload
            case 0x8:
                throw CodexAppServerClientError.socket("App server closed the connection")
            case 0x9:
                try sendFrame(opcode: 0xA, payload: frame.payload)
            default:
                continue
            }
        }

        throw CodexAppServerClientError.socket("Timed out waiting for app server response")
    }

    private func sendFrame(opcode: UInt8, payload: Data) throws {
        var frame = Data([0x80 | opcode])
        let count = payload.count

        if count < 126 {
            frame.append(UInt8(0x80 | count))
        } else if count <= UInt16.max {
            frame.append(0x80 | 126)
            frame.append(UInt8((count >> 8) & 0xFF))
            frame.append(UInt8(count & 0xFF))
        } else {
            frame.append(0x80 | 127)
            for shift in stride(from: 56, through: 0, by: -8) {
                frame.append(UInt8((UInt64(count) >> UInt64(shift)) & 0xFF))
            }
        }

        let mask = (0..<4).map { _ in UInt8.random(in: 0...255) }
        frame.append(contentsOf: mask)

        var maskedPayload = Data(capacity: payload.count)
        for (index, byte) in payload.enumerated() {
            maskedPayload.append(byte ^ mask[index % 4])
        }
        frame.append(maskedPayload)

        try Self.writeAll(fd: fd, data: frame)
    }

    private func readFrame() throws -> (opcode: UInt8, payload: Data) {
        let header = try Self.readExactly(fd: fd, count: 2)
        let first = header[0]
        let second = header[1]
        var length = Int(second & 0x7F)

        if length == 126 {
            let bytes = try Self.readExactly(fd: fd, count: 2)
            length = (Int(bytes[0]) << 8) | Int(bytes[1])
        } else if length == 127 {
            let bytes = try Self.readExactly(fd: fd, count: 8)
            length = bytes.reduce(0) { ($0 << 8) | Int($1) }
        }

        let mask: [UInt8]?
        if second & 0x80 != 0 {
            mask = Array(try Self.readExactly(fd: fd, count: 4))
        } else {
            mask = nil
        }

        var payload = try Self.readExactly(fd: fd, count: length)
        if let mask {
            for index in 0..<payload.count {
                payload[index] = payload[index] ^ mask[index % 4]
            }
        }

        return (first & 0x0F, payload)
    }

    private static func setTimeouts(fd: Int32) throws {
        var timeout = timeval(tv_sec: 4, tv_usec: 0)
        let size = socklen_t(MemoryLayout<timeval>.size)
        guard Darwin.setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, size) == 0,
              Darwin.setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, size) == 0 else {
            throw CodexAppServerClientError.socket("Could not configure socket timeout")
        }
    }

    private static func connect(fd: Int32, socketPath: String) throws {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)

        var pathBytes = Array(socketPath.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            throw CodexAppServerClientError.socket("App server socket path is too long")
        }
        pathBytes.append(0)
        withUnsafeMutableBytes(of: &address.sun_path) { rawBuffer in
            rawBuffer.copyBytes(from: pathBytes)
        }

        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                Darwin.connect(fd, socketAddress, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard result == 0 else {
            throw CodexAppServerClientError.socket("Could not connect to Codex app server")
        }
    }

    private static func performHandshake(fd: Int32) throws {
        let key = Data((0..<16).map { _ in UInt8.random(in: 0...255) }).base64EncodedString()
        let request = """
        GET / HTTP/1.1\r
        Host: localhost\r
        Upgrade: websocket\r
        Connection: Upgrade\r
        Sec-WebSocket-Key: \(key)\r
        Sec-WebSocket-Version: 13\r
        \r

        """
        try writeAll(fd: fd, data: Data(request.utf8))

        var response = Data()
        let terminator = Data([13, 10, 13, 10])
        while response.range(of: terminator) == nil {
            response.append(try readExactly(fd: fd, count: 1))
            guard response.count <= 8_192 else {
                throw CodexAppServerClientError.socket("Invalid app server handshake")
            }
        }

        guard let text = String(data: response, encoding: .utf8),
              text.hasPrefix("HTTP/1.1 101") || text.hasPrefix("HTTP/1.0 101") else {
            throw CodexAppServerClientError.socket("App server did not accept the websocket handshake")
        }
    }

    private static func writeAll(fd: Int32, data: Data) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            var sent = 0
            while sent < rawBuffer.count {
                let result = Darwin.send(fd, base.advanced(by: sent), rawBuffer.count - sent, 0)
                guard result > 0 else {
                    throw CodexAppServerClientError.socket("Failed writing to Codex app server")
                }
                sent += result
            }
        }
    }

    private static func readExactly(fd: Int32, count: Int) throws -> Data {
        guard count > 0 else { return Data() }

        var buffer = [UInt8](repeating: 0, count: count)
        var received = 0
        while received < count {
            let result = buffer.withUnsafeMutableBytes { rawBuffer in
                Darwin.recv(fd, rawBuffer.baseAddress!.advanced(by: received), count - received, 0)
            }

            guard result > 0 else {
                throw CodexAppServerClientError.socket("Timed out reading from Codex app server")
            }
            received += result
        }

        return Data(buffer)
    }
}

private struct RateLimitsEnvelope: Decodable {
    let result: CodexRateLimitsResponse?
    let error: JSONRPCErrorPayload?
}

private struct JSONRPCErrorPayload: Decodable {
    let message: String
}

private struct CodexRateLimitsResponse: Decodable {
    let rateLimits: CodexRateLimitSnapshot
    let rateLimitsByLimitId: [String: CodexRateLimitSnapshot]?
    let rateLimitResetCredits: CodexRateLimitResetCredits?
}

private struct CodexRateLimitResetCredits: Decodable {
    let availableCount: Int?
}

private struct CodexRateLimitSnapshot: Decodable {
    let limitId: String?
    let limitName: String?
    let primary: CodexRateLimitWindow?
    let secondary: CodexRateLimitWindow?
}

private struct CodexRateLimitWindow: Decodable, Equatable {
    let usedPercent: Int
    let windowDurationMins: Int?
    let resetsAt: Int?
}

private enum CodexAppServerClientError: LocalizedError {
    case socket(String)
    case server(String)
    case missingResult

    var errorDescription: String? {
        switch self {
        case .socket(let message), .server(let message):
            return message
        case .missingResult:
            return "Codex app server returned no rate limit result"
        }
    }
}

enum SwitchError: LocalizedError {
    case noProfiles(String)
    case noUsableProfiles
    case missingProfile(String)
    case invalidProfileName
    case noActiveAuth
    case profileExists(String)
    case authStale(String, String)
    case authInstallVerificationFailed
    case activeTurnsRunning(Int)

    var errorDescription: String? {
        switch self {
        case .noProfiles(let path):
            return "No profiles found in \(path)"
        case .noUsableProfiles:
            return "No account has known usage left"
        case .missingProfile(let name):
            return "No profile named \(name)"
        case .invalidProfileName:
            return "Enter a profile name"
        case .noActiveAuth:
            return "No Codex auth.json found. Finish codex login first"
        case .profileExists(let name):
            return "A profile named \(name) already exists"
        case .authStale(let name, let reason):
            return "\(name) auth is stale; refresh this account login before switching. \(reason)"
        case .authInstallVerificationFailed:
            return "The selected auth file was not installed correctly"
        case .activeTurnsRunning(let count):
            let suffix = count == 1 ? "" : "s"
            return "\(count) active turn\(suffix) still running"
        }
    }
}

private struct CodePilotSetupStatus {
    let rows: [CodePilotSetupRow]

    static func load() -> CodePilotSetupStatus {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let codexAuth = home.appendingPathComponent(".codex/auth.json").path
        let appDir = home.appendingPathComponent(".codex-account-switcher", isDirectory: true)
        let accountsDir = appDir.appendingPathComponent("accounts", isDirectory: true)
        let tokenPath = appDir.appendingPathComponent("phone-gateway-token")
        let accountCount = (try? FileManager.default.contentsOfDirectory(
            at: accountsDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("auth.json").path) }.count) ?? 0

        let codexCLI = executablePath(named: "codex")
        let cloudflared = executablePath(named: "cloudflared")
        let cloudflareRequirement: CodePilotSetupRequirement
        let cloudflareDetail: String
        if cloudflared == nil {
            cloudflareRequirement = .cloudflareMissing
            cloudflareDetail = "Install cloudflared to enable remote iPhone access."
        } else if cloudflareMetadataExists() || cloudflareConfigExists() {
            cloudflareRequirement = .cloudflareReady
            cloudflareDetail = cloudflareReadyDetail(defaultPath: cloudflared)
        } else {
            cloudflareRequirement = .cloudflareNeedsConfiguration
            cloudflareDetail = "cloudflared is installed; set up a tunnel for remote access."
        }
        return CodePilotSetupStatus(rows: [
            CodePilotSetupRow(
                title: "Codex CLI",
                requirement: codexCLI == nil ? .codexCLIMissing : .codexCLIInstalled,
                detail: codexCLI ?? "Install Codex before using CodePilot."
            ),
            CodePilotSetupRow(
                title: "Codex Login",
                requirement: FileManager.default.fileExists(atPath: codexAuth) ? .codexSignedIn : .codexSignedOut,
                detail: FileManager.default.fileExists(atPath: codexAuth) ? "Signed in" : "Missing auth.json"
            ),
            CodePilotSetupRow(
                title: "Account Profiles",
                requirement: accountCount > 0 ? .profilesCreated : .profilesMissing,
                detail: accountCount == 1 ? "1 profile" : "\(accountCount) profiles"
            ),
            CodePilotSetupRow(
                title: "Gateway Token",
                requirement: FileManager.default.fileExists(atPath: tokenPath.path) ? .gatewayTokenPresent : .gatewayTokenMissing,
                detail: FileManager.default.fileExists(atPath: tokenPath.path) ? "Token present" : "Missing token"
            ),
            CodePilotSetupRow(
                title: "Gateway",
                requirement: gatewayHealthRequirement(),
                detail: gatewayHealthDetail()
            ),
            CodePilotSetupRow(
                title: "Cloudflare",
                requirement: cloudflareRequirement,
                detail: cloudflareDetail
            )
        ])
    }

    private static func executablePath(named name: String) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func gatewayHealthRequirement() -> CodePilotSetupRequirement {
        let tokenPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex-account-switcher/phone-gateway-token")
        guard let token = try? String(contentsOf: tokenPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty,
              let url = URL(string: "http://127.0.0.1:18790/api/health") else {
            return .gatewayStopped
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let data = synchronousData(for: request), !data.isEmpty else {
            return .gatewayStopped
        }
        return .gatewayRunning
    }

    private static func synchronousData(for request: URLRequest) -> Data? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Data?
        let task = URLSession.shared.dataTask(with: request) { data, _, _ in
            result = data
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 2)
        return result
    }

    private static func gatewayHealthDetail() -> String {
        gatewayHealthRequirement() == .gatewayRunning
            ? "Reachable on 127.0.0.1:18790"
            : "Not reachable on 127.0.0.1:18790"
    }

    private static func cloudflareMetadataExists() -> Bool {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex-account-switcher/cloudflare-setup.json")
        return FileManager.default.fileExists(atPath: path.path)
    }

    private static func cloudflareConfigExists() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let modern = home.appendingPathComponent(".cloudflared/codepilot-config.yaml")
        let legacy = home.appendingPathComponent(".cloudflared/codex-phone-config.yaml")
        return FileManager.default.fileExists(atPath: modern.path) || FileManager.default.fileExists(atPath: legacy.path)
    }

    private static func cloudflareReadyDetail(defaultPath: String?) -> String {
        if let metadata = loadCloudflareMetadata(), !metadata.hostname.isEmpty {
            return metadata.hostname
        }
        return defaultPath ?? "Configured"
    }

    private static func loadCloudflareMetadata() -> CodePilotCloudflareMetadata? {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex-account-switcher/cloudflare-setup.json")
        guard let data = try? Data(contentsOf: path) else { return nil }
        return try? JSONDecoder().decode(CodePilotCloudflareMetadata.self, from: data)
    }
}

struct CodePilotSetupRow: Equatable {
    let title: String
    let requirement: CodePilotSetupRequirement
    let detail: String
}

struct CodePilotCloudflareMetadata: Codable, Equatable {
    let mode: String
    let hostname: String
    let tunnelName: String
    let tunnelId: String
    let configPath: String
    let launchAgentLabel: String
    let lastVerifiedAt: String?

    var safeSummary: String {
        let host = hostname.isEmpty ? "No hostname configured" : hostname
        return "\(mode) tunnel \(tunnelName) for \(host)"
    }
}

enum CodePilotCloudflareErrorMapper {
    static func message(forExitCode code: Int32) -> String {
        switch code {
        case 20:
            return "Homebrew is missing. Install Homebrew or use Cloudflare's manual cloudflared installer, then retry."
        case 21:
            return "cloudflared is missing. Install it from the Cloudflare setup step before continuing."
        default:
            return "Cloudflare setup did not finish. Open details, review the last command output, and retry the failed step."
        }
    }
}

enum CodePilotSetupRequirement: Equatable {
    case codexCLIInstalled
    case codexCLIMissing
    case codexSignedIn
    case codexSignedOut
    case profilesCreated
    case profilesMissing
    case gatewayTokenPresent
    case gatewayTokenMissing
    case gatewayRunning
    case gatewayStopped
    case gatewayBlockedByActiveTurn
    case cloudflareReady
    case cloudflareOptional
    case cloudflareMissing
    case cloudflareNeedsConfiguration
    case screenRecordingMissing
    case accessibilityMissing
    case notificationsOptional

    var statusLabel: String {
        switch self {
        case .codexCLIInstalled, .codexSignedIn, .profilesCreated, .gatewayTokenPresent, .gatewayRunning, .cloudflareReady:
            return "Ready"
        case .cloudflareNeedsConfiguration:
            return "Needs setup"
        case .gatewayStopped:
            return "Stopped"
        case .gatewayBlockedByActiveTurn:
            return "Blocked by active turn"
        case .cloudflareOptional, .notificationsOptional:
            return "Optional"
        case .codexCLIMissing, .codexSignedOut, .profilesMissing, .gatewayTokenMissing, .cloudflareMissing, .screenRecordingMissing, .accessibilityMissing:
            return "Missing"
        }
    }
}

private final class CodePilotSetupWindowController: NSWindowController {
    private let statusStack = NSStackView()
    private let outputLabel = NSTextField(labelWithString: "")
    private var cloudflareWizardController: CodePilotCloudflareWizardController?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Setup CodePilot"
        self.init(window: window)
        buildUI()
        refreshStatus()
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 16
        root.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            root.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            root.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -20)
        ])

        let title = NSTextField(labelWithString: "CodePilot Setup")
        title.font = .systemFont(ofSize: 24, weight: .semibold)
        root.addArrangedSubview(title)

        let subtitle = NSTextField(wrappingLabelWithString: "Connect CodePilot to Codex, the local gateway, and optional Cloudflare remote access.")
        subtitle.textColor = .secondaryLabelColor
        root.addArrangedSubview(subtitle)

        statusStack.orientation = .vertical
        statusStack.alignment = .leading
        statusStack.spacing = 8
        root.addArrangedSubview(statusStack)

        root.addArrangedSubview(section(
            title: "Codex",
            buttons: [
                button("Open Codex Login", #selector(openCodexLogin)),
                button("Open Accounts Folder", #selector(openAccountsFolder))
            ]
        ))
        root.addArrangedSubview(section(
            title: "Gateway",
            buttons: [
                button("Restart Gateway When Idle", #selector(restartGatewayWhenIdle)),
                button("Force Restart Gateway...", #selector(forceRestartGateway)),
                button("Copy iOS Token", #selector(copyToken))
            ]
        ))
        root.addArrangedSubview(section(
            title: "Cloudflare Remote Access",
            buttons: [
                button("Set Up Remote Access...", #selector(openCloudflareWizard)),
                button("Restart Tunnel", #selector(restartCloudflareTunnel)),
                button("Open Cloudflare Guide", #selector(openCloudflareGuide))
            ]
        ))

        let refresh = button("Refresh Status", #selector(refreshStatusAction))
        root.addArrangedSubview(refresh)

        outputLabel.textColor = .secondaryLabelColor
        outputLabel.lineBreakMode = .byTruncatingMiddle
        root.addArrangedSubview(outputLabel)
    }

    private func section(title: String, buttons: [NSButton]) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        stack.addArrangedSubview(label)

        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        buttons.forEach { row.addArrangedSubview($0) }
        stack.addArrangedSubview(row)
        return stack
    }

    private func button(_ title: String, _ action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }

    private func refreshStatus() {
        statusStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let status = CodePilotSetupStatus.load()
        status.rows.forEach { status in
            let row = NSTextField(labelWithString: "\(status.title): \(status.requirement.statusLabel) - \(status.detail)")
            row.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            statusStack.addArrangedSubview(row)
        }
    }

    @objc private func refreshStatusAction() {
        refreshStatus()
    }

    @objc private func openCodexLogin() {
        runInTerminal("codex login")
    }

    @objc private func openAccountsFolder() {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex-account-switcher/accounts", isDirectory: true)
        NSWorkspace.shared.open(url)
    }

    @objc private func restartGatewayWhenIdle() {
        runBundledScript(named: "install-phone-gateway-agent.sh")
    }

    @objc private func forceRestartGateway() {
        let alert = NSAlert()
        alert.messageText = "Force Restart Gateway?"
        alert.informativeText = "This can interrupt active phone turns. Use Restart Gateway When Idle unless you need to recover a stuck gateway."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Force Restart")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        runBundledScript(named: "install-phone-gateway-agent.sh", force: true)
    }

    @objc private func openCloudflareWizard() {
        let controller = CodePilotCloudflareWizardController()
        cloudflareWizardController = controller
        window?.beginSheet(controller.window!) { [weak self] _ in
            self?.cloudflareWizardController = nil
            self?.refreshStatus()
        }
    }

    @objc private func restartCloudflareTunnel() {
        runBundledScript(named: "setup-cloudflare-remote-access.sh", arguments: ["restart-service"])
    }

    @objc private func copyToken() {
        let tokenPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex-account-switcher/phone-gateway-token")
        guard let token = try? String(contentsOf: tokenPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else {
            outputLabel.stringValue = "No gateway token found."
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(token, forType: .string)
        outputLabel.stringValue = "Copied iOS token."
    }

    @objc private func openCloudflareGuide() {
        let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("docs/CLOUDFLARE_SETUP.md")
        if FileManager.default.fileExists(atPath: sourceURL.path) {
            NSWorkspace.shared.open(sourceURL)
        } else if let url = URL(string: "https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/") {
            NSWorkspace.shared.open(url)
        }
    }

    private func runBundledScript(named name: String, arguments: [String] = [], force: Bool = false) {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("scripts/\(name)"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("scripts/\(name)")
        ].compactMap { $0 }
        guard let script = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) || FileManager.default.fileExists(atPath: $0.path) }) else {
            outputLabel.stringValue = "Could not find \(name)."
            return
        }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [script.path] + arguments + (force ? ["--force"] : [])
        process.standardOutput = pipe
        process.standardError = pipe
        process.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        outputLabel.stringValue = "Running \(name)..."
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                DispatchQueue.main.async {
                    self.outputLabel.stringValue = output.isEmpty ? "\(name) exited \(process.terminationStatus)." : output
                    self.refreshStatus()
                }
            } catch {
                DispatchQueue.main.async {
                    self.outputLabel.stringValue = error.localizedDescription
                }
            }
        }
    }

    private func runInTerminal(_ command: String) {
        let script = """
        tell application "Terminal"
            activate
            do script "\(command.replacingOccurrences(of: "\"", with: "\\\""))"
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        if let error {
            outputLabel.stringValue = String(describing: error)
        }
    }
}

private final class CodePilotCloudflareWizardController: NSWindowController {
    private let outputLabel = NSTextField(wrappingLabelWithString: "")
    private let hostnameField = NSTextField(string: "")
    private let tunnelNameField = NSTextField(string: "codepilot")
    private let detailsLabel = NSTextField(wrappingLabelWithString: "")

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Set Up Cloudflare Remote Access"
        self.init(window: window)
        buildUI()
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 14
        root.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            root.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            root.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -20)
        ])

        let title = NSTextField(labelWithString: "Cloudflare Remote Access")
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        root.addArrangedSubview(title)

        let intro = NSTextField(wrappingLabelWithString: """
        CodePilot can use Cloudflare Tunnel so your iPhone can reach the Mac gateway away from your local network. Setup may install cloudflared, sign in to Cloudflare, create a tunnel, add a DNS route, write ~/.cloudflared/codepilot-config.yaml, and install a LaunchAgent to keep the tunnel running. No inbound ports are opened; the iOS app still needs the gateway token.
        """)
        intro.textColor = .secondaryLabelColor
        root.addArrangedSubview(intro)

        let fields = NSGridView(views: [
            [NSTextField(labelWithString: "Hostname"), hostnameField],
            [NSTextField(labelWithString: "Tunnel name"), tunnelNameField]
        ])
        fields.column(at: 0).xPlacement = .trailing
        fields.column(at: 1).width = 420
        hostnameField.placeholderString = "codepilot.example.com"
        root.addArrangedSubview(fields)

        root.addArrangedSubview(buttonRow([
            button("Install cloudflared", #selector(installCloudflared)),
            button("Sign In or Create Account", #selector(loginCloudflare))
        ]))
        root.addArrangedSubview(buttonRow([
            button("Configure Permanent Hostname", #selector(configurePermanent)),
            button("Start Temporary Test URL", #selector(startTemporary))
        ]))
        root.addArrangedSubview(buttonRow([
            button("Open Cloudflare Dashboard", #selector(openCloudflareDashboard)),
            button("Close", #selector(closeSheet))
        ]))

        outputLabel.textColor = .labelColor
        outputLabel.stringValue = "Choose a setup step."
        root.addArrangedSubview(outputLabel)

        detailsLabel.textColor = .secondaryLabelColor
        detailsLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        detailsLabel.maximumNumberOfLines = 8
        detailsLabel.stringValue = "Details will appear here after a step runs."
        root.addArrangedSubview(detailsLabel)
    }

    private func buttonRow(_ buttons: [NSButton]) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        buttons.forEach { row.addArrangedSubview($0) }
        return row
    }

    private func button(_ title: String, _ action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }

    @objc private func installCloudflared() {
        runCloudflareStep(["install-cloudflared"], successMessage: "cloudflared is installed.")
    }

    @objc private func loginCloudflare() {
        guard let script = scriptURL() else {
            outputLabel.stringValue = "Could not find setup-cloudflare-remote-access.sh."
            return
        }
        let command = "cd \(shellQuoted(FileManager.default.currentDirectoryPath)) && \(shellQuoted(script.path)) login"
        runInTerminal(command)
        outputLabel.stringValue = "Cloudflare sign-in opened in Terminal. Return here after the browser flow completes."
        detailsLabel.stringValue = command
    }

    @objc private func configurePermanent() {
        let hostname = hostnameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawTunnelName = tunnelNameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let tunnelName = rawTunnelName.isEmpty ? "codepilot" : rawTunnelName
        guard !hostname.isEmpty else {
            outputLabel.stringValue = "Enter a hostname such as codepilot.example.com."
            return
        }

        runCloudflareSteps([
            ["configure-permanent", "--hostname", hostname, "--tunnel-name", tunnelName],
            ["install-service"],
            ["verify", "--url", "https://\(hostname)"]
        ], successMessage: "Remote access is configured for https://\(hostname).")
    }

    @objc private func startTemporary() {
        runCloudflareStep(["start-trycloudflare"], successMessage: "Temporary Cloudflare URL started. Use this only for testing.")
    }

    @objc private func openCloudflareDashboard() {
        if let url = URL(string: "https://dash.cloudflare.com/") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func closeSheet() {
        guard let window else { return }
        window.sheetParent?.endSheet(window)
    }

    private func runCloudflareStep(_ arguments: [String], successMessage: String) {
        runCloudflareSteps([arguments], successMessage: successMessage)
    }

    private func runCloudflareSteps(_ steps: [[String]], successMessage: String) {
        guard let script = scriptURL() else {
            outputLabel.stringValue = "Could not find setup-cloudflare-remote-access.sh."
            return
        }
        outputLabel.stringValue = "Running Cloudflare setup..."
        detailsLabel.stringValue = steps.map { ([script.path] + $0).joined(separator: " ") }.joined(separator: "\n")

        DispatchQueue.global(qos: .userInitiated).async {
            var combinedOutput: [String] = []
            for arguments in steps {
                let result = self.runProcess(script: script, arguments: arguments)
                combinedOutput.append(result.output)
                if result.status != 0 {
                    DispatchQueue.main.async {
                        self.outputLabel.stringValue = CodePilotCloudflareErrorMapper.message(forExitCode: result.status)
                        self.detailsLabel.stringValue = combinedOutput.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    return
                }
            }

            DispatchQueue.main.async {
                self.outputLabel.stringValue = successMessage
                self.detailsLabel.stringValue = combinedOutput.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }

    private func runProcess(script: URL, arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [script.path] + arguments
        process.standardOutput = pipe
        process.standardError = pipe
        process.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return (process.terminationStatus, output)
        } catch {
            return (1, error.localizedDescription)
        }
    }

    private func scriptURL() -> URL? {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("scripts/setup-cloudflare-remote-access.sh"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("scripts/setup-cloudflare-remote-access.sh")
        ].compactMap { $0 }
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func runInTerminal(_ command: String) {
        let script = """
        tell application "Terminal"
            activate
            do script "\(command.replacingOccurrences(of: "\"", with: "\\\""))"
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        if let error {
            outputLabel.stringValue = String(describing: error)
        }
    }

    private func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

private enum RemoteDesktopRPCValidationError: Error {
    case invalidRequest
}

private struct RemoteDesktopSignalResponse: Codable {
    let signals: [MacPeerSignal]
}

private final class RemoteDesktopResultBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Result<Value, Error>?

    func store(_ value: Result<Value, Error>) {
        lock.lock()
        self.value = value
        lock.unlock()
    }

    func load() -> Result<Value, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private final class GatewayRemoteInputValidator: RemoteInputLeaseValidating {
    private let lock = NSLock()
    private var lastSequenceBySession: [String: UInt64] = [:]

    func validateInput(sessionID: String, sequence: UInt64) throws {
        lock.lock()
        defer { lock.unlock() }
        if let last = lastSequenceBySession[sessionID], sequence <= last {
            throw RemoteDesktopSecurityError.sequenceReplay
        }
        lastSequenceBySession[sessionID] = sequence
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let switcher = CodexAccountSwitcher()
    private let remoteFrameCaptureService = RemoteFrameCaptureService()
    private let remoteInputInjector = RemoteInputInjector(validator: GatewayRemoteInputValidator())
    private lazy var macPeerConnection = MacPeerConnection { [weak self] event in
        guard let self else { return nil }
        let displayFrame = CGDisplayBounds(CGMainDisplayID())
        try self.remoteInputInjector.handle(event, displayFrame: displayFrame)
        let cursor = CGEvent(source: nil)?.location ?? .zero
        return CGPoint(
            x: min(1, max(0, (cursor.x - displayFrame.minX) / displayFrame.width)),
            y: min(1, max(0, (cursor.y - displayFrame.minY) / displayFrame.height))
        )
    }
    private var remoteDesktopCoordinator: RemoteDesktopCoordinator?
    private var remoteDesktopSocketServer: RemoteDesktopSocketServer?
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var setupWindowController: CodePilotSetupWindowController?
    private var remoteDesktopWindowController: RemoteDesktopWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        CodePilotHostServicesManager.ensureConfiguredOnLaunch()

        if !CGPreflightScreenCaptureAccess() {
            _ = CGRequestScreenCaptureAccess()
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "CodePilot"
        menu.delegate = self
        statusItem.menu = menu
        remoteDesktopCoordinator = try? RemoteDesktopCoordinator()
        if let remoteDesktopCoordinator {
            do {
                let server = RemoteDesktopSocketServer { [weak self, weak remoteDesktopCoordinator] request in
                    guard let self, let remoteDesktopCoordinator else {
                        return Self.remoteDesktopRPCError(request.id, status: 503, code: "host_unavailable")
                    }
                    return self.handleRemoteDesktopRPC(request, coordinator: remoteDesktopCoordinator)
                }
                try server.start()
                remoteDesktopSocketServer = server
            } catch {
                NSLog("CodePilot remote desktop host failed to start: \(error.localizedDescription)")
            }
        }
        switcher.onChange = { [weak self] in self?.updateStatusTitle() }
        switcher.start()
        updateStatusTitle()
    }

    private func updateStatusTitle() {
        DispatchQueue.main.async {
            let active = self.switcher.activeAccountName()
            let usage = self.switcher.usage(for: active)
            let warning = self.switcher.staleAuthProfiles().isEmpty ? "" : "! "
            self.statusItem.button?.title = "CodePilot: \(warning)\(active) \(self.compactRateLimitSummary(usage))"
            let isRemoteControlled = self.remoteDesktopCoordinator?.snapshot.activeSession != nil
            self.statusItem.button?.contentTintColor = isRemoteControlled ? .systemRed : nil
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenuItems(in: menu)
    }

    private func rebuildMenuItems(in menu: NSMenu) {
        menu.removeAllItems()

        let status = NSMenuItem(title: switcher.statusMessage, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        let active = NSMenuItem(title: "Active: \(switcher.activeAccountName())", action: nil, keyEquivalent: "")
        active.isEnabled = false
        menu.addItem(active)

        let staleProfiles = switcher.staleAuthProfiles()
        if !staleProfiles.isEmpty {
            menu.addItem(.separator())
            for profile in staleProfiles {
                let item = NSMenuItem(
                    title: "Auth stale: \(profile.name) - Refresh Login...",
                    action: #selector(beginRefreshProfileLogin(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = profile.name
                item.toolTip = switcher.authStaleReason(for: profile.name)
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        let setup = NSMenuItem(title: "Setup CodePilot...", action: #selector(openSetup), keyEquivalent: ",")
        setup.target = self
        menu.addItem(setup)

        let remoteDesktop = NSMenuItem(title: "Remote Desktop...", action: #selector(openRemoteDesktop), keyEquivalent: "r")
        remoteDesktop.target = self
        remoteDesktop.isEnabled = remoteDesktopCoordinator != nil
        menu.addItem(remoteDesktop)

        let profiles = switcher.profiles()
        if profiles.isEmpty {
            let item = NSMenuItem(title: "No account profiles found", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else {
            for profile in profiles {
                let usage = switcher.usage(for: profile.name)
                let staleSuffix = switcher.authStaleReason(for: profile.name) == nil ? "" : "  [auth stale]"
                let item = NSMenuItem(
                    title: "\(profile.name)\(staleSuffix)  \(rateLimitSummary(usage))",
                    action: #selector(switchToProfile(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = profile.name
                item.state = profile.name == switcher.activeAccountName() ? .on : .off
                item.toolTip = usageDetail(usage)
                menu.addItem(item)
            }
        }

        let refreshProjects = NSMenuItem(title: "Refresh Codex Project List", action: #selector(refreshCodexProjectList), keyEquivalent: "")
        refreshProjects.target = self
        menu.addItem(refreshProjects)

        menu.addItem(.separator())
        if switcher.loginCapturePending {
            let saveTitle: String
            if let replacement = switcher.loginReplacementAccountName {
                saveTitle = "Save Refreshed Login for \(replacement)"
            } else {
                saveTitle = "Save Logged-In Account..."
            }
            let saveLogin = NSMenuItem(title: saveTitle, action: #selector(saveLoggedInAccount), keyEquivalent: "l")
            saveLogin.target = self
            menu.addItem(saveLogin)

            let cancelLogin = NSMenuItem(title: "Cancel Login Capture", action: #selector(cancelManualLogin), keyEquivalent: "")
            cancelLogin.target = self
            menu.addItem(cancelLogin)
        } else {
            let login = NSMenuItem(title: "Log In New Account...", action: #selector(beginManualLogin), keyEquivalent: "l")
            login.target = self
            menu.addItem(login)
        }

        let switchNow = NSMenuItem(title: "Switch Now", action: #selector(switchNow), keyEquivalent: "s")
        switchNow.target = self
        menu.addItem(switchNow)

        let pauseTitle = switcher.isPaused ? "Resume Monitoring" : "Pause Monitoring"
        let pause = NSMenuItem(title: pauseTitle, action: #selector(togglePaused), keyEquivalent: "p")
        pause.target = self
        menu.addItem(pause)

        let openFolder = NSMenuItem(title: "Open Accounts Folder", action: #selector(openAccountsFolder), keyEquivalent: "o")
        openFolder.target = self
        menu.addItem(openFolder)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
    }

    @objc private func switchNow() {
        switcher.switchNow()
    }

    @objc private func togglePaused() {
        switcher.togglePaused()
    }

    @objc private func openAccountsFolder() {
        switcher.openAccountsFolder()
    }

    @objc private func openSetup() {
        if setupWindowController == nil {
            setupWindowController = CodePilotSetupWindowController()
        }
        setupWindowController?.showWindow(nil)
        setupWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openRemoteDesktop() {
        guard let remoteDesktopCoordinator else { return }
        if remoteDesktopWindowController == nil {
            remoteDesktopWindowController = RemoteDesktopWindowController(coordinator: remoteDesktopCoordinator)
        }
        remoteDesktopWindowController?.showWindow(nil)
        remoteDesktopWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func handleRemoteDesktopRPC(
        _ request: HostRPCRequest,
        coordinator: RemoteDesktopCoordinator
    ) -> HostRPCResponse {
        do {
            switch request.method {
            case "status":
                coordinator.refreshStatus()
                let status = coordinator.snapshot
                let displayFrame = CGDisplayBounds(CGMainDisplayID())
                let cursor = CGEvent(source: nil)?.location ?? .zero
                return try Self.remoteDesktopRPCJSON(request.id, [
                    "ok": true,
                    "screenRecordingGranted": status.screenRecordingGranted,
                    "accessibilityGranted": status.accessibilityGranted,
                    "macUnlocked": status.macUnlocked,
                    "trustedDeviceCount": status.trustedDevices.count,
                    "displayFrame": [
                        "width": displayFrame.width,
                        "height": displayFrame.height
                    ],
                    "cursor": [
                        "x": min(1, max(0, (cursor.x - displayFrame.minX) / displayFrame.width)),
                        "y": min(1, max(0, (cursor.y - displayFrame.minY) / displayFrame.height))
                    ],
                    "capabilities": [
                        "pairing": true,
                        "sessions": true,
                        "screen": true,
                        "input": status.accessibilityGranted
                    ]
                ])

            case "pairing.start":
                let payload = try Self.remoteDesktopRPCPayload(request.payload)
                let deviceID = try Self.remoteDesktopString(payload["deviceId"])
                let name = try Self.remoteDesktopString(payload["name"])
                let publicKey = try Self.remoteDesktopBase64(payload["publicKey"])
                let pending = try coordinator.beginPairing(
                    deviceID: deviceID,
                    name: name,
                    publicKeyRawRepresentation: publicKey,
                    macName: Host.current().localizedName ?? "Mac"
                )
                return try Self.remoteDesktopRPCCodable(request.id, pending.challenge)

            case "pairing.complete":
                let payload = try Self.remoteDesktopRPCPayload(request.payload)
                let challengeID = try Self.remoteDesktopString(payload["challengeId"])
                let deviceID = try Self.remoteDesktopString(payload["deviceId"])
                let signature = try Self.remoteDesktopBase64(payload["signature"])
                let approval = try coordinator.verifyPendingPairing(
                    challengeID: challengeID,
                    deviceID: deviceID,
                    signature: signature
                )
                return try Self.remoteDesktopRPCCodable(request.id, approval)

            case "devices.list":
                coordinator.refreshStatus()
                return try Self.remoteDesktopRPCJSON(request.id, [
                    "devices": try Self.remoteDesktopJSONArray(coordinator.snapshot.trustedDevices)
                ])

            case "devices.revoke":
                let payload = try Self.remoteDesktopRPCPayload(request.payload)
                let deviceID = try Self.remoteDesktopString(payload["deviceId"])
                let device = try coordinator.pairingStore.revokeDevice(id: deviceID)
                coordinator.refreshStatus()
                return try Self.remoteDesktopRPCCodable(request.id, device)

            case "audit.list":
                coordinator.refreshStatus()
                return try Self.remoteDesktopRPCJSON(request.id, [
                    "events": try Self.remoteDesktopJSONArray(coordinator.snapshot.auditEvents),
                    "nextCursor": NSNull()
                ])

            case "frame.capture":
                let frame = try remoteFrameCaptureService.captureMainDisplayJPEG()
                return HostRPCResponse(id: request.id, status: 200, payload: frame, errorCode: nil)

            case "session.signal":
                let payload = try Self.remoteDesktopRPCPayload(request.payload)
                let sessionID = try Self.remoteDesktopString(payload["sessionId"])
                let sequence = try Self.remoteDesktopUInt64(payload["sequence"])
                let kindRaw = try Self.remoteDesktopString(payload["kind"])
                guard let kind = MacPeerSignal.Kind(rawValue: kindRaw) else {
                    throw RemoteDesktopRPCValidationError.invalidRequest
                }
                let signalPayload = try Self.remoteDesktopBase64(payload["payload"])
                if macPeerConnection.state == .idle || macPeerConnection.state == .disconnected(leaseID: sessionID) {
                    macPeerConnection.start(leaseID: sessionID)
                }
                let signal = MacPeerSignal(
                    leaseID: sessionID,
                    sequence: sequence,
                    kind: kind,
                    payload: signalPayload
                )
                try macPeerConnection.acceptRemoteSignal(signal)
                guard kind == .offer, let offer = String(data: signalPayload, encoding: .utf8) else {
                    return try Self.remoteDesktopRPCCodable(request.id, RemoteDesktopSignalResponse(signals: []))
                }
                let answer = try Self.remoteDesktopAwait {
                    try await self.macPeerConnection.answer(offerSDP: offer)
                }
                let answerSignal = MacPeerSignal(
                    leaseID: sessionID,
                    sequence: 1,
                    kind: .answer,
                    payload: Data(answer.utf8)
                )
                return try Self.remoteDesktopRPCCodable(
                    request.id,
                    RemoteDesktopSignalResponse(signals: [answerSignal])
                )

            case "session.end":
                macPeerConnection.disconnect()
                return try Self.remoteDesktopRPCJSON(request.id, ["ok": true])

            case "input.inject":
                coordinator.refreshStatus()
                guard coordinator.snapshot.accessibilityGranted else {
                    return Self.remoteDesktopRPCError(request.id, status: 403, code: "accessibility_required")
                }
                let decoder = JSONDecoder()
                let event = try decoder.decode(RemoteInputEvent.self, from: request.payload)
                let displayFrame = CGDisplayBounds(CGMainDisplayID())
                try remoteInputInjector.handle(event, displayFrame: displayFrame)
                let cursor = CGEvent(source: nil)?.location ?? .zero
                return try Self.remoteDesktopRPCJSON(request.id, [
                    "ok": true,
                    "cursor": [
                        "x": min(1, max(0, (cursor.x - displayFrame.minX) / displayFrame.width)),
                        "y": min(1, max(0, (cursor.y - displayFrame.minY) / displayFrame.height))
                    ]
                ])

            default:
                return Self.remoteDesktopRPCError(request.id, status: 404, code: "unsupported_method")
            }
        } catch {
            return Self.remoteDesktopRPCError(
                request.id,
                status: 400,
                code: Self.remoteDesktopRPCErrorCode(error)
            )
        }
    }

    private static func remoteDesktopRPCPayload(_ data: Data) throws -> [String: Any] {
        if data.isEmpty {
            return [:]
        }
        let object = try JSONSerialization.jsonObject(with: data)
        guard let payload = object as? [String: Any] else {
            throw RemoteDesktopRPCValidationError.invalidRequest
        }
        return payload
    }

    private static func remoteDesktopString(_ value: Any?) throws -> String {
        guard let string = value as? String, !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RemoteDesktopRPCValidationError.invalidRequest
        }
        return string
    }

    private static func remoteDesktopUInt64(_ value: Any?) throws -> UInt64 {
        if let number = value as? NSNumber, number.uint64Value > 0 {
            return number.uint64Value
        }
        throw RemoteDesktopRPCValidationError.invalidRequest
    }

    private static func remoteDesktopBase64(_ value: Any?) throws -> Data {
        let string = try remoteDesktopString(value)
        guard let data = Data(base64Encoded: string) else {
            throw RemoteDesktopRPCValidationError.invalidRequest
        }
        return data
    }

    private static func remoteDesktopRPCCodable<T: Encodable>(_ id: UUID, _ value: T) throws -> HostRPCResponse {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.dataEncodingStrategy = .base64
        return HostRPCResponse(id: id, status: 200, payload: try encoder.encode(value), errorCode: nil)
    }

    private static func remoteDesktopJSONArray<T: Encodable>(_ values: [T]) throws -> [[String: Any]] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.dataEncodingStrategy = .base64
        let data = try encoder.encode(values)
        return (try JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
    }

    private static func remoteDesktopRPCJSON(_ id: UUID, _ value: [String: Any]) throws -> HostRPCResponse {
        HostRPCResponse(
            id: id,
            status: 200,
            payload: try JSONSerialization.data(withJSONObject: value),
            errorCode: nil
        )
    }

    private static func remoteDesktopRPCError(_ id: UUID, status: Int, code: String) -> HostRPCResponse {
        HostRPCResponse(id: id, status: status, payload: Data(), errorCode: code)
    }

    private static func remoteDesktopRPCErrorCode(_ error: Error) -> String {
        switch error as? RemoteDesktopSecurityError {
        case .challengeExpired, .challengeAlreadyUsed, .challengeUnknown:
            return "pairing_expired"
        case .invalidSignature:
            return "invalid_signature"
        case .deviceRevoked, .untrustedDevice:
            return "untrusted_device"
        default:
            return "invalid_request"
        }
    }

    private static func remoteDesktopAwait<T>(
        timeout: TimeInterval = 10,
        operation: @escaping () async throws -> T
    ) throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        let result = RemoteDesktopResultBox<T>()
        Task {
            let value: Result<T, Error>
            do { value = .success(try await operation()) }
            catch { value = .failure(error) }
            result.store(value)
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + timeout) == .success else {
            throw RemoteDesktopRPCValidationError.invalidRequest
        }
        guard let value = result.load() else {
            throw RemoteDesktopRPCValidationError.invalidRequest
        }
        return try value.get()
    }

    @objc private func switchToProfile(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        switcher.switchToAccount(named: name)
    }

    @objc private func refreshCodexProjectList() {
        switcher.refreshCodexProjectList()
    }

    @objc private func beginManualLogin() {
        switcher.beginManualLogin()
    }

    @objc private func beginRefreshProfileLogin(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        switcher.beginProfileLoginRefresh(named: name)
    }

    @objc private func saveLoggedInAccount() {
        if let replacement = switcher.loginReplacementAccountName {
            switcher.saveLoggedInAccount(named: replacement)
            return
        }

        let alert = NSAlert()
        alert.messageText = "Save Logged-In Account"
        alert.informativeText = "Enter the account name to show in the switcher."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        input.placeholderString = "personal, work, backup"
        alert.accessoryView = input

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            switcher.saveLoggedInAccount(named: input.stringValue)
        }
    }

    @objc private func cancelManualLogin() {
        switcher.cancelManualLogin()
    }

    private func rateLimitSummary(_ usage: AccountUsage) -> String {
        "\(fiveHourSummary(usage))  \(weeklySummary(usage))"
    }

    private func compactRateLimitSummary(_ usage: AccountUsage) -> String {
        "\(fiveHourSummary(usage)) \(weeklySummary(usage))"
    }

    private func percent(_ value: Int?) -> String {
        guard let value else { return "--" }
        return "\(max(0, min(100, value)))%"
    }

    private func fiveHourSummary(_ usage: AccountUsage) -> String {
        "5h: \(percent(usage.dailyLimitRemainingPercent))\(compactReset(usage.dailyLimitResetsAt, style: .fiveHour))"
    }

    private func weeklySummary(_ usage: AccountUsage) -> String {
        "W: \(percent(usage.weeklyLimitRemainingPercent))\(compactReset(usage.weeklyLimitResetsAt, style: .weekly))"
    }

    private func compactReset(_ date: Date?, style: RefreshCountdownStyle) -> String {
        guard let date else { return "" }
        return " (\(durationUntilRefresh(date, style: style)))"
    }

    private func usageDetail(_ usage: AccountUsage) -> String {
        var parts = [
            "5h remaining: \(percent(usage.dailyLimitRemainingPercent))\(resetSuffix(usage.dailyLimitResetsAt, style: .fiveHour))",
            "Weekly remaining: \(percent(usage.weeklyLimitRemainingPercent))\(resetSuffix(usage.weeklyLimitResetsAt, style: .weekly))",
            "5h used: \(percent(usage.dailyLimitUsedPercent))\(windowSuffix(usage.dailyLimitWindowMins))",
            "Weekly used: \(percent(usage.weeklyLimitUsedPercent))\(windowSuffix(usage.weeklyLimitWindowMins))",
            "Turn events tracked locally: \(usage.turnEvents)",
            "Limit hits tracked locally: \(usage.limitHits)",
            "Manual switches: \(usage.manualSwitches)",
            "Automatic switches: \(usage.automaticSwitches)"
        ]
        if let lastRateLimitRefreshAt = usage.lastRateLimitRefreshAt {
            parts.append("Rate limits refreshed: \(Self.dateFormatter.string(from: lastRateLimitRefreshAt))")
        }
        if let authStaleAt = usage.authStaleAt {
            parts.append("Auth marked stale: \(Self.dateFormatter.string(from: authStaleAt))")
        }
        if let authStaleReason = usage.authStaleReason, !authStaleReason.isEmpty {
            parts.append("Auth stale reason: \(authStaleReason)")
        }
        if let rateLimitError = usage.rateLimitError, !rateLimitError.isEmpty {
            parts.append("Rate limit refresh error: \(rateLimitError)")
        }
        if let lastUsedAt = usage.lastUsedAt {
            parts.append("Last used: \(Self.dateFormatter.string(from: lastUsedAt))")
        }
        if let lastLimitAt = usage.lastLimitAt {
            parts.append("Last limit: \(Self.dateFormatter.string(from: lastLimitAt))")
        }
        return parts.joined(separator: "\n")
    }

    private func resetSuffix(_ date: Date?, style: RefreshCountdownStyle) -> String {
        guard let date else { return "" }
        return " (resets in \(durationUntilRefresh(date, style: style)))"
    }

    private func windowSuffix(_ minutes: Int?) -> String {
        guard let minutes else { return "" }
        if minutes % 10_080 == 0 {
            let weeks = minutes / 10_080
            return weeks == 1 ? " (weekly window)" : " (\(weeks)-week window)"
        }
        if minutes % 1_440 == 0 {
            let days = minutes / 1_440
            return days == 1 ? " (24h window)" : " (\(days)-day window)"
        }
        if minutes % 60 == 0 {
            return " (\(minutes / 60)h window)"
        }
        return " (\(minutes)m window)"
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
