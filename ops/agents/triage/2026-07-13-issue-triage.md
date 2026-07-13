# CodePilot Issue Triage - 2026-07-13

Remote write policy: public GitHub writes are allowed only after privacy audit and only when directly permitted by the launch-autonomy policy. Non-GitHub external system mutation is prohibited in this unattended run.

## Reviewed Issues

- #2 Support or disable the iOS Same Network setup path
  - Current labels: `setup`, `ios`, `gateway`, `severity: medium`.
  - Triage: maintainer decision remains to hide/disable Same Network for public beta and keep Cloudflare Tunnel as the supported default iPhone path.
  - Reproduction/fix status: first-run setup already used `GatewayConnectionKind.publicBetaCases`, but Settings still used `GatewayConnectionKind.allCases`, leaving Same Network selectable after setup. Public docs and the App Store metadata draft also still referenced same-network setup.
  - Action: patched the iOS Settings picker to use public-beta selectable cases, normalized any stored disabled selection back to Cloudflare, and updated public beta copy.
- #3 Require clear Remote Desktop pairing approval in setup
  - Current labels: `setup`, `remote-desktop`, `mac`, `ios`, `severity: high`.
  - Triage: maintainer decision remains explicit Mac approval before trust.
  - Reproduction/fix status: prior implementation appears present; no new pairing change made in this pass.
  - Proposed next action: maintainer should confirm closure, or ask for a follow-up issue if more pairing setup work remains.
- #8 Prepare sanitized public screenshot set
  - Current labels: `documentation`, `severity: low`.
  - Triage: sanitized demo-only screenshot set remains approved.
  - Work status: draft PR #16 (`agent/issue-8-screenshot-plan`) remains open and cleanly mergeable.
  - Proposed next action: continue screenshot capture/publishing work through PR #16; no screenshot assets were created in this pass.

## Local Changes

- Updated `ios/CodexPhone/CodexPhone/CodexPhoneApp.swift` so both connection pickers use Cloudflare-only public beta selectable cases.
- Added focused test coverage in `ios/CodexPhone/CodexPhoneTests/RemoteDesktopTests.swift`.
- Updated `docs/index.md` and `docs/APP_STORE_METADATA_DRAFT.md` to stop advertising same-network beta setup.

## Verification

- Red: focused iOS test failed because `GatewayConnectionKind.selectableCases` was missing.
- Green: focused iOS simulator test passed on `iPhone 17, OS 26.5`.
- Broader check: `CodexPhoneTests/RemoteDesktopTests` passed on `iPhone 17, OS 26.5` with 28 tests and 0 failures.
- Privacy audit: `scripts/privacy-audit.sh` passed.

## Blockers

- OTA build and public OTA asset verification are still required for iOS changes, but were not run because this unattended policy prohibits non-GitHub external system mutation.
- Closing stale GitHub issues or draft PRs remains maintainer cleanup; this policy allows creating issues, branches, commits, pushes, and draft PRs, but does not explicitly allow closing existing public GitHub items.
