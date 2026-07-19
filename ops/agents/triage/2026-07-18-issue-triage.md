# CodePilot Issue Triage - 2026-07-18

Five open GitHub issues were reviewed for the Mac app, iOS app, gateway, release tooling, setup flow, and public documentation.

## Reviewed Issues

- #30 Fix asc guard recursion in unattended release checks
  - Proposed labels: `bug`, `release`, and `severity: high`.
  - Reproduced: with the command-guard directory first on `PATH` and no exported real executable, `asc appstore list --output json` recursively invoked the guard and timed out.
  - Fixed on `agent/issue-30-asc-guard`: the runner captures and exports the real `asc` path before prepending guards, and the guard rejects self-resolution as a fail-safe.
  - Verification: shell syntax, public-write guard tests, runner environment tests, and the privacy audit pass.
- #28 Fail gateway tests when a worker thread raises
  - Proposed labels: `bug`, `gateway`, and `severity: low`; current labels match.
  - Draft PR #29 contains the focused fix and its CI check passes.
- #27 Complete public beta repository settings
  - Proposed labels: `documentation` and `severity: high`.
  - Still requires maintainer review and merge of the prepared documentation, followed by repository administration for Pages, repository metadata, and private vulnerability reporting.
- #25 Enforce paired-device leases on every Remote Desktop path
  - Proposed labels: `bug`, `remote-desktop`, `mac`, `ios`, `gateway`, and `severity: critical`; current labels match.
  - Remains a cross-stack security and distribution blocker. Keep Remote Desktop disabled until the signed-lease requirements and authorization regression coverage pass.
- #8 Prepare sanitized public screenshot set
  - Proposed labels: `documentation` and `severity: low`; current labels match.
  - The approved demo-only screenshot task remains open. No screenshot assets were created or published in this pass.

## Blockers

- #25 requires a coordinated authorization fix across iOS, gateway, native RPC, expiry and revocation, and WebRTC/HTTP paths. Draft PR #22 provides containment only.
- #27 requires maintainer approval and repository administration that this unattended run is not authorized to perform.
