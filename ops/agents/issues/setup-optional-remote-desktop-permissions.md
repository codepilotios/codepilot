# Setup Friction: Optional Remote Desktop Permissions Look Required

Labels: `setup`, `onboarding`, `mac`, `permissions`, `remote-desktop`

## Summary

The Mac setup checklist labels Screen Recording and Accessibility as **Missing** when they have not been granted, even though both permissions are optional unless the user chooses Remote Desktop. This makes an otherwise complete first-run setup appear incomplete.

## Reproduction

1. Open CodePilot on a Mac that has not granted Remote Desktop permissions.
2. Choose **Setup CodePilot...**.
3. Review the Screen Recording and Accessibility rows.

## Expected

The checklist identifies both permissions as optional and explains which Remote Desktop capability each one enables. The dedicated permission window can continue to report whether each permission is technically granted or missing.

## Actual Before The Audit Fix

Both setup rows show **Missing**, with copy that directs the user to System Settings without explaining that normal account, gateway, and iPhone setup can continue.

## Local Fix

The `agent/setup-audit` branch labels ungranted Screen Recording and Accessibility requirements as **Optional** in the main setup checklist. The row details now state that Screen Recording enables viewing the Mac remotely and Accessibility enables remote control.
