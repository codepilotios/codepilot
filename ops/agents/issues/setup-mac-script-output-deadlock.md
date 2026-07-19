# Setup Friction: Mac Setup Commands Can Stall On Verbose Output

Labels: `setup`, `onboarding`, `mac`, `cloudflare`, `gateway`

## Summary

The Mac setup window and Cloudflare wizard wait for each child process to exit before draining the pipe used for combined standard output and standard error. A verbose setup command can fill the pipe buffer, leaving the child blocked on its next write while CodePilot waits for the child to exit.

## Reproduction

1. Run a bundled setup step that emits more output than the pipe can buffer, such as a verbose dependency installation or a diagnostic version of the gateway installer.
2. Open **Setup CodePilot...** and start that step.
3. Observe that the setup window continues to show the command as running even though the child is blocked while writing output.

## Expected

CodePilot should drain command output while the child is running, then report the exit status and captured details without stalling the setup flow.

## Actual

Both `CodePilotSetupWindowController.runBundledScript` and `CodePilotCloudflareWizardController.runProcess` call `waitUntilExit()` before `readDataToEndOfFile()`. The same source file already uses the safe reverse order for its SQLite helper.

## Suggested Fix

Drain the pipe before waiting for process termination, or attach a readability handler that accumulates output while the command runs. Add a regression test with a helper process that writes more than the pipe capacity before exiting. Keep the separate managed-process design from the TryCloudflare issue for commands that intentionally run indefinitely.
