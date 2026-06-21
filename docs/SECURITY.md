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

## Account Switching

CodePilot swaps local provider auth files. It waits for active turns to finish before automatic switching, but users should still avoid manually editing auth files while turns are running.

## Reporting Issues

Do not include auth files, bearer tokens, logs containing tokens, or uploaded private files in issue reports.

