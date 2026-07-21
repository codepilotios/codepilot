# CodePilot Issue Triage - 2026-07-21

The full open GitHub issue queue was reviewed against current `origin/main` and the live repository settings. No new issue has been opened since the 2026-07-20 pass. Three open issues were reviewed.

## Reviewed Issues

- #27 Complete public beta repository settings
  - Proposed labels: `documentation` and `severity: high`. The repository does not provide a `release` label, so `documentation` remains the closest available component label.
  - The live settings gap remains reproducible: the GitHub Pages API returns 404, the repository website field is unset, the repository description still uses the pre-beta wording, and private vulnerability reporting reports `enabled: false`.
  - This remains repository-administration work and is not a low-risk source change.
- #25 Enforce paired-device leases on every Remote Desktop path
  - Proposed labels: `bug`, `remote-desktop`, `mac`, `ios`, `gateway`, and `severity: critical`. The current labels match.
  - Current `origin/main` continues to fail closed with `remote_desktop_disabled`, and the focused gateway containment test passes.
  - Containment does not implement approved-device signed leases, expiry and revocation, or authorization parity across HTTP, WebRTC, and native boundaries. Keep the feature disabled until the full cross-stack contract and regression coverage pass.
- #8 Prepare sanitized public screenshot set
  - Proposed labels: `documentation` and `severity: low`. The current labels match.
  - No PNG, JPEG, or WebP screenshot asset is committed under `docs/`.
  - Completion still requires the approved sanitized demo capture session and manual full-resolution privacy inspection; no code-only fix can complete this issue.

## Actions

- Recorded the refreshed issue queue and component/severity proposals locally.
- Rechecked the live repository settings for #27 without mutating them.
- Rechecked the fail-closed Remote Desktop boundary for #25 and ran its focused gateway test.
- Rechecked the documentation tree for screenshot assets relevant to #8.
- Ran the repository privacy audit and its regression suite before updating the public draft branch.
- Did not change labels or product code because the current labels already match where present and none of the remaining work is a low-risk source fix.

## Blockers

- #25: keep Remote Desktop disabled and keep distribution containing the feature blocked until paired-device lease enforcement and all authorization regression paths pass.
- #27: a maintainer with repository administration access must enable Pages from `main`/`docs`, verify the public URLs, set the approved website and beta description, enable private vulnerability reporting, and align security-reporting links.
- #8: a sanitized demo capture session and manual full-resolution privacy review are still required. Existing approval already covers the demo-only capture set.

## 21:26 CEST Refresh

- The open queue remains unchanged at issues #27, #25, and #8; none has received a new issue update since the preceding review.
- Reproduced #25 containment against current `origin/main`: all 24 focused Remote Desktop gateway tests pass, including the fail-closed `remote_desktop_disabled` response. This does not satisfy the signed-lease requirements tracked by the issue.
- Rechecked #27: the Pages API still returns 404, the repository website remains unset, the description still uses the pre-beta wording, and private vulnerability reporting remains disabled.
- Rechecked #8: no PNG, JPEG, or WebP screenshot asset is present under `docs/`.
- No additional source fix, label change, issue comment, or escalation is warranted from this unchanged evidence.

## 22:17 CEST Refresh

Two release-readiness issues were opened after the preceding sweep and were reviewed against current `origin/main`.

- #48 Align OTA bundle identity, provenance, and public install path
  - Proposed labels: `ios`, `cloudflare`, and `severity: high`. The current labels match. The repository has no `release` component label.
  - Xcode and Fastlane consistently declare `io.codepilot.iOS`, but the reported completed OTA artifact has a different bundle identity and no source commit. The reported public install entry points also return HTTP 403.
  - Completion requires confirmation against the existing Apple and OTA records, a build from current public `main`, recorded source provenance, public endpoint verification, and an installed-update check. Those are release/distribution operations and are outside this unattended run's permitted mutations.
- #49 Add iOS privacy manifest and flatten App Store icons
  - Proposed labels: `ios` and `severity: high`. The current labels match.
  - Reproduced both packaging gaps: no app-owned `PrivacyInfo.xcprivacy` exists, and `sips` reports alpha channels on all nine AppIcon PNGs while their dimensions remain correct.
  - The privacy manifest cannot be authored responsibly until the app data-use inventory is completed and approved. An icon-only patch would still be an iOS change requiring the mandatory OTA workflow, which this run may not mutate, so no partial source change was created.

### Actions

- Added the new issue findings and component/severity proposals to this local triage record.
- Added the maintainer-controlled identity, distribution, and privacy-inventory requirements to the issue-triage escalation.
- Ran the repository privacy audit and its regression suite before updating the public draft branch.
- Did not duplicate the already-correct labels or add public issue comments that would merely repeat the issue bodies.

### Blockers

- #48: a maintainer with access to the existing Apple and OTA records must confirm the canonical bundle identity and authorize the release/distribution verification workflow.
- #49: a maintainer must approve the app data-use inventory before the privacy manifest is encoded; any resulting iOS asset or manifest change must complete the mandatory OTA verification workflow.

## 23:08 CEST Refresh

- The open queue remains unchanged at issues #49, #48, #27, #25, and #8; none has received a new issue update since the 22:17 CEST review.
- Re-ran the focused Remote Desktop gateway suite for #25: all 24 tests pass with the feature still failing closed. The signed-lease implementation and cross-stack authorization coverage remain outstanding.
- Re-ran the live public-presence audit for #27: it still reports seven findings covering the repository copy and website field, Pages configuration, private vulnerability reporting, and the three public Pages URLs.
- Rechecked #49: no app-owned privacy manifest exists, all nine AppIcon PNGs retain alpha channels, and their required dimensions remain intact. Xcode and Fastlane continue to declare `io.codepilot.iOS` consistently for #48.
- Rechecked #8: no PNG, JPEG, or WebP screenshot asset exists under `docs/`.
- No low-risk source fix, label change, issue comment, or new escalation is warranted from this unchanged evidence.

## 23:54 CEST Refresh

- The open queue remains unchanged at issues #49, #48, #27, #25, and #8; none has received a new issue update or comment since the preceding review.
- Re-ran the focused Remote Desktop gateway suite for #25: all 24 tests pass, including the fail-closed `remote_desktop_disabled` response. The signed-lease implementation and cross-stack authorization coverage remain outstanding.
- Re-ran the live public-presence audit for #27: it still reports seven findings covering the repository copy and website field, Pages configuration, private vulnerability reporting, and the three public Pages URLs.
- Rechecked #49: no app-owned privacy manifest exists, all nine AppIcon PNGs retain alpha channels, and their required dimensions remain intact. Xcode and Fastlane continue to declare `io.codepilot.iOS` consistently for #48.
- Rechecked #8: no PNG, JPEG, or WebP screenshot asset exists under `docs/`.
- No low-risk source fix, label change, issue comment, or new escalation is warranted from this unchanged evidence.
