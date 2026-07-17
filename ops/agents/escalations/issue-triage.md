# Issue Triage Escalations

Date: 2026-07-17

- Release blocker: GitHub issue #25 is confirmed. Remote Desktop frame capture, input, and signaling do not consistently enforce an approved device and active signed lease at the gateway and native-host boundaries; the iOS control view also bypasses the signed-session setup flow.
- Required intervention: assign and coordinate a cross-stack security fix, and keep OTA, TestFlight, and App Store distribution containing Remote Desktop blocked until the issue's authorization regression coverage passes.
- Issue triage did not attempt a partial fix because the change is security-sensitive and spans iOS, gateway, native RPC, expiry/revocation, and WebRTC/HTTP parity.
