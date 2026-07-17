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

The Mac must remain awake and online, and both the CodePilot gateway and Cloudflare Tunnel must keep running, for the iPhone app to stay connected. The current beta does not provide a hosted relay or remote wake feature.

For the public beta, enter the Cloudflare Tunnel URL. The Mac gateway listens on `127.0.0.1:18790` by default, which is only reachable from the Mac itself. Same Network setup is disabled until CodePilot provides an explicit LAN-binding mode with firewall and trust guidance.

The gateway URL must include `http://` or `https://`.

## Notifications

The iOS app can register for turn-finished notifications. APNs certificates or keys must be configured in the gateway environment before background notifications can be delivered reliably.

## File Uploads

Files selected in the iOS app are uploaded to the Mac gateway and saved under the CodePilot state directory. Image attachments can be passed into Codex turns when supported by the current runner.

Uploads are not removed automatically after a turn. Delete files you no longer need from the Mac, and review the [privacy data-flow summary](PRIVACY.md#beta-data-flow-at-a-glance) before sharing sensitive attachments.
