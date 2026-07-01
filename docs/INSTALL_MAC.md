# Mac Installation

CodePilot Mac is a menu bar app. It currently builds from source with SwiftPM.

## Requirements

- macOS 13 or later.
- Git.
- Xcode command line tools.
- Codex installed and available as `codex`.
- A local Codex login at `~/.codex/auth.json`.

Successful setup means the menu bar app shows `CodePilot`, at least one account profile exists, and the setup window marks the gateway token and gateway as ready.

## Get The Source

```sh
git clone https://github.com/codepilotios/codepilot.git
cd codepilot
```

## Build

```sh
scripts/build-app.sh
open "build/CodePilot.app"
```

## Update A Source Build

Finish active turns, then update the checkout and rebuild:

```sh
git pull --ff-only
scripts/build-app.sh
scripts/install-switcher-agent.sh
scripts/install-phone-gateway-agent.sh
```

The gateway installer defers its restart if it detects an active phone turn. If that happens, let the turn finish and run the gateway installer again. Do not force a restart just to apply a routine update.

If the update changes setup requirements, review the latest [changelog](CHANGELOG.md) and rerun the relevant setup step before reconnecting the iPhone app.

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

That local address is for CodePilot on the Mac and for Cloudflare Tunnel. A physical iPhone cannot reach `127.0.0.1` on the Mac directly; use Cloudflare remote access for the default setup, or deliberately start the gateway on a LAN address before using the iOS **Same Network** option.

The bearer token is stored at:

```text
~/.codex-account-switcher/phone-gateway-token
```

Copy this token into the iOS app connection screen. Do not share it in issue reports or screenshots.

## Remote iPhone Access

For access away from the local network, open **Setup CodePilot...** in the Mac menu bar app and use **Cloudflare Remote Access**. The setup wizard can install `cloudflared`, sign in to Cloudflare, configure a permanent hostname, or start a temporary TryCloudflare URL for testing.

## Remote Desktop Permissions

Open **Remote Desktop...** from the Mac menu bar app to check Screen Recording and Accessibility. Screen Recording is required to view the Mac, and Accessibility is required for pointer and keyboard control. Restart CodePilot after granting either macOS privacy permission.
