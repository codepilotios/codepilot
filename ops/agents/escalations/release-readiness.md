# CodePilot Release Readiness Escalation

Date: 2026-07-18

Status: CodePilot is not ready for a new OTA, TestFlight, or App Store release. Local builds, gateway tests, and public CI are healthy, but release identity, signing/App Store Connect access, privacy work, screenshots, and review metadata remain blocked.

## Verified Locally

- `scripts/privacy-audit.sh`: passed its generic private-path, email, and secret-pattern checks. The optional project-specific private-identifier denylist was not available in this worktree, so this is not a complete private-name/host signoff.
- `swift test`: passed; 57 tests, 0 failures.
- The release-readiness draft PR and the open draft PRs referenced below remain mergeable, and their latest completed public CI checks passed. This worktree was also re-verified locally on July 18.
- Gateway unit tests: passed with Python 3.13; 112 tests, 0 failures. An alternate Xcode-provided Python 3.9 invocation cannot import `tomllib`, confirming that local gateway verification must use the documented Python 3.11-or-newer runtime.
- macOS Swift release build: passed.
- iOS clean Release simulator build: passed with code signing disabled.
- Unsigned generic-device iOS Release archive compile: passed with Xcode 26.5.
- iOS simulator tests: passed; 37 tests, 0 failures.
- The iOS build emits one non-blocking compiler warning for an unused `resetRateLimit` return value; release compilation still succeeds.
- Fastlane Ruby syntax, iOS `Info.plist`, entitlements, and version metadata JSON validation passed. With the supported Ruby 4.0.4 and Bundler 4.0.11 selected explicitly, `bundle check` and Fastlane lane discovery pass. The default unattended working-directory environment still selects system Ruby 2.6 and cannot start the lockfile-required Bundler, so the release entrypoint is not yet deterministic. No signed archive or upload lane was run.
- Public-write guard, agent-runner model-selection, and scheduler-lock tests: passed.
- A July 18 read-only check of the canonical local OTA status endpoint still points to a July 8 build with no recorded source commit. Its tokenized manifest and IPA both returned HTTP 200, but the manifest does not match the current bundle ID and the public CodePilot install page returned HTTP 403. No OTA build or external-state mutation was performed in this run.

## Release Blockers

- **Remote Desktop pairing is not enforced on the active capture/control paths (issue #25 remains open and labeled critical).** The frame, input, and WebRTC signaling routes accept arbitrary session identifiers after the shared gateway bearer token check; they do not require a trusted device or validate an active signed lease. The iOS control view also bypasses the available session-start API. This can let any gateway-token holder view or control the Mac without the documented per-device pairing boundary. Draft PR #26 records the cross-stack remediation and verification scope, but does not implement the fix. Block OTA, TestFlight, and App Store distribution until the native host, gateway routes, and iOS client enforce one lease end-to-end with regression tests for unpaired, expired, revoked, replayed, and mismatched sessions.
- **Canonical bundle identity requires a maintainer decision.** The latest distributed OTA build uses a legacy identifier that differs from the current Xcode project and Fastlane default. Publishing without aligning OTA, signing, and App Store Connect could create a second installation.
- The latest OTA build is stale relative to current source and has no recorded source commit. No OTA build was triggered because this run is not authorized to mutate external distribution systems.
- The public OTA install page currently returns HTTP 403. Restore unauthenticated install-page access and verify it from a real iPhone before treating OTA distribution as release-ready.
- App Store Connect inspection was unavailable in this run. The Apple developer team setting is empty, and the launch guard blocked even `asc auth status`; the app record, processed builds, availability, version attachment, and strict validation therefore could not be checked without maintainer-provided release access.
- The unattended Fastlane entrypoint does not select the supported Ruby/Bundler toolchain deterministically. Add a repository-owned release wrapper or equivalent environment setup before relying on a scheduled TestFlight build.
- The project-specific private-identifier denylist is unavailable in this release worktree. Restore the ignored local denylist before treating the public-content privacy audit as complete.
- Public Git history contains 11 legacy commits authored with a non-CodePilot identity. Review the redacted author metadata and decide whether it is intentionally public before treating repository-history privacy as complete.
- No signed device archive/export was run. TestFlight upload, group distribution, build processing, and App Store submission were intentionally not run.
- `metadata/version/0.1/en-US.json` still needs approved support and privacy-policy URLs plus App Review notes/contact and gateway access instructions.
- The App Store draft and canonical JSON currently disagree on subtitle and promotional/keyword copy; reconcile one approved canonical metadata set before staging.
- App Privacy, privacy labels, age rating, content rights, export compliance, category, availability, and any pricing/legal settings require maintainer confirmation in App Store Connect.
- No app-owned `PrivacyInfo.xcprivacy` is present despite required-reason API use. Draft PR #22 prepares gateway-token Keychain migration, file-access scoping, localhost-capability constraints, and additional gateway hardening; it remains open, mergeable, and green but must be reconciled and verified before release.
- The published privacy, support, and screenshot URLs currently return HTTP 404, and the corresponding pages are absent on this branch. Draft PR #17 prepares those pages; it remains open, mergeable, and green but must be reconciled before the links can be treated as release-ready.
- App Store-ready screenshots are absent. All future captures need synthetic accounts, hosts, paths, and tokens.
- All nine App icon files include alpha channels, including the marketing icon; flatten and validate them before archive upload.
- Fastlane now uses the prepared 0.1 What-to-Test notes by default, excludes Remote Desktop from its default beta description, and requires an approved privacy-policy URL for external distribution. The App Store JSON is still not connected to a staging/validation lane, and external TestFlight metadata still lacks an approved feedback email and review contact.
- The locally built Mac app is arm64-only; Intel/universal distribution has not been verified.

## Prepared Artifacts

- Draft TestFlight notes, including total-credit, Live Activity, and reset-credit coverage: `metadata/testflight/0.1/en-US.md`.
- Draft App Store metadata and benefit-focused release notes: `metadata/version/0.1/en-US.json`.
- Screenshot capture/redaction checklist, including sanitized total-credit and Live Activity captures: `metadata/screenshots/README.md`.

## Maintainer Actions

1. Confirm the canonical iOS bundle identifier and align Xcode, OTA, signing, and the App Store Connect record before another distributed build.
2. Approve and verify an end-to-end Remote Desktop trust boundary that requires a paired device and active signed lease for capture, signaling, and input.
3. Provide an authorized release environment for a signed archive and read-only App Store Connect validation.
4. Approve the support/privacy URLs, review contact and gateway-access instructions, privacy answers, age rating, content-rights answer, and export-compliance answer.
5. Supply a sanitized 6.9-inch iPhone screenshot set and approve remediation of the token-storage/privacy-manifest issues.
6. Review the redacted legacy Git author metadata and confirm whether it may remain in public history.
