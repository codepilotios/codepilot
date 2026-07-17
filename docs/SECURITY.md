# Security

CodePilot handles local coding-agent credentials. Treat the Mac running CodePilot as a trusted machine.

## Sensitive Files

- `~/.codex/auth.json`
- `~/.codex-account-switcher/accounts/*/auth.json`
- `~/.codex-account-switcher/phone-gateway-token`
- `~/.codex-account-switcher/phone-gateway.env`
- `~/.codex-account-switcher/phone-uploads/`

Do not commit these files.

## Gateway Exposure

The gateway should only be exposed through a trusted network path and must require the bearer token.

Recommended:

- Use HTTPS when remote.
- Use a long random bearer token.
- Rotate the token if a device is lost.
- Restrict Cloudflare access where practical.

The iOS client refuses non-HTTPS gateway URLs except for explicit loopback development addresses. It also rejects gateway URLs containing user information, query strings, or fragments, and credential-bearing requests do not follow cross-origin redirects.

The gateway health response is intentionally public-safe, but it is still operational metadata. Treat the gateway URL and token as private.

Localhost web sessions use short-lived capability URLs so WebView subresources can load without exposing the gateway bearer token to page content. Do not share those URLs. Sessions are restricted to the selected loopback origin, expire after ten minutes, and have bounded request counts.

Remote file previews are restricted to files uploaded through CodePilot by default. Advanced local setups can add explicit roots with the `CODEPILOT_FILE_DOWNLOAD_ROOTS` environment variable, using the platform path separator between roots. Never add a credential, SSH, cloud configuration, or account-auth directory.

## Account Switching

CodePilot swaps local provider auth files. It waits for active turns to finish before automatic switching, but users should still avoid manually editing auth files while turns are running.

## Loopback Web Links

CodePilot can proxy `http` and `https` links for `localhost`, `127.0.0.1`, and `::1` through an authenticated, short-lived gateway session. Non-loopback targets are rejected. Treat local page contents, URL paths, and query strings as private because they pass through the gateway and Cloudflare Tunnel to the iPhone.

Do not open local admin panels or dashboards containing credentials through this workflow. Do not share local-web session URLs, page contents, or screenshots in public issues.

## Remote Desktop

Remote Desktop is not part of the supported public beta while device-pairing and session-authorization enforcement is being completed and independently verified. Do not enable it in beta builds or expose its routes through a tunnel.

## Reporting Issues

Do not include auth files, bearer tokens, logs containing tokens, or uploaded private files in issue reports.

Before sharing logs, search for account names, email addresses, hostnames, tokens, Apple team identifiers, and local file paths.

CodePilot does not currently publish a private security-reporting channel. Do not put credentials, exploit details, private files, or other sensitive evidence in a public issue. If coordination is necessary, open only a minimal public issue requesting a private reporting path and include no sensitive details.
