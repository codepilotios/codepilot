# Setup Friction: Custom Codex Home Produces Split Setup State

Labels: `setup`, `onboarding`, `mac`, `gateway`, `auth`

## Summary

Codex supports moving its state with `CODEX_HOME`, but CodePilot currently reads the default `~/.codex` directory in the Mac app and gateway installer. A user who is signed in under a custom Codex home can therefore appear signed out in CodePilot, and the gateway can read different auth and thread state from the Codex CLI.

## Reproduction

1. Set `CODEX_HOME` to a non-default directory.
2. Sign in with the Codex CLI and confirm that the custom directory contains the active auth and state.
3. Start CodePilot and open **Setup CodePilot...**.
4. Observe that **Codex Login** checks the default `~/.codex/auth.json` instead.
5. Install or restart the gateway and observe that its default `--codex-home` also points at `~/.codex`.

## Expected

The Mac app, account switcher, setup checklist, gateway LaunchAgent, and gateway process use one resolved Codex home. If a custom location cannot be supported safely, setup detects it and explains the limitation before account or gateway configuration continues.

## Actual

`Settings.load()` and `CodePilotSetupStatus.load()` construct `~/.codex` directly. The gateway defaults to the same directory, and the LaunchAgent installer does not propagate or configure `CODEX_HOME`.

## Suggested Fix

Define one validated Codex-home resolver, require an absolute existing directory for overrides, and pass the resolved value explicitly to the gateway LaunchAgent. Add tests covering the default, a valid custom directory, relative or missing overrides, and agreement between Mac setup and gateway state.

## Local Audit Mitigation

The Mac install guide now states that the current beta setup requires the default `~/.codex` directory so users do not complete a custom-home login that CodePilot cannot see.
