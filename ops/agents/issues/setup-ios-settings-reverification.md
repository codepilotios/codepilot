# Setup Friction: iOS Settings Requires A Second Connection Test

Labels: `setup`, `onboarding`, `ios`, `gateway`

## Summary

Changing the gateway URL, iOS connection token, or connection mode in iOS Settings invalidates the saved verification fingerprint, as intended. However, a successful authenticated test from Settings did not save a replacement fingerprint. Closing Settings therefore returned the user to first-run setup, where the same connection had to be tested again.

## Reproduction

1. Complete iOS setup with a verified gateway connection.
2. Open **Settings** and change the gateway URL, iOS connection token, or connection mode.
3. Tap **Test Connection** and receive a successful **Connected** result.
4. Close Settings.

## Expected

The authenticated test in Settings should verify the current configuration and keep the user in the main app.

## Actual Before The Audit Fix

Only the first-run form stored the verification fingerprint. Settings reported success but left the new configuration unverified, so the app returned to first-run setup.

## Local Fix

The `agent/setup-audit` branch passes the saved verification state into Settings and updates it after the same authenticated account-status request succeeds. Settings also uses the shared Cloudflare-first default and fallback for connection mode.
