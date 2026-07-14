# Setup Friction: iOS Install Doc Mixed User Setup With App Store Account Setup

Labels: `setup`, `onboarding`, `ios`, `docs`, `release`

## Summary

The iOS installation guide included maintainer-only App Store Connect session and app-record commands in the same flow as ordinary iPhone gateway setup. First-run users do not need Apple account access to connect the app to their Mac, and unattended setup audits must not create accounts, upload builds, or submit release changes.

## Reproduction

1. Open `docs/INSTALL_IOS.md`.
2. Follow the first-run connection steps.
3. Continue into the App Store Connect section.

## Expected

The iOS install guide should stay focused on connecting the app to a Mac gateway. Apple account and release-preparation steps should be separate maintainer documentation with clear approval boundaries.

## Actual

End-user setup and maintainer App Store setup appeared in one document, making the first-run path look more complex and increasing the chance that an unattended agent or user treats Apple account work as part of normal setup.

## Local Audit Fix

The `agent/setup-audit` branch moves App Store Connect setup into `docs/APP_STORE_CONNECT_SETUP.md` and replaces the iOS install section with a maintainer-only pointer.
