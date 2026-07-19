# Setup Friction: iOS Network Errors Lack Recovery Actions

Labels: `setup`, `onboarding`, `ios`, `gateway`, `cloudflare`

## Summary

The iOS first-run and Settings connection tests show the system networking error description when the iPhone is offline, DNS fails, the Mac gateway cannot be reached, or the request times out. These messages do not tell a tester which CodePilot components to check.

## Reproduction

1. Open first-run setup or **Settings** in the iOS app.
2. Enter an otherwise valid gateway URL and iOS connection token.
3. Stop the gateway or tunnel, use an unresolvable hostname, or disconnect the iPhone network.
4. Tap **Test Connection**.

## Expected

The failure should distinguish an offline iPhone, an unreachable gateway, and a timeout, then name the Mac gateway, Cloudflare tunnel, or local network recovery action.

## Actual Before The Audit Fix

The app falls back to `localizedDescription` for URL loading failures. The resulting system message does not connect the failure to CodePilot setup or explain what to retry.

## Local Audit Fix

The `agent/setup-audit` branch maps common offline, DNS, connection, network-loss, and timeout errors to CodePilot-specific recovery copy in both first-run setup and Settings. `docs/TROUBLESHOOTING.md` now documents the same recovery path.
