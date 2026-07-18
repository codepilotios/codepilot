# Setup Friction: iOS Notification Permission Lacks Visible Status And Recovery

Labels: `setup`, `onboarding`, `ios`, `permissions`, `notifications`

## Summary

CodePilot asks for notification permission only after it observes a running turn. The Connection screen does not explain when the prompt will appear, show the current authorization or device-registration state, or provide recovery after permission or APNs registration fails.

## Reproduction

1. Connect CodePilot iOS to a gateway.
2. Start the first turn and respond to the notification permission prompt.
3. Deny the prompt, or let remote notification registration fail.
4. Open the iOS Connection screen.

## Expected

The app should show notification authorization and gateway device-registration state, explain that background alerts depend on gateway APNs configuration, and link to iOS Settings when permission is denied.

## Actual

The Connection screen has no notification row. Registration errors are saved internally but never displayed, so a tester cannot distinguish denied permission, failed device registration, or an unconfigured gateway.

## Local Audit Mitigation

`docs/INSTALL_IOS.md` now explains when the permission prompt appears and how to recover after denying it. A future iOS change should add an explicit status and recovery control; that change requires the approved OTA build workflow before release completion.
