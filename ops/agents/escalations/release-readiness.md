# CodePilot Release Readiness Escalation

Date: 2026-07-17

Status: CodePilot is not ready for a new OTA, TestFlight, or App Store release. Local builds and tests are healthy, and the currently linked OTA assets are reachable, but release identity, signing/App Store Connect access, privacy work, screenshots, and review metadata remain blocked.

## Verified Locally

- `scripts/privacy-audit.sh`: passed after moving the optional private-identifier denylist to ignored local configuration.
- `swift test`: passed; 56 tests, 0 failures.
- Gateway unit tests: passed with Python 3.12; 102 tests, 0 failures. The default developer-tools Python is too old for the gateway's `tomllib` dependency.
- `scripts/build-app.sh`: passed and produced the local CodePilot Mac app bundle.
- iOS simulator Release build: passed with code signing disabled.
- iOS simulator tests: passed; 26 tests, 0 failures.
- Fastlane Ruby syntax and version metadata JSON validation: passed.
- The current install-linked OTA manifest and IPA are reachable, and the IPA content length matches the OTA status record.

## Release Blockers

- **Canonical bundle identity requires a maintainer decision.** The latest distributed OTA build uses a legacy identifier that differs from the current Xcode project and Fastlane default. Publishing without aligning OTA, signing, and App Store Connect could create a second installation.
- The latest OTA build is stale relative to current source and has no recorded source commit. No OTA build was triggered because this run is not authorized to mutate external distribution systems.
- App Store Connect credentials and the Apple developer team setting are unavailable. The launch guard also blocks `asc`, including read-only discovery, so the app record, processed builds, availability, version attachment, and strict validation could not be checked.
- Fastlane dependencies are incomplete and no lockfile is committed, so the release toolchain is not reproducibly ready. Both TestFlight lanes upload builds; the external lane also changes tester-group state.
- No signed device archive/export was run. TestFlight upload, group distribution, build processing, and App Store submission were intentionally not run.
- `metadata/version/0.1/en-US.json` still needs approved support and privacy-policy URLs plus App Review notes/contact and gateway access instructions.
- App Privacy, privacy labels, age rating, content rights, export compliance, category, availability, and any pricing/legal settings require maintainer confirmation in App Store Connect.
- No `PrivacyInfo.xcprivacy` is present despite required-reason API use. The gateway token is stored in app preferences rather than Keychain and should be fixed or explicitly risk-accepted.
- Same-network gateway support has no local-network usage description in the generated app configuration; confirm the device behavior and add approved purpose text if required.
- App Store-ready screenshots are absent. All future captures need synthetic accounts, hosts, paths, and tokens.
- App icon files include alpha channels, including the marketing icon; flatten and validate them before archive upload.
- Draft metadata is not connected to the Fastlane lanes, which otherwise use a generic changelog. There is no local App Store metadata staging/validation path.
- The locally built Mac app is arm64-only; Intel/universal distribution has not been verified.

## Prepared Artifacts

- Draft TestFlight notes: `metadata/testflight/0.1/en-US.md`.
- Draft App Store metadata and release notes: `metadata/version/0.1/en-US.json`.
- Screenshot capture/redaction checklist: `metadata/screenshots/README.md`.

## Maintainer Actions

1. Confirm the canonical iOS bundle identifier and align Xcode, OTA, signing, and the App Store Connect record before another distributed build.
2. Provide an authorized release environment for a signed archive and read-only App Store Connect validation.
3. Approve the support/privacy URLs, review contact and gateway-access instructions, privacy answers, age rating, content-rights answer, and export-compliance answer.
4. Supply sanitized App Store screenshots for the required iPhone display sizes and approve remediation of the token-storage/privacy-manifest issues.
