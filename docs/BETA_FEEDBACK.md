# Beta Feedback Guide

CodePilot public beta feedback is most useful when it helps reproduce a real Codex CLI workflow without exposing private data.

## Best Reports

Include:

- The area affected: Mac app, iPhone app, gateway, Cloudflare setup, account switching, usage status, connector/plugin status, file upload, notifications, docs, or the Remote Desktop availability guard.
- What you were trying to do.
- What happened instead.
- The visible recovery message or status text.
- Whether the failing step was setup, Cloudflare Tunnel, gateway connection, token entry, thread loading, usage or connector status, upload, notification delivery, turn control, or an unavailable feature appearing unexpectedly.
- macOS version, iOS version, CodePilot build or commit, and Codex CLI version when available.
- Sanitized logs or screenshots only when they make the issue clearer.

## Useful Workflow Notes

For AI coding users and existing Codex CLI users, please call out:

- Whether Codex CLI itself was already working on the Mac before CodePilot setup.
- Whether active turns were running when account switching, gateway restart, steering, or stop-turn actions were attempted.
- Whether the issue happened on the Mac, through the iPhone app, or only through Cloudflare Tunnel.
- Whether refreshing Codex login, restarting the gateway when idle, or retesting the connection changed the result.

## Do Not Share

Remove these before opening an issue or attaching screenshots:

- Codex auth files, gateway bearer tokens, and Cloudflare tunnel URLs.
- Private hostnames, account names, personal names, email addresses, Apple identifiers, and team identifiers.
- Local file paths, private repository names, uploaded files, private prompts, thread names, and live desktop contents.
- Logs containing any of the above.

For security-sensitive reports, follow [Security](SECURITY.md) and avoid posting exploit details or secrets publicly.

Remote Desktop is outside the supported public beta. Report only if it appears or can be enabled; do not test its routes or share desktop captures.
