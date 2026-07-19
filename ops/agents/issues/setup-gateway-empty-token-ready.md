# Setup Friction: Empty Gateway Token File Appears Ready

Labels: `setup`, `onboarding`, `mac`, `gateway`, `auth`

## Summary

The Mac setup checklist treated the iOS connection token as ready whenever the token file existed. An interrupted or malformed gateway start can leave an empty file, causing setup to show **Ready** even though **Copy iOS Connection Token** immediately reports that no token was found.

## Reproduction

1. Create an empty CodePilot gateway-token file in the app state directory.
2. Open **Setup CodePilot...** and refresh status.
3. Compare the **iOS Connection Token** row with **Copy iOS Connection Token**.

## Expected

The token row should be ready only when the file contains a non-whitespace value, and otherwise direct the user to restart the gateway.

## Actual Before The Audit

File existence alone produced **Ready to copy to iPhone**, while the copy action rejected the empty value.

## Local Audit Fix

The `agent/setup-audit` branch now applies the same non-empty check to setup status and token copying. A focused unit test covers missing, whitespace-only, and populated token files.
