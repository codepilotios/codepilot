# iOS Installation

CodePilot iOS connects to a Mac running the CodePilot gateway.

## Requirements

- A Mac running the CodePilot gateway.
- A reachable gateway URL.
- The gateway bearer token from the Mac.
- Optional: Cloudflare Tunnel for remote access outside the local network.

## Connection

On first launch:

1. Choose **Same Network** or **Cloudflare**.
2. Enter the gateway URL.
3. Enter the token from `~/.codex-account-switcher/phone-gateway-token` on the Mac.
4. Tap **Test Connection**.

Success means the app shows the active account from the Mac gateway.

The app stores these values locally on the device.

For the default Mac setup, choose **Cloudflare** and enter the Cloudflare Tunnel URL. The Mac gateway listens on `127.0.0.1:18790` by default, which is only reachable from the Mac itself. Use **Same Network** only after configuring the gateway to listen on a Mac LAN address.

The gateway URL must include `http://` or `https://`.

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

## Remote Desktop

Remote Desktop requires the Mac app to show Screen Recording as granted before viewing and Accessibility as granted before control. If pairing reports missing permissions, grant them in macOS System Settings, restart CodePilot on the Mac, then retry pairing from the iOS app.
