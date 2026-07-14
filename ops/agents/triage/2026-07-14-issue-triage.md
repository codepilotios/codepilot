# CodePilot Issue Triage - 2026-07-14

Remote write policy: public GitHub writes are allowed only after privacy audit and only when directly permitted by the launch-autonomy policy. Non-GitHub external system mutation is prohibited in this unattended run.

## Reviewed Issues

- #2 Support or disable the iOS Same Network setup path
  - Current labels: `setup`, `ios`, `gateway`, `severity: medium`.
  - Triage: maintainer decision remains to hide/disable Same Network for public beta and keep Cloudflare Tunnel as the supported default iPhone path.
  - Status: no new issue comments or label changes since the 2026-07-03 maintainer decision. Follow-up patch for Settings exposure remains prepared in draft PR #19.
  - Proposed next action: review/merge PR #19, then maintainer can close #2 when satisfied.
- #3 Require clear Remote Desktop pairing approval in setup
  - Current labels: `setup`, `remote-desktop`, `mac`, `ios`, `severity: high`.
  - Triage: maintainer decision remains explicit Mac approval before Remote Desktop pairing trust.
  - Status: no new issue comments or label changes since the 2026-07-03 maintainer decision. Prior implementation remains represented by merged PR #14 and follow-up triage state in PR #19.
  - Proposed next action: maintainer should confirm closure, or file/ask for a follow-up issue if more pairing setup work remains.
- #8 Prepare sanitized public screenshot set
  - Current labels: `documentation`, `severity: low`.
  - Triage: sanitized demo-only screenshot set remains approved.
  - Status: no new issue comments or label changes since the 2026-07-03 maintainer approval. Screenshot manifest work remains isolated in draft PR #16.
  - Proposed next action: continue screenshot capture/publishing work through PR #16; do not publish screenshot assets without privacy audit and manual public-safety review.

## Related Pull Requests

- PR #19 (`agent/issue-triage-2026-07-08`) remains open as a draft, cleanly mergeable, with the latest `Test and Audit` check passing.
- PR #16 (`agent/issue-8-screenshot-plan`) remains open as a draft, cleanly mergeable, with `Test and Audit` passing.
- PR #15, PR #18, and PR #20 remain open draft PRs with dirty merge state; no issue-triage-owned public write is required for them in this sweep.

## Local Changes

- Added this triage note only.
- No product code, docs copy, app metadata, or release tooling files were changed in this sweep.

## Verification

- Queried open GitHub issues; #2, #3, and #8 remain the only open issues.
- Reviewed issue bodies and comments for #2, #3, and #8; no new comments were present after the 2026-07-03 maintainer decisions.
- Queried open draft PR state; PR #19 and PR #16 remain clean with passing checks.

## Blockers

- No new blocker or maintainer decision was identified during this sweep.
- Existing cleanup remains: maintainer should close stale/superseded public GitHub items when ready because unattended policy does not explicitly allow closing existing issues or PRs.

## Launch-Autonomy Sweep

- Open issue inventory rechecked on 2026-07-14: #2, #3, and #8 remain the only open issues.
- Issue bodies, labels, and comments were reviewed; no issue has changed since the 2026-07-03 maintainer decisions.
- Proposed labels remain unchanged:
  - #2: `setup`, `ios`, `gateway`, `severity: medium`.
  - #3: `setup`, `remote-desktop`, `mac`, `ios`, `severity: high`.
  - #8: `documentation`, `severity: low`.
- Draft PR #19 for `agent/issue-triage-2026-07-08` remains open, cleanly mergeable, and its latest `Test and Audit` check is passing.
- Draft PR #16 for `agent/issue-8-screenshot-plan` remains open, cleanly mergeable, and its latest `Test and Audit` check is passing.
- Draft PRs #15, #18, and #20 remain open and merge-conflicted; no issue-triage-owned public write is required for them in this sweep.
- Draft PR #17 remains open, cleanly mergeable, and passing, but it is presence-maintenance scope rather than issue-triage scope.
- No new reproduction attempt was needed because no new actionable bug reports were filed.
- No public GitHub issue, comment, label, branch push, or PR write was made during remote inspection.
