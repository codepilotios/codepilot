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

        if pendingSwitchReason == nil, let exhausted = events.first(where: { $0.isTokenExhaustion }) {
            pendingSwitchReason = exhausted.summary
            pendingSwitchRequiresExhaustedActive = false
            recordLimitHit(for: active)
            statusMessage = "Limit detected; waiting for Codex to finish"
            appendAudit("Queued automatic switch for \(active): \(Self.singleLine(exhausted.summary, limit: 180))")
            startRateLimitRefreshIfNeeded(force: true)
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

        return Self.summary(from: rateLimit)
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

    private static func summary(from rateLimit: WhamRateLimit) -> RateLimitSummary {
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

        return RateLimitSummary(daily: daily, weekly: weekly)
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

    enum CodingKeys: String, CodingKey {
        case rateLimit = "rate_limit"
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
            weekly: weeklySource.map(windowSummary)
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
    let codexCLI: String
    let codexAuth: String
    let accounts: String
    let gatewayToken: String
    let gateway: String
    let cloudflared: String

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

        return CodePilotSetupStatus(
            codexCLI: executablePath(named: "codex") ?? "Not found",
            codexAuth: FileManager.default.fileExists(atPath: codexAuth) ? "Signed in" : "Missing auth.json",
            accounts: accountCount == 1 ? "1 profile" : "\(accountCount) profiles",
            gatewayToken: FileManager.default.fileExists(atPath: tokenPath.path) ? "Token present" : "Missing token",
            gateway: gatewayHealth(),
            cloudflared: executablePath(named: "cloudflared") ?? "Not found"
        )
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

    private static func gatewayHealth() -> String {
        guard let url = URL(string: "http://127.0.0.1:18790/api/health"),
              let data = try? Data(contentsOf: url),
              !data.isEmpty else {
            return "Not reachable"
        }
        return "Reachable"
    }
}

private final class CodePilotSetupWindowController: NSWindowController {
    private let statusStack = NSStackView()
    private let outputLabel = NSTextField(labelWithString: "")

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
                button("Install / Restart Gateway", #selector(installGateway)),
                button("Copy iOS Token", #selector(copyToken))
            ]
        ))
        root.addArrangedSubview(section(
            title: "Cloudflare",
            buttons: [
                button("Install Cloudflare Service", #selector(installCloudflare)),
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
        [
            ("Codex CLI", status.codexCLI),
            ("Codex Auth", status.codexAuth),
            ("Accounts", status.accounts),
            ("Gateway Token", status.gatewayToken),
            ("Gateway", status.gateway),
            ("Cloudflare", status.cloudflared)
        ].forEach { label, value in
            let row = NSTextField(labelWithString: "\(label): \(value)")
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

    @objc private func installGateway() {
        runBundledScript(named: "install-phone-gateway-agent.sh")
    }

    @objc private func installCloudflare() {
        runBundledScript(named: "install-phone-cloudflared-agent.sh")
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

    private func runBundledScript(named name: String) {
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
        process.arguments = [script.path, "--force"]
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

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let switcher = CodexAccountSwitcher()
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var setupWindowController: CodePilotSetupWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "CodePilot"
        menu.delegate = self
        statusItem.menu = menu
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
