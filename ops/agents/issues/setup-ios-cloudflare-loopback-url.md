# Setup Friction: iOS Cloudflare Setup Accepted Loopback URLs

Labels: `setup`, `onboarding`, `ios`, `cloudflare`

## Summary

The iOS first-run setup rejected `localhost` and `127.0.0.1` only when **Same Network** was selected. If users selected **Cloudflare** and pasted a loopback URL with `https://`, setup validation allowed the value even though the phone cannot reach the Mac gateway through its own loopback interface.

## Reproduction

1. Launch the iOS app in the first-run setup state.
2. Select **Cloudflare**.
3. Enter `https://127.0.0.1:18790` as the gateway URL.
4. Enter any non-empty iOS connection token.

## Expected

The setup form should explain that Cloudflare mode needs the public tunnel URL from the Mac setup screen.

## Actual

The form allowed the loopback URL because Cloudflare validation only required an `https://` scheme.

## Local Audit Fix

The `agent/setup-audit` branch now rejects `localhost`, `127.0.0.1`, and `::1` in Cloudflare mode and keeps setup incomplete until the user enters a public tunnel URL.
