import XCTest
@testable import CodexAccountSwitcher

final class ActiveTurnTrackerTests: XCTestCase {
    func testRevokedTokenUsageErrorMarksAuthStale() {
        let message = #"Codex usage request failed with HTTP 401: { "error": { "message": "Encountered invalidated oauth token for user, failing request", "code": "token_revoked" }, "status": 401 }"#

        XCTAssertTrue(AuthStaleClassifier.isStaleAuthMessage(message))
    }

    func testPollingTimerFiresDuringEventTrackingRunLoopMode() {
        var didFire = false
        let timer = PollingTimerFactory.scheduleCommonModeTimer(interval: 0.01, repeats: false) { _ in
            didFire = true
        }
        defer { timer.invalidate() }

        let deadline = Date(timeIntervalSinceNow: 0.5)
        while !didFire && Date() < deadline {
            RunLoop.main.run(mode: .eventTracking, before: Date(timeIntervalSinceNow: 0.02))
        }

        XCTAssertTrue(didFire)
    }

    func testTokenUsageDoesNotCompleteTurn() {
        var tracker = ActiveTurnTracker()

        tracker.apply(LogEvent(
            id: 1,
            timestamp: Date(timeIntervalSince1970: 1_000),
            target: "codex_core::session::turn",
            body: "session_loop{thread_id=thread-a}:turn{thread.id=thread-a turn.id=turn-a}:run_turn:run_sampling_request{turn_id=turn-a}",
            estimatedBytes: 0
        ))

        XCTAssertEqual(tracker.activeTurnCount, 1)

        tracker.apply(LogEvent(
            id: 2,
            timestamp: Date(timeIntervalSince1970: 1_010),
            target: "codex_core::session::turn",
            body: "session_loop{thread_id=thread-a}:turn{thread.id=thread-a turn.id=turn-a}:run_turn: post sampling token usage turn_id=turn-a model_needs_follow_up=false has_pending_input=false needs_follow_up=false",
            estimatedBytes: 0
        ))

        XCTAssertEqual(tracker.activeTurnCount, 1)
    }

    func testFollowUpUsageLineDoesNotCompleteTurn() {
        var tracker = ActiveTurnTracker()

        tracker.apply(LogEvent(
            id: 1,
            timestamp: Date(timeIntervalSince1970: 1_000),
            target: "codex_core::session::turn",
            body: "session_loop{thread_id=thread-a}:turn{thread.id=thread-a turn.id=turn-a}:run_turn:run_sampling_request{turn_id=turn-a}",
            estimatedBytes: 0
        ))
        tracker.apply(LogEvent(
            id: 2,
            timestamp: Date(timeIntervalSince1970: 1_010),
            target: "codex_core::session::turn",
            body: "session_loop{thread_id=thread-a}:turn{thread.id=thread-a turn.id=turn-a}:run_turn: post sampling token usage turn_id=turn-a model_needs_follow_up=true has_pending_input=false needs_follow_up=true",
            estimatedBytes: 0
        ))

        XCTAssertEqual(tracker.activeTurnCount, 1)
    }

    func testAgentLoopExitClearsThreadTurns() {
        var tracker = ActiveTurnTracker()

        tracker.apply(LogEvent(
            id: 1,
            timestamp: Date(timeIntervalSince1970: 1_000),
            target: "codex_core::session::turn",
            body: "session_loop{thread_id=thread-a}:turn{thread.id=thread-a turn.id=turn-a}:run_turn",
            estimatedBytes: 0
        ))
        tracker.apply(LogEvent(
            id: 2,
            timestamp: Date(timeIntervalSince1970: 1_005),
            target: "codex_core::session::turn",
            body: "session_loop{thread_id=thread-b}:turn{thread.id=thread-b turn.id=turn-b}:run_turn",
            estimatedBytes: 0
        ))
        tracker.apply(LogEvent(
            id: 3,
            timestamp: Date(timeIntervalSince1970: 1_010),
            target: "codex_core::session::handlers",
            body: "session_loop{thread_id=thread-a}: Agent loop exited",
            estimatedBytes: 0
        ))

        XCTAssertEqual(tracker.activeTurnCount, 1)
        XCTAssertEqual(tracker.activeTurnDescriptions, ["thread-b/turn-b"])
    }

    func testThreadIdleStatusClearsThreadTurns() {
        var tracker = ActiveTurnTracker()

        tracker.apply(LogEvent(
            id: 1,
            timestamp: Date(timeIntervalSince1970: 1_000),
            target: "codex_core::session::turn",
            body: "session_loop{thread_id=thread-a}:turn{thread.id=thread-a turn.id=turn-a}:run_turn",
            estimatedBytes: 0
        ))
        tracker.apply(LogEvent(
            id: 2,
            timestamp: Date(timeIntervalSince1970: 1_005),
            target: "codex_core::session::turn",
            body: "session_loop{thread_id=thread-b}:turn{thread.id=thread-b turn.id=turn-b}:run_turn",
            estimatedBytes: 0
        ))
        tracker.apply(LogEvent(
            id: 3,
            timestamp: Date(timeIntervalSince1970: 1_010),
            target: "log",
            body: #"Sending frame: Frame { payload: b"{\"type\":\"server_message\",\"message\":{\"method\":\"thread/status/changed\",\"params\":{\"threadId\":\"thread-a\",\"status\":{\"type\":\"idle\"}}}}" }"#,
            estimatedBytes: 0
        ))

        XCTAssertEqual(tracker.activeTurnCount, 1)
        XCTAssertEqual(tracker.activeTurnDescriptions, ["thread-b/turn-b"])
    }

    func testQuitGuardAllowsWhenNoTurnOrPhoneJobsAreActive() {
        XCTAssertEqual(
            CodexQuitGuard.blockers(activeTurnDescriptions: [], phoneGatewayJobDescriptions: []),
            []
        )
    }

    func testQuitGuardBlocksWhenLogTurnIsActive() {
        XCTAssertEqual(
            CodexQuitGuard.blockers(activeTurnDescriptions: ["thread-a/turn-a"], phoneGatewayJobDescriptions: []),
            ["thread-a/turn-a"]
        )
    }

    func testQuitGuardBlocksWhenPhoneJobIsActive() {
        XCTAssertEqual(
            CodexQuitGuard.blockers(activeTurnDescriptions: [], phoneGatewayJobDescriptions: ["phone:thread-b/job-b"]),
            ["phone:thread-b/job-b"]
        )
    }

    func testAuthProfileSynchronizerPersistsNewerActiveAuthToActiveProfile() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let codexDir = root.appendingPathComponent("codex", isDirectory: true)
        let accountsDir = root.appendingPathComponent("accounts", isDirectory: true)
        let mainDir = accountsDir.appendingPathComponent("Main", isDirectory: true)
        try FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: mainDir, withIntermediateDirectories: true)

        let activeAuth = codexDir.appendingPathComponent("auth.json")
        let marker = root.appendingPathComponent("active-account.txt")
        let profileAuth = mainDir.appendingPathComponent("auth.json")

        try #"{"last_refresh":"2026-06-24T08:00:00Z","tokens":{"account_id":"main-account","access_token":"active-refreshed"}}"#
            .write(to: activeAuth, atomically: true, encoding: .utf8)
        try #"{"last_refresh":"2026-06-23T08:00:00Z","tokens":{"account_id":"main-account","access_token":"old-profile"}}"#
            .write(to: profileAuth, atomically: true, encoding: .utf8)
        try "Main\n".write(to: marker, atomically: true, encoding: .utf8)

        let didSync = try AuthProfileSynchronizer.syncActiveAuthToProfile(
            activeAuth: activeAuth,
            activeAccountMarker: marker,
            accountsDir: accountsDir
        )

        XCTAssertTrue(didSync)
        let persisted = try String(contentsOf: profileAuth, encoding: .utf8)
        XCTAssertTrue(persisted.contains("active-refreshed"))
    }
}
