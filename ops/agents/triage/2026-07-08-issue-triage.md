# CodePilot Issue Triage - 2026-07-08

Remote write policy: public GitHub writes are allowed only after privacy audit and only when directly permitted by the launch-autonomy policy. This pass did not mutate GitHub or non-GitHub external systems.

## Reviewed Issues

- #2 Support or disable the iOS Same Network setup path
  - Current labels: `setup`, `ios`, `gateway`, `severity: medium`.
  - Triage: maintainer decision remains to hide/disable Same Network for public beta.
  - Reproduction/fix status: implementation appears landed on `main` through merged PR #14 (`fix: require approved remote pairing for beta`) on 2026-07-04. Issue remains open.
  - Proposed next action: maintainer should confirm closure, or ask for a follow-up issue if more Same Network work remains.
- #3 Require clear Remote Desktop pairing approval in setup
  - Current labels: `setup`, `remote-desktop`, `mac`, `ios`, `severity: high`.
  - Triage: maintainer decision remains explicit Mac approval before trust.
  - Reproduction/fix status: implementation appears landed on `main` through merged PR #14 on 2026-07-04. Issue remains open.
  - Proposed next action: maintainer should confirm closure, or ask for a follow-up issue if more pairing setup work remains.
- #8 Prepare sanitized public screenshot set
  - Current labels: `documentation`, `severity: low`.
  - Triage: sanitized demo-only screenshot set remains approved.
  - Work status: draft PR #16 (`agent/issue-8-screenshot-plan`) is open, cleanly mergeable, and its CI `Test and Audit` check is passing.
  - Proposed next action: continue screenshot capture/publishing work through PR #16; no new issue needed.

## Related Pull Requests

- PR #14 `[codex] Require Mac-approved Remote Desktop pairing`: merged 2026-07-04 into `main`; appears to cover #2 and #3.
- PR #15 `[codex] Fix public beta setup blockers`: still open as a draft from the same `agent/issue-2-3-public-beta-setup` branch, now merge-conflicted. It appears stale/duplicative after PR #14 merged.
- PR #16 `[codex] Add public screenshot manifest`: open draft, clean merge state, CI passing; covers #8 planning.
- PR #18 `Harden gateway file access and launch artifacts`: open draft, merge-conflicted; security-scan scope, not issue-triage scope.

## Local Changes

- Added this triage note.
- Updated `ops/agents/escalations/issue-triage.md` with the stale GitHub cleanup item.

## Verification

- GitHub issue list queried for open issues: #2, #3, and #8 remain the only open issues.
- GitHub PR list queried for open draft PRs: #15, #16, #17, and #18 are open; #15 and #18 report dirty merge state.
- No app or gateway tests were run because this pass made no product code changes.

## Blockers

- Maintainer GitHub cleanup is needed for stale-open issues #2/#3 and duplicate conflicted PR #15. This run did not close issues or PRs because the unattended public-write permissions explicitly allow creating issues, branches, commits, pushes, and draft PRs, but do not explicitly allow closing existing public GitHub items.
