# CodePilot Security Scan Escalation

Maintainer decision status: approved by maintainer on 2026-07-06.

## 2026-07-17 Remote-Desktop Release Blocker

- The running remote-desktop host does not enforce the trusted-device lease model on screen capture or WebRTC signaling. Its HTTP input path validates only sequence ordering, not lease ownership. Possession of the general gateway bearer token is therefore sufficient to reach screen capture and control paths when Mac permissions are granted.
- This branch makes all remote-control routes fail closed at the public gateway by default while preserving status reporting. Do not re-enable them until nonce issuance, trusted-device signature verification, active lease validation, Mac-lock invalidation, and per-lease signaling/frame authorization are enforced end to end and covered by integration tests.
- Re-enabling remote desktop requires maintainer coordination because the safe implementation changes the iOS session flow and must complete the authorized OTA verification process.

## 2026-07-17 Remaining High-Risk Work

- Deliver the iOS Keychain migration through the authorized OTA/TestFlight process, then rotate gateway tokens used by beta devices that may have backed up the old preference value. This unattended scan did not publish a build because its public-write policy prohibits non-GitHub external mutations.
- A scan of all 209 reachable commits found private-identifier matches in 128 historical commit trees and no recognized live-secret pattern. The current tree passes the privacy audit. Coordinate a history rewrite and clone migration before representing the repository history as sanitized; never paste historical values into an issue or pull request.
- Localhost proxy sessions remain bearerless capability URLs after creation. This branch removes wildcard CORS and adds no-referrer/nosniff response headers, but a leaked live capability URL can still reach the selected loopback port until its short expiry. Keep the capability private and consider a WebView-bound authentication design before broad launch.

## 2026-07-17 Hardening Completed Locally

- Restricted file previews to CodePilot uploads by default, with explicit opt-in download roots for advanced setups.
- Migrated the iOS gateway bearer token from preferences to a device-only Keychain item and removed the legacy preference after a successful migration.
- Forced gateway tokens, uploads, secret-bearing environment files, and generated LaunchAgent plists to owner-only permissions; gateway token symlinks and empty token files are rejected.
- Added remote-desktop tests to CI and made agent guard tests independent of inherited autonomy/model environment settings.
- Removed remaining private identity strings from the current tracked source and aligned the APNs topic with the public bundle identifier.
