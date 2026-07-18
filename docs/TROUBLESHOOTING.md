# Troubleshooting

## iPhone Cannot Reach The Gateway

Confirm the iPhone has an internet or local-network connection and the Mac is awake. On the Mac, open CodePilot and choose **Restart Gateway When Idle**. For Cloudflare connections, also restart the tunnel from **Setup CodePilot... > Cloudflare Remote Access**.

If the connection test still cannot find the host, confirm the iPhone gateway URL exactly matches the verified remote access URL from the Mac setup screen. Do not use the Mac gateway's `127.0.0.1` address on the iPhone.

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

Open **Remote Desktop...** on the Mac and confirm Screen Recording and Accessibility permissions are granted. Use **Allow Screen Recording** or **Allow Accessibility** for a missing permission, then restart CodePilot after changing macOS privacy permissions.

## Localhost Link Does Not Open

The Mac-side web server must still be running on `localhost`, `127.0.0.1`, or `::1`. Reopen the link from the iOS app if the local-web session expired.
