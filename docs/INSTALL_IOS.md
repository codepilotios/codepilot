# iOS Installation

CodePilot iOS connects to a Mac running the CodePilot gateway.

## Requirements

- An iPhone running iOS 17 or later.
- Access to an approved CodePilot beta build.
- A Mac running the CodePilot gateway.
- A reachable gateway URL.
- The gateway bearer token from the Mac.
- Cloudflare Tunnel for the public beta connection path.

## Connection

On first launch:

1. Choose **Cloudflare**.
2. Enter the gateway URL.
3. Enter the token from `~/.codex-account-switcher/phone-gateway-token` on the Mac.
4. Tap **Test Connection**.

Success means the app shows the active account from the Mac gateway.

The app stores these values locally on the device.

For the default Mac setup, choose **Cloudflare** and enter the Cloudflare Tunnel URL. The Mac gateway listens on `127.0.0.1:18790` by default, which is only reachable from the Mac itself. Use **Same Network** only after configuring the gateway to listen on a Mac LAN address.

The gateway URL must include `http://` or `https://`.

## Notifications

The iOS app can register for turn-finished notifications. APNs certificates or keys must be configured in the gateway environment before background notifications can be delivered reliably.

Notification permission and Live Activities are separate iOS settings. Enable only the features you want, and see [Troubleshooting](TROUBLESHOOTING.md#turn-finished-notifications-do-not-arrive) if a completed turn does not produce a notification.

## File Uploads

Files selected in the iOS app are uploaded to the Mac gateway and saved under the CodePilot state directory. Image attachments can be passed into Codex turns when supported by the current runner.

## Remote Desktop

Remote Desktop requires the Mac app to show Screen Recording as granted before viewing and Accessibility as granted before control. If pairing reports missing permissions, grant them in macOS System Settings, restart CodePilot on the Mac, then retry pairing from the iOS app.
