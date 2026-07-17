# Setup Audit Escalation

Date: 2026-07-17

Remote Desktop pairing needs maintainer review before public beta. The current flow signs a challenge from the iOS device and approves the device after `pairing.complete`; Mac-side Approve/Reject UI is not part of the happy path. Because Remote Desktop can control the Mac, decide whether bearer-token possession is sufficient for pairing or whether pairing must require explicit Mac-side approval.

The public beta also needs an approved iOS distribution path. The user guide currently assumes testers already have the app; provide the TestFlight invitation or other approved install link before launch. No App Store Connect account or distribution state was changed by this audit.

This branch changes iOS setup behavior. The required OTA build was not triggered because this unattended audit may not mutate the external OTA service. Run and verify the approved CodePilot OTA build after review and before treating the iOS change as release-complete.
