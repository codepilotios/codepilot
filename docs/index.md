# CodePilot Public Beta

CodePilot is a Mac menu bar app, local gateway, and iPhone companion for Codex CLI users who want to monitor and steer coding-agent sessions from a Mac they control.

The beta is focused on practical workflows for AI coding users:

- See active Codex usage and account status from the Mac and iPhone.
- Switch saved Codex account profiles after active turns finish.
- Connect the iPhone app to the Mac gateway through a user-owned Cloudflare Tunnel during the public beta.
- Upload files, inspect threads, steer or stop turns where supported, and receive turn-finished notifications.
- Use remote desktop features only after pairing and macOS permission checks.

CodePilot is source-available for noncommercial use. It is not OSI open source. See the repository license files before redistributing or using it commercially.

## Start Here

- [Mac installation](INSTALL_MAC.md)
- [iOS installation](INSTALL_IOS.md)
- [Cloudflare remote access](CLOUDFLARE_SETUP.md)
- [Troubleshooting](TROUBLESHOOTING.md)
- [FAQ](FAQ.md)
- [Privacy](PRIVACY.md)
- [Support](SUPPORT.md)
- [Changelog](CHANGELOG.md)
- [App Store metadata draft](APP_STORE_METADATA_DRAFT.md)
- [Screenshot plan](SCREENSHOTS.md)

## Beta Limits

CodePilot currently targets Codex CLI. Future provider support is not part of the first beta promise.

The public-beta iPhone setup uses Cloudflare Tunnel. Same-network iPhone access is not part of the supported beta path until CodePilot ships explicit LAN-binding, firewall, and trust guidance.

Do not share screenshots, logs, gateway URLs, tokens, account names, hostnames, or local file paths in public issues unless they have been sanitized.
