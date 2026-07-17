# CodePilot Issue Triage - 2026-07-18

No new GitHub issues were opened after the 2026-07-17 triage pass. The two open issues and the existing draft triage PR were reviewed for changes.

## Reviewed Issues

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

- No issue labels needed updating. Added a concise #25 comment linking the containment in PR #22 while keeping the lease-enforcement blocker explicit.
- No code change was attempted. Issue #25 requires a coordinated cross-stack security fix, and issue #8 requires full-resolution visual inspection of newly captured demo assets.
- After the privacy audit passed, the triage branch was updated and the containment note was added to #25.

## Blockers

- The existing #25 escalation remains active. PR #22 provides safe fail-closed containment if merged, but keep Remote Desktop disabled and distribution blocked until the required authorization regression coverage passes.
