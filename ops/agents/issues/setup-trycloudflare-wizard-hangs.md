# Setup Friction: Temporary Cloudflare URL Step Does Not Complete

Labels: `setup`, `onboarding`, `cloudflare`, `mac`

## Summary

The Mac Cloudflare setup wizard starts the temporary TryCloudflare flow through the same blocking command runner used for finite setup steps. `cloudflared tunnel --url ...` is a long-running process, so the wizard can remain in a running state instead of clearly surfacing the temporary URL and next action.

## Reproduction

1. Open CodePilot on macOS.
2. Choose **Setup CodePilot...**.
3. Open **Cloudflare Remote Access**.
4. Click **Start Temporary Test URL**.

## Expected

The wizard should show the generated `trycloudflare.com` URL, explain that it is temporary, and provide a clear stop/restart action.

## Actual

The setup step uses the blocking process path, so the success message is not reliable for a command that intentionally keeps running.

## Suggested Fix

Handle TryCloudflare as a managed background tunnel step, parse the first generated public URL from output, display it for iOS setup, and provide a stop action.
