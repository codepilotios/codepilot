# CodePilot Production Readiness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make CodePilot ready for a public beta across TestFlight and GitHub/source distribution in parallel.

**Architecture:** Implement a stable gateway status/error contract first, then consume it from the Mac menu bar app and iOS app. Keep release documentation and verification scripts close to the behavior they describe, and avoid public docs or support diagnostics leaking machine-specific or account-specific secrets.

**Tech Stack:** SwiftPM/AppKit/SwiftUI for the Mac app, SwiftUI/UIKit/WebKit for iOS, Python `http.server` gateway, existing shell scripts, OTA build server, Fastlane/App Store Connect tooling.

---

## File Structure

- Modify `gateway/codex_phone_gateway.py`: add structured health fields and normalized error responses.
- Modify `gateway/test_codex_phone_gateway.py`: add contract tests for health, common errors, and local-web proxy errors.
- Modify `Sources/CodexAccountSwitcher/main.swift`: add setup/status model and safer gateway operation labels.
- Modify `Tests/CodexAccountSwitcherTests/*.swift`: add Mac-side tests for setup state and restart wording where testable.
- Modify `ios/CodexPhone/CodexPhone/CodexPhoneApp.swift`: add iOS connection wizard, status display, and stable error mapping inside the existing large SwiftUI file unless a task splits focused subviews.
- Modify `ios/CodexPhone/CodexPhoneTests/*.swift`: add tests for error mapping and connection-state decoding.
- Modify `docs/README.md` if it exists, otherwise `README.md`: keep the public overview current.
- Modify `docs/INSTALL_MAC.md`, `docs/INSTALL_IOS.md`, `docs/CLOUDFLARE_SETUP.md`, `docs/SECURITY.md`, and `docs/ARCHITECTURE.md`: production copy and public setup instructions.
- Create `docs/TROUBLESHOOTING.md`: user-facing recovery guide.
- Create `docs/RELEASE_CHECKLIST.md`: repeatable TestFlight and GitHub/source checklist.
- Modify `.superpowers/brainstorm/...` only for local planning visuals; do not commit those files.

## Task 1: Gateway Health And Error Contract

**Files:**
- Modify: `gateway/codex_phone_gateway.py`
- Modify: `gateway/test_codex_phone_gateway.py`

- [ ] **Step 1: Write failing tests for health shape**

Add tests that assert `/api/health` returns public-safe fields without token values:

```python
def test_health_exposes_public_gateway_status(self):
    status, payload = self.request_json("GET", "/api/health")
    self.assertEqual(status, 200)
    self.assertIn("gateway", payload)
    self.assertIn("accounts", payload)
    self.assertIn("notifications", payload)
    self.assertIn("remoteDesktop", payload)
    self.assertIn("localWeb", payload)
    self.assertNotIn("token", json.dumps(payload).lower())
```

- [ ] **Step 2: Write failing tests for normalized errors**

Add tests that verify known failures include `error.code`, `error.message`, and `error.recovery`:

```python
def test_error_payload_has_stable_code_and_recovery(self):
    status, payload = self.request_json("POST", "/api/local-web/open", body={"url": "file:///etc/passwd"})
    self.assertEqual(status, 400)
    self.assertEqual(payload["error"]["code"], "local_web_invalid_target")
    self.assertIn("localhost", payload["error"]["recovery"].lower())
```

- [ ] **Step 3: Run gateway tests and confirm failure**

Run:

```sh
cd gateway
python3 -m unittest test_codex_phone_gateway
```

Expected: the new tests fail because the health/error contract is incomplete.

- [ ] **Step 4: Add helper functions**

In `gateway/codex_phone_gateway.py`, add:

```python
def error_payload(code: str, message: str, recovery: str, details: dict | None = None) -> dict:
    payload = {"error": {"code": code, "message": message, "recovery": recovery}}
    if details:
        payload["error"]["details"] = details
    return payload


def json_error(handler, status: int, code: str, message: str, recovery: str, details: dict | None = None):
    json_response(handler, status, error_payload(code, message, recovery, details))
```

- [ ] **Step 5: Implement structured health**

Add a `GatewayState.public_health()` method that returns:

```python
{
    "gateway": {"version": read_marker(self.switcher_home / "gateway-version", "dev"), "running": True},
    "accounts": {"active": read_marker(self.active_account_marker(), ""), "auth": self.app_server_auth_status()},
    "turns": {"running": self.has_running_jobs()},
    "notifications": {"configured": bool(APNsPushNotifier.from_environment())},
    "remoteDesktop": self.remote_desktop.public_status() if self.remote_desktop else {"available": False},
    "localWeb": {"available": True, "sessionSeconds": LOCAL_WEB_SESSION_TIMEOUT_SECONDS},
}
```

Keep secrets, tokens, full auth paths, email addresses, and private hostnames out of the response.

- [ ] **Step 6: Replace raw common error responses**

Update local-web, unauthorized, thread-not-found, job-not-found, stale-auth, and app-server unavailable paths to call `json_error(...)` with these codes:

```python
"unauthorized"
"gateway_unavailable"
"app_server_unavailable"
"active_turn_running"
"auth_stale"
"account_unavailable"
"thread_not_found"
"job_not_found"
"local_web_invalid_target"
"local_web_unavailable"
"remote_desktop_permission_missing"
```

- [ ] **Step 7: Run gateway tests**

Run:

```sh
cd gateway
python3 -m unittest test_codex_phone_gateway test_remote_desktop_gateway
```

Expected: all tests pass.

- [ ] **Step 8: Commit**

```sh
git add gateway/codex_phone_gateway.py gateway/test_codex_phone_gateway.py
git commit -m "feat: expose stable gateway health and errors"
```

## Task 2: Mac Setup And Gateway Operations UI

**Files:**
- Modify: `Sources/CodexAccountSwitcher/main.swift`
- Modify: `Tests/CodexAccountSwitcherTests/ActiveTurnTrackerTests.swift` or create `Tests/CodexAccountSwitcherTests/SetupStatusTests.swift`

- [ ] **Step 1: Write tests for setup labels**

Create a small pure model test:

```swift
func testSetupStatusLabelsAreUserFacing() {
    XCTAssertEqual(SetupRequirement.gatewayStopped.statusLabel, "Stopped")
    XCTAssertEqual(SetupRequirement.gatewayBlockedByActiveTurn.statusLabel, "Blocked by active turn")
    XCTAssertEqual(SetupRequirement.cloudflareOptional.statusLabel, "Optional")
}
```

- [ ] **Step 2: Run Swift tests and confirm failure**

Run:

```sh
swift test --filter SetupStatusTests
```

Expected: failure because the setup model does not exist.

- [ ] **Step 3: Add setup model**

Add a small enum/model near existing settings types:

```swift
enum SetupRequirement: Equatable {
    case codexCLIInstalled
    case codexSignedIn
    case profilesCreated
    case gatewayRunning
    case gatewayStopped
    case gatewayBlockedByActiveTurn
    case cloudflareOptional
    case screenRecordingMissing
    case accessibilityMissing
    case notificationsOptional

    var statusLabel: String {
        switch self {
        case .codexCLIInstalled, .codexSignedIn, .profilesCreated, .gatewayRunning:
            return "Ready"
        case .gatewayStopped:
            return "Stopped"
        case .gatewayBlockedByActiveTurn:
            return "Blocked by active turn"
        case .cloudflareOptional, .notificationsOptional:
            return "Optional"
        case .screenRecordingMissing, .accessibilityMissing:
            return "Missing"
        }
    }
}
```

- [ ] **Step 4: Replace menu copy**

Update menu titles to public CodePilot wording:

```swift
"Setup CodePilot..."
"Open Gateway Status..."
"Restart Gateway"
"Restart Gateway When Idle"
"Force Restart Gateway..."
"Refresh Login..."
"Remote Desktop..."
```

Keep any destructive or interrupting action behind explicit confirmation.

- [ ] **Step 5: Run Mac tests**

Run:

```sh
swift test
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```sh
git add Sources/CodexAccountSwitcher/main.swift Tests/CodexAccountSwitcherTests
git commit -m "feat: clarify CodePilot setup and gateway operations"
```

## Task 3: iOS Connection Wizard And Error Mapping

**Files:**
- Modify: `ios/CodexPhone/CodexPhone/CodexPhoneApp.swift`
- Modify: `ios/CodexPhone/CodexPhoneTests/RemoteDesktopTests.swift` or create `ios/CodexPhone/CodexPhoneTests/GatewayErrorMappingTests.swift`

- [ ] **Step 1: Write error mapping tests**

Add tests for stable gateway errors:

```swift
func testGatewayErrorRecoveryCopy() {
    let error = GatewayErrorPayload.ErrorBody(
        code: "gateway_unavailable",
        message: "Gateway unavailable",
        recovery: "Restart CodePilot Gateway on your Mac."
    )
    XCTAssertEqual(GatewayErrorPresenter.title(for: error), "Gateway unavailable")
    XCTAssertTrue(GatewayErrorPresenter.recovery(for: error).contains("Restart"))
}
```

- [ ] **Step 2: Run iOS tests and confirm failure**

Run:

```sh
xcodebuild -project ios/CodexPhone/CodexPhone.xcodeproj -scheme CodexPhone -destination 'platform=iOS Simulator,name=iPhone 16' test
```

Expected: failure because the presenter does not exist.

- [ ] **Step 3: Add Codable error type and presenter**

Add:

```swift
struct GatewayErrorPayload: Decodable, Equatable {
    struct ErrorBody: Decodable, Equatable {
        let code: String
        let message: String
        let recovery: String
    }
    let error: ErrorBody
}

enum GatewayErrorPresenter {
    static func title(for error: GatewayErrorPayload.ErrorBody) -> String { error.message }
    static func recovery(for error: GatewayErrorPayload.ErrorBody) -> String { error.recovery }
}
```

- [ ] **Step 4: Replace generic network messages**

Where the app currently displays raw request failures, try to decode `GatewayErrorPayload` first and show the recovery text. Keep raw details behind a disclosure or copied diagnostics only.

- [ ] **Step 5: Add connection wizard state**

Add a connection setup enum and persist existing keys:

```swift
enum GatewayConnectionKind: String, CaseIterable, Identifiable {
    case local
    case cloudflare
    var id: String { rawValue }
}
```

The first-run screen should ask for connection type, gateway URL, token, then test `/api/health`.

- [ ] **Step 6: Run iOS tests and build**

Run:

```sh
xcodebuild -project ios/CodexPhone/CodexPhone.xcodeproj -scheme CodexPhone -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build
xcodebuild -project ios/CodexPhone/CodexPhone.xcodeproj -scheme CodexPhone -destination 'platform=iOS Simulator,name=iPhone 16' test
```

Expected: build and tests pass.

- [ ] **Step 7: Run required OTA build**

Because this task changes `ios/CodexPhone/`, run:

```sh
curl -fsS -X POST http://127.0.0.1:8787/codexphone/api/build
curl -fsS http://127.0.0.1:8787/codexphone/api/status
```

Wait until `current.state == "complete"`, then verify the manifest and IPA from the approved OTA host, for example `https://ota.example.com`, return HTTP 200.

- [ ] **Step 8: Commit**

```sh
git add ios/CodexPhone/CodexPhone ios/CodexPhone/CodexPhoneTests
git commit -m "feat: add CodePilot iOS connection setup"
```

## Task 4: Public Docs, Troubleshooting, And Privacy Sweep

**Files:**
- Modify: `README.md`
- Modify: `docs/INSTALL_MAC.md`
- Modify: `docs/INSTALL_IOS.md`
- Modify: `docs/CLOUDFLARE_SETUP.md`
- Modify: `docs/SECURITY.md`
- Modify: `docs/ARCHITECTURE.md`
- Create: `docs/TROUBLESHOOTING.md`
- Create: `docs/RELEASE_CHECKLIST.md`

- [ ] **Step 1: Add troubleshooting doc**

Create `docs/TROUBLESHOOTING.md` with sections for:

```markdown
# Troubleshooting

## iPhone Shows 502

Cloudflare reached your hostname, but your Mac gateway was not reachable. Open CodePilot on the Mac and choose `Restart Gateway When Idle`.

## iPhone Shows 401 Or 403

The saved gateway token is missing or wrong. Copy the current token from CodePilot on the Mac and update the iPhone connection.

## Login Is Stale

Use `Refresh Login` for the affected account. CodePilot will keep existing turns running and apply the refreshed account to future turns.
```

- [ ] **Step 2: Add release checklist**

Create `docs/RELEASE_CHECKLIST.md` with:

```markdown
# Release Checklist

- [ ] `swift test`
- [ ] Gateway unit tests
- [ ] iOS simulator build
- [ ] iOS simulator tests
- [ ] Privacy audit
- [ ] OTA build if iOS changed
- [ ] TestFlight upload if shipping beta
- [ ] Public docs checked for personal names, emails, tokens, hostnames, and machine paths
```

- [ ] **Step 3: Update install docs**

Update Mac/iOS/Cloudflare docs so the first screen tells users what they need, what is optional, and what success looks like.

- [ ] **Step 4: Run privacy audit**

Run:

```sh
scripts/privacy-audit.sh
```

Expected: pass with no private names, emails, tokens, Apple team IDs, or machine-specific hostnames in public docs.

- [ ] **Step 5: Commit**

```sh
git add README.md docs
git commit -m "docs: prepare CodePilot public beta guides"
```

## Task 5: Visual Companion Command Reliability

**Files:**
- Modify the visual companion page generator or local HTML under `.superpowers/brainstorm/...` only if this tooling is intentionally kept out of the product.
- If production code owns the companion page, modify the owning source file instead.

- [ ] **Step 1: Reproduce missed click**

Open the visual page from the iPhone, click an option, and check:

```sh
rtk ls .superpowers/brainstorm/*/state
rtk read .superpowers/brainstorm/*/state/events --tail-lines 20
```

Expected current bug: the click visibly changes the page but no event reaches `state/events`.

- [ ] **Step 2: Add acknowledgement behavior**

Update the page script so every click:

```javascript
await fetch("/event", {
  method: "POST",
  headers: {"Content-Type": "application/json"},
  body: JSON.stringify({kind: "selection", value})
});
document.querySelector("[data-selection-status]").textContent = "Selection received";
```

- [ ] **Step 3: Add fallback copy**

Each visual companion page should include:

```html
<p class="fallback">If tapping a choice does not show “Selection received”, reply in chat with the option name.</p>
```

- [ ] **Step 4: Verify from phone**

Click from the iPhone and confirm `state/events` contains the selected value.

- [ ] **Step 5: Commit only if source-owned**

If changes are in tracked source:

```sh
git add <tracked-visual-companion-source>
git commit -m "fix: acknowledge visual companion selections"
```

If changes are only under `.superpowers/`, do not commit them.

## Task 6: Distribution Verification In Parallel

**Files:**
- Modify: `ios/CodexPhone/fastlane/Fastfile` only if required.
- Modify: `ios/CodexPhone/fastlane/README.md` only if instructions changed.
- Modify: `scripts/build-app.sh` only if Mac build output is wrong.

- [ ] **Step 1: Verify bundle identity updates the existing app**

Inspect the iOS bundle ID in `ios/CodexPhone/CodexPhone.xcodeproj/project.pbxproj` and confirm it matches the already-installed app identity, not a new CodePilot-only identity.

- [ ] **Step 2: Build iOS for simulator**

Run:

```sh
xcodebuild -project ios/CodexPhone/CodexPhone.xcodeproj -scheme CodexPhone -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds.

- [ ] **Step 3: Run OTA build if any iOS files changed**

Run:

```sh
curl -fsS -X POST http://127.0.0.1:8787/codexphone/api/build
```

Poll:

```sh
curl -fsS http://127.0.0.1:8787/codexphone/api/status
```

Expected: `current.state` becomes `complete`.

- [ ] **Step 4: Verify OTA assets**

Run:

```sh
curl -I https://ota.example.com/codexphone/manifest.plist
curl -I https://ota.example.com/codexphone/CodePilot.ipa
```

Expected: HTTP 200 or the exact current generated manifest/IPA paths return HTTP 200.
Use example OTA hostnames in public docs. Keep real OTA hostnames in private
release notes or maintainer-run scripts unless they are approved for publishing.

- [ ] **Step 5: Verify GitHub/source package state**

Run:

```sh
git status --short
scripts/privacy-audit.sh
```

Expected: only intentional untracked scratch files remain; privacy audit passes.

- [ ] **Step 6: Commit**

```sh
git add ios/CodexPhone/fastlane scripts docs README.md
git commit -m "chore: verify CodePilot beta distribution"
```

## Final Verification

- [ ] Run `swift test`.
- [ ] Run `cd gateway && python3 -m unittest test_codex_phone_gateway test_remote_desktop_gateway`.
- [ ] Run iOS simulator build.
- [ ] Run iOS simulator tests.
- [ ] Run `scripts/privacy-audit.sh`.
- [ ] Run OTA build if iOS files changed.
- [ ] Confirm `.superpowers/` scratch files are not committed.
- [ ] Confirm the implementation branch has one focused commit per task.

## Spec Coverage Check

- Gateway health and error model: Task 1.
- Mac setup/status and safe gateway operations: Task 2.
- iOS first-run setup and recovery UX: Task 3.
- Public docs, install flow, Cloudflare guidance, privacy language: Task 4.
- Visual companion click reliability: Task 5.
- TestFlight and GitHub/source release target in parallel: Task 6.
- Localhost URL opening is already implemented; Task 1 and Task 3 keep its status/error behavior production-ready.
