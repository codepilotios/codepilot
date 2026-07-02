# Secure Remote Desktop Design

## Objective

Add secure remote viewing and full control of an unlocked Mac desktop to the CodePilot gateway and iOS app. A trusted iPhone can connect unattended after initial local approval, switch between all attached displays, control pointer and keyboard input, use explicit clipboard transfer, and send or retrieve files.

The remote desktop must not weaken the existing gateway. Possession of the gateway bearer token alone must never authorize screen viewing or input control.

## Scope

The first complete release supports:

- Full pointer, scrolling, keyboard, modifier, function-key, and shortcut input.
- One active controlling device at a time.
- All attached displays, selected one at a time.
- Direct-touch and relative-trackpad interaction modes.
- Explicit bidirectional text clipboard transfer.
- File transfer through the existing authenticated gateway infrastructure.
- Trusted-device unattended access after initial local Mac approval.
- Face ID authorization for each new remote-control lease.
- Operation only while the macOS user session is logged in and unlocked.

The first release does not support the login window, locked-screen control, simultaneous controllers, continuous clipboard synchronization, audio streaming, or persistent recording.

## Architecture

### Native Mac Remote Host

A new Swift component inside the CodePilot menu-bar app owns all privileged and performance-sensitive macOS behavior:

- Enumerate displays and capture the selected display with ScreenCaptureKit.
- Encode video with VideoToolbox for WebRTC delivery.
- Inject pointer, scroll, keyboard, and modifier events through Core Graphics.
- Read and write the clipboard only for explicit session actions.
- Report screen-recording, accessibility, lock-state, and capture health.
- Display an always-visible active-session indicator and immediate disconnect control.

The native host does not open a network listener. It communicates with the gateway through a permission-restricted Unix domain socket.

### Gateway Coordinator

The Python gateway remains the public API and signaling boundary. It:

- Manages pairing challenges and trusted-device public keys.
- Verifies signed session challenges and creates short-lived controller leases.
- Brokers WebRTC SDP and ICE signaling.
- Generates short-lived Cloudflare TURN credentials server-side.
- Coordinates display selection, clipboard actions, and file transfers.
- Maintains an append-only local security audit log.
- Invalidates sessions on expiry, revocation, restart, host failure, or Mac lock.

### iOS Remote Client

The CodePilot iOS app adds a dedicated full-screen remote desktop surface containing:

- WebRTC video renderer.
- Display switcher and connection-quality indicator.
- Direct-touch and relative-trackpad modes.
- Pinch-to-zoom and pan that do not alter Mac display resolution.
- Keyboard entry and a shortcut panel for Command, Option, Control, Escape, Tab, arrows, function keys, and common combinations.
- Explicit clipboard send and pull actions.
- Existing file picker and transfer workflows.
- An always-reachable emergency disconnect action.

### Cloudflare Boundary

The existing Cloudflare Tunnel carries HTTPS gateway APIs and WebRTC signaling. Screen video and input use WebRTC directly when possible and short-lived Cloudflare TURN relay credentials when direct connectivity fails. Long-lived TURN secrets remain server-side and are never included in the iOS app.

## Pairing And Device Trust

1. The Mac generates a cryptographically random, single-use pairing challenge that expires after two minutes and displays it as a QR code.
2. The iPhone creates a non-exportable Secure Enclave P-256 signing key.
3. The iPhone submits its public key and a signature over the pairing challenge.
4. The Mac requires explicit local approval and shows the device name and key fingerprint.
5. The Mac stores only the public key, device metadata, approval time, and revocation state.

A rejected, consumed, or expired challenge cannot be reused. Removing a trusted device immediately invalidates all of its active and pending sessions.

## Session Authorization

1. The iPhone requests a fresh server nonce using the existing authenticated gateway connection.
2. The app requires successful Face ID or device-owner authentication.
3. The Secure Enclave key signs the nonce plus the requested session capabilities.
4. The gateway verifies device trust, freshness, signature, revocation state, and controller availability.
5. The gateway creates a short-lived, single-controller lease and begins WebRTC negotiation.

The existing bearer token remains required but is insufficient by itself. Every control message includes the lease identifier and a monotonically increasing sequence number. The host rejects expired leases, stale or duplicate sequence numbers, non-controller input, and all input while macOS is locked.

WebRTC protects video with DTLS-SRTP and carries input and control messages over an encrypted data channel. TURN credentials are session-specific and short-lived.

## Control And Coordinate Model

Each display response includes stable display identity, logical frame, pixel dimensions, scale factor, rotation, and current selection. Pointer coordinates are normalized against the transmitted video frame and converted by the native host into the selected display's global macOS coordinate space.

Direct-touch mode maps tap, double-tap, long-press, drag, and two-finger scroll to desktop actions. Trackpad mode treats gestures as relative pointer input. Modifier state is explicit and is always released on disconnect, timeout, background suspension, or transport failure.

Only one controller lease is allowed. Other trusted devices may query availability but cannot view or take control until the current lease ends.

## Clipboard And Files

Clipboard contents never synchronize continuously. The user explicitly chooses:

- Send iPhone text to Mac clipboard.
- Pull Mac text into the iPhone clipboard.

Clipboard values are not written to logs. Initial support is limited to text with a defined size limit.

Files use the existing authenticated upload and download path rather than the real-time data channel. Transfers enforce configured size limits, use temporary files with restrictive permissions, and record metadata but not contents in the audit log.

## User Interface

The remote desktop occupies the primary screen area. A compact top status region shows the Mac name, connection state, latency, and selected display. A bottom toolbar provides keyboard, shortcuts, clipboard, files, interaction-mode switching, and a red disconnect action.

Connection errors identify the failed stage rather than reporting a generic network failure. Permission problems link to clear Mac-side remediation in the menu-bar app.

The Mac menu-bar app provides:

- Screen Recording and Accessibility permission status.
- Pair-new-device QR flow with local approval.
- Trusted-device list with revoke controls.
- Active-session identity and duration.
- Immediate disconnect.
- Local audit-log viewer.

## Lifecycle And Failure Handling

- Brief network interruptions trigger WebRTC ICE restart and reconnection under the same lease.
- Input pauses during reconnect and stale input is discarded rather than replayed.
- Poor bandwidth lowers video resolution and frame rate before compromising input responsiveness.
- Backgrounding iOS suspends video and preserves the lease for a short grace period. Returning after expiry requires Face ID and a new signed challenge.
- Gateway or host restart invalidates active leases. Control never resumes automatically after a process restart.
- Locking macOS immediately stops capture and input and invalidates the lease.
- The host watchdog releases stuck keys and mouse buttons, closes capture sessions, cancels clipboard actions, and removes temporary transfer files.
- Local keyboard or mouse use may temporarily pause remote input to prevent conflicting control.

## Security And Privacy

- iPhone private keys remain in Secure Enclave and Keychain.
- Mac pairing records and Cloudflare TURN secrets live outside the repository with owner-only permissions.
- The gateway remote-desktop endpoints require both normal gateway authentication and device-signature authorization.
- Pairing, lease creation, revocation, display changes, clipboard actions, file-transfer metadata, and disconnect reasons are recorded in an append-only local audit log.
- Screen contents, recordings, keystrokes, clipboard values, file contents, bearer tokens, private keys, and TURN long-lived secrets are never logged.
- The native remote host binds no public TCP or UDP listener.

## Delivery Stages

1. Pairing, trusted-device management, permission checks, leases, and audit logging.
2. Local-network single-display video and pointer/keyboard control.
3. Remote WebRTC connectivity with Cloudflare TURN fallback, reconnection, and adaptive quality.
4. Multi-display switching, clipboard, files, shortcuts, lifecycle hardening, and UI polish.

Each stage must preserve ordinary CodePilot chat and account-management behavior when remote-desktop permissions or configuration are absent.

## Verification

Automated coverage includes:

- Pairing expiry, one-time use, malformed requests, approval, and revocation.
- Signature validation, nonce replay, lease expiry, controller exclusion, and sequence replay.
- Gateway and native-host protocol compatibility over the Unix domain socket.
- Display geometry, scaling, rotation, and coordinate conversion.
- Modifier cleanup and input rejection while locked or disconnected.
- Clipboard limits and temporary-file cleanup.
- Gateway restart, host restart, WebRTC interruption, ICE restart, TURN fallback, and lease expiry.
- iOS background and foreground transitions.

Manual physical-device verification covers Wi-Fi, cellular, network handoff, multiple displays, poor bandwidth, Mac lock, permission revocation, emergency disconnect, and trusted-device revocation. iOS changes require a successful simulator/device build plus the repository-mandated OTA build with publicly reachable manifest and IPA.

## Platform Basis

- Apple ScreenCaptureKit provides high-performance display capture and runtime content-filter updates: <https://developer.apple.com/documentation/screencapturekit>
- Core Graphics provides low-level keyboard, pointer, and scroll event creation and posting: <https://developer.apple.com/documentation/coregraphics/cgevent>
- Cloudflare TURN provides relay connectivity with server-generated expiring credentials: <https://developers.cloudflare.com/realtime/turn/>
