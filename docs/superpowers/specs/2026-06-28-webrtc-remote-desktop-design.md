# CodePilot WebRTC Remote Desktop Design

## Goal

Replace request-per-frame JPEG polling with a persistent, low-latency WebRTC video session and make zoomed navigation follow the remote pointer like established trackpad-mode remote desktop clients.

## Architecture

The Mac host captures the main display with ScreenCaptureKit. Frames enter a WebRTC video source and are encoded by WebRTC's hardware-backed H.264 pipeline where available. The existing gateway remains the authenticated signaling relay for offer, answer, and ICE candidates. Cloudflare TURN credentials returned by the existing status endpoint provide relay connectivity when direct ICE cannot connect.

The iOS app creates the offer, exchanges signaling through the gateway, and renders the received video track with an RTC video renderer. JPEG polling remains available only as a reconnect fallback and stops immediately after the WebRTC video track produces frames.

## Components

### Mac Host

- `ScreenCaptureService` owns one ScreenCaptureKit stream for the active remote session.
- `MacPeerConnection` owns the native WebRTC peer connection, video source, video track, ICE handling, and teardown.
- The remote desktop RPC handler starts, signals, and ends a peer session.
- Only one controlling session can be active.

### Gateway

- Existing authenticated session signaling endpoints carry SDP and ICE payloads.
- Signaling queues remain bounded and sequence checked.
- TURN credentials remain short-lived and are never persisted or returned to logs.
- The JPEG frame endpoint remains as a temporary fallback.

### iOS Client

- `RemotePeerConnection` owns the native iOS WebRTC peer connection and renderer-facing video track.
- Signaling reconnects after foregrounding and obtains a fresh session when the previous lease expired.
- The full-screen remote desktop view renders WebRTC video edge-to-edge.
- JPEG fallback is shown only while WebRTC negotiates or reconnects.

## Pointer And Viewport

Finger drags send relative pointer deltas. Input deltas are coalesced so at most one move is in flight and accumulated movement is not lost.

When zoom is greater than 1x, the viewport follows the remote pointer and attempts to keep it at the visual center. The viewport offset clamps at the captured display edges, allowing the pointer to move away from center only when the viewport has reached an edge. Pinch zoom preserves the pointer as the zoom anchor. Taps click at the current remote pointer position.

Cursor position is sent over the WebRTC data channel with video-relative normalized coordinates. The iOS client draws the cursor locally for immediate visual feedback; the Mac-composited cursor remains enabled only for JPEG fallback.

## Keyboard And Input

The native iOS keyboard streams text, deletion, return, and common modifier keys live. Pointer and keyboard events use the WebRTC data channel when connected and fall back to the authenticated HTTP input endpoint during reconnects.

## Failure Handling

- If WebRTC negotiation fails, show a reconnecting state and continue JPEG fallback.
- Retry signaling with bounded exponential backoff.
- Tear down capture, tracks, and input state when the user exits or the app exceeds the background grace period.
- Reject stale signaling and input sequences.
- Surface missing Screen Recording or Accessibility permissions explicitly.

## Verification

- Unit tests for signaling sequence handling, relative pointer coalescing, viewport cursor-follow clamping, and teardown.
- Gateway tests for offer, answer, ICE, and fallback behavior.
- Mac integration check confirms ScreenCaptureKit emits frames and WebRTC reaches connected state.
- iOS build and simulator tests cover renderer/session state.
- Device test verifies remote video latency, pointer tracking, zoom-edge clamping, keyboard input, reconnect, and fallback.
- Every iOS change is followed by an OTA build with public manifest and IPA verification.

## Non-Goals

- Audio streaming.
- Multi-monitor selection in the first release.
- File transfer over WebRTC.
- Multiple simultaneous controllers.
