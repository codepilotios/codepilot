# CodePilot Security Scan Escalation

Maintainer decision status: approved by maintainer on 2026-07-06.

## 2026-07-17 Repository-History Finding

- Reachable commits on the public mainline contain machine-specific absolute paths that were removed from the current tree.
- The current tracked tree passes the privacy audit, but the old values remain recoverable from Git history.
- Maintainer intervention is required to coordinate a history rewrite across affected public refs and collaborator clones. Do not paste the historical values into public issues or pull requests.
- No private email address or recognized live-token pattern was found in the mainline history scan.

## 2026-07-17 Pending Release Hardening

- The current mainline iOS app stores the gateway bearer token in preferences rather than a device-only Keychain item. A Keychain migration exists on the older security branch, but that draft now conflicts with main and requires an iOS OTA verification that this unattended run is not authorized to publish.
- The current mainline file-preview API still accepts arbitrary readable absolute paths from an authenticated client. The approved thread-workspace scoping change also exists on the older security branch, but it requires coordinated iOS request changes and the same maintainer-run OTA verification.
- Before public release, rebase or reimplement those two changes on current main, run the iOS test suite and authorized OTA process, and rotate the gateway token for any beta device that may have backed up the preference value.

Maintainer intervention was requested before public launch for these product-boundary decisions:

1. Authenticated arbitrary file download remains enabled.
   - Surface: `gateway/codex_phone_gateway.py` exposes `/api/files/download?path=...`.
   - Current behavior: any client with the gateway bearer token can request any absolute file path readable by the gateway process.
   - Risk: a leaked or phished gateway token becomes direct local file disclosure, independent of Codex approval/sandbox controls.
   - Decision: approved to proceed with the proposed hardening direction. Keep the feature, but narrow the allowed scope before public launch to uploaded files, explicit per-thread workspace roots, or short-lived file-preview grants.

2. Localhost proxy sessions are bearerless capability URLs.
   - Surface: `POST /api/local-web/sessions` requires the bearer token, but the returned `/api/local-web/<session>/...` URL is fetched without bearer auth.
   - Current behavior: the random session id gates access for the session lifetime.
   - Risk: anyone who obtains a live session URL can proxy GET requests to the selected loopback port through the public gateway until expiry.
   - Decision: approved to proceed with the proposed hardening direction. Keep WebView compatibility, but shorten and constrain capability sessions before public launch unless an authenticated browser/proxy design is ready.

Local hardening already applied in this branch:

- Removed public embedded private identifier patterns from the privacy audit and made local denylist patterns opt-in via `CODEPILOT_PRIVACY_PATTERNS_FILE`.
- Removed machine-specific default repository paths from local agent scripts.
- Changed gateway-created Codex app-server threads to use safe approval/sandbox settings unless dangerous mode is explicitly enabled.
- Bounded ordinary JSON request bodies and attachment-bearing request envelopes.
- Shortened localhost capabilities to ten minutes, capped active sessions and requests, and blocked redirects outside the selected loopback origin.
