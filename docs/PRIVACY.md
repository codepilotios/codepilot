# Privacy

CodePilot is a public beta for people who already run Codex CLI on a Mac they control. The current beta does not require a hosted CodePilot account service.

This page describes the repository beta behavior. App Store privacy labels and any hosted service policy still require maintainer approval before submission.

## Local Data

CodePilot works with local coding-agent state on your Mac, including Codex login state, saved account profiles, usage data, gateway settings, uploaded files, thread metadata, and notification state.

Sensitive local files include:

- `~/.codex/auth.json`
- `~/.codex/state_5.sqlite`
- `~/.codex-account-switcher/accounts/`
- `~/.codex-account-switcher/phone-gateway-token`
- `~/.codex-account-switcher/phone-gateway.env`
- `~/.codex-account-switcher/phone-uploads/`

Do not commit these files, include them in public issues, or show them in screenshots.

## Mac Gateway

The CodePilot gateway runs on your Mac and requires a bearer token. It exposes CodePilot features to trusted clients, including account status, usage status, thread access, file upload, notification registration, turn controls where supported, and remote desktop features after pairing and macOS permission checks.

The gateway token, gateway URL, hostnames, thread names, uploaded files, prompts, and local paths should be treated as private.

## iPhone App

The iPhone app stores the gateway URL and token locally on the device so it can connect to your Mac gateway. Files selected in the iPhone app are uploaded to the Mac gateway and saved under the CodePilot state directory.

If notifications are enabled, the app and gateway use Apple Push Notification service infrastructure for turn-finished notification delivery. Notification payloads should remain minimal and must not include auth files, bearer tokens, private prompts, or uploaded file contents.

## Cloudflare Tunnel

During the public beta, remote iPhone access uses a user-owned Cloudflare Tunnel. Cloudflare may process connection metadata for tunnel operation according to your Cloudflare account configuration and Cloudflare's own terms and policies.

CodePilot still requires the gateway bearer token when using Cloudflare Tunnel. Treat temporary TryCloudflare URLs, permanent tunnel hostnames, and the gateway token as private support data.

## Remote Desktop

Remote desktop features require pairing and macOS Screen Recording and Accessibility permissions. Do not share screenshots or recordings that show private desktops, files, prompts, credentials, account names, hostnames, or local paths.

## Support And Issues

Before opening public issues, remove:

- Auth files and bearer tokens.
- Private hostnames, tunnel URLs, and local network details.
- Personal names, email addresses, account names, Apple identifiers, and team identifiers.
- Local file paths, private repository names, private prompts, uploaded files, and unsanitized screenshots.
- Logs containing any of the above.

For security issues involving exposed credentials, unsafe gateway access, remote desktop bypass, or uploaded private files, avoid posting sensitive details publicly. Open a minimal issue saying a security report is available and coordinate disclosure with the maintainers.
