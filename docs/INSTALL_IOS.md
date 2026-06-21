# iOS Installation

CodePilot iOS connects to a Mac running the CodePilot gateway.

## Requirements

- A Mac running the CodePilot gateway.
- A reachable gateway URL.
- The gateway bearer token from the Mac.
- Optional: Cloudflare Tunnel for remote access outside the local network.

## Connection

On first launch, enter:

- **Gateway URL**: local or Cloudflare URL for your CodePilot gateway.
- **Token**: contents of `~/.codex-account-switcher/phone-gateway-token` on the Mac.

The app stores these values locally on the device.

## App Store Connect Setup

The local Fastlane credentials live in the ignored file:

```sh
ios/CodexPhone/fastlane/.env
```

To create an Apple web session for App Store record creation, run from the repo root:

```sh
scripts/apple-spaceauth.sh
```

Paste the generated `FASTLANE_SESSION` into `ios/CodexPhone/fastlane/.env`, then run:

```sh
scripts/create-app-store-record.sh
```

The App Store Connect API key can manage signing resources, but Apple still requires an Apple ID web session for creating a new App Store app record.

## Notifications

The iOS app can register for turn-finished notifications. APNs certificates or keys must be configured in the gateway environment before background notifications can be delivered reliably.

## File Uploads

Files selected in the iOS app are uploaded to the Mac gateway and saved under the CodePilot state directory. Image attachments can be passed into Codex turns when supported by the current runner.
