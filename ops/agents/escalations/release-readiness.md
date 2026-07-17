# CodePilot Release Readiness Escalation

Date: 2026-07-17

Status: CodePilot is not ready for a new OTA, TestFlight, or App Store release. Local unsigned builds and tests are healthy, but release identity, signing/App Store Connect access, privacy work, screenshots, and review metadata remain blocked.

## Verified Locally

- `scripts/privacy-audit.sh`: passed after moving the optional private-identifier denylist to ignored local configuration.
- `swift test`: passed; 57 tests, 0 failures.
- Gateway unit tests: passed with the default Python toolchain; 112 tests, 0 failures.
- macOS Swift release build: passed.
- iOS simulator Debug and clean Release builds: passed with code signing disabled.
- Unsigned generic-device iOS Release archive compile: passed.
- iOS simulator tests: passed; 37 tests, 0 failures.
- Fastlane Ruby syntax and version metadata JSON validation: passed.
- Public-write guard, agent-runner model-selection, and scheduler-lock tests: passed.
- The current install-linked OTA manifest and IPA both returned HTTP 200 in a read-only check, but no OTA build or external-state mutation was performed in this run.

## Release Blockers

- **Remote Desktop pairing is not enforced on the active capture/control paths (issue #25).** The frame, input, and WebRTC signaling routes accept arbitrary session identifiers after the shared gateway bearer token check; they do not require a trusted device or validate an active signed lease. The iOS control view also bypasses the available session-start API. This can let any gateway-token holder view or control the Mac without the documented per-device pairing boundary. Block OTA, TestFlight, and App Store distribution until the native host, gateway routes, and iOS client enforce one lease end-to-end with regression tests for unpaired, expired, revoked, replayed, and mismatched sessions.
- **Canonical bundle identity requires a maintainer decision.** The latest distributed OTA build uses a legacy identifier that differs from the current Xcode project and Fastlane default. Publishing without aligning OTA, signing, and App Store Connect could create a second installation.
- The latest OTA build is stale relative to current source and has no recorded source commit. No OTA build was triggered because this run is not authorized to mutate external distribution systems.
- App Store Connect credentials and the Apple developer team setting are unavailable. The launch guard also blocks `asc`, including read-only discovery, so the app record, processed builds, availability, version attachment, and strict validation could not be checked.
- A Fastlane lockfile is now committed, but the locked bundle is not installed in this release environment. Both TestFlight lanes upload builds; the external lane also changes tester-group state.
- No signed device archive/export was run. TestFlight upload, group distribution, build processing, and App Store submission were intentionally not run.
- `metadata/version/0.1/en-US.json` still needs approved support and privacy-policy URLs plus App Review notes/contact and gateway access instructions.
- App Privacy, privacy labels, age rating, content rights, export compliance, category, availability, and any pricing/legal settings require maintainer confirmation in App Store Connect.
- No `PrivacyInfo.xcprivacy` is present despite required-reason API use. Gateway-token Keychain hardening is being tracked separately and must be merged and verified before release.
- The published docs currently link to privacy, support, and screenshot pages that are absent on this branch. Draft PR #17 prepares those pages and must be reconciled before the links can be treated as release-ready.
- App Store-ready screenshots are absent. All future captures need synthetic accounts, hosts, paths, and tokens.
- App icon files include alpha channels, including the marketing icon; flatten and validate them before archive upload.
- Draft metadata is not connected to the Fastlane lanes, which otherwise use a generic changelog. External TestFlight metadata still lacks an approved beta description, feedback email, and review contact. There is no local App Store metadata staging/validation path.
- The locally built Mac app is arm64-only; Intel/universal distribution has not been verified.

## Prepared Artifacts

- Draft TestFlight notes: `metadata/testflight/0.1/en-US.md`.
- Draft App Store metadata and release notes: `metadata/version/0.1/en-US.json`.
- Screenshot capture/redaction checklist: `metadata/screenshots/README.md`.

## Maintainer Actions

1. Confirm the canonical iOS bundle identifier and align Xcode, OTA, signing, and the App Store Connect record before another distributed build.
2. Approve and verify an end-to-end Remote Desktop trust boundary that requires a paired device and active signed lease for capture, signaling, and input.
3. Provide an authorized release environment for a signed archive and read-only App Store Connect validation.
4. Approve the support/privacy URLs, review contact and gateway-access instructions, privacy answers, age rating, content-rights answer, and export-compliance answer.
5. Supply a sanitized 6.9-inch iPhone screenshot set and approve remediation of the token-storage/privacy-manifest issues.
