# CodePilot Security Maintenance Notice

Maintainer intervention is needed before public launch for one remaining product-boundary decision.

## Localhost Proxy Capability URLs

- Surface: `POST /api/local-web/sessions` requires the gateway bearer token, but the returned `/api/local-web/<session>/...` URL is fetched without bearer authentication.
- Current behavior: a random, 24-byte URL-safe session id gates access for up to one hour and proxies only the selected loopback port.
- Risk: anyone who obtains a live session URL can proxy GET requests to that loopback port through the public gateway until expiry.
- Decision needed: decide whether this bearerless capability URL is acceptable for WebView compatibility, should use a shorter lifetime, or should move to an authenticated browser/proxy design.

Local hardening already applied on this branch:

- Gateway file previews now require a thread id and only serve files inside that thread workspace.
- Remote desktop frame capture and input injection are bound to an active trusted-device lease.
- Privacy audit passes with no tracked private identifiers or secret-looking material.
