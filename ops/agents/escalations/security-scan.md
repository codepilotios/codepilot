# CodePilot Security Maintenance Notice

Maintainer intervention is needed before public launch for one product-boundary decision.

## Localhost Proxy Capability URLs

- Surface: `POST /api/local-web/sessions` requires the gateway bearer token, but returned `/api/local-web/<session>/...` URLs are fetched without bearer authentication.
- Current behavior: a random URL-safe session id gates access for up to one hour and proxies only the selected loopback port.
- Risk: anyone who obtains a live session URL can proxy GET requests to that selected loopback port through a public gateway until expiry.
- Decision needed: choose the intended auth model for proxied local-web subresources.

Validated scan outcome:

- No live secrets, private keys, private email addresses, or machine-specific absolute paths were found in tracked source/docs during the configured privacy audit.
- Gateway file previews require a thread id and only serve files inside that thread workspace.
- Remote desktop frame capture and input injection are bound to an active trusted-device lease.
- Privacy audit passes with no tracked private identifiers or secret-looking material.

Suggested paths:

- Require bearer auth for every local-web proxy request and update the iOS loading layer to attach the header for subresources.
- Or treat local-web session URLs as explicit bearer-equivalent capabilities, shorten their lifetime, and document that they must not be shared.
