# Mac Installation

CodePilot Mac is a menu bar app. It currently builds from source with SwiftPM.

## Requirements

- macOS 13 or later.
- Xcode command line tools.
- Codex installed and available as `codex`.
- A local Codex login at `~/.codex/auth.json`.

Successful setup means the menu bar app shows `CodePilot`, at least one account profile exists, and the setup window marks the gateway token and gateway as ready.

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

The script restarts the gateway only when it can verify that no phone turn is running. Use the menu bar app's **Force Restart Gateway...** action only when recovering a stuck gateway.

The gateway listens on:

```text
http://127.0.0.1:18790
```

The bearer token is stored at:

```text
~/.codex-account-switcher/phone-gateway-token
```

Copy this token into the iOS app connection screen. Do not share it in issue reports or screenshots.
