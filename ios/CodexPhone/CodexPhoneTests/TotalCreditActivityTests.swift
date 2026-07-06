import Foundation
import XCTest
@testable import CodexPhone

final class TotalCreditActivityTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testAvailableAccountsProduceBoundedActivityState() {
        let state = TotalCreditStatus(
            accounts: [
                account(name: "One", remaining: 100),
                account(name: "Two", remaining: 36),
            ],
            now: now
        ).activityState

        XCTAssertEqual(state.kind, .available)
        XCTAssertEqual(state.percent, 68)
        XCTAssertEqual(state.usableAccountCount, 2)
        XCTAssertEqual(state.reportedAccountCount, 2)
        XCTAssertEqual(state.progress, 0.68, accuracy: 0.001)
    }

    func testExhaustedAccountsUseEarliestFutureRefresh() {
        let resetAt = Int(now.timeIntervalSince1970) + 3_600
        let state = TotalCreditStatus(
            accounts: [account(name: "One", remaining: 0, resetAt: resetAt)],
            now: now
        ).activityState

        XCTAssertEqual(state.kind, .refilling)
        XCTAssertEqual(state.nextRefreshAt, resetAt)
        XCTAssertEqual(state.refreshLabel, "5h")
    }

    func testWeeklyExhaustionLimitsFiveHourCredit() {
        let weeklyResetAt = Int(now.timeIntervalSince1970) + 604_800
        let state = TotalCreditStatus(
            accounts: [
                account(
                    name: "One",
                    remaining: 99,
                    resetAt: Int(now.timeIntervalSince1970) + 3_600,
                    weeklyRemaining: 0,
                    weeklyResetAt: weeklyResetAt
                )
            ],
            now: now
        ).activityState

        XCTAssertEqual(state.kind, .refilling)
        XCTAssertNil(state.percent)
        XCTAssertEqual(state.progress, 0, accuracy: 0.001)
        XCTAssertEqual(state.usableAccountCount, 0)
        XCTAssertEqual(state.nextRefreshAt, weeklyResetAt)
        XCTAssertEqual(state.refreshLabel, "weekly")
    }

    func testAllStaleAccountsRequireAuthentication() {
        let state = TotalCreditStatus(
            accounts: [account(name: "Private Account", remaining: 80, authStale: true)],
            now: now
        ).activityState

        XCTAssertEqual(state.kind, .authenticationRequired)
        XCTAssertNil(state.percent)
        XCTAssertFalse(String(describing: state).contains("Private Account"))
    }

    func testMissingUsageIsUnavailableRatherThanZeroPercent() {
        let state = TotalCreditStatus(
            accounts: [account(name: "One", remaining: nil)],
            now: now
        ).activityState

        XCTAssertEqual(state.kind, .unavailable)
        XCTAssertNil(state.percent)
    }

    func testUnsupportedLiveActivitiesCannotRemainEnabled() {
        XCTAssertFalse(LiveActivityPreference.resolvedEnabled(requested: true, activitiesEnabled: false))
        XCTAssertTrue(LiveActivityPreference.resolvedEnabled(requested: true, activitiesEnabled: true))
    }

    func testThreadListDeepLinkResolvesToRootRoute() throws {
        let url = try XCTUnwrap(URL(string: "codepilot://threads"))

        XCTAssertEqual(CodePilotRoute(url: url), .threadList)
        XCTAssertNil(CodePilotRoute(url: try XCTUnwrap(URL(string: "https://example.com"))))
    }

    @MainActor
    func testRepeatedReconciliationDoesNotCreateDuplicateActivity() async throws {
        let sessions = FakeCreditActivitySessions()
        let controller = TotalCreditActivityController(sessions: sessions)
        let state = TotalCreditStatus(
            accounts: [account(name: "One", remaining: 68)],
            now: now
        ).activityState

        try await controller.reconcile(enabled: true, state: state)
        try await controller.reconcile(enabled: true, state: state)

        XCTAssertEqual(sessions.startCount, 1)
        XCTAssertEqual(sessions.updateCount, 1)
    }

    @MainActor
    func testDisablingEndsEveryCreditActivity() async throws {
        let sessions = FakeCreditActivitySessions()
        let controller = TotalCreditActivityController(sessions: sessions)
        let state = TotalCreditStatus(accounts: [], now: now).activityState

        try await controller.reconcile(enabled: true, state: state)
        try await controller.reconcile(enabled: false, state: state)

        XCTAssertEqual(sessions.endAllCount, 1)
        XCTAssertTrue(sessions.activeActivityIDs.isEmpty)
    }

    private func account(
        name: String,
        remaining: Int?,
        resetAt: Int? = nil,
        weeklyRemaining: Int? = nil,
        weeklyResetAt: Int? = nil,
        authStale: Bool = false
    ) -> AccountUsageStatus {
        AccountUsageStatus(
            name: name,
            isActive: false,
            fiveHourRemainingPercent: remaining,
            fiveHourUsedPercent: remaining.map { 100 - $0 },
            fiveHourWindowMins: 300,
            fiveHourResetsAt: resetAt,
            weeklyRemainingPercent: weeklyRemaining,
            weeklyUsedPercent: weeklyRemaining.map { 100 - $0 },
            weeklyWindowMins: weeklyRemaining == nil && weeklyResetAt == nil ? nil : 10_080,
            weeklyResetsAt: weeklyResetAt,
            rateLimitResetCreditsRemaining: nil,
            lastRefreshAt: nil,
            lastUsedAt: nil,
            lastLimitAt: nil,
            lastSwitchAt: nil,
            turnEvents: 0,
            limitHits: 0,
            manualSwitches: 0,
            automaticSwitches: 0,
            rateLimitError: "",
            authStale: authStale,
            authStaleAt: nil,
            authStaleReason: ""
        )
    }
}

@MainActor
private final class FakeCreditActivitySessions: CreditActivitySessionManaging {
    var activeActivityIDs: [String] = []
    var startCount = 0
    var updateCount = 0
    var endAllCount = 0

    func configureRegistration(baseURL: String, token: String, environment: String) {}

    func start(state: TotalCreditActivityAttributes.ContentState) async throws {
        startCount += 1
        activeActivityIDs = ["activity-1"]
    }

    func updateAll(state: TotalCreditActivityAttributes.ContentState) async {
        updateCount += 1
    }

    func endAll() async {
        endAllCount += 1
        activeActivityIDs = []
    }
}
