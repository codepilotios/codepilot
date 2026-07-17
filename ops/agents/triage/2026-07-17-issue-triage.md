# CodePilot Issue Triage - 2026-07-17

Remote write policy: public GitHub writes require a privacy audit. This pass pushed the focused `agent/issue-triage-remote-desktop-lease-blocker` branch and opened draft PR #26 after the audit passed.

## Reviewed Issues

- #25 Enforce paired-device leases on every Remote Desktop path
  - Proposed labels: `bug`, `remote-desktop`, `mac`, `ios`, `gateway`, `severity: critical`.
  - Current labels already match the proposal; no label change is needed.
  - Classification: confirmed security defect and release blocker for OTA, TestFlight, and App Store distribution.

## Reproduction and Diagnosis

- Gateway frame capture calls `frame.capture` without a lease identifier or proof.
- Gateway signaling accepts an arbitrary syntactically valid session ID, queues the signal, and forwards it to the native host.
- The native signaling handler starts a peer connection for the supplied ID without validating it against `SessionLeaseStore`.
- Native input validation only enforces monotonically increasing sequence numbers per caller-supplied session ID; it does not validate a trusted device or active lease.
- The iOS Remote Desktop view generates a random session ID on appearance and immediately starts frame polling, WebRTC signaling, and input. It does not pair or call `startSession` first.
- Existing gateway tests explicitly pass arbitrary session IDs to frame, signaling, clipboard, and input paths and expect success.

## Verification

- `python3 -m unittest gateway.test_remote_desktop_gateway.RemoteDesktopGatewayTests`: passed.
- `swift test --filter RemoteDesktop`: passed (20 tests).
- Full `gateway.test_remote_desktop_gateway` execution was blocked by the local Python 3.9 runtime lacking the standard-library `tomllib` module required by the phone gateway. This does not affect the confirmed authorization-path diagnosis.

## Action

- No code fix was attempted. Correct enforcement spans the iOS session lifecycle, gateway routing, native RPC boundary, lease expiry/revocation, and HTTP/WebRTC parity; a partial patch would be security-sensitive and outside low-risk issue triage.
- Keep Remote Desktop distribution blocked until regression tests prove that unpaired, expired, revoked, replayed, arbitrary, and mismatched sessions fail at both gateway and native boundaries.

## Blockers

- A maintainer must assign and coordinate the cross-stack security fix before any OTA, TestFlight, or App Store distribution containing Remote Desktop.
