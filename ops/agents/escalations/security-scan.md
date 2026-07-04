# CodePilot Security Scan Escalation

Maintainer intervention is needed before public launch for these product-boundary decisions:

1. Authenticated arbitrary file download remains enabled.
   - Surface: `gateway/codex_phone_gateway.py` exposes `/api/files/download?path=...`.
   - Current behavior: any client with the gateway bearer token can request any absolute file path readable by the gateway process.
   - Risk: a leaked or phished gateway token becomes direct local file disclosure, independent of Codex approval/sandbox controls.
   - Decision needed: define the allowed file scope for iPhone previews, such as uploaded files, explicit per-thread workspace roots, or short-lived file-preview grants.

2. Localhost proxy sessions are bearerless capability URLs.
   - Surface: `POST /api/local-web/sessions` requires the bearer token, but the returned `/api/local-web/<session>/...` URL is fetched without bearer auth.
   - Current behavior: the random session id gates access for the session lifetime.
   - Risk: anyone who obtains a live session URL can proxy GET requests to the selected loopback port through the public gateway until expiry.
   - Decision needed: decide whether this is acceptable for WebView compatibility, should have a shorter lifetime, or should move to an authenticated browser/proxy design.

Local hardening already applied in this branch:

- Removed public embedded private identifier patterns from the privacy audit and made local denylist patterns opt-in via `CODEPILOT_PRIVACY_PATTERNS_FILE`.
- Removed machine-specific default repository paths from local agent scripts.
- Changed gateway-created Codex app-server threads to use safe approval/sandbox settings unless dangerous mode is explicitly enabled.
