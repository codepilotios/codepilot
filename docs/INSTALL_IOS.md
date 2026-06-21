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

## Notifications

The iOS app can register for turn-finished notifications. APNs certificates or keys must be configured in the gateway environment before background notifications can be delivered reliably.

## File Uploads

Files selected in the iOS app are uploaded to the Mac gateway and saved under the CodePilot state directory. Image attachments can be passed into Codex turns when supported by the current runner.

