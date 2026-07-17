# CodePilot Issue Triage - 2026-07-17

Remote write policy: public GitHub writes are allowed only after the privacy audit and only when directly permitted by the launch-autonomy policy. Non-GitHub external system mutation is prohibited in this unattended run.

## Reviewed Issues

- #2 Support or disable the iOS Same Network setup path
  - Proposed labels: `setup`, `ios`, `gateway`, `severity: medium` (already applied).
  - No comments or label changes have appeared since the 2026-07-03 maintainer decision to keep the public beta Cloudflare-only.
  - The remaining Settings exposure and public-copy fix is prepared in draft PR #19, which is mergeable and has a passing `Test and Audit` check.
  - Proposed next action: review and merge PR #19, then close #2 when the implementation is accepted.
- #3 Require clear Remote Desktop pairing approval in setup
  - Proposed labels: `setup`, `remote-desktop`, `mac`, `ios`, `severity: high` (already applied).
  - No comments or label changes have appeared since the 2026-07-03 maintainer decision requiring explicit Mac approval.
  - The approved pairing flow is present on `main` through merged PR #14; no additional defect was reported or reproduced in this sweep.
  - Proposed next action: close #3 if the merged behavior satisfies the acceptance criteria, or file a focused follow-up for any remaining setup gap.
- #8 Prepare sanitized public screenshot set
  - Proposed labels: `documentation`, `severity: low` (already applied).
  - No comments or label changes have appeared since the 2026-07-03 approval for sanitized demo-only screenshots.
  - Draft PR #16 remains mergeable with a passing `Test and Audit` check and contains the screenshot manifest and manual privacy-review procedure.
  - Proposed next action: continue capture and review through PR #16; do not publish assets without privacy audit and manual pixel review.

## Related Pull Requests

- PR #19 (`agent/issue-triage-2026-07-08`) is a mergeable draft with passing CI and contains the focused #2 follow-up.
- PR #16 (`agent/issue-8-screenshot-plan`) is a mergeable draft with passing CI and covers #8 planning.
- PR #22 (`agent/security-scan-2026-07-17`) is a mergeable draft with passing CI, but remains security-agent scope.
- PRs #15, #18, and #20 remain stale or merge-conflicted drafts; no issue-triage-owned public mutation is authorized for them.

## Local Changes and Verification

- Added this triage note only; no product code, App Store metadata, or release tooling changed in this sweep.
- Queried all open issues and reviewed the bodies, labels, and comments for #2, #3, and #8.
- Queried related draft PR merge state and CI results.
- No new reproduction run was needed because no new actionable report was filed; the existing #2 fix remains verified by PR #19 CI.

## Blockers

- No new outage, security finding, credential need, or product decision requires escalation.
- Maintainer cleanup is still needed to merge or close existing issues and draft PRs because this unattended policy authorizes creation of issues and draft PRs, but not closure or merging.
- Any merged iOS change still requires the separate OTA workflow; this run cannot mutate non-GitHub distribution systems.
