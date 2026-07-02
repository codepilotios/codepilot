# CodePilot

CodePilot is a Mac menu bar app and iPhone companion for running coding-agent sessions from a Mac you control. It currently focuses on Codex account switching, usage visibility, remote iPhone access, file uploads, connector status, notifications, and gateway-backed conversation control.

The project is designed to become provider-neutral over time, including future Claude Code compatibility.

## License

CodePilot is source-available under the PolyForm Noncommercial License 1.0.0. It is **not open source** under the OSI definition because commercial use is restricted.

Commercial use requires a separate written license. See [LICENSE.md](LICENSE.md), [COMMERCIAL-LICENSE.md](COMMERCIAL-LICENSE.md), and [NOTICE.md](NOTICE.md).

## Components

- **CodePilot Mac**: a macOS menu bar app that tracks usage, manages account profiles, and coordinates automatic account switching.
- **CodePilot Gateway**: a local Python gateway that exposes threads, jobs, files, usage, notifications, and account controls to trusted clients.
- **CodePilot iOS**: an iPhone app that connects to the gateway for remote chat, file uploads, usage status, steering, stopping turns, and notifications.
- **Cloudflare Tunnel support**: optional remote access to the gateway through a user-owned Cloudflare Tunnel.

## Current Provider Support

CodePilot currently supports Codex by working with the local Codex home on the Mac:

- `~/.codex/auth.json`
- `~/.codex/state_5.sqlite`
- `~/.codex-account-switcher/accounts/`
- `~/.codex-account-switcher/usage.json`

The public product name is provider-neutral, but the first implementation remains Codex-specific internally.

## Quick Start

1. Install Codex on the Mac that will run CodePilot.
2. Build the Mac app:

   ```sh
   scripts/build-app.sh
   open "build/CodePilot.app"
   ```

3. Use the menu bar app to add account profiles.
4. Install and start the gateway from the app setup screen or the helper script:

   ```sh
   scripts/install-phone-gateway-agent.sh
   ```

5. Optional: configure Cloudflare Tunnel for remote iPhone access.
6. Install the iOS app and enter the gateway URL plus bearer token.

See:

- [Mac Installation](docs/INSTALL_MAC.md)
- [iOS Installation](docs/INSTALL_IOS.md)
- [Cloudflare Setup](docs/CLOUDFLARE_SETUP.md)
- [Security](docs/SECURITY.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)
- [Release Checklist](docs/RELEASE_CHECKLIST.md)

## Features

- Manual account profile capture and switching.
- Automatic switching only after active turns are finished.
- 5-hour and weekly usage status across accounts.
- Global iOS credit progress indicator.
- iOS remote chat and file upload.
- Conversation steering and stop-turn controls where supported.
- Thread pinning, renaming, deletion, and project grouping.
- Connector/plugin status visibility.
- Turn-finished notifications.
- Gateway-backed auth refresh flows.

## Screenshots

Screenshots will be added before the first public release.

## Public Release Status

CodePilot is being prepared for broader publishing. Expect some internal names, bundle identifiers, LaunchAgent labels, and local state paths to still contain legacy Codex-specific names during the first migration phase.
