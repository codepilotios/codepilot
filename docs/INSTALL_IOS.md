# iOS Installation

CodePilot iOS connects to a Mac running the CodePilot gateway.

This guide configures a beta build that a tester has already received. A public TestFlight or App Store install link has not been approved yet.

## Requirements

- An iPhone running iOS 17 or later.
- Access to an approved CodePilot beta build.
- A Mac running the CodePilot gateway.
- A reachable gateway URL.
- The iOS connection token from the Mac setup screen.
- Optional: Cloudflare Tunnel for remote access outside the local network.

## Connection

On first launch:

1. Keep the recommended **Cloudflare** connection selected.
2. Configure a permanent Cloudflare hostname from the Mac setup screen if you have not already done so.
3. On the Mac, use **Setup CodePilot... > iPhone Connection** to copy the remote access URL and enter it as the gateway URL.
4. Copy the iOS connection token from the same Mac setup section.
5. Tap **Test Connection**.

The first-run screen remains open until the authenticated connection test succeeds. Success means the app opens CodePilot and shows the active account from the Mac gateway.

The app stores these values locally on the device. Do not share the token in issue reports or screenshots.

The Mac gateway listens on `127.0.0.1:18790` by default, which is only reachable from the Mac itself. **Same Network (Advanced)** is not supported by the standard installer; use it only after deliberately configuring and securing the gateway on a Mac LAN address.

The gateway URL must include `http://` or `https://`.

## App Store Connect

App Store Connect setup is maintainer-only and is not required to connect the iOS app to your Mac. It requires Apple account access and explicit release approval. Maintainer notes live in `docs/APP_STORE_CONNECT_SETUP.md`.

## Notifications

The iOS app can register for turn-finished notifications. APNs certificates or keys must be configured in the gateway environment before background notifications can be delivered reliably.

Notification permission and Live Activities are separate iOS settings. Enable only the features you want, and see [Troubleshooting](TROUBLESHOOTING.md#turn-finished-notifications-do-not-arrive) if a completed turn does not produce a notification.

## File Uploads

Files selected in the iOS app are uploaded to the Mac gateway and saved under the CodePilot state directory. Image attachments can be passed into Codex turns when supported by the current runner.

## Remote Desktop

Remote Desktop requires the Mac app to show Screen Recording as granted before viewing and Accessibility as granted before control. If pairing reports missing permissions, grant them in macOS System Settings, restart CodePilot on the Mac, then retry pairing from the iOS app.
