# CodePilot Issue Triage - 2026-07-22

The full open GitHub issue queue was reviewed against current `origin/main` and the live repository settings. No issue, comment, or label update has landed since the late 2026-07-21 pass. Five open issues were reviewed.

## Reviewed Issues

- #49 Add iOS privacy manifest and flatten App Store icons
  - Proposed labels: `ios` and `severity: high`. The current labels match.
  - Reproduced both packaging gaps: no app-owned `PrivacyInfo.xcprivacy` exists, and all nine AppIcon PNGs retain alpha channels while preserving their required dimensions.
  - The app data-use inventory still requires maintainer approval before a privacy manifest can be encoded. An icon-only change would remain an incomplete iOS fix and would require the prohibited external OTA workflow, so no partial patch was created.
- #48 Align OTA bundle identity, provenance, and public install path
  - Proposed labels: `ios`, `cloudflare`, and `severity: high`. The current labels match. The repository has no `release` component label.
  - Xcode and Fastlane continue to declare `io.codepilot.iOS` consistently. The reported OTA artifact identity, provenance, public endpoint, and installed-update checks require access to Apple and OTA records plus distribution mutations outside this unattended run's authority.
- #27 Complete public beta repository settings
  - Proposed labels: `documentation` and `severity: high`. The repository has no `release` component label.
  - The live public-presence audit still reports seven findings: repository description, website field, Pages configuration, private vulnerability reporting, and the landing, privacy, and support URLs.
  - Completion remains repository-administration work rather than a low-risk source fix.
- #25 Enforce paired-device leases on every Remote Desktop path
  - Proposed labels: `bug`, `remote-desktop`, `mac`, `ios`, `gateway`, and `severity: critical`. The current labels match.
  - All 24 focused gateway tests pass with Remote Desktop still failing closed. Containment does not implement approved-device signed leases, expiry and revocation, or authorization parity across HTTP, WebRTC, and native boundaries.
- #8 Prepare sanitized public screenshot set
  - Proposed labels: `documentation` and `severity: low`. The current labels match.
  - No PNG, JPEG, or WebP screenshot asset is committed under `docs/`.
  - Completion still requires a sanitized demo capture session and manual full-resolution privacy review under the existing approval.

## Actions

- Recorded the refreshed queue, reproduction results, and component/severity proposals locally.
- Re-ran the focused Remote Desktop gateway test suite: all 24 tests passed.
- Re-ran the live public-presence audit: seven findings remain.
- Rechecked the iOS privacy manifest, AppIcon alpha and dimensions, canonical bundle identifier declarations, and documentation screenshot inventory.
- Did not change labels or add issue comments because the current labels already match where present and no new diagnosis would be added publicly.
- Did not change product code, App Store metadata, repository settings, or external distribution systems.

## Blockers

- #49: maintainer approval of the app data-use inventory and an authorized OTA verification workflow are required.
- #48: maintainer access to the existing Apple and OTA records and an authorized distribution verification workflow are required.
- #27: repository administration is required to enable and verify Pages, update approved repository metadata, and enable private vulnerability reporting.
- #25: keep Remote Desktop disabled and distribution containing the feature blocked until signed-lease enforcement and cross-stack authorization regressions pass.
- #8: a sanitized demo capture session and manual full-resolution privacy review are still required.
