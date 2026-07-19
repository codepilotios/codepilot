# Setup Friction: Gateway Requires Python 3.11 TOML Module On Stock macOS

Labels: `setup`, `gateway`, `install`, `mac`

## Summary

The gateway imported Python's `tomllib` module directly. `tomllib` is only available in Python 3.11 and later, while stock macOS `/usr/bin/python3` can still be Python 3.9. The gateway LaunchAgent setup prefers `/usr/local/bin/python3` and falls back to `/usr/bin/python3`, so first-run gateway startup can fail before the iOS app can connect.

## Reproduction

1. Use a Mac where `python3 --version` reports Python 3.9.
2. Run the documented gateway tests from the repo root with the gateway command environment, or start the gateway LaunchAgent.
3. Observe `ModuleNotFoundError: No module named 'tomllib'`.

## Expected

The gateway should start with the Python version selected by the setup scripts without requiring the user to install a new Python package.

## Actual

The gateway failed while importing `tomllib`, before setup health checks or recovery copy could run.

## Local Audit Fix

The `agent/setup-audit` branch replaces the direct `tomllib` dependency with a stdlib-only parser for the constrained Codex config TOML subset used by plugin setup, and adds a gateway test for quoted plugin table paths.
