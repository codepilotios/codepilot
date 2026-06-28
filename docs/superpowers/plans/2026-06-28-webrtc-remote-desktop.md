# WebRTC Remote Desktop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace JPEG polling with a ScreenCaptureKit/WebRTC video stream and make the zoomed viewport follow a relative remote cursor until display edges are reached.

**Architecture:** The Mac captures `CMSampleBuffer` frames with ScreenCaptureKit and feeds them to a native WebRTC video source. The authenticated gateway relays SDP/ICE signaling, while the iOS peer renders the incoming track and uses the existing HTTP input path as a fallback. Cursor coordinates drive a deterministic iOS viewport controller.

**Tech Stack:** Swift 5.9, ScreenCaptureKit, LiveKit WebRTC XCFramework on macOS, stasel WebRTC XCFramework on iOS, SwiftUI, Python gateway, XCTest, unittest.

---

### Task 1: Cursor-Follow Viewport Model

**Files:**
- Create: `ios/CodexPhone/CodexPhone/RemoteDesktop/RemoteViewport.swift`
- Modify: `ios/CodexPhone/CodexPhone/RemoteDesktop/RemoteDesktopView.swift`
- Test: `ios/CodexPhone/CodexPhoneTests/RemoteDesktopTests.swift`

- [ ] **Step 1: Write failing viewport tests**

Add tests proving a 2x viewport centers normalized cursor `(0.5, 0.5)`, follows `(0.75, 0.5)`, and clamps at cursor `(1, 1)` without exposing space outside the frame.

- [ ] **Step 2: Run the focused tests and verify failure**

Run: `xcodebuild -project ios/CodexPhone/CodexPhone.xcodeproj -scheme CodexPhone -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO test -only-testing:CodexPhoneTests/RemoteDesktopTests`

Expected: failure because `RemoteViewport` does not exist.

- [ ] **Step 3: Implement the viewport model**

Create a value type with `zoom`, `cursor`, and `offset(container:image:)`. Compute the desired offset by placing the normalized cursor at the container center, then clamp the offset to half the scaled overflow on each axis.

- [ ] **Step 4: Connect cursor updates to the view**

Replace free-form zoomed pan state with `RemoteViewport`. Keep pinch zoom, but make cursor updates authoritative for pan offset. Render the local cursor above the video at its transformed position.

- [ ] **Step 5: Run tests and commit**

Run the focused iOS tests and simulator build. Commit only viewport files with `feat: follow remote cursor while zoomed`.

### Task 2: ScreenCaptureKit Frame Producer

**Files:**
- Modify: `Sources/CodexAccountSwitcher/RemoteDesktop/ScreenCaptureService.swift`
- Create: `Sources/CodexAccountSwitcher/RemoteDesktop/WebRTCFrameAdapter.swift`
- Test: `Tests/CodexAccountSwitcherTests/ScreenCaptureServiceTests.swift`

- [ ] **Step 1: Write failing lifecycle tests**

Use a fake stream driver to verify `start(displayID:frameHandler:)` starts once, delivers frames, and `stop()` releases the handler and stream.

- [ ] **Step 2: Run the focused test and verify failure**

Run: `swift test --filter ScreenCaptureServiceTests`

Expected: failure because streaming APIs are absent.

- [ ] **Step 3: Implement ScreenCaptureKit streaming**

Configure `SCStreamConfiguration` for the selected display, 30 fps minimum frame interval, BGRA pixel format, cursor excluded, queue depth 5, and scaled width capped at 1920. Deliver `.screen` sample buffers on a dedicated serial queue.

- [ ] **Step 4: Implement the WebRTC frame adapter**

Convert each sample buffer image buffer into `RTCCVPixelBuffer`, timestamp it in nanoseconds, and call the WebRTC video source capturer delegate.

- [ ] **Step 5: Run tests and commit**

Run `swift test --filter ScreenCaptureServiceTests` and `swift build`. Commit capture files with `feat: stream display frames with ScreenCaptureKit`.

### Task 3: Native WebRTC Peer And Signaling

**Files:**
- Modify: `Sources/CodexAccountSwitcher/RemoteDesktop/MacPeerConnection.swift`
- Modify: `Sources/CodexAccountSwitcher/RemoteDesktop/RemoteDesktopSocketServer.swift`
- Modify: `Sources/CodexAccountSwitcher/main.swift`
- Modify: `gateway/remote_desktop_gateway.py`
- Test: `Tests/CodexAccountSwitcherTests/MacPeerConnectionTests.swift`
- Test: `gateway/test_remote_desktop_gateway.py`

- [ ] **Step 1: Write failing peer and gateway tests**

Test offer acceptance, answer generation, local ICE draining, duplicate sequence rejection, disconnect cleanup, and gateway forwarding of a client signal to `session.signal` while returning native outbound signals.

- [ ] **Step 2: Verify the focused tests fail**

Run: `swift test --filter MacPeerConnectionTests` and `python3 -m unittest gateway.test_remote_desktop_gateway.RemoteDesktopGatewayTests -v`.

- [ ] **Step 3: Implement the Mac peer**

Create one `RTCPeerConnectionFactory`, peer connection, H.264-preferred video transceiver, video source, and track per session. Apply remote SDP, create/set local answer, collect ICE candidates, and expose outbound canonical `MacPeerSignal` values.

- [ ] **Step 4: Wire host RPC and gateway relay**

Add `session.start`, `session.signal`, and `session.end` handlers. `session.signal` decodes one inbound signal, applies it to the Mac peer, and returns an array of answer/ICE signals. Gateway POST validates and forwards the signal; GET returns queued host signals only.

- [ ] **Step 5: Verify and commit**

Run focused Swift/Python tests, `swift test`, and `swift build`. Commit peer, RPC, and gateway files with `feat: negotiate Mac WebRTC remote desktop peer`.

### Task 4: iOS WebRTC Client And Renderer

**Files:**
- Modify: `ios/CodexPhone/CodexPhone/RemoteDesktop/RemotePeerConnection.swift`
- Modify: `ios/CodexPhone/CodexPhone/RemoteDesktop/RemoteDesktopAPI.swift`
- Create: `ios/CodexPhone/CodexPhone/RemoteDesktop/RemoteVideoView.swift`
- Modify: `ios/CodexPhone/CodexPhone/RemoteDesktop/RemoteDesktopView.swift`
- Test: `ios/CodexPhone/CodexPhoneTests/RemoteDesktopTests.swift`

- [ ] **Step 1: Write failing API and state tests**

Test signaling request paths, monotonic sequence values, connected state after receiving a video track, fallback activation before the first frame, and teardown after disconnect.

- [ ] **Step 2: Verify tests fail**

Run the focused CodexPhone tests with `xcodebuild`.

- [ ] **Step 3: Implement iOS negotiation**

Create the peer factory and receive-only video transceiver, use ICE servers from `/api/remote/status`, create/set the local offer, post signals, apply the answer and ICE candidates, and publish connection/first-frame state on the main actor.

- [ ] **Step 4: Implement native video rendering and fallback**

Wrap `RTCMTLVideoView` in `UIViewRepresentable`. Show it full-screen after the first WebRTC frame; run JPEG polling only during negotiation/reconnect and stop polling immediately when video is active.

- [ ] **Step 5: Verify and commit**

Run focused tests and the simulator build. Commit iOS peer/API/renderer files with `feat: render WebRTC remote desktop video on iOS`.

### Task 5: Reconnect, Input Path, And Release Verification

**Files:**
- Modify: `ios/CodexPhone/CodexPhone/RemoteDesktop/RemoteDesktopView.swift`
- Modify: `ios/CodexPhone/CodexPhone/RemoteDesktop/RemoteDesktopSession.swift`
- Modify: `Sources/CodexAccountSwitcher/RemoteDesktop/MacPeerConnection.swift`
- Test: `ios/CodexPhone/CodexPhoneTests/RemoteDesktopTests.swift`
- Test: `Tests/CodexAccountSwitcherTests/MacPeerConnectionTests.swift`

- [ ] **Step 1: Add failing reconnect and teardown tests**

Test foreground reconnect within grace, fresh negotiation after expiry, no capture after disconnect, and HTTP input fallback while the WebRTC data channel is unavailable.

- [ ] **Step 2: Implement bounded reconnect**

Retry negotiation after 0.5, 1, 2, and 4 seconds, then remain on JPEG fallback with an explicit Retry control. Cancel all retry, polling, capture, and peer tasks on exit.

- [ ] **Step 3: Run full verification**

Run `swift test`, gateway unittest suites, and the iOS simulator build. Rebuild/restart the signed Mac app and gateway. Verify WebRTC reaches connected state and JPEG requests stop.

- [ ] **Step 4: Run device and OTA verification**

Trigger `POST http://127.0.0.1:8787/codexphone/api/build`, wait for complete status, and verify the public manifest and IPA return HTTP 200. Confirm pointer following, edge clamping, keyboard input, reconnect, and fallback on the iPhone.

- [ ] **Step 5: Commit release-ready changes**

Commit remaining session/reconnect files with `feat: harden WebRTC remote desktop sessions`.
