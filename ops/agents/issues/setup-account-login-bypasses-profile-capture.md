# Setup Friction: Setup Login Bypasses Account Profile Capture

Labels: `setup`, `onboarding`, `mac`, `auth`

## Summary

The Mac setup window's **Open Codex Login** button runs a plain `codex login`, but CodePilot's account workflow starts from **Log In New Account...** in the menu and enables **Save Logged-In Account...** after login. A first-run user following the setup window can finish Codex authentication while the required **Account Profiles** row remains missing.

## Reproduction

1. Start CodePilot without an account profile.
2. Open **Setup CodePilot...**.
3. Click **Open Codex Login** and complete authentication.
4. Refresh setup status.

## Expected

The setup action should start CodePilot's profile-capture workflow and lead the user through naming and saving the authenticated account.

## Actual

The action launches `codex login` directly. It does not set CodePilot's login-capture state or expose the save step from the setup window.

## Suggested Fix

Route the setup button through the same account workflow as **Log In New Account...**, then surface the save action and completion status in the setup window.
