# CodePilot Public Beta

CodePilot is a Mac menu bar app, local gateway, and iPhone companion for AI coding users who already run Codex CLI on a Mac they control.

The public beta focuses on Codex account switching, usage visibility, remote iPhone access through a user-owned Cloudflare Tunnel, file uploads, connector status, optional notifications, and gateway-backed conversation control. The current beta is Codex-focused; support for other coding agents is not part of the beta promise.

## License

CodePilot is source-available under the PolyForm Noncommercial License 1.0.0. It is **not open source** under the OSI definition because commercial use is restricted.

Commercial use requires a separate written license. See [LICENSE.md](LICENSE.md), [COMMERCIAL-LICENSE.md](COMMERCIAL-LICENSE.md), and [NOTICE.md](NOTICE.md).

## Components

- **CodePilot Mac**: a macOS menu bar app that tracks usage, manages account profiles, and coordinates automatic account switching.
- **CodePilot Gateway**: a local Python gateway that exposes threads, jobs, files, usage, notifications, and account controls to trusted clients.
- **CodePilot iOS**: an iPhone app that connects to the gateway for remote chat, file uploads, usage status, steering, stopping turns, and notifications.
- **Cloudflare Tunnel support**: public-beta iPhone access to the gateway through a user-owned Cloudflare Tunnel.

## Current Provider Support

CodePilot currently supports Codex by working with the local Codex home on the Mac:

- `~/.codex/auth.json`
- `~/.codex/state_5.sqlite`
- `~/.codex-account-switcher/accounts/`
- `~/.codex-account-switcher/usage.json`

The public product name is provider-neutral, but the first implementation remains Codex-specific internally.

## Quick Start

1. [Install Codex CLI](https://developers.openai.com/codex/cli/) on the Mac that will run CodePilot, then run `codex` once to sign in.
2. Build the Mac app:

   ```sh
   scripts/build-app.sh
   open "build/CodePilot.app"
   ```

4. Use the menu bar app to add account profiles.
5. Install and start the gateway from the app setup screen or the helper script:

   ```sh
   scripts/install-phone-gateway-agent.sh
   ```

5. Configure Cloudflare Tunnel for the standard iPhone setup. The advanced same-network path requires a deliberately configured and secured LAN listener.
6. After receiving an approved beta build, install the iOS app and enter the gateway URL plus iOS connection token from the Mac setup screen. A public install link is not available yet.

See:

- [Mac Installation](docs/INSTALL_MAC.md)
- [iOS Installation](docs/INSTALL_IOS.md)
- [Cloudflare Setup](docs/CLOUDFLARE_SETUP.md)
- [FAQ](docs/FAQ.md)
- [Beta Feedback Guide](docs/BETA_FEEDBACK.md)
- [Privacy, beta data flow, and deletion](docs/PRIVACY.md#beta-data-flow-at-a-glance)
- [Support](docs/SUPPORT.md)
- [Changelog](docs/CHANGELOG.md)
- [App Store Metadata Draft](docs/APP_STORE_METADATA_DRAFT.md)
- [Screenshot Plan](docs/SCREENSHOTS.md)
- [Public Presence Checklist](docs/PUBLIC_PRESENCE_CHECKLIST.md)
- [Security](docs/SECURITY.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)
- [Release Checklist](docs/RELEASE_CHECKLIST.md)

## Beta Feedback

- [Report a beta bug](https://github.com/codepilotios/codepilot/issues/new?template=bug_report.md)
- [Request a beta improvement](https://github.com/codepilotios/codepilot/issues/new?template=feature_request.md)

Remove gateway URLs, tokens, hostnames, localhost or local-web session URLs, local page contents, account names, local paths, private prompts, uploaded files, and unsanitized screenshots before submitting. For security-sensitive findings, read the [security reporting guidance](docs/SECURITY.md) first and do not post sensitive evidence publicly.

## Features

- Manual account profile capture and switching.
- Automatic switching only after active turns are finished.
- 5-hour and weekly usage status, reset timing, and available reset credits per account.
- Global iOS credit progress indicator.
- iOS remote chat and file upload.
- Conversation steering and stop-turn controls where supported.
- In-app opening of `localhost`, `127.0.0.1`, and `::1` web links through the authenticated Mac gateway.
- Thread pinning, renaming, deletion, and project grouping.
- Connector/plugin status visibility.
- Turn-finished notifications when APNs is configured for the gateway.
- Gateway-backed auth refresh flows.

## Screenshots

No public screenshots are committed yet. The beta screenshot checklist is tracked in [docs/SCREENSHOTS.md](docs/SCREENSHOTS.md) so public images use demo data and avoid tokens, hostnames, local paths, private prompts, account names, or live desktop content.

## Public Beta Status

CodePilot is being prepared for broader publishing through beta-first docs, sanitized screenshots, and maintainer-reviewed App Store metadata. Expect some internal names, bundle identifiers, LaunchAgent labels, and local state paths to still contain legacy Codex-specific names during the first migration phase.

Remote Desktop is not part of the supported public beta while its device-pairing and session-authorization enforcement is being completed and independently verified. Do not enable or promote it in beta builds yet.
