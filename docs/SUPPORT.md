# Support

CodePilot beta support is handled through public repository issues and pull requests.

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

- Mac app, gateway, or iOS app area affected.
- What you expected to happen.
- What happened instead.
- Whether setup, Cloudflare Tunnel, gateway connection, token entry, thread loading, file upload, notification delivery, turn control, or remote desktop is the failing step.
- The visible recovery message, if one appears.
- Whether Codex CLI was already working on the Mac before CodePilot setup.
- Sanitized logs with private values removed.

## Do Not Share

Do not include:

- Codex auth files.
- Gateway bearer tokens.
- Private hostnames or Cloudflare tunnel URLs.
- Personal account names or email addresses.
- Apple account, team, signing, or TestFlight identifiers.
- Screenshots that show private files, paths, accounts, tokens, or hosts.

## Security Reports

For issues involving exposed credentials, unsafe gateway access, remote desktop bypass, or uploaded private files, avoid public details. Review [Security](SECURITY.md) first, then open only a minimal issue that says a security report is available if maintainer coordination is needed.
