# Setup Friction: iOS Connection Token Is Stored In UserDefaults

Labels: `setup`, `onboarding`, `ios`, `gateway`, `security`

## Summary

The iOS connection token is a bearer credential for the Mac gateway, including authenticated Remote Desktop operations, but the iOS app persists it in `UserDefaults` through `@AppStorage`. Launch-argument setup also writes the token directly to the same defaults store.

## Reproduction

1. Complete first-run iOS setup with a gateway URL and iOS connection token.
2. Inspect the app's preferences container in a development or simulator build.
3. Observe the `gatewayToken` value in the preferences property list.

## Expected

Store the iOS connection token in Keychain with an appropriate device-only accessibility class. Keep only non-secret connection preferences, such as the gateway URL and connection kind, in `UserDefaults`.

## Actual

`RootView`, `EmptySettingsView`, and `SettingsView` bind the token with `@AppStorage("gatewayToken")`. Notification registration and launch configuration also read or write `gatewayToken` through `UserDefaults.standard`.

## Suggested Fix

Introduce a small Keychain-backed credential store, migrate and remove any existing `gatewayToken` defaults value on first access, and update notification registration to read from that store. Add tests for migration, update, deletion, and unavailable-Keychain recovery. Treat the change as iOS release work and run the required OTA verification before completion.
