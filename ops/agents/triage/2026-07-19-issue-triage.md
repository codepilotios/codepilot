# CodePilot Issue Triage - 2026-07-19

The full open GitHub issue queue was reviewed after the 2026-07-19 launch-readiness merges. No issue was opened or updated after the latest merged triage work. Three issues remain open.

A later 2026-07-19 refresh again found no new or updated issues. Draft PR #33 has passing CI and improves public-beta access copy, but it does not change the three-issue queue or complete the repository-administration work tracked by #27.

A subsequent refresh found the queue unchanged after draft PRs #34 and #35 opened. Both are cleanly mergeable with passing CI: #34 narrows unauthenticated health diagnostics, while #35 records a community-promotion restriction. Neither changes the classification or next action for #27, #25, or #8.

## Reviewed Issues

- #27 Complete public beta repository settings
  - Proposed labels: `documentation` and `severity: high`. No `release` label currently exists, so `documentation` remains the closest available component label.
  - The documentation prerequisite is now complete: PR #17 merged to `main` on 2026-07-19 with the landing, privacy, support, and security guidance.
  - The remaining configuration gap was reproduced read-only. The GitHub Pages API returns 404, the repository website field is unset, the repository description still uses the pre-beta wording, and private vulnerability reporting is not enabled.
  - Completion requires repository administration. This unattended run is not authorized to change repository settings.
- #25 Enforce paired-device leases on every Remote Desktop path
  - Proposed labels: `bug`, `remote-desktop`, `mac`, `ios`, `gateway`, and `severity: critical`. The current labels match.
  - PR #22 merged to `main` on 2026-07-19 and provides fail-closed containment by disabling the native host and public remote-control routes.
  - Containment removes the exposed path but does not implement approved-device signed leases, expiry/revocation enforcement, or the required HTTP/WebRTC/native-boundary regression coverage. The issue remains a critical distribution blocker.
  - No partial implementation was attempted because enabling any path before the cross-stack authorization contract passes would weaken the merged containment.
- #8 Prepare sanitized public screenshot set
  - Proposed labels: `documentation` and `severity: low`. The current labels match.
  - PR #16 merged the approved demo capture brief and privacy checklist. No real screenshot assets are committed.
  - Capture remains actionable only in a deliberately sanitized Mac and iPhone demo session, followed by manual full-resolution inspection. No screenshot was fabricated from non-running UI state during issue triage.

## Actions

- Recorded the post-merge issue state and label proposals locally.
- Reproduced the remaining #27 repository-setting gaps using read-only GitHub API queries.
- Confirmed the linked preparation, containment, and triage pull requests are merged.
- Reviewed draft PR #33 and confirmed its documentation changes do not alter the current issue classifications or blockers.
- Reviewed draft PRs #34 and #35 and confirmed that their security-health and community-policy changes do not resolve or reclassify an open issue.
- Did not change issue labels or comments because the queue has no new evidence beyond the already published blocker updates.
- Did not change product code: #25 requires a coordinated security implementation, while #8 requires controlled visual capture rather than a code patch.

## Blockers

- #25: keep Remote Desktop disabled and keep OTA, TestFlight, and App Store distribution containing the feature blocked until paired-device lease enforcement and all authorization regression paths pass.
- #27: a maintainer with repository administration access must enable Pages from `main`/`docs`, verify the landing/privacy/support URLs, set the verified website and approved beta description, enable private vulnerability reporting, and then align security-reporting links.
- #8: a sanitized demo capture session and manual pixel review are still required. This is launch content work, not a credential, legal, pricing, or App Store submission decision.
