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
