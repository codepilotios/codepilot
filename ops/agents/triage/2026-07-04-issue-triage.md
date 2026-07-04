# CodePilot Issue Triage - 2026-07-04

Remote write policy: public GitHub writes are allowed after privacy audit when they directly advance launch readiness. Non-GitHub external system mutation is prohibited in this unattended run.

## Reviewed Issues

- #2 Support or disable the iOS Same Network setup path
  - Current labels: `setup`, `ios`, `gateway`, `severity: medium`.
  - Maintainer decision found: hide/disable Same Network for public beta; Cloudflare remains the supported default remote connection path.
  - Action: implemented on branch `agent/issue-2-3-public-beta-setup`.
- #3 Require clear Remote Desktop pairing approval in setup
  - Current labels: `setup`, `remote-desktop`, `mac`, `ios`, `severity: high`.
  - Maintainer decision found: require explicit approval on the Mac; iOS must remain pending until approval or rejection.
  - Action: implemented on branch `agent/issue-2-3-public-beta-setup`.
- #8 Prepare sanitized public screenshot set
  - Current labels: `documentation`, `severity: low`.
  - Maintainer approval found for sanitized demo-only screenshots.
  - Action: created a dedicated screenshot manifest on branch `agent/issue-8-screenshot-plan` and opened draft PR #16; no screenshot assets were captured or published.

## Follow-up Check - 2026-07-04

- Checked open GitHub issues for `codepilotios/codepilot`: #2, #3, and #8 remain the only open issues.
- Checked issues created on 2026-07-04: none found.
- Confirmed draft PR #15 remains open for #2/#3 on `agent/issue-2-3-public-beta-setup`.
- Confirmed draft PR #16 remains open for #8 on `agent/issue-8-screenshot-plan`; CI `Test and Audit` is passing.
- Ran `scripts/privacy-audit.sh`: passed.
- No new public GitHub writes were needed in this follow-up pass.

## Local Changes

- Disabled Same Network from the iOS public beta connection picker and updated setup docs to point users to Cloudflare.
- Changed Remote Desktop pairing so `pairing.complete` verifies the phone proof and returns `pending_mac_approval`; Mac approval is now required before the device is trusted.
- Removed the unused iOS pairing-code field and kept Start Session disabled until refresh sees a paired Mac state.
- Added focused Mac and iOS tests for public-beta connection modes and pending Mac approval.
- Added `docs/SCREENSHOTS.md` on `agent/issue-8-screenshot-plan` so the README screenshot link resolves and the beta screenshot capture has fixed demo data, filenames, and manual privacy-review checks.

## Verification

- `swift test`: passed.
- Focused iOS simulator tests for RemoteDesktopTests: passed.
- iOS simulator build with code signing disabled: passed.
- OTA build: not run because it would mutate non-GitHub OTA distribution systems, which this unattended run is not allowed to do.

## Blockers

- OTA build and public OTA asset verification require an allowed release/OTA run outside this issue-triage policy.
- #8 screenshot capture remains launch work; the manifest is ready, but actual image capture still needs a sanitized app/device state and manual pixel review.
