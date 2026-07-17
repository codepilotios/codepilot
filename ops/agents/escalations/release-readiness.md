# CodePilot Release Readiness Escalation

Date: 2026-07-17

Status: CodePilot is not ready for OTA/TestFlight/App Store release work without maintainer intervention. Local builds and tests are healthy, and the current install-linked OTA assets are reachable, but bundle identity, signing/App Store Connect validation, screenshots, and compliance metadata are still blocked.

## Fresh Checks

- `scripts/privacy-audit.sh`: passed.
- `swift test`: passed; XCTest reported 56 executed tests and 0 failures.
- Gateway unit tests: passed under Python 3.13; 102 tests ran with 0 failures. The system Python 3.9 is too old for the gateway's `tomllib` dependency.
- `ruby -c ios/CodexPhone/fastlane/Fastfile`: passed.
- `python3 -m json.tool metadata/version/0.1/en-US.json`: passed.
- `scripts/build-app.sh`: passed and produced the local CodePilot Mac app bundle.
- iOS simulator Debug tests: passed; XCTest reported 26 executed tests and 0 failures.
- iOS simulator Release build: passed. The only warning was benign AppIntents metadata extraction being skipped because the app does not use AppIntents.
- The install-linked OTA manifest and IPA both return HTTP 200 and the IPA length matches the recorded build size. Untokenized direct asset paths return HTTP 403, as expected for the access-protected OTA host.

## Release Blockers

- **Bundle identity decision required:** the latest published OTA build uses a different bundle identifier from the current Xcode project and Fastlane default. Publishing as-is would create a second app rather than update the installed OTA app. Confirm the canonical identifier before the next OTA, TestFlight, or App Store build.
- The latest published OTA build is from 2026-07-08, is stale relative to the current source, and does not identify a source commit. No OTA build was triggered because this readiness run is not authorized to mutate external distribution systems.
- A signed device archive/export was not run. The local Fastlane session is missing its App Store Connect API and developer-team environment, although local code-signing identities are installed.
- The repository's launch-autonomy guard blocks `asc`, including read-only discovery commands, so the App Store record, version, processed builds, availability, and strict `asc validate` results could not be checked.
- TestFlight upload, group distribution, and build processing were intentionally not run.
- App Store privacy labels, review details, support URL, privacy policy URL, content rights, encryption answers, age rating, availability, pricing, and submission state still need maintainer review or approval.
- App Store-ready screenshots are not present. `metadata/screenshots/README.md` lists the required screenshot set.
- The locally built Mac app is arm64-only; Intel/universal distribution has not been verified.

## Metadata Status

- Draft TestFlight notes exist at `metadata/testflight/0.1/en-US.md`.
- Draft App Store version metadata exists at `metadata/version/0.1/en-US.json`.
- The App Store subtitle was shortened to fit Apple's 30-character limit.
- Screenshot requirements exist at `metadata/screenshots/README.md`.

## Maintainer Actions

1. Choose the canonical iOS bundle identifier and align Xcode, Fastlane, OTA, signing, and the App Store Connect record before producing another build.
2. Provide or approve the support URL, privacy policy URL, App Review notes/contact path, privacy answers, age rating, content-rights answer, and export-compliance answer.
3. Supply sanitized App Store screenshots for the required iPhone display sizes.
4. In an authorized release session, run a signed archive/export, confirm the App Store Connect app/version/build state, and run strict validation without submitting.
