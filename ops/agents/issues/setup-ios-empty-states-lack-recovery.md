# Setup Friction: iOS Empty States Lack Recovery Actions

Labels: `setup`, `onboarding`, `ios`, `accounts`

## Summary

After a successful gateway connection, a new tester can encounter **No Threads**, **No Projects**, or **No Accounts** without an explanation of where those records come from or what to do next. This makes a working connection look incomplete or broken at the first useful-product step.

## Reproduction

1. Connect the iOS app to a new or minimally configured Mac gateway.
2. Open the thread list, the new-thread project picker, or the account switcher before corresponding data exists.
3. Observe the empty state.

## Expected

Each empty state should name the next recovery action and whether it belongs on the iPhone or the connected Mac.

## Actual Before The Audit Fix

The app showed only **No Threads**, **No Projects**, or **No Accounts**. It did not explain how to create a first thread, supply a workspace path, save a Mac account profile, or refresh the result.

## Local Fix

The `agent/setup-audit` branch adds actionable descriptions to these empty states and documents the first-thread path in `docs/INSTALL_IOS.md`. A future guided onboarding flow could make the first successful prompt a tracked completion step.
