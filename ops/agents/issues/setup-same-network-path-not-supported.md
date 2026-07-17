# Setup Friction: Same Network Path Has No Supported Mac Configuration

Labels: `setup`, `onboarding`, `ios`, `gateway`, `security`

## Summary

The iOS first-run screen offers **Same Network**, but the supported Mac gateway installer always binds to `127.0.0.1`. The docs say to configure a LAN address deliberately without providing a supported setting, command, or security guidance.

## Reproduction

1. Install the Mac gateway through **Setup CodePilot...**.
2. Choose **Same Network** in the iOS first-run screen.
3. Try to obtain a reachable Mac gateway URL from the setup window or install guide.

## Expected

Either provide a supported, authenticated LAN-listening setup with firewall and network-exposure guidance, or hide **Same Network** until that path is implemented.

## Actual

The installed gateway is loopback-only, and iOS correctly rejects loopback addresses because they refer to the iPhone itself. No supported Mac action completes the selected setup path.

## Suggested Fix

For public beta, default to Cloudflare and mark **Same Network** as advanced or unavailable. If LAN mode is retained, add an explicit Mac-side configuration and validate that authentication remains required on every non-health endpoint.
