# Setup Friction: iOS Accepts Gateway URLs With URL Extras

Labels: `setup`, `onboarding`, `ios`, `gateway`, `validation`

## Summary

The iOS setup form accepts gateway URLs containing credentials, paths, queries, or fragments even though CodePilot expects the gateway server address and the Mac setup screen copies an origin-only URL. A user who pastes a dashboard link or an API endpoint can pass local validation but receive confusing connection behavior.

## Reproduction

1. Open CodePilot on iOS before setup is complete.
2. Enter an HTTPS URL such as `https://codepilot.example.com/api/health` with a non-empty iOS connection token.
3. Observe that **Test Connection** is enabled.

## Expected

The setup form accepts only the gateway server address and explains how to remove unsupported URL components before testing.

## Actual Before The Audit Fix

The shared setup validator checked the scheme and host but allowed credentials, non-root paths, queries, and fragments.

## Local Fix

The `agent/setup-audit` branch now rejects unsupported URL components with actionable copy and documents the server-address-only requirement. The root path with or without a trailing slash remains valid. Focused iOS tests cover credentials, paths, queries, fragments, and the valid trailing-slash case.
