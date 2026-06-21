# Mac Installation

CodePilot Mac is a menu bar app. It currently builds from source with SwiftPM.

## Requirements

- macOS 13 or later.
- Xcode command line tools.
- Codex installed and available as `codex`.
- A local Codex login at `~/.codex/auth.json`.

## Build

```sh
scripts/build-app.sh
open "build/CodePilot.app"
```

## Start At Login

The existing helper installs a LaunchAgent for the menu bar app:

```sh
scripts/install-switcher-agent.sh
```

## Add Accounts

Use the CodePilot menu bar app:

1. Choose **Log In New Account...**.
2. Complete the Codex login flow.
3. Choose **Save Logged-In Account...**.
4. Give the profile a clear name.

Profiles are stored under:

```text
~/.codex-account-switcher/accounts/<profile>/auth.json
```

## Gateway

For iPhone access, install the local gateway:

```sh
scripts/install-phone-gateway-agent.sh
```

The gateway listens on:

```text
http://127.0.0.1:18790
```

The bearer token is stored at:

```text
~/.codex-account-switcher/phone-gateway-token
```

