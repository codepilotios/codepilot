# Secure Remote Desktop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add paired, Face-ID-authorized, low-latency remote viewing and full control of an unlocked Mac from the CodePilot iOS app.

**Architecture:** A native Swift host inside the CodePilot menu-bar process owns ScreenCaptureKit, WebRTC, input injection, device trust, and controller leases. The Python gateway remains the bearer-authenticated public signaling boundary and forwards remote-desktop operations to the native host over an owner-only Unix socket. The iOS app holds a Secure Enclave identity, negotiates WebRTC through the gateway, and renders a full-screen multi-display controller.

**Tech Stack:** Swift 5.9, AppKit, SwiftUI, ScreenCaptureKit, VideoToolbox, Security/Secure Enclave, LocalAuthentication, Core Graphics, Google WebRTC M149 binary XCFramework, Python 3 `http.server`, Unix domain sockets, XCTest/Swift Testing, Python `unittest`, Cloudflare Tunnel and TURN.

---

## File Structure

### Mac host

- `Sources/CodexAccountSwitcher/RemoteDesktop/RemoteDesktopModels.swift`: Codable wire contracts shared by native host modules.
- `Sources/CodexAccountSwitcher/RemoteDesktop/PairingStore.swift`: pairing challenges, trusted public keys, revocation, signature verification.
- `Sources/CodexAccountSwitcher/RemoteDesktop/SessionLeaseStore.swift`: one-controller lease state, nonce replay protection, sequence validation.
- `Sources/CodexAccountSwitcher/RemoteDesktop/RemoteDesktopAuditLog.swift`: privacy-safe append-only JSONL audit events.
- `Sources/CodexAccountSwitcher/RemoteDesktop/RemoteDesktopSocketServer.swift`: owner-only Unix socket request dispatcher.
- `Sources/CodexAccountSwitcher/RemoteDesktop/ScreenCaptureService.swift`: ScreenCaptureKit display enumeration and frame capture.
- `Sources/CodexAccountSwitcher/RemoteDesktop/InputInjector.swift`: coordinate conversion and Core Graphics input posting.
- `Sources/CodexAccountSwitcher/RemoteDesktop/MacPeerConnection.swift`: WebRTC peer, video source, data channel, ICE lifecycle.
- `Sources/CodexAccountSwitcher/RemoteDesktop/RemoteDesktopCoordinator.swift`: session lifecycle and component orchestration.
- `Sources/CodexAccountSwitcher/RemoteDesktop/RemoteDesktopWindowController.swift`: permissions, pairing QR, trusted devices, active session, audit UI.
- `Sources/CodexAccountSwitcher/main.swift`: menu wiring and coordinator startup only.

### Gateway

- `gateway/remote_desktop_gateway.py`: validated public API, native-host socket client, signaling relay, TURN credential provider.
- `gateway/test_remote_desktop_gateway.py`: API, replay, expiry, error, and redaction tests.
- `gateway/codex_phone_gateway.py`: route registration and `GatewayState` composition only.

### iOS

- `ios/CodexPhone/CodexPhone/RemoteDesktop/RemoteDesktopModels.swift`: iOS wire contracts and display geometry.
- `ios/CodexPhone/CodexPhone/RemoteDesktop/RemoteDeviceIdentity.swift`: Secure Enclave key and signed challenge operations.
- `ios/CodexPhone/CodexPhone/RemoteDesktop/RemoteDesktopAPI.swift`: gateway pairing, lease, signaling, clipboard, display, and session calls.
- `ios/CodexPhone/CodexPhone/RemoteDesktop/RemotePeerConnection.swift`: WebRTC peer and data-channel lifecycle.
- `ios/CodexPhone/CodexPhone/RemoteDesktop/RemoteDesktopSession.swift`: observable session state and reconnect policy.
- `ios/CodexPhone/CodexPhone/RemoteDesktop/RemoteDesktopView.swift`: full-screen renderer and status overlays.
- `ios/CodexPhone/CodexPhone/RemoteDesktop/RemoteControlBar.swift`: keyboard, shortcuts, clipboard, files, mode, and disconnect controls.
- `ios/CodexPhone/CodexPhone/RemoteDesktop/RemoteInputMapper.swift`: gesture-to-wire-event conversion.
- `ios/CodexPhone/CodexPhone/CodexPhoneApp.swift`: navigation entry point only.
- `ios/CodexPhone/CodexPhone.xcodeproj/project.pbxproj`: source files, WebRTC package product, usage descriptions, test target.
- `ios/CodexPhone/CodexPhoneTests/RemoteDesktopTests.swift`: identity, mapping, sequence, and lifecycle tests.

## Task 1: Add WebRTC Dependencies And Wire Contracts

**Files:**
- Modify: `Package.swift`
- Modify: `ios/CodexPhone/CodexPhone.xcodeproj/project.pbxproj`
- Create: `Sources/CodexAccountSwitcher/RemoteDesktop/RemoteDesktopModels.swift`
- Create: `ios/CodexPhone/CodexPhone/RemoteDesktop/RemoteDesktopModels.swift`
- Create: `Tests/CodexAccountSwitcherTests/RemoteDesktopModelsTests.swift`
- Create: `ios/CodexPhone/CodexPhoneTests/RemoteDesktopTests.swift`

- [ ] **Step 1: Add failing Codable compatibility tests**

Define one canonical fixture in both test suites and assert it decodes to matching fields:

```swift
let fixture = #"{"sessionId":"s1","sequence":4,"kind":"pointer","x":0.25,"y":0.75,"button":0,"keyCode":null,"text":null,"deltaX":null,"deltaY":null}"#.data(using: .utf8)!
let event = try JSONDecoder().decode(RemoteInputEvent.self, from: fixture)
#expect(event.sessionId == "s1")
#expect(event.sequence == 4)
#expect(event.kind == .pointer)
#expect(event.x == 0.25)
```

- [ ] **Step 2: Run tests and verify the missing-type failure**

Run: `rtk err swift test --filter RemoteDesktopModelsTests`

Expected: FAIL because `RemoteInputEvent` does not exist.

- [ ] **Step 3: Add WebRTC M149 and focused model types**

Add package dependency `https://github.com/stasel/WebRTC.git` exact version `149.0.0` and product `WebRTC` to the Mac executable and iOS app. Add an iOS XCTest target. Define identical Codable contracts on both clients:

```swift
enum RemoteInputKind: String, Codable {
    case pointer, buttonDown, buttonUp, scroll, keyDown, keyUp, text
}

struct RemoteInputEvent: Codable, Equatable {
    let sessionId: String
    let sequence: UInt64
    let kind: RemoteInputKind
    let x: Double?
    let y: Double?
    let button: Int?
    let keyCode: UInt16?
    let text: String?
    let deltaX: Double?
    let deltaY: Double?
}

struct RemoteDisplay: Codable, Equatable, Identifiable {
    let id: UInt32
    let name: String
    let pixelWidth: Int
    let pixelHeight: Int
    let scale: Double
    let rotation: Double
}
```

Also define pairing challenge, trusted device, lease, SDP, ICE candidate, clipboard request, and audit-event response types. Do not put capture, crypto, or UI behavior in model files.

- [ ] **Step 4: Verify both build graphs resolve WebRTC**

Run: `rtk err swift test --filter RemoteDesktopModelsTests`

Run: `rtk err xcodebuild -project ios/CodexPhone/CodexPhone.xcodeproj -scheme CodexPhone -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build`

Expected: both commands pass and Xcode resolves `WebRTC` at `149.0.0`.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Package.resolved Sources/CodexAccountSwitcher/RemoteDesktop Tests/CodexAccountSwitcherTests/RemoteDesktopModelsTests.swift ios/CodexPhone/CodexPhone.xcodeproj ios/CodexPhone/CodexPhone/RemoteDesktop/RemoteDesktopModels.swift ios/CodexPhone/CodexPhoneTests
git commit -m "build: add remote desktop wire contracts"
```

## Task 2: Implement Native Device Trust And Controller Leases

**Files:**
- Create: `Sources/CodexAccountSwitcher/RemoteDesktop/PairingStore.swift`
- Create: `Sources/CodexAccountSwitcher/RemoteDesktop/SessionLeaseStore.swift`
- Create: `Sources/CodexAccountSwitcher/RemoteDesktop/RemoteDesktopAuditLog.swift`
- Create: `Tests/CodexAccountSwitcherTests/PairingStoreTests.swift`
- Create: `Tests/CodexAccountSwitcherTests/SessionLeaseStoreTests.swift`

- [ ] **Step 1: Write failing security-state tests**

Cover challenge single use and two-minute expiry, P-256 signature verification, revoked devices, nonce replay, one-controller exclusion, lease expiry, sequence replay, and redacted audit encoding:

```swift
@Test func reusedNonceIsRejected() throws {
    let store = SessionLeaseStore(clock: { Date(timeIntervalSince1970: 100) })
    let nonce = try store.issueNonce(for: "device-1")
    _ = try store.createLease(deviceID: "device-1", nonce: nonce, signatureIsValid: true)
    #expect(throws: RemoteDesktopSecurityError.nonceAlreadyUsed) {
        try store.createLease(deviceID: "device-1", nonce: nonce, signatureIsValid: true)
    }
}
```

- [ ] **Step 2: Confirm tests fail before implementation**

Run: `rtk err swift test --filter PairingStoreTests`

Run: `rtk err swift test --filter SessionLeaseStoreTests`

Expected: FAIL with missing stores.

- [ ] **Step 3: Implement persistent trust and ephemeral leases**

Use `P256.Signing.PublicKey` from CryptoKit and atomic owner-only JSON persistence under `~/.codepilot/remote-desktop/trusted-devices.json`. Pairing records contain no private material:

```swift
struct TrustedRemoteDevice: Codable, Identifiable {
    let id: String
    var name: String
    let publicKeyRawRepresentation: Data
    let approvedAt: Date
    var revokedAt: Date?
}

func verify(signature: Data, message: Data, deviceID: String) throws {
    guard let device = devices[deviceID], device.revokedAt == nil else {
        throw RemoteDesktopSecurityError.untrustedDevice
    }
    let key = try P256.Signing.PublicKey(rawRepresentation: device.publicKeyRawRepresentation)
    let signature = try P256.Signing.ECDSASignature(derRepresentation: signature)
    guard key.isValidSignature(signature, for: message) else {
        throw RemoteDesktopSecurityError.invalidSignature
    }
}
```

Keep leases and used nonces in memory. Default nonce TTL is 60 seconds; lease TTL is 10 minutes with explicit renewal after another signed nonce. Audit JSONL must exclude keystrokes, clipboard values, screen contents, tokens, and file contents.

- [ ] **Step 4: Run security-state tests**

Run: `rtk err swift test --filter PairingStoreTests`

Run: `rtk err swift test --filter SessionLeaseStoreTests`

Expected: PASS, including expiry and replay cases under injected clocks.

- [ ] **Step 5: Commit**

```bash
git add Sources/CodexAccountSwitcher/RemoteDesktop Tests/CodexAccountSwitcherTests
git commit -m "feat: add remote desktop device trust"
```

## Task 3: Add Owner-Only Native Host IPC

**Files:**
- Create: `Sources/CodexAccountSwitcher/RemoteDesktop/RemoteDesktopSocketServer.swift`
- Create: `gateway/remote_desktop_gateway.py`
- Create: `gateway/test_remote_desktop_gateway.py`
- Modify: `Sources/CodexAccountSwitcher/main.swift`

- [ ] **Step 1: Write failing socket permission and request tests**

Use a temporary socket and assert mode `0600`, peer requests are length-bounded, unknown methods fail closed, and malformed JSON cannot terminate the server. In Python, test connection-unavailable mapping separately from HTTP routes.

```python
def test_native_client_rejects_oversized_response(self):
    client = NativeRemoteHostClient(self.socket_path, max_response_bytes=128)
    with self.assertRaises(RemoteDesktopHostError):
        client.call("status", {}, fake_response=b"x" * 129)
```

- [ ] **Step 2: Run targeted tests and verify failure**

Run: `rtk err swift test --filter RemoteDesktopSocketServerTests`

Run: `rtk err python3 -m unittest gateway.test_remote_desktop_gateway.NativeRemoteHostClientTests -v`

Expected: FAIL with missing socket server/client types.

- [ ] **Step 3: Implement framed local RPC**

Use a Unix socket at `~/.codepilot/remote-desktop/host.sock`, create its parent with `0700`, set the socket to `0600`, and use a four-byte big-endian length prefix followed by JSON. Cap request and response bodies at 1 MiB. The request envelope is:

```swift
struct HostRPCRequest: Codable {
    let id: UUID
    let method: String
    let payload: Data
}

struct HostRPCResponse: Codable {
    let id: UUID
    let status: Int
    let payload: Data?
    let errorCode: String?
}
```

Allowlist methods explicitly: `status`, `pairing.start`, `pairing.complete`, `devices.list`, `devices.revoke`, `session.nonce`, `session.start`, `session.signal`, `session.end`, `session.display`, `session.clipboard`, and `audit.list`.

- [ ] **Step 4: Wire host startup without changing account-switch behavior**

Create the coordinator and socket server after `NSApplication` delegate startup; on failure, log remote desktop as unavailable while leaving account switching and gateway features operational.

- [ ] **Step 5: Run focused and full tests**

Run: `rtk err swift test`

Run: `rtk err python3 -m unittest gateway.test_remote_desktop_gateway -v`

Expected: all tests pass and the socket test reports owner-only permissions.

- [ ] **Step 6: Commit**

```bash
git add Sources/CodexAccountSwitcher gateway/remote_desktop_gateway.py gateway/test_remote_desktop_gateway.py
git commit -m "feat: add private remote host channel"
```

## Task 4: Expose Pairing, Lease, And Signaling APIs

**Files:**
- Modify: `gateway/remote_desktop_gateway.py`
- Modify: `gateway/codex_phone_gateway.py`
- Modify: `gateway/test_remote_desktop_gateway.py`

- [ ] **Step 1: Write failing authenticated route tests**

Test every endpoint without bearer auth, with host unavailable, malformed identifiers, expired pairing, signature rejection, replay, controller conflict, and successful forwarding. Required routes:

```text
POST /api/remote/pairing/start
POST /api/remote/pairing/complete
GET  /api/remote/devices
POST /api/remote/devices/{id}/revoke
POST /api/remote/sessions/nonce
POST /api/remote/sessions
POST /api/remote/sessions/{id}/signal
GET  /api/remote/sessions/{id}/signal?after={sequence}
POST /api/remote/sessions/{id}/display
POST /api/remote/sessions/{id}/clipboard
POST /api/remote/sessions/{id}/disconnect
GET  /api/remote/status
```

- [ ] **Step 2: Verify route tests fail**

Run: `rtk err python3 -m unittest gateway.test_remote_desktop_gateway.RemoteDesktopRouteTests -v`

Expected: FAIL with 404 responses.

- [ ] **Step 3: Implement strict schemas and relay queues**

Keep route parsing in `codex_phone_gateway.py` small by delegating to `RemoteDesktopGateway`. Reject unknown body keys, cap request bodies, normalize base64 with validated decoding, and map native errors to stable public codes without exposing paths or exceptions:

```python
ERROR_STATUS = {
    "host_unavailable": 503,
    "pairing_expired": 410,
    "untrusted_device": 403,
    "invalid_signature": 403,
    "controller_busy": 409,
    "session_expired": 410,
}
```

Signaling queues are per-session, monotonically sequenced, bounded to 256 entries, and removed at disconnect or expiry.

- [ ] **Step 4: Add Cloudflare TURN credential provider**

Read `CODEPILOT_TURN_KEY_ID` and `CODEPILOT_TURN_API_TOKEN` from the gateway environment. Generate credentials server-side with a five-minute TTL and return only the resulting ICE server array. Never log request headers, the API token, or generated passwords. When unset, return STUN-only configuration and a `relayAvailable: false` capability.

- [ ] **Step 5: Run gateway suites**

Run: `rtk err python3 -m unittest gateway.test_remote_desktop_gateway -v`

Run: `rtk err python3 -m unittest gateway.test_codex_phone_gateway -v`

Expected: PASS with no live home-directory state dependency in the new tests.

- [ ] **Step 6: Commit**

```bash
git add gateway/remote_desktop_gateway.py gateway/codex_phone_gateway.py gateway/test_remote_desktop_gateway.py
git commit -m "feat: add remote desktop gateway APIs"
```

## Task 5: Build Mac Permissions, Pairing, And Session Management UI

**Files:**
- Create: `Sources/CodexAccountSwitcher/RemoteDesktop/RemoteDesktopCoordinator.swift`
- Create: `Sources/CodexAccountSwitcher/RemoteDesktop/RemoteDesktopWindowController.swift`
- Modify: `Sources/CodexAccountSwitcher/main.swift`
- Create: `Tests/CodexAccountSwitcherTests/RemoteDesktopCoordinatorTests.swift`

- [ ] **Step 1: Write failing coordinator state tests**

Test unavailable permissions, pending local approval, approved/rejected pairing, active-session indicator, revoke-active-device, Mac lock, and emergency disconnect using protocol-backed fake capture and input services.

- [ ] **Step 2: Verify state tests fail**

Run: `rtk err swift test --filter RemoteDesktopCoordinatorTests`

Expected: FAIL because the coordinator does not exist.

- [ ] **Step 3: Implement permission and lifecycle state**

Use `CGPreflightScreenCaptureAccess`, `CGRequestScreenCaptureAccess`, `AXIsProcessTrustedWithOptions`, and `NSWorkspace.sessionDidResignActiveNotification`. The coordinator exposes a single immutable snapshot:

```swift
struct RemoteDesktopStatus: Equatable {
    let screenRecordingGranted: Bool
    let accessibilityGranted: Bool
    let macUnlocked: Bool
    let pendingPairing: PendingPairing?
    let trustedDevices: [TrustedRemoteDevice]
    let activeSession: ActiveRemoteSession?
}
```

- [ ] **Step 4: Add a restrained AppKit management window and menu state**

Add `Remote Desktop…` to the status menu. The window shows permission rows, pairing QR with expiry, pending approval details and key fingerprint, trusted-device revoke actions, active controller/duration, emergency disconnect, and privacy-safe audit entries. Show a red status-item indicator while control is active.

- [ ] **Step 5: Verify tests and manual permission states**

Run: `rtk err swift test`

Run: `rtk err swift build`

Expected: PASS. Launch locally and verify account switching still works when both permissions are denied.

- [ ] **Step 6: Commit**

```bash
git add Sources/CodexAccountSwitcher Tests/CodexAccountSwitcherTests
git commit -m "feat: add remote desktop trust management UI"
```

## Task 6: Implement Mac Capture, WebRTC, And Input

**Files:**
- Create: `Sources/CodexAccountSwitcher/RemoteDesktop/ScreenCaptureService.swift`
- Create: `Sources/CodexAccountSwitcher/RemoteDesktop/InputInjector.swift`
- Create: `Sources/CodexAccountSwitcher/RemoteDesktop/MacPeerConnection.swift`
- Modify: `Sources/CodexAccountSwitcher/RemoteDesktop/RemoteDesktopCoordinator.swift`
- Create: `Tests/CodexAccountSwitcherTests/InputInjectorTests.swift`

- [ ] **Step 1: Write failing coordinate and input-policy tests**

Cover Retina scaling, negative display origins, rotation, out-of-bounds clamping, stale sequence rejection, lock rejection, and forced modifier release:

```swift
@Test func mapsNormalizedPointToNegativeOriginDisplay() {
    let frame = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
    #expect(DisplayCoordinateMapper.map(x: 0.5, y: 0.5, into: frame) == CGPoint(x: -960, y: 540))
}
```

- [ ] **Step 2: Verify input tests fail**

Run: `rtk err swift test --filter InputInjectorTests`

Expected: FAIL with missing mapper/injector.

- [ ] **Step 3: Implement display capture and adaptive frame delivery**

Enumerate `SCShareableContent.displays`, capture one selected `SCDisplay`, exclude the CodePilot management window, and configure a maximum 1920-pixel long edge at 30 fps initially. Feed `CMSampleBuffer` frames to WebRTC's native video source without JPEG conversion. Support runtime display/filter and resolution updates.

- [ ] **Step 4: Implement input injection with fail-closed policy**

Validate the active lease and sequence before creating any `CGEvent`. Clamp normalized coordinates, map through the selected display frame, track pressed keys/buttons, and release all state on disconnect or error. Unicode text uses `keyboardSetUnicodeString`; shortcuts use explicit key-down/up and modifier transitions.

- [ ] **Step 5: Implement Mac WebRTC peer lifecycle**

Create one `RTCPeerConnection` per lease with unified-plan semantics, one video track, and one ordered data channel. Accept SDP/ICE only for the active lease. Data messages decode to bounded `RemoteInputEvent` or control envelopes; unknown kinds close the channel with an audit event. Trigger ICE restart on disconnected state and end the lease on failed state after the configured grace period.

- [ ] **Step 6: Verify local peer and cleanup behavior**

Run: `rtk err swift test`

Run: `rtk err swift build`

Expected: PASS. A local WebRTC loopback harness receives video; disconnect releases all simulated modifiers and stops `SCStream`.

- [ ] **Step 7: Commit**

```bash
git add Sources/CodexAccountSwitcher/RemoteDesktop Tests/CodexAccountSwitcherTests
git commit -m "feat: stream and control the Mac desktop"
```

## Task 7: Add iOS Secure Identity And Pairing

**Files:**
- Create: `ios/CodexPhone/CodexPhone/RemoteDesktop/RemoteDeviceIdentity.swift`
- Create: `ios/CodexPhone/CodexPhone/RemoteDesktop/RemoteDesktopAPI.swift`
- Create: `ios/CodexPhone/CodexPhone/RemoteDesktop/RemotePairingView.swift`
- Modify: `ios/CodexPhone/CodexPhone/CodexPhoneApp.swift`
- Modify: `ios/CodexPhone/CodexPhoneTests/RemoteDesktopTests.swift`

- [ ] **Step 1: Write failing identity and API tests**

Inject Keychain and authentication protocols. Test stable key identity, non-exportable private key behavior, signature verification fixture, Face ID cancellation, revoked-device response, and pairing expiry.

- [ ] **Step 2: Verify iOS tests fail**

Run: `rtk err xcodebuild test -project ios/CodexPhone/CodexPhone.xcodeproj -scheme CodexPhone -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO`

Expected: FAIL with missing identity/API types.

- [ ] **Step 3: Implement Secure Enclave identity**

Generate a P-256 key with `kSecAttrTokenIDSecureEnclave`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, and user-presence access control. Store only the key reference. Expose public X9.63 representation and DER ECDSA signatures. Simulator tests use an injected software-key implementation.

- [ ] **Step 4: Implement pairing flow**

Use VisionKit/DataScanner where available and a manual code fallback. Show the Mac identity, challenge expiry, and approval-waiting state. Do not place the pairing payload, public key, or signatures in `UserDefaults` or logs.

- [ ] **Step 5: Add remote desktop entry point**

Add a desktop icon button to the main toolbar and a settings section showing paired/unpaired, Mac permission status, active controller, and trusted device name. Disable Start Session with a precise reason when host permissions are missing or another controller is active.

- [ ] **Step 6: Run iOS tests and build**

Run: `rtk err xcodebuild test -project ios/CodexPhone/CodexPhone.xcodeproj -scheme CodexPhone -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add ios/CodexPhone
git commit -m "feat: pair trusted CodePilot devices"
```

## Task 8: Implement iOS WebRTC Session And Full-Screen Controls

**Files:**
- Create: `ios/CodexPhone/CodexPhone/RemoteDesktop/RemotePeerConnection.swift`
- Create: `ios/CodexPhone/CodexPhone/RemoteDesktop/RemoteDesktopSession.swift`
- Create: `ios/CodexPhone/CodexPhone/RemoteDesktop/RemoteDesktopView.swift`
- Create: `ios/CodexPhone/CodexPhone/RemoteDesktop/RemoteControlBar.swift`
- Create: `ios/CodexPhone/CodexPhone/RemoteDesktop/RemoteInputMapper.swift`
- Modify: `ios/CodexPhone/CodexPhoneTests/RemoteDesktopTests.swift`

- [ ] **Step 1: Write failing input and session-state tests**

Test direct tap, drag, two-finger scroll, relative trackpad movement, monotonic sequences, reconnect suspension, background grace expiry, stale event discard, and disconnect cleanup.

- [ ] **Step 2: Verify tests fail**

Run: `rtk err xcodebuild test -project ios/CodexPhone/CodexPhone.xcodeproj -scheme CodexPhone -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO`

Expected: FAIL with missing mapper/session types.

- [ ] **Step 3: Implement authenticated session negotiation**

Request a nonce, run `LAContext.evaluatePolicy`, sign `nonce || canonicalCapabilities`, create the lease, then negotiate WebRTC using returned ICE servers. Send signaling through `RemoteDesktopAPI`; poll with `after` sequence until connected, then reduce polling to ICE restarts only.

- [ ] **Step 4: Implement renderer and gesture modes**

Wrap `RTCMTLVideoView` in `UIViewRepresentable` with fixed aspect-fit geometry. Direct mode maps gestures to normalized coordinates. Trackpad mode maps deltas relative to the rendered frame. Pinch changes only local zoom/pan. Keep control hit targets outside the remote content coordinate surface.

- [ ] **Step 5: Implement keyboard, shortcut, quality, and disconnect UI**

Use a hidden first-responder text input for normal typing and explicit buttons for modifier/function keys. The bottom bar uses icons for keyboard, keys, clipboard, files, mode, and disconnect. Show connecting, direct, relayed, reconnecting, suspended, and failed states with latency. Disconnect remains reachable in every state.

- [ ] **Step 6: Implement lifecycle policy**

On background, disable the video track and preserve the lease for 30 seconds. On foreground within the grace period, request current signaling state and resume. After expiry, discard the peer and require Face ID plus a new lease. Never replay queued input after reconnect.

- [ ] **Step 7: Run iOS tests and simulator UI checks**

Run: `rtk err xcodebuild test -project ios/CodexPhone/CodexPhone.xcodeproj -scheme CodexPhone -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO`

Run: `rtk err xcodebuild -project ios/CodexPhone/CodexPhone.xcodeproj -scheme CodexPhone -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build`

Expected: PASS with no layout overflow at portrait and landscape sizes.

- [ ] **Step 8: Commit**

```bash
git add ios/CodexPhone
git commit -m "feat: add iPhone remote desktop controls"
```

## Task 9: Add Displays, Clipboard, Files, And Network Hardening

**Files:**
- Modify: `Sources/CodexAccountSwitcher/RemoteDesktop/RemoteDesktopCoordinator.swift`
- Modify: `Sources/CodexAccountSwitcher/RemoteDesktop/MacPeerConnection.swift`
- Modify: `gateway/remote_desktop_gateway.py`
- Modify: `ios/CodexPhone/CodexPhone/RemoteDesktop/RemoteDesktopSession.swift`
- Modify: `ios/CodexPhone/CodexPhone/RemoteDesktop/RemoteDesktopView.swift`
- Modify: `gateway/test_remote_desktop_gateway.py`
- Modify: `ios/CodexPhone/CodexPhoneTests/RemoteDesktopTests.swift`

- [ ] **Step 1: Add failing cross-feature tests**

Cover display removal during a session, display switch geometry, clipboard size/type rejection, explicit clipboard direction, transfer metadata redaction, direct-to-TURN fallback, ICE restart, host restart, gateway restart, and controller lease loss.

- [ ] **Step 2: Run focused suites and verify failures**

Run: `rtk err swift test --filter RemoteDesktop`

Run: `rtk err python3 -m unittest gateway.test_remote_desktop_gateway -v`

Run the iOS XCTest command from Task 8.

Expected: new tests fail on missing behavior.

- [ ] **Step 3: Implement multi-display switching**

Return all active displays and update the ScreenCaptureKit content filter without recreating the lease. If the selected display disappears, pause input, select the main display, send updated geometry, and require a fresh frame before re-enabling input.

- [ ] **Step 4: Implement explicit clipboard and existing file flow integration**

Limit clipboard to UTF-8 text of at most 1 MiB. Each send or pull requires an explicit UI action and audit metadata only. Reuse `downloadRemoteFile` and existing attachment upload APIs for files; do not send file bytes over the WebRTC data channel.

- [ ] **Step 5: Implement transport resilience**

Prefer host/srflx candidates, allow relay candidates from server-generated credentials, expose selected path as direct or relayed, perform ICE restart on network changes, and bound retries to avoid immortal sessions. Video adaptation targets input responsiveness first: 30 to 15 to 8 fps and 1920 to 1280 to 960 long edge.

Observe local HID activity separately from injected remote events. When local mouse or keyboard activity occurs, pause remote input for three seconds, show that state on iOS, and resume without replaying events received during the pause.

- [ ] **Step 6: Verify all automated suites**

Run: `rtk err swift test`

Run: `rtk err python3 -m unittest discover -s gateway -p 'test_*.py' -v`

Run the iOS XCTest command from Task 8.

Expected: all pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/CodexAccountSwitcher gateway ios/CodexPhone
git commit -m "feat: harden remote desktop sessions"
```

## Task 10: Security Review, Documentation, And Physical-Device Release Verification

**Files:**
- Modify: `docs/SECURITY.md`
- Modify: `docs/CLOUDFLARE_SETUP.md`
- Modify: `README.md`
- Modify: `scripts/install-phone-gateway-agent.sh`
- Modify: `scripts/install-phone-cloudflared-agent.sh`
- Test: all Mac, gateway, and iOS suites

- [ ] **Step 1: Add configuration validation tests**

Test startup with missing TURN settings, invalid socket parent permissions, stale socket, inaccessible audit directory, and unsupported macOS. Remote desktop must disable itself without preventing gateway chat or account switching.

- [ ] **Step 2: Run a scoped security scan and fix validated findings**

Review only the new remote-desktop paths for authentication bypass, replay, IDOR, unsafe deserialization, unbounded allocation, secret logging, socket permission races, path traversal, and session cleanup. Add a regression test before each validated fix.

- [ ] **Step 3: Document setup and revocation**

Document the tested macOS deployment target, Screen Recording and Accessibility grants, Cloudflare TURN key/token setup, pairing, Face ID requirement, active-session visibility, device revocation, emergency disconnect, audit location, and the unlocked-session limitation. Explicitly state that the gateway bearer token alone cannot authorize remote desktop.

- [ ] **Step 4: Run complete automated verification**

Run: `rtk err swift test`

Run: `rtk err python3 -m unittest discover -s gateway -p 'test_*.py' -v`

Run: `rtk err xcodebuild test -project ios/CodexPhone/CodexPhone.xcodeproj -scheme CodexPhone -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO`

Run: `rtk err xcodebuild -project ios/CodexPhone/CodexPhone.xcodeproj -scheme CodexPhone -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build`

Expected: every command passes.

- [ ] **Step 5: Run physical-device matrix**

Verify pairing approval, Face ID session start, Wi-Fi direct path, cellular TURN path, Wi-Fi-to-cellular handoff, two-display switching, pointer/keyboard/shortcuts, clipboard send/pull, file upload/download, Mac lock, permission revocation, local emergency disconnect, device revocation, gateway restart, and app background/foreground. Record failures by stage-specific error code.

- [ ] **Step 6: Run and verify the mandatory OTA release**

Run:

```bash
cd /path/to/ios-release-worktree
python3 scripts/dke_ota_build.py build --app codexphone --branch release
```

Expected: status reaches `complete`; output reports the existing configured bundle ID; both public manifest and IPA return HTTP 200; the OTA install updates the configured CodePilot app rather than creating another instance.

- [ ] **Step 7: Commit**

```bash
git add README.md docs/SECURITY.md docs/CLOUDFLARE_SETUP.md scripts Sources gateway ios/CodexPhone
git commit -m "docs: complete secure remote desktop rollout"
```
