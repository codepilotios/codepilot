# Support

CodePilot beta support is handled through public repository issues and pull requests.

- [Report a beta bug](https://github.com/codepilotios/codepilot/issues/new?template=bug_report.md)
- [Request a beta improvement](https://github.com/codepilotios/codepilot/issues/new?template=feature_request.md)

## Before Opening An Issue

Check:

- [Mac installation](INSTALL_MAC.md)
- [iOS installation](INSTALL_IOS.md)
- [Cloudflare setup](CLOUDFLARE_SETUP.md)
- [Troubleshooting](TROUBLESHOOTING.md)
- [Beta feedback guide](BETA_FEEDBACK.md)
- [Security](SECURITY.md)
- [FAQ](FAQ.md)

## Helpful Issue Details

Use the repository bug report template when available.

Include:

- The affected area: Mac app, iPhone app, gateway, Cloudflare setup, account switching, usage status, connector/plugin status, file upload, notifications, docs, or the Remote Desktop availability guard.
- What you expected to happen.
- What happened instead.
- Whether setup, Cloudflare Tunnel, gateway connection, token entry, thread loading, file upload, notification delivery, turn control, or an unavailable feature appearing unexpectedly is the failing step.
- The visible recovery message, if one appears.
- Whether Codex CLI was already working on the Mac before CodePilot setup.
- macOS version, iOS version, CodePilot build or commit, and Codex CLI version when available.
- Sanitized logs with private values removed.

## Do Not Share

Do not include:

- Codex auth files.
- Gateway bearer tokens.
- Private hostnames or Cloudflare tunnel URLs.
- Personal account names or email addresses.
- Apple account, team, signing, or TestFlight identifiers.
- Screenshots that show private files, paths, accounts, tokens, or hosts.
- Desktop captures from the unavailable Remote Desktop feature.

Remote Desktop is outside the supported public beta. Report only if it appears or can be enabled; do not test its routes.

## Security Reports

For issues involving exposed credentials, unsafe gateway access, remote desktop bypass, or uploaded private files, avoid public details. Review [Security](SECURITY.md) first, then open only a minimal issue that says a security report is available if maintainer coordination is needed.
