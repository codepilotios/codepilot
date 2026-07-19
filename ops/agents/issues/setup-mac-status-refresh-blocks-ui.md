# Setup Friction: Mac Status Refresh Blocks The Setup Window

Labels: `setup`, `onboarding`, `mac`, `gateway`

## Summary

Opening **Setup CodePilot...** or choosing **Refresh Status** performs the local gateway health request synchronously on the main thread. When the gateway is stopped or unresponsive, the setup window can appear frozen for up to the two-second probe timeout.

## Reproduction

1. Stop the CodePilot gateway or make `127.0.0.1:18790` accept a connection without responding.
2. Open **Setup CodePilot...**.
3. Try to move, resize, or interact with the window while status loads.
4. Repeat with **Refresh Status**.

## Expected

The setup window should appear and remain interactive immediately. Gateway status should show a progress state and update when the health request completes or times out.

## Actual

`CodePilotSetupStatus.load()` calls the gateway health probe through a semaphore wait. Both initial load and manual refresh call it from the main thread, blocking AppKit event handling until the request finishes or the timeout expires.

## Suggested Fix

Load filesystem and permission status immediately, render the gateway row as **Checking**, and perform the health request asynchronously. Apply the result on the main actor and cancel or supersede stale refresh requests.
