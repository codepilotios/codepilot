# Setup Friction: iOS Leaves Setup Before Connection Test

Labels: `setup`, `onboarding`, `ios`, `gateway`

## Summary

The iOS first-run form disappears as soon as the gateway URL and iOS connection token pass local format validation. A tester can therefore reach the main app without tapping **Test Connection**, and usually cannot see the test result from the first-run form.

## Reproduction

1. Launch the iOS app with no saved gateway configuration.
2. Enter a syntactically valid URL for an unreachable gateway.
3. Enter any non-empty iOS connection token.
4. Observe that the app replaces the setup form with the main screen before **Test Connection** succeeds.

## Expected

First-run setup should remain visible until an authenticated gateway request succeeds. The form should then offer an explicit **Continue** action or automatically continue after showing a successful result.

## Actual

The root view treats locally valid input as completed setup. The **Test Connection** button checks the real gateway, but successful testing is not part of the completion state.

## Local Fix

Store a connection-verified flag tied to the normalized URL, connection mode, and token. Clear it whenever those values change, and leave first-run setup visible until the current configuration passes an authenticated request.

The `agent/setup-audit` branch now stores a SHA-256 fingerprint after **Test Connection** successfully loads authenticated account status. The first-run form remains visible until that fingerprint matches the current URL, connection mode, and token; changing any field invalidates the match without storing another copy of the token.
