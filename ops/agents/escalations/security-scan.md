# CodePilot Security Scan Escalation

Maintainer decision status: approved by maintainer on 2026-07-06.

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
