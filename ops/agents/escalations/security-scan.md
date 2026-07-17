# CodePilot Security Scan Escalation

Maintainer decision status: approved by maintainer on 2026-07-06.

## 2026-07-17 Remote-Desktop Release Blocker

- The running remote-desktop host does not enforce the trusted-device lease model on screen capture or WebRTC signaling. Its HTTP input path validates only sequence ordering, not lease ownership. Possession of the general gateway bearer token is therefore sufficient to reach screen capture and control paths when Mac permissions are granted.
- This branch makes all remote-control routes fail closed at the public gateway by default while preserving status reporting. Do not re-enable them until nonce issuance, trusted-device signature verification, active lease validation, Mac-lock invalidation, and per-lease signaling/frame authorization are enforced end to end and covered by integration tests.
- Re-enabling remote desktop requires maintainer coordination because the safe implementation changes the iOS session flow and must complete the authorized OTA verification process.

## 2026-07-17 Remaining High-Risk Work

- Treat the gateway bearer token as a host-control credential. This branch removes the accidental approval-free, full-filesystem turn override and blocks accidental non-loopback binds, but an authenticated caller can still ask the coding agent to read host data available to its process, including configured connector credentials. Before public launch, add an independent tunnel identity policy, per-device/scoped credentials with revocation, a least-privilege execution boundary, and request/rate limits. Rotate beta gateway tokens after that migration.
- Deliver the iOS Keychain migration through the authorized OTA/TestFlight process, then rotate gateway tokens used by beta devices that may have backed up the old preference value. This unattended scan did not publish a build because its public-write policy prohibits non-GitHub external mutations.
- A scan of all 251 reachable commits found private-identifier matches in 241 historical commit trees and no recognized live-secret pattern. Commit metadata also includes four distinct identities, with non-public identity or email metadata on a small subset of commits. The current tree passes the privacy audit. Coordinate a history-and-metadata rewrite plus clone migration before representing the repository history as sanitized; never paste historical values into an issue or pull request.
- Localhost proxy sessions remain bearerless capability URLs after creation. This branch removes wildcard CORS and adds no-referrer/nosniff response headers, but a leaked live capability URL can still reach the selected loopback port until its short expiry. Keep the capability private and consider a WebView-bound authentication design before broad launch.
- Uploaded attachments and temporary previews need an explicit retention/cleanup policy; current restrictive permissions prevent other local users from reading them, but sensitive content can persist indefinitely.

## 2026-07-17 Hardening Completed Locally

- Restored approval-required, workspace-scoped policy for ordinary app-server turns; full access now requires the gateway's explicit dangerous-mode opt-in.
- Refused direct non-loopback gateway binds unless the operator explicitly opts in for a trusted proxy deployment.
- Removed the production iOS launch argument that accepted a gateway token through observable process arguments.
- Made desktop-sync archives owner-only and rejected archive links and special entries during import.
- Sanitized current tracked documentation and test fixtures, and extended the privacy audit with quiet regression-tested checks for private identifiers, non-placeholder OTA hosts, and private bundle namespaces.
- Restricted file previews to CodePilot uploads by default, with explicit opt-in download roots for advanced setups.
- Migrated the iOS gateway bearer token from preferences to a device-only Keychain item and removed the legacy preference after a successful migration.
- Forced gateway tokens, uploads, secret-bearing environment files, and generated LaunchAgent plists to owner-only permissions; gateway token symlinks and empty token files are rejected.
- Made cached assistant thread messages and their cache directory owner-only, using exclusive temporary files and atomic replacement instead of a predictable default-permission temporary path.
- Added remote-desktop tests to CI and made agent guard tests independent of inherited autonomy/model environment settings.
- Removed remaining private identity strings from the current tracked source and aligned the APNs topic with the public bundle identifier.
- Made fallback Codex output files owner-only and removed them immediately after ingestion instead of leaving private turn output in the shared temporary directory.
- Redacted query strings and localhost capability identifiers from gateway access logs, and escaped control characters to prevent forged log lines.
- Removed APNs authorization JWTs and device push tokens from `curl` process arguments; private request data now travels through curl's standard-input configuration.
- Removed the gateway bearer token from the installer idle check's `curl` process arguments and added a CI regression guard.
- Centralized iOS gateway-origin validation, required HTTPS except for loopback development, rejected ambiguous credential/query/fragment URLs, and prevented credential-bearing requests from following cross-origin redirects.
