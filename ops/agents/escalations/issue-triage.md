# Issue Triage Escalations

Date: 2026-07-17

- Release blocker: GitHub issue #25 is confirmed. Remote Desktop frame capture, input, and signaling do not consistently enforce an approved device and active signed lease at the gateway and native-host boundaries; the iOS control view also bypasses the signed-session setup flow.
- Required intervention: assign and coordinate a cross-stack security fix, and keep OTA, TestFlight, and App Store distribution containing Remote Desktop blocked until the issue's authorization regression coverage passes.
- Issue triage did not attempt a partial fix because the change is security-sensitive and spans iOS, gateway, native RPC, expiry/revocation, and WebRTC/HTTP parity.
- Containment update (2026-07-18): draft security PR #22 disables the native Remote Desktop host and fail-closes the public remote-control routes. If merged, that safely removes the exposed path, but Remote Desktop must remain disabled until #25's paired-device lease enforcement and regression coverage are complete.
- Public beta repository settings (issue #27): review and merge draft PR #17, then enable GitHub Pages from `main`/`docs`, verify the landing, privacy, and support pages, add the verified URL to the repository website field, and enable private vulnerability reporting. Repository administration and pull-request merge are outside this unattended run's authority.
