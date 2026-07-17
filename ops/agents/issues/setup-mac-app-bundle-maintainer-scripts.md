# Setup Friction: Mac App Bundle Included Maintainer Scripts

Labels: `setup`, `install`, `mac`, `release`, `security`

## Summary

The Mac app build copied every shell and Python helper from the repository into `Contents/Resources/scripts`, including maintainer-only release, session, agent-installation, and audit helpers unrelated to first-run setup.

## Reproduction

1. Run `scripts/build-app.sh`.
2. Inspect `CodePilot.app/Contents/Resources/scripts`.
3. Observe scripts beyond the gateway and Cloudflare runtime helpers used by the app.

## Expected

The distributed app should contain only the runtime resources needed for its supported setup actions.

## Actual

The build used wildcard copies, expanding the public app bundle's contents whenever any repository helper was added.

## Local Fix

The `agent/setup-audit` branch replaces wildcard copies with an allowlist containing the gateway installer, Cloudflare setup helper, and Cloudflare service launcher. The bundled gateway modules remain included for the gateway LaunchAgent.
