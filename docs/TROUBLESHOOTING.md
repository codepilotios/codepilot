# Troubleshooting

## iPhone Shows 502

Cloudflare reached your hostname, but the Mac gateway was not reachable. Open CodePilot on the Mac and choose **Restart Gateway When Idle**.

If the Mac is asleep, offline, or the Cloudflare tunnel is stopped, bring the Mac online and restart the tunnel.

## Cloudflare Setup Fails

Open **Setup CodePilot... > Cloudflare Remote Access** and review the details for the failed step.

- If `cloudflared` is missing, run the install step or install it manually from Cloudflare.
- If Homebrew is missing, install Homebrew or use Cloudflare's manual package.
- If login fails, rerun **Sign In or Create Account**.
- If DNS routing fails, confirm the hostname belongs to a Cloudflare-managed domain.
- If public verification fails, confirm the local gateway is running and restart the tunnel.

## iPhone Shows 401 Or 403

The saved iOS connection token is missing or wrong. Copy the current token from CodePilot on the Mac and update the iPhone connection.

If the token was rotated, every connected iPhone must be updated.

## Login Is Stale

Use **Refresh Login** for the affected account. CodePilot keeps existing turns running and applies the refreshed account to future turns.

## Gateway Restart Is Deferred

CodePilot avoids restarting the gateway while a phone turn is running. Wait for the turn to finish, then choose **Restart Gateway When Idle** again.

Use **Force Restart Gateway...** only when the gateway is stuck and interrupting an active phone turn is acceptable.

## Threads Or Messages Look Stale

Pull to refresh the thread list. If a live stream was interrupted, open the thread again after the turn finishes so saved messages can reload from the Mac gateway.

## File Upload Is Rejected

Confirm the iPhone can still load threads from the Mac gateway, then retry with a smaller selection. One turn can include up to eight attachments, with a 25 MB limit per file and a 50 MB combined limit.

Uploads that succeed remain under the CodePilot state directory on the Mac until you delete them. Do not attach the original private file or an unsanitized gateway response to a public issue. If the same sanitized sample file still fails, report the visible recovery message and the file's approximate size and type.

## Turn-Finished Notifications Do Not Arrive

Check each part of the optional notification path:

1. In iOS Settings, confirm notifications are allowed for CodePilot.
2. Confirm the Mac is awake and online and that the CodePilot gateway and Cloudflare Tunnel are running.
3. Confirm the iPhone can still load threads using the saved gateway URL and token.
4. For background delivery, confirm APNs is configured in the gateway environment.

Live Activities use a separate iOS control. Enabling notifications does not automatically enable Live Activities, and disabling one does not disable the other.

If delivery still fails, report whether it fails only in the background or also while CodePilot is open. Share only sanitized recovery text; notification registration details and device tokens are private.

## Remote Desktop Is Unavailable

Remote Desktop is not part of the supported public beta while its device-pairing and session-authorization enforcement is being completed and independently verified. Do not work around this restriction or enable the feature in beta builds.

## Localhost Link Does Not Open

The Mac-side web server must still be running on `localhost`, `127.0.0.1`, or `::1`. Reopen the link from the iOS app if the local-web session expired.
