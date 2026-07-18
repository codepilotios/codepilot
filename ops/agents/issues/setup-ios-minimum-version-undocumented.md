# Setup Friction: iOS Minimum Version Was Undocumented

Labels: `setup`, `onboarding`, `ios`, `docs`

## Summary

The iOS installation guide did not state that the current app target requires an iPhone running iOS 17 or later. A tester could complete the Mac gateway, account, and Cloudflare preparation before learning that the beta build cannot be installed on their device.

## Reproduction

1. Read `docs/INSTALL_IOS.md` before requesting or installing the beta build.
2. Check the listed requirements.
3. Compare them with the iOS app target, which uses an iOS 17 deployment target and the iPhone device family.

## Expected

The installation requirements identify the supported device family and minimum iOS version before the tester starts configuring the Mac.

## Actual Before The Audit Fix

The guide listed the Mac gateway, gateway URL, connection token, and Cloudflare hostname, but no iPhone or iOS version requirement.

## Local Audit Fix

The `agent/setup-audit` branch now lists an iPhone running iOS 17 or later as the first iOS installation requirement. This matches the current Xcode target without changing the app's deployment settings or distribution state.
