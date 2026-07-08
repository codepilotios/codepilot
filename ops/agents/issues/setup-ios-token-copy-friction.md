# Setup Friction: iOS Connection Still Requires Manual Token Copying

Labels: `setup`, `onboarding`, `ios`, `gateway`

## Summary

The iOS first-run flow now uses public wording for the iOS connection token, but the setup still requires users to manually copy a long token from the Mac setup screen into the iPhone app. This is a reasonable beta fallback, but it is still a high-friction step for ordinary users and can lead to support screenshots that expose the token.

## Reproduction

1. Install and start CodePilot on the Mac.
2. Open the iOS app for the first time.
3. Enter the gateway URL.
4. Copy the iOS connection token from the Mac setup screen into the iOS app.

## Expected

The Mac and iOS setup flows should offer a low-risk pairing path that avoids manual token transcription, such as a QR code or one-time pairing code shown by the Mac setup screen.

## Actual

Users must copy the token manually. The current copy warns users not to share it, but setup still depends on handling a secret directly.

## Suggested Fix

Add a Mac-generated QR code or short-lived pairing code that transfers the gateway URL and token to the iOS app. Keep manual entry as an advanced fallback and ensure QR screenshots are treated as sensitive.

## Local Audit Fix

The `agent/setup-audit` branch changes iOS and docs copy from protocol-level "bearer token" wording to "iOS connection token" and removes the hidden token file path from primary iOS setup screens.
