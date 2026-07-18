# CodePilot Issue Triage - 2026-07-18

One new GitHub issue was opened after the earlier 2026-07-18 triage pass. The three open issues and related draft pull requests were reviewed for changes.

## Reviewed Issues

- #27 Complete public beta repository settings
  - Proposed labels are `documentation` and `severity: high`. No `release` component label currently exists; `documentation` is the closest available component label.
  - Reproduced the reported configuration gap: the GitHub Pages API returns 404, the repository website field is empty, and private vulnerability reporting is disabled.
  - Draft PR #17 contains the prepared `docs/` landing, privacy, support, and security pages and remains open, mergeable, and passing its `Test and Audit` check.
  - Completion requires maintainer review and merge of PR #17 followed by repository-setting changes. This unattended run is not authorized to merge pull requests or change repository settings.
- #25 Enforce paired-device leases on every Remote Desktop path
  - Proposed labels remain `bug`, `remote-desktop`, `mac`, `ios`, `gateway`, and `severity: critical`; the current labels match.
  - The critical authorization defect remains open and release-blocking. `origin/main` has not changed since the confirmed 2026-07-17 reproduction.
  - Draft security PR #22 now contains fail-closed containment: it disables the native Remote Desktop host and makes public remote-control routes unavailable. This removes the exposed path if merged, but it does not implement the paired-device lease behavior or regression coverage required to resolve #25.
  - PR #22 is open, mergeable, and passing its `Test and Audit` check.
  - Draft PR #26 remains open, mergeable, and passing its `Test and Audit` check.
- #8 Prepare sanitized public screenshot set
  - Proposed labels remain `documentation` and `severity: low`; the current labels match.
  - The approved demo-only capture task remains open. No screenshot assets were added or published in this pass.

## Action

- No issue labels were changed. Added a concise #25 comment linking the containment in PR #22 while keeping the lease-enforcement blocker explicit.
- Recorded #27's verified configuration state and maintainer-only completion steps in the issue-triage escalation.
- No code change was attempted. Issue #25 requires a coordinated cross-stack security fix, and issue #8 requires full-resolution visual inspection of newly captured demo assets.
- After the privacy audit passed, the triage branch was updated and the containment note was added to #25.

## Blockers

- The existing #25 escalation remains active. PR #22 provides safe fail-closed containment if merged, but keep Remote Desktop disabled and distribution blocked until the required authorization regression coverage passes.
- Issue #27 requires maintainer approval and repository administration: review and merge PR #17, enable Pages from `main`/`docs`, verify the site, set the repository website URL, enable private vulnerability reporting, and then update security-reporting links.

## Follow-up Pass

- No new GitHub issues or issue updates appeared after the preceding pass. The open queue remains #27, #25, and #8.
- The proposed labels and existing blocker assessments remain unchanged.
- `origin/main` remains unchanged. GitHub Pages still returns 404, the repository website field remains empty, and private vulnerability reporting remains disabled.
- Draft PR #17 received public-metadata and documentation updates, and draft PR #22 received agent-write audit hardening. Neither update changes the #27 maintainer steps or resolves #25's paired-device lease requirements.
- Draft PRs #17, #22, and #26 remain open, mergeable, and passing `Test and Audit` on their latest commits.
- No additional issue comment, branch, or code fix was needed. The existing escalation covers the two maintainer actions that remain necessary.
