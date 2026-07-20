# CodePilot Release Readiness Escalation

Date: 2026-07-19

Status: **Not ready for OTA, TestFlight, or App Store distribution.** Current public `main` builds and tests cleanly, but a critical Remote Desktop authorization issue, release-source divergence, distribution identity drift, incomplete OTA provenance, broken public install entry points, and unfinished App Store preparation remain blockers.

## Verified

- A fresh detached checkout of current public `main` passed 71 Swift tests, 148 gateway tests, 48 iOS simulator tests, unsigned simulator and generic-device Release builds, the macOS Release app build, the repository privacy audit, Cloudflare setup tests, and the agent guard tests.
- The latest public CI runs on `main` passed.
- Public `main` has two non-blocking iOS compiler warnings: an unused reset-credit result and an unused pairing response. App Intents metadata extraction is skipped because the app does not link App Intents.
- The isolated release-readiness branch passed 57 Swift tests, 112 gateway tests, 37 iOS simulator tests, unsigned simulator and generic-device Release builds, the macOS Release app build, Cloudflare setup tests, and the agent guard tests.
- The isolated branch is 36 commits behind and 65 commits ahead of public `main`; its passing results do not make it a valid release source.
- The repository privacy audit passed its generic private-path, email, and secret-pattern checks. The optional project-specific private-identifier denylist is unavailable, so privacy signoff is incomplete.
- Read-only OTA inspection found a completed July 19 version 0.1 artifact. Its tokenized manifest and IPA return HTTP 200, but it has no recorded source commit and its bundle identity does not match the current Xcode/Fastlane identity. Both public install entry points return HTTP 403.
- The 0.1 TestFlight notes are wired into Fastlane. The App Store JSON is valid and its name, subtitle, keywords, promotional text, description, and 770-character What's New copy fit their field limits.
- Public issue #25, the critical Remote Desktop authorization blocker, and issue #8, the sanitized screenshot task, remain open. Issue #30 is closed and its `asc` guard fix is on `main`.
- Fastlane syntax validation passed. The unattended default Ruby cannot start the lockfile-required Bundler, and no real `asc` executable is configured behind the read-only command guard, so App Store Connect inspection still cannot run deterministically.
- No App Store Connect API-key or Apple development-team environment variables are present. No secret values were inspected or printed.

## Release Blockers

1. **Critical Remote Desktop lease enforcement remains open in issue #25.** Block distribution until the native host, gateway, and iOS client reject unpaired, expired, revoked, replayed, and mismatched sessions end to end.
2. **The release-readiness branch is not based on current public `main`.** Recreate the working branch from `main` before using local artifacts or reports for release work.
3. **Canonical bundle identity is unresolved.** The latest OTA artifact and current Xcode/Fastlane configuration identify different apps, risking a second installation instead of an update.
4. **OTA provenance and public installation are incomplete.** The latest artifact records no source commit, does not match current source identity, and the public install pages return HTTP 403. No OTA build was triggered because this run cannot mutate external distribution state.
5. **Signed distribution is unverified.** No Apple-signed archive/export, provisioning check, TestFlight upload/processing, tester distribution, notarization, or App Store strict validation was run.
6. **The unattended App Store toolchain is not deterministic.** The default Ruby lacks the lockfile-required Bundler, no real read-only `asc` executable is configured behind the guard, and release credentials are absent.
7. **App Store metadata is incomplete and inconsistent.** The canonical JSON still contains placeholder support/privacy URLs and review notes, differs from the prose draft, and is not connected to a verified staging lane. Reviewer contact and gateway-access instructions are not approved.
8. **Screenshots are missing.** No App Store-ready 6.9-inch iPhone captures are present. Use synthetic accounts, balances, hosts, paths, prompts, and tokens; exclude Remote Desktop while issue #25 is open.
9. **Privacy and asset packaging remain incomplete.** No app-owned `PrivacyInfo.xcprivacy` is tracked, the App Store privacy-label inventory is not approved, and all nine app icons contain alpha channels, including the marketing icon.
10. **Public support/privacy delivery is not ready.** The repository's Pages API and both public install entry points return 404/403 rather than approved live support, privacy, and install pages.
11. **Maintainer-controlled App Store decisions remain open.** Privacy labels, age rating, content rights, export compliance, category, availability, review contact, and any pricing/legal settings require approval in App Store Connect.

## Prepared Local Artifacts

- TestFlight What to Test notes: `metadata/testflight/0.1/en-US.md`
- App Store copy and What's New draft: `metadata/version/0.1/en-US.json`
- Screenshot capture and redaction checklist: `metadata/screenshots/README.md`

## Maintainer Actions

1. Recreate the release-readiness branch from current `main`, confirm the canonical iOS bundle identifier, and align Xcode, Fastlane, OTA, signing, and the existing App Store Connect record.
2. Close issue #25 only after end-to-end paired-device lease enforcement and regression coverage are verified.
3. Provide an authorized deterministic release environment for a signed archive and read-only App Store Connect validation.
4. Approve live support/privacy URLs, reviewer contact and access instructions, privacy/compliance answers, category, availability, and final metadata copy.
5. Supply or approve sanitized 6.9-inch screenshots, flattened icons, and the app privacy manifest/data inventory.
