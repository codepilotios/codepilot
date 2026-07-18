# Setup Friction: Setup Actions Allow Concurrent Runs

Labels: `setup`, `onboarding`, `mac`, `gateway`, `cloudflare`

## Summary

The Mac setup window and Cloudflare wizard leave every action enabled while a setup command is running. Repeated clicks can start overlapping gateway restarts, tunnel installation, tunnel creation, DNS routing, or verification against the same local files and services.

## Reproduction

1. Open **Setup CodePilot...** or **Cloudflare Remote Access**.
2. Start a command that takes several seconds, such as **Restart Gateway When Idle** or **Configure Permanent Hostname**.
3. Click the same action again, or start another action before the first command completes.
4. Observe that CodePilot launches another process and the single result label is updated by whichever process finishes last.

## Expected

Only one mutating setup operation runs at a time. Relevant controls show a busy state, duplicate actions are disabled, and closing the window either cancels a cancellable task or clearly allows it to finish in the background.

## Actual

`CodePilotSetupWindowController.runBundledScript` and `CodePilotCloudflareWizardController.runCloudflareSteps` do not retain an operation state or disable their buttons. Concurrent commands can race LaunchAgent reloads, Cloudflare metadata writes, and the result shown to the user.

## Suggested Fix

Give each controller one owned setup task, disable mutating actions until it completes, and ignore stale completions by operation identifier. Add an explicit progress indicator and define close/cancel behavior before enabling cancellation for commands that may have already changed external state.
