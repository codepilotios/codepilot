# CodePilot Issue Triage - 2026-07-18

Four open GitHub issues were reviewed for the Mac app, iOS app, gateway, release tooling, setup flow, and public documentation.

## Reviewed Issues

- #28 Fail gateway tests when a worker thread raises
  - Proposed labels: `bug`, `gateway`, and `severity: low`.
  - Reproduced: the focused unit test exited successfully while its daemon worker raised a `TypeError` because the test double used the old `run_turn` signature.
  - Fixed on `agent/issue-28-worker-thread-tests`: the test double accepts the current reasoning-effort argument and the affected test runs its worker synchronously so worker exceptions fail the owning test.
  - Verification: the focused regression test and all 90 gateway tests pass without a background exception.
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

- #25 requires a coordinated security fix across iOS, gateway, native RPC, expiry and revocation, and WebRTC/HTTP paths.
- #27 requires maintainer approval and repository administration that this unattended run is not authorized to perform.
