# iOS Installation

CodePilot iOS connects to a Mac running the CodePilot gateway.

This guide configures a beta build that a tester has already received. A public TestFlight or App Store install link has not been approved yet.

## Requirements

- An iPhone running iOS 17 or later.
- A Mac running the CodePilot gateway.
- A reachable gateway URL.
- The iOS connection token from the Mac setup screen.
- A permanent Cloudflare Tunnel hostname for the supported setup path.

## Connection

On first launch:

1. Keep the recommended **Cloudflare** connection selected.
2. Configure a permanent Cloudflare hostname from the Mac setup screen if you have not already done so.
3. On the Mac, use **Setup CodePilot... > iPhone Connection** to copy the remote access URL and enter it as the gateway URL.
4. Copy the iOS connection token from the same Mac setup section.
5. Tap **Test Connection**.

The first-run screen remains open until the authenticated connection test succeeds. Success means the app opens CodePilot and shows the active account from the Mac gateway.

## First Thread

After the connection test succeeds, tap the compose button to start a thread. Choose an existing project or enter its workspace path on the connected Mac. If CodePilot shows **No Accounts**, add and save an account profile from the CodePilot menu on the Mac, then refresh the iPhone app.

The app stores these values locally on the device. Do not share the token in issue reports or screenshots.

The Mac gateway listens on `127.0.0.1:18790` by default, which is only reachable from the Mac itself. This makes Cloudflare required for the standard iPhone setup. **Same Network (Advanced)** is not supported by the standard installer; use it only after deliberately configuring and securing the gateway on a Mac LAN address.

The gateway URL must include `http://` or `https://`. Enter only the server address, without credentials, an API path, a query, or a fragment. Cloudflare mode requires an `https://` tunnel hostname, not a local or public IP address.

## App Store Connect

App Store Connect setup is maintainer-only and is not required to connect the iOS app to your Mac. It requires Apple account access and explicit release approval. Maintainer notes live in `docs/APP_STORE_CONNECT_SETUP.md`.

## Notifications

The iOS app can register for turn-finished notifications. APNs certificates or keys must be configured in the gateway environment before background notifications can be delivered reliably.

CodePilot asks for notification permission when it observes the first running turn. If permission was denied, open iOS **Settings > Notifications > CodePilot**, allow notifications, then start another turn so the device can register with the gateway. The Mac setup checklist reports whether its gateway is configured for background delivery.

## File Uploads

Files selected in the iOS app are uploaded to the Mac gateway and saved under the CodePilot state directory. Image attachments can be passed into Codex turns when supported by the current runner.

## Remote Desktop

Remote Desktop requires the Mac app to show Screen Recording as granted before viewing and Accessibility as granted before control. If pairing reports missing permissions, open **Remote Desktop...** on the Mac, use the matching **Allow** action, restart CodePilot, then retry pairing from the iOS app.
