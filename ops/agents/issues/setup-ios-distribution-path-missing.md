# Setup Friction: iOS Guide Does Not Provide An Install Path

Labels: `setup`, `onboarding`, `ios`, `release`, `docs`

## Summary

The iOS guide explains how to connect an installed app to the Mac gateway, but it does not tell a beta user how to obtain the iOS app. There is no public TestFlight invitation, App Store link, or source-build path in the user setup flow.

## Reproduction

1. Start from the repository README as a new beta user.
2. Follow the iOS installation link.
3. Try to install CodePilot iOS before entering the gateway URL and iOS connection token.

## Expected

The guide should lead with one approved distribution path, then continue into gateway connection steps. Maintainer-only App Store Connect commands should remain in the separate release document.

## Actual

The guide begins with requirements for an already installed app and provides no user-accessible installation step.

## Suggested Fix

After maintainer approval, add the public beta's TestFlight invitation or App Store link. Until then, label the iOS guide as connection configuration for testers who have already received a build.

## Local Audit Progress

The `agent/setup-audit` branch now labels the iOS guide as configuration for testers who already received a beta build and makes the same limitation explicit in the README. Adding an install link remains blocked on maintainer approval of the distribution path.
