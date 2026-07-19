# Total Credit Live Activity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an optional, gateway-updated Live Activity that displays aggregate CodePilot account credit on the Lock Screen and Dynamic Island.

**Architecture:** Extract aggregate credit into a presentation-neutral shared model, render it from a WidgetKit extension, and manage ActivityKit lifecycle through an injected coordinator. Register Live Activity push tokens with authenticated gateway endpoints and publish deduplicated APNs liveactivity updates from the existing account-status refresh path.

**Tech Stack:** Swift 5, SwiftUI, ActivityKit, WidgetKit, XCTest, Python 3, `unittest`, APNs HTTP/2, Xcode project targets, CodePilot OTA tooling.

---

## File Map

- Create `ios/CodexPhone/Shared/TotalCreditActivityAttributes.swift`: Codable ActivityKit attributes and presentation-neutral aggregate state shared by app and widget.
- Create `ios/CodexPhone/CodexPhone/TotalCreditStatus.swift`: account-usage to activity-state calculation.
- Create `ios/CodexPhone/CodexPhone/TotalCreditActivityController.swift`: ActivityKit lifecycle, push-token registration, and reconciliation.
- Create `ios/CodexPhone/CodePilotCreditWidget/CodePilotCreditWidget.swift`: Lock Screen and Dynamic Island rendering.
- Create `ios/CodexPhone/CodePilotCreditWidget/Info.plist`: widget extension metadata.
- Create `ios/CodexPhone/CodexPhoneTests/TotalCreditActivityTests.swift`: state and lifecycle tests.
- Modify `ios/CodexPhone/CodexPhone/CodexPhoneApp.swift`: settings toggle, app reconciliation, deep link, and shared status use.
- Modify `ios/CodexPhone/CodexPhone.xcodeproj/project.pbxproj`: shared files and widget extension target/embed phase.
- Modify `gateway/codex_phone_gateway.py`: registration storage, authenticated routes, state publication, and APNs liveactivity requests.
- Modify `gateway/test_codex_phone_gateway.py`: endpoint, deduplication, payload, and token cleanup tests.

### Task 1: Shared Aggregate Credit State

**Files:**
- Create: `ios/CodexPhone/Shared/TotalCreditActivityAttributes.swift`
- Create: `ios/CodexPhone/CodexPhone/TotalCreditStatus.swift`
- Create: `ios/CodexPhone/CodexPhoneTests/TotalCreditActivityTests.swift`
- Modify: `ios/CodexPhone/CodexPhone/CodexPhoneApp.swift:2708-2805`

- [ ] **Step 1: Write failing aggregate-state tests**

Cover available credit, refilling, authentication required, unavailable data, bounded progress, and absence of account names from the content state. Use fixed dates and existing `AccountUsageStatus` fixtures.

```swift
func testAvailableAccountsProduceBoundedActivityState() {
    let state = TotalCreditStatus(accounts: fixtures, now: Date(timeIntervalSince1970: 1_800_000_000)).activityState
    XCTAssertEqual(state.kind, .available)
    XCTAssertEqual(state.percent, 68)
    XCTAssertEqual(state.usableAccountCount, 3)
    XCTAssertEqual(state.reportedAccountCount, 4)
    XCTAssertEqual(state.progress, 0.68, accuracy: 0.001)
}
```

- [ ] **Step 2: Verify the new tests fail**

Run: `xcodebuild test -project ios/CodexPhone/CodexPhone.xcodeproj -scheme CodexPhone -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:CodexPhoneTests/TotalCreditActivityTests`

Expected: FAIL because `TotalCreditStatus` and `TotalCreditActivityAttributes` do not exist.

- [ ] **Step 3: Implement the shared data types and calculator**

Define `TotalCreditActivityAttributes.ContentState` with `kind`, `percent`, `progress`, `usableAccountCount`, `reportedAccountCount`, `nextRefreshAt`, `refreshLabel`, and `generatedAt`. Move calculation out of the SwiftUI view; adapt `AggregateCreditBar` to render `TotalCreditStatus`.

- [ ] **Step 4: Verify aggregate tests pass**

Run the command from Step 2.

Expected: PASS.

- [ ] **Step 5: Commit the shared model**

```bash
git add ios/CodexPhone/Shared ios/CodexPhone/CodexPhone/TotalCreditStatus.swift ios/CodexPhone/CodexPhoneTests/TotalCreditActivityTests.swift ios/CodexPhone/CodexPhone/CodexPhoneApp.swift
git commit -m "feat: share aggregate credit state"
```

### Task 2: Testable ActivityKit Lifecycle

**Files:**
- Create: `ios/CodexPhone/CodexPhone/TotalCreditActivityController.swift`
- Modify: `ios/CodexPhone/CodexPhoneTests/TotalCreditActivityTests.swift`
- Modify: `ios/CodexPhone/CodexPhone/CodexPhoneApp.swift`

- [ ] **Step 1: Write failing lifecycle tests**

Use an `ActivitySessionManaging` fake to assert that enabling starts exactly one activity, repeated reconciliation updates rather than duplicates, disabling ends activities, and a changed push token replaces registration.

```swift
func testRepeatedReconciliationDoesNotCreateDuplicateActivity() async throws {
    let sessions = FakeActivitySessions()
    let controller = TotalCreditActivityController(sessions: sessions, registrar: FakeRegistrar())
    try await controller.reconcile(enabled: true, state: .fixture)
    try await controller.reconcile(enabled: true, state: .fixture)
    XCTAssertEqual(sessions.startCount, 1)
    XCTAssertEqual(sessions.updateCount, 1)
}
```

- [ ] **Step 2: Verify lifecycle tests fail**

Run the focused Xcode test command from Task 1.

Expected: FAIL because the lifecycle interfaces and controller do not exist.

- [ ] **Step 3: Implement lifecycle interfaces and controller**

Wrap `Activity<TotalCreditActivityAttributes>` behind `ActivitySessionManaging`. Request with `.token`, observe `pushTokenUpdates`, register changed tokens, update existing content, and end all activities when disabled. Expose concise recoverable errors for Settings.

- [ ] **Step 4: Verify lifecycle tests pass**

Run the focused Xcode test command.

Expected: PASS.

- [ ] **Step 5: Commit lifecycle code**

```bash
git add ios/CodexPhone/CodexPhone/TotalCreditActivityController.swift ios/CodexPhone/CodexPhoneTests/TotalCreditActivityTests.swift
git commit -m "feat: manage total credit live activity"
```

### Task 3: Widget And Dynamic Island UI

**Files:**
- Create: `ios/CodexPhone/CodePilotCreditWidget/CodePilotCreditWidget.swift`
- Create: `ios/CodexPhone/CodePilotCreditWidget/Info.plist`
- Modify: `ios/CodexPhone/CodexPhone.xcodeproj/project.pbxproj`

- [ ] **Step 1: Add the widget target and shared source membership**

Create an app-extension product with bundle identifier `io.codepilot.iOS.credit-widget`, embed it in `CodexPhone`, include the shared attributes file in both targets, and set `NSSupportsLiveActivities = YES` for the app.

- [ ] **Step 2: Implement the approved informative layout**

Render `CodePilot credit`, status percentage or fallback title, progress bar, account count, freshness, and refill countdown. Add compact/minimal bolt-plus-percentage regions and the expanded progress presentation. Set `.widgetURL(URL(string: "codepilot://threads"))`.

- [ ] **Step 3: Build the app and extension**

Run: `xcodebuild build -project ios/CodexPhone/CodexPhone.xcodeproj -scheme CodexPhone -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO`

Expected: `** BUILD SUCCEEDED **` and an embedded `CodePilotCreditWidget.appex`.

- [ ] **Step 4: Commit widget integration**

```bash
git add ios/CodexPhone/CodePilotCreditWidget ios/CodexPhone/CodexPhone.xcodeproj/project.pbxproj
git commit -m "feat: add total credit live activity widget"
```

### Task 4: Settings, Reconciliation, And Deep Link

**Files:**
- Modify: `ios/CodexPhone/CodexPhone/CodexPhoneApp.swift`
- Modify: `ios/CodexPhone/CodexPhoneTests/TotalCreditActivityTests.swift`

- [ ] **Step 1: Write failing preference and route tests**

Test that the persisted toggle defaults off, unsupported authorization cannot remain enabled, and `codepilot://threads` resolves to the root thread-list route.

- [ ] **Step 2: Verify tests fail**

Run the focused Xcode test command.

Expected: FAIL because the preference coordinator and route are absent.

- [ ] **Step 3: Implement Settings and app lifecycle integration**

Add an `@AppStorage("totalCreditLiveActivityEnabled")` toggle with explanatory footer and inline error. Reconcile on toggle changes, account-status changes, foreground entry, launch, and manual refresh. Add `onOpenURL` routing that clears presented flows and returns to the thread list.

- [ ] **Step 4: Verify tests and simulator build pass**

Run the focused tests and generic simulator build.

Expected: both PASS.

- [ ] **Step 5: Commit app integration**

```bash
git add ios/CodexPhone/CodexPhone/CodexPhoneApp.swift ios/CodexPhone/CodexPhoneTests/TotalCreditActivityTests.swift
git commit -m "feat: control credit activity from settings"
```

### Task 5: Gateway Registration API

**Files:**
- Modify: `gateway/codex_phone_gateway.py`
- Modify: `gateway/test_codex_phone_gateway.py`

- [ ] **Step 1: Write failing registration tests**

Test authenticated `POST /api/live-activities` and `DELETE /api/live-activities/{activity_id}`, rejected unauthenticated requests, storage separation from notification devices, APNs environment validation, and idempotent token replacement.

```python
def test_live_activity_registration_is_separate_from_notification_devices(self):
    response = self.client.post("/api/live-activities", json=self.live_activity_registration, headers=self.auth)
    self.assertEqual(response.status_code, 204)
    self.assertEqual(self.gateway.live_activity_store.all()[0].activity_id, "activity-1")
    self.assertEqual(self.gateway.notification_store.all(), [])
```

- [ ] **Step 2: Verify registration tests fail**

Run: `python3 -m unittest gateway.test_codex_phone_gateway.LiveActivityTests`

Expected: FAIL because routes and storage are absent.

- [ ] **Step 3: Implement validated persistent registration storage and routes**

Store activity ID, hex push token, APNs environment, bundle topic, and update timestamp under the gateway state directory. Apply existing bearer authentication and atomic JSON persistence patterns.

- [ ] **Step 4: Verify registration tests pass**

Run the command from Step 2.

Expected: PASS.

- [ ] **Step 5: Commit gateway registration**

```bash
git add gateway/codex_phone_gateway.py gateway/test_codex_phone_gateway.py
git commit -m "feat: register live activity push tokens"
```

### Task 6: Gateway APNs Publication

**Files:**
- Modify: `gateway/codex_phone_gateway.py`
- Modify: `gateway/test_codex_phone_gateway.py`

- [ ] **Step 1: Write failing publication tests**

Test the `liveactivity` push type, topic suffix `.push-type.liveactivity`, timestamp/event/content-state payload, state fingerprint deduplication, changed-state delivery, retry-safe failures, and deletion after terminal APNs token responses.

- [ ] **Step 2: Verify publication tests fail**

Run the focused gateway Live Activity test class.

Expected: FAIL because publication is absent.

- [ ] **Step 3: Extend APNs notifier and account-status publisher**

Add a dedicated notifier method with headers `apns-push-type: liveactivity`, `apns-priority: 10`, and the Live Activity topic. Publish after account-status snapshots are generated, but isolate all failures from status responses, switching, and turns. Persist the last successful content-state fingerprint per activity.

- [ ] **Step 4: Verify focused and complete gateway tests**

Run:

```bash
python3 -m unittest gateway.test_codex_phone_gateway.LiveActivityTests
python3 -m unittest gateway.test_codex_phone_gateway
```

Expected: PASS.

- [ ] **Step 5: Commit publication support**

```bash
git add gateway/codex_phone_gateway.py gateway/test_codex_phone_gateway.py
git commit -m "feat: push aggregate credit live updates"
```

### Task 7: Full Verification And OTA Release

**Files:**
- Modify only if verification exposes a defect in files already scoped above.

- [ ] **Step 1: Run privacy and repository checks**

Run:

```bash
scripts/privacy-audit.sh
git diff --check
```

Expected: PASS with no private identifiers or whitespace errors.

- [ ] **Step 2: Run iOS and gateway tests**

Run the full CodexPhone test target, generic simulator build, and complete gateway test module.

Expected: PASS.

- [ ] **Step 3: Trigger the mandatory OTA build**

POST to `http://127.0.0.1:8787/codexphone/api/build`, poll `/codexphone/api/status` until `current.state == "complete"`, and record the build identifier.

- [ ] **Step 4: Verify public OTA artifacts**

Fetch the generated tokenized manifest and IPA URLs from the approved OTA host, for example `https://ota.example.com`.

Expected: HTTP 200 for both, manifest bundle identifier `io.codepilot.iOS`, and the widget extension embedded in the IPA.

- [ ] **Step 5: Restart and health-check the gateway**

Use the repository gateway restart workflow, then confirm the authenticated health and account-status endpoints return 200.

- [ ] **Step 6: Commit any verification-only corrections**

Commit only scoped corrections after rerunning their failing test and the full verification set.
