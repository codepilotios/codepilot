# Setup Friction: Mac Bundle Omits Terminal Automation Permission Metadata

Labels: `setup`, `onboarding`, `mac`, `permissions`, `auth`, `cloudflare`

## Summary

CodePilot sends Apple events to Terminal when starting interactive Codex and Cloudflare sign-in flows. The generated Mac app previously omitted both the Apple Events usage description and the hardened-runtime Apple Events entitlement, so macOS could block the setup action instead of presenting an understandable permission prompt.

## Reproduction

1. Build the Mac app with `scripts/build-app.sh` using an Apple Development signing identity.
2. Inspect the generated app's Info.plist and code-signing entitlements.
3. Choose **Log In New Account...** or **Sign In or Create Account** from Cloudflare setup.

## Expected

The signed app declares Terminal automation access and explains that it opens Terminal for interactive Codex and Cloudflare sign-in commands.

## Actual Before The Audit Fix

The app was signed with hardened runtime but had no `NSAppleEventsUsageDescription` entry and no `com.apple.security.automation.apple-events` entitlement.

## Local Fix

The `agent/setup-audit` branch adds a concise purpose string to the generated Info.plist and supplies the narrowly scoped Apple Events entitlement during app signing. No broad runtime exception or external permission change is made.
