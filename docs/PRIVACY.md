# Privacy

CodePilot is a public beta for people who already run Codex CLI on a Mac they control. The current beta does not require a hosted CodePilot account service.

This page describes the repository beta behavior. App Store privacy labels and any hosted service policy still require maintainer approval before submission.

CodePilot is not an offline coding tool. When you start or continue a Codex turn, the gateway passes your prompt and selected attachments to Codex on the Mac. Codex can send that content, conversation context, and related service metadata to OpenAI according to your Codex account, configuration, and the policies that apply to that service. CodePilot does not replace or change those provider terms, retention rules, or account controls.

## Beta Data Flow At A Glance

| When you use | What stays on the Mac | What can leave the Mac |
| --- | --- | --- |
| Account and usage status | Codex login state, saved account profiles, and cached usage data | Codex and OpenAI can process account and usage requests made by the local Codex setup. |
| A Codex turn | Gateway state, thread metadata, and local Codex state | Prompts, conversation context, selected attachments, and related service metadata can be sent to Codex and OpenAI. |
| The iPhone companion | Gateway settings, uploaded files, and the gateway's copy of notification state | Gateway requests and responses pass through the user-owned Cloudflare Tunnel. |
| File upload | The uploaded file is saved under the CodePilot state directory | The file passes through Cloudflare when uploaded from iPhone and can be sent to Codex and OpenAI when selected for a turn. |
| Notifications or Live Activities | The gateway stores registered device and activity tokens | Apple can process device tokens and the notification or Live Activity payload described below. |

CodePilot does not operate an account, analytics, or relay service for the current repository beta. This does not remove the data handling performed by Codex, OpenAI, Cloudflare, or Apple when you enable workflows that use those services.

## Local Data

CodePilot works with local coding-agent state on your Mac, including Codex login state, saved account profiles, usage data, gateway settings, uploaded files, thread metadata, and notification state.

Sensitive local files include:

- `~/.codex/auth.json`
- `~/.codex/state_5.sqlite`
- `~/.codex-account-switcher/accounts/`
- `~/.codex-account-switcher/phone-gateway-token`
- `~/.codex-account-switcher/phone-gateway.env`
- `~/.codex-account-switcher/phone-uploads/`
- `~/.codex-account-switcher/phone-notification-devices.json`
- `~/.codex-account-switcher/phone-live-activities.json`

Do not commit these files, include them in public issues, or show them in screenshots.

Uploaded files remain under the CodePilot state directory after a turn finishes. The current beta does not automatically remove them; delete uploads from the Mac when they are no longer needed.

## Mac Gateway

The CodePilot gateway runs on your Mac and requires a bearer token. It exposes CodePilot features to trusted clients, including account status, usage status, thread access, file upload, notification registration, and turn controls where supported.

The gateway token, gateway URL, hostnames, thread names, uploaded files, prompts, and local paths should be treated as private.

## iPhone App

The iPhone app stores the gateway URL and token locally on the device so it can connect to your Mac gateway. Files selected in the iPhone app are uploaded to the Mac gateway and saved under the CodePilot state directory.

If notifications are enabled, the app registers a device token with the Mac gateway and the gateway stores that token locally. Turn-finished payloads sent through Apple Push Notification service can include a thread title, a short failure summary, and internal thread and job identifiers. Live Activity updates can include aggregate account-usage status, counts, and refresh timing. These values may be visible on the device according to its notification settings, so use non-sensitive thread titles and disable CodePilot notifications or Live Activities in iOS settings if that disclosure is not acceptable.

Notification payloads do not intentionally include auth files, gateway bearer tokens, private prompt text, or uploaded file contents. A failure summary can still reproduce text from an underlying error, so treat notification previews as potentially sensitive during the beta.

## Cloudflare Tunnel

During the public beta, remote iPhone access uses a user-owned Cloudflare Tunnel. Gateway requests and responses pass through Cloudflare, including thread data, prompts, turn output, usage and account status, and uploaded file contents when those features are used. Cloudflare also processes connection metadata for tunnel operation according to your Cloudflare account configuration and Cloudflare's own terms and policies.

Use an HTTPS tunnel URL. CodePilot still requires the gateway bearer token when using Cloudflare Tunnel. Treat temporary TryCloudflare URLs, permanent tunnel hostnames, and the gateway token as private support data.

## External Services

The repository beta does not require a CodePilot-operated analytics or account service, but supported workflows can involve other services:

- Codex and OpenAI process coding prompts, conversation context, and selected attachments when you use coding-agent features.
- Cloudflare processes tunneled gateway traffic and connection metadata when you use the supported remote iPhone path.
- Apple Push Notification service processes device tokens and notification or Live Activity payloads when those features are enabled.

Review the settings and policies for each service you enable. Disabling notifications stops new CodePilot notification and Live Activity delivery, but it does not remove data already retained by Codex, OpenAI, Cloudflare, Apple, or the local Mac state.

## Remote Desktop

Remote Desktop is not part of the supported public beta while its device-pairing and session-authorization enforcement is being completed and independently verified. Do not enable it in beta builds yet.

Any future Remote Desktop beta must require explicit device pairing plus macOS Screen Recording and Accessibility permissions. Screenshots or recordings must never expose private desktops, files, prompts, credentials, account names, hostnames, or local paths.

## Support And Issues

Before opening public issues, remove:

- Auth files and bearer tokens.
- Private hostnames, tunnel URLs, and local network details.
- Personal names, email addresses, account names, Apple identifiers, and team identifiers.
- Local file paths, private repository names, private prompts, uploaded files, and unsanitized screenshots.
- Logs containing any of the above.

For security issues involving exposed credentials, unsafe gateway access, remote desktop bypass, or uploaded private files, avoid posting sensitive details publicly. Open a minimal issue saying a security report is available and coordinate disclosure with the maintainers.
