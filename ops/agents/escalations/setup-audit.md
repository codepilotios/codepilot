# Setup Audit Escalation

Date: 2026-07-18

Remote Desktop pairing needs maintainer review before public beta. The Mac window displays Approve/Reject controls, but `pairing.complete` already trusts the device after verifying its signature and does not wait for either action; the pending UI can then remain visible beside the trusted device. Because Remote Desktop can control the Mac, decide whether bearer-token possession is sufficient for pairing or whether pairing must require explicit Mac-side approval.

The public beta also needs an approved iOS distribution path. The user guide currently assumes testers already have the app; provide the TestFlight invitation or other approved install link before launch. No App Store Connect account or distribution state was changed by this audit.

This branch changes iOS setup behavior and first-use recovery copy. The required OTA build was not triggered because this unattended audit may not mutate the external OTA service. Run and verify the approved CodePilot OTA build after review and before treating the iOS changes as release-complete.
