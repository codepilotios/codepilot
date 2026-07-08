# Setup Friction: Setup Checklist Rows Lack Direct Actions

Labels: `setup`, `onboarding`, `mac`

## Summary

The Mac setup window shows a useful readiness checklist, but the actions are grouped below the list instead of attached to the row that needs attention. First-run users must translate **Missing**, **Stopped**, or **Needs setup** into the right button, guide, path, or separate window.

## Reproduction

1. Open CodePilot on macOS with one or more setup items missing.
2. Choose **Setup CodePilot...**.
3. Review a row such as **Gateway: Stopped**, **Gateway Token: Missing**, **Cloudflare: Needs setup**, or **Screen Recording: Missing**.

## Expected

Each setup row should include one primary recovery action and an advanced details disclosure for paths, logs, commands, and raw script output.

## Actual

The checklist rows are read-only text. Recovery controls are grouped by section below the checklist, so users must infer which button fixes each failed row.

## Suggested Fix

Turn setup rows into structured row views with:

- Status label.
- Short explanation.
- One primary action.
- Optional advanced details disclosure.

Keep advanced paths and commands available, but keep the default row copy focused on the recovery action.
