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

The gateway health response is intentionally public-safe, but it is still operational metadata. Treat the gateway URL and token as private.

## Account Switching

CodePilot swaps local provider auth files. It waits for active turns to finish before automatic switching, but users should still avoid manually editing auth files while turns are running.

## Reporting Issues

Do not include auth files, bearer tokens, logs containing tokens, or uploaded private files in issue reports.

Before sharing logs, search for account names, email addresses, hostnames, tokens, Apple team identifiers, and local file paths.
