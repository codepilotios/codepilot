# Setup Friction: Screen Recording Prompt Appears Before Setup Context

Labels: `setup`, `onboarding`, `mac`, `permissions`, `remote-desktop`

## Summary

CodePilot requests Screen Recording permission as soon as the Mac app launches, before the user opens setup or chooses Remote Desktop. The system prompt does not explain why a menu bar account and gateway app needs screen access, which can reduce trust during first run.

## Reproduction

1. Install and open CodePilot on a Mac where Screen Recording has not been granted.
2. Observe the macOS permission prompt during application launch.

## Expected

Request Screen Recording only after the user chooses to set up Remote Desktop, with nearby copy explaining that viewing requires Screen Recording and control separately requires Accessibility.

## Actual

Application startup calls the Screen Recording request API unconditionally when permission is absent.

## Suggested Fix

Move the request behind a clear action in the setup or Remote Desktop window. Keep both permission statuses visible and provide direct links to the relevant System Settings panes.
