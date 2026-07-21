# CodePilot Issue Triage - 2026-07-20

The full open GitHub issue queue was reviewed against current `origin/main`. Issue #47 was created after the initial 2026-07-20 sweep, so it was reproduced in a follow-up pass. Four issues were reviewed.

## Reviewed Issues

- #47 Pin Python 3.11+ for gateway tests and release checks
  - Proposed labels: `gateway`, `invalid`, and `severity: low`.
  - The report is stale against current `origin/main`. PR #20 replaced the gateway's direct `tomllib` dependency before #47 was filed.
  - The documented gateway command completed successfully with stock Python 3.9.6: all 151 tests passed. The gateway source contains no `tomllib` import, so test discovery no longer has the reported Python 3.11 dependency.
  - No code or documentation fix is required. Close #47 with the current-main reproduction evidence.
- #27 Complete public beta repository settings
  - Proposed labels: `documentation` and `severity: high`. The repository does not currently provide a `release` label, so `documentation` remains the closest available component label.
  - The remaining settings gap was reproduced read-only: the GitHub Pages API returns 404, the repository website field is unset, the repository description still uses the pre-beta wording, and private vulnerability reporting is not enabled.
  - Draft PR #45 refreshes the public-presence audit but explicitly leaves the repository settings unchanged. Completion still requires repository administration outside this run's authority.
- #25 Enforce paired-device leases on every Remote Desktop path
  - Proposed labels: `bug`, `remote-desktop`, `mac`, `ios`, `gateway`, and `severity: critical`. The current labels match.
  - Current `origin/main` retains fail-closed containment: public Remote Desktop requests return `remote_desktop_disabled`. This removes the exposed path but does not implement approved-device signed leases, expiry/revocation enforcement, or HTTP/WebRTC/native-boundary regression coverage.
  - Draft PR #42 preserves the disabled route and adds boundary hardening; it does not satisfy the issue's cross-stack authorization contract. No partial lease implementation was attempted.
- #8 Prepare sanitized public screenshot set
  - Proposed labels: `documentation` and `severity: low`. The current labels match.
  - No PNG, JPEG, or WebP screenshot asset is committed under `docs/`.
  - Draft PR #44 strengthens capture guidance but explicitly does not add screenshots or complete the issue. A deliberately sanitized demo capture session and manual full-resolution inspection remain required.

## Actions

- Recorded the issue queue and label proposals locally.
- Reproduced #47 with the documented gateway command on Python 3.9.6; all 151 tests passed.
- Reproduced #27's live repository-setting gaps with read-only GitHub API queries.
- Verified #25 remains safely contained and reviewed draft PR #42 for issue impact.
- Verified #8 still has no committed screenshot set and reviewed draft PR #44 for issue impact.
- Reviewed draft PR #45 and confirmed it does not resolve or reclassify an open issue.
- Ran `scripts/privacy-audit.sh` and its regression suite successfully before the public write.
- Closed #47 as not planned with concise current-main reproduction evidence; no labels were changed.
- Did not change product code because the remaining work is either cross-stack security work, repository administration, or controlled visual capture.

## Blockers

- #25: keep Remote Desktop disabled and keep OTA, TestFlight, and App Store distribution containing the feature blocked until paired-device lease enforcement and all authorization regression paths pass.
- #27: a maintainer with repository administration access must enable Pages from `main`/`docs`, verify the public URLs, set the approved website and beta description, enable private vulnerability reporting, and align security-reporting links.
- #8: a sanitized demo capture session and manual full-resolution privacy review are still required. Existing approval already covers the demo-only capture set.
