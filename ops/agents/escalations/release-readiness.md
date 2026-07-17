# CodePilot Release Readiness Escalation

Date: 2026-07-17

Status: CodePilot is not ready for a new OTA, TestFlight, or App Store release. Local unsigned builds and tests are healthy, but release identity, signing/App Store Connect access, privacy work, screenshots, and review metadata remain blocked.

## Verified Locally

- `scripts/privacy-audit.sh`: passed after moving the optional private-identifier denylist to ignored local configuration.
- `swift test`: passed; 78 tests, 0 failures.
- Gateway unit tests: passed with the default Python toolchain; 112 tests, 0 failures.
- macOS Swift release build: passed.
- iOS simulator Debug and clean Release builds: passed with code signing disabled.
- Unsigned generic-device iOS Release build: passed.
- iOS simulator tests: passed; 37 tests, 0 failures.
- Fastlane Ruby syntax and version metadata JSON validation: passed.
- Public-write guard, agent-runner model-selection, and scheduler-lock tests: passed.
- The last recorded install-linked OTA manifest and IPA check passed, but no OTA build or external-state mutation was performed in this run.

## Release Blockers

- **Canonical bundle identity requires a maintainer decision.** The latest distributed OTA build uses a legacy identifier that differs from the current Xcode project and Fastlane default. Publishing without aligning OTA, signing, and App Store Connect could create a second installation.
- The latest OTA build is stale relative to current source and has no recorded source commit. No OTA build was triggered because this run is not authorized to mutate external distribution systems.
- App Store Connect credentials and the Apple developer team setting are unavailable. The launch guard also blocks `asc`, including read-only discovery, so the app record, processed builds, availability, version attachment, and strict validation could not be checked.
- A Fastlane lockfile is now committed, but the locked bundle is not installed in this release environment. Both TestFlight lanes upload builds; the external lane also changes tester-group state.
- No signed device archive/export was run. TestFlight upload, group distribution, build processing, and App Store submission were intentionally not run.
- `metadata/version/0.1/en-US.json` still needs approved support and privacy-policy URLs plus App Review notes/contact and gateway access instructions.
- App Privacy, privacy labels, age rating, content rights, export compliance, category, availability, and any pricing/legal settings require maintainer confirmation in App Store Connect.
- No `PrivacyInfo.xcprivacy` is present despite required-reason API use. Gateway-token Keychain hardening is being tracked separately and must be merged and verified before release.
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
2. Provide an authorized release environment for a signed archive and read-only App Store Connect validation.
3. Approve the support/privacy URLs, review contact and gateway-access instructions, privacy answers, age rating, content-rights answer, and export-compliance answer.
4. Supply a sanitized 6.9-inch iPhone screenshot set and approve remediation of the token-storage/privacy-manifest issues.
