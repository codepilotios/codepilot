# CodePilot Issue Triage - 2026-07-01

Remote write policy: read-only GitHub inspection only. No remote comments, labels, pushes, PRs, or issue edits were made.

## Reviewed Issues

- #1 Add permissions and notification readiness to the Mac setup checklist
  - Proposed labels: `setup`, `remote-desktop`, `mac`, `notifications`, `severity: low`.
  - Triage: confirmed from existing issue body/comment that the setup checklist still needed visible Screen Recording, Accessibility, and notification/APNs readiness rows.
  - Local fix: added setup checklist rows for Screen Recording, Accessibility, and Notifications; added setup-window recovery buttons for the macOS permission prompts and iOS notification guide; added status-label coverage for the new Ready/Optional/Missing states.
- #2 Support or disable the iOS Same Network setup path
  - Proposed labels: `setup`, `ios`, `gateway`, `severity: medium`.
  - Triage: product/security decision required because default gateway binding is loopback-only while iOS exposes Same Network setup. Already escalated locally.
- #3 Require clear Remote Desktop pairing approval in setup
  - Proposed labels: `setup`, `remote-desktop`, `mac`, `ios`, `severity: high`.
  - Triage: trust-model decision required before public beta. Already escalated locally.
- #4 TryCloudflare setup step waits forever for the tunnel process
  - Proposed labels: `bug`, `setup`, `mac`, `cloudflare`, `severity: medium`.
  - Triage: reproduced by code inspection. `startTemporary()` previously called `runCloudflareStep(["start-trycloudflare"])`, which uses `runProcess` and waits for process exit; `cloudflared tunnel --url` is long-running.
  - Local fix: changed the TryCloudflare action to open the long-running command in Terminal so stdout can stream and the temporary URL appears without the setup sheet waiting for process exit.
- #5 Permanent Cloudflare setup does not safely reuse existing tunnels
  - Proposed labels: `bug`, `setup`, `mac`, `cloudflare`, `severity: medium`.
  - Triage: already has a prior local/draft fix referenced by the existing issue comment. No duplicate fix made.
- #8 Prepare sanitized public screenshot set
  - Proposed labels: `documentation`, `severity: low`.
  - Triage: maintainer approval required before screenshots are captured, committed, or reused publicly. Already escalated locally.

## Local Validation

- `swift test --filter CloudflareSetupTests/testTryCloudflareTerminalCommandUsesLongRunningSubcommand` failed before implementation because `CodePilotTryCloudflareCommand` was missing.
- `swift test --filter CloudflareSetupTests` passed after implementation.
- `swift test --filter SetupStatusTests` passed after adding setup readiness rows for #1.
- `swift test` passed after the #1 setup checklist changes.

## Local Branches And Commits

- Branch: `agent/setup-readiness-fixes`.
- Existing local commit: `1d46890 fix: launch trycloudflare setup in terminal`.
- New local commit: `fix: show setup readiness for remote desktop`.

## Escalations

No new escalation beyond the existing `ops/agents/escalations/issue-triage.md` entries for #2, #3, and #8.
