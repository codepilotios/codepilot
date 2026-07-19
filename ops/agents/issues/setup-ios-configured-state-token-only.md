# Setup Friction: iOS Treats Token-Only State As Configured

Labels: `setup`, `onboarding`, `ios`, `gateway`

## Summary

The iOS app considered first-run setup complete as soon as an iOS connection token existed. If the gateway URL was empty, malformed, or still set to an unreachable Same Network loopback address, the app could leave setup and show the main thread list with connection failures instead of keeping the user in the setup form.

## Reproduction

1. Launch the iOS app with `gatewayToken` populated but `gatewayURL` empty or invalid.
2. Observe that the app attempts to load the main CodePilot screen instead of presenting the setup form.
3. Repeat with **Same Network** selected and `http://127.0.0.1:18790` saved as the gateway URL.

## Expected

The app should stay in first-run setup until both the gateway URL and iOS connection token pass the same validation used by **Test Connection**.

## Actual

The root view only checked whether the token was empty, so token-only or invalid-url state could bypass setup.

## Local Audit Fix

The `agent/setup-audit` branch now uses the shared setup validation helper to decide whether setup is complete. Invalid URL, missing token, and Same Network loopback states keep the app on the setup screen.
