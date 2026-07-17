# CodePilot Public Beta

CodePilot is a Mac menu bar app, local gateway, and iPhone companion for Codex CLI users who want to monitor and steer coding-agent sessions from a Mac they control.

The current release track is a public beta for existing Codex CLI users. It is not intended for production teams or unattended access to an untrusted Mac.

The beta is focused on practical workflows for AI coding users:

- See active Codex usage and account status from the Mac and iPhone.
- Switch saved Codex account profiles after active turns finish.
- Connect the iPhone app to the Mac gateway through a user-owned Cloudflare Tunnel during the public beta.
- Upload files, inspect threads, steer or stop turns where supported, and receive turn-finished notifications.

CodePilot is source-available for noncommercial use. It is not OSI open source. See the repository license files before redistributing or using it commercially.

## Start Here

- [Mac installation](INSTALL_MAC.md)
- [iOS installation](INSTALL_IOS.md)
- [Cloudflare remote access](CLOUDFLARE_SETUP.md)
- [Troubleshooting](TROUBLESHOOTING.md)
- [FAQ](FAQ.md)
- [Beta feedback guide](BETA_FEEDBACK.md)
- [Privacy](PRIVACY.md)
- [Security](SECURITY.md)
- [Support](SUPPORT.md)
- [Changelog](CHANGELOG.md)

## Before You Install

- Use a Mac you control and keep the gateway bearer token private.
- Review the [privacy](PRIVACY.md) and [security](SECURITY.md) guidance before exposing the gateway through Cloudflare Tunnel.
- Expect beta limitations and recovery work. CodePilot does not replace Codex CLI or provide a hosted CodePilot account service.
- Sanitize logs and screenshots before opening a public issue.

## Beta Limits

CodePilot currently targets Codex CLI. Future provider support is not part of the first beta promise.

The public-beta iPhone setup uses Cloudflare Tunnel. Same-network iPhone access is not part of the supported beta path until CodePilot ships explicit LAN-binding, firewall, and trust guidance.

Remote Desktop is not part of the supported public beta while its device-pairing and session-authorization enforcement is being completed and independently verified. Do not enable it in beta builds yet.

Do not share screenshots, logs, gateway URLs, tokens, account names, hostnames, or local file paths in public issues unless they have been sanitized.

For beta reports, include the affected area, the failing step, visible recovery text, and whether Codex CLI was already working on the Mac. See the [beta feedback guide](BETA_FEEDBACK.md).

CodePilot is source-available for noncommercial use and is not OSI open source. Review the license files in the [public repository](https://github.com/codepilotios/codepilot) before redistribution or commercial use.
