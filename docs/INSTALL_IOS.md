# iOS Installation

CodePilot iOS connects to a Mac running the CodePilot gateway.

## Requirements

- A Mac running the CodePilot gateway.
- A reachable gateway URL.
- The gateway bearer token from the Mac.
- Optional: Cloudflare Tunnel for remote access outside the local network.

## Beta Installation

TestFlight is the intended iPhone distribution path during the public beta. Install the beta build from the TestFlight invite shared by the maintainers, then connect it to your own Mac gateway.

Developers building from source can open the Xcode project under `ios/CodexPhone/` and build the `CodexPhone` scheme for a simulator or device configured with their own signing setup.

## Connection

On first launch:

1. Choose **Same Network** or **Cloudflare**.
2. Enter the gateway URL.
3. Enter the token from `~/.codex-account-switcher/phone-gateway-token` on the Mac.
4. Tap **Test Connection**.

Success means the app shows the active account from the Mac gateway.

The app stores these values locally on the device.

## Notifications

The iOS app can register for turn-finished notifications. APNs certificates or keys must be configured in the gateway environment before background notifications can be delivered reliably.

## File Uploads

Files selected in the iOS app are uploaded to the Mac gateway and saved under the CodePilot state directory. Image attachments can be passed into Codex turns when supported by the current runner.
