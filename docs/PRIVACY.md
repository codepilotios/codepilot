# Privacy

CodePilot is designed around a Mac you control. In the current beta there is no hosted CodePilot account service.

## Data On The Mac

The Mac app and gateway use local Codex and CodePilot state, including auth files, saved account profiles, usage metadata, uploaded files, and gateway configuration. Treat the Mac as trusted infrastructure.

Sensitive local files include:

- `~/.codex/auth.json`
- `~/.codex-account-switcher/accounts/*/auth.json`
- `~/.codex-account-switcher/phone-gateway-token`
- `~/.codex-account-switcher/phone-gateway.env`
- `~/.codex-account-switcher/phone-uploads/`

Do not commit these files or include their contents in screenshots, logs, issues, or support requests.

## iPhone App

The iPhone app stores the gateway URL and token locally on the device so it can reconnect to your Mac gateway. The app talks to the gateway you configure; it does not need a hosted CodePilot account for the current beta.

## Gateway And Remote Access

The gateway exposes local Codex-related actions to trusted clients. It must require the gateway token. If you use Cloudflare Tunnel, Cloudflare becomes part of your network path and its own terms and privacy practices apply.

Do not publish gateway URLs, bearer tokens, private hostnames, or screenshots showing connection details.

## Diagnostics And Support

Before sharing logs or screenshots, remove:

- Account names and email addresses.
- Gateway URLs and hostnames.
- Bearer tokens and auth file contents.
- Local file paths and uploaded file names.
- Apple team identifiers or signing details.

This privacy copy is intended for the beta docs and should be reviewed before any App Store, paid, or broader public release.
