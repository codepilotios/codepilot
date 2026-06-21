# Architecture

CodePilot has three main runtime pieces.

## Mac Menu Bar App

The Mac app is a Swift/AppKit menu bar utility. It watches local Codex usage and account state, manages saved account profiles, and coordinates account switching.

Current implementation target: `CodexAccountSwitcher`.

## Gateway

The gateway is a Python HTTP service that runs on the Mac. It reads the local Codex home and exposes a token-protected API for the iOS app.

Responsibilities:

- List threads and projects.
- Start, steer, stop, and observe turns.
- Upload files from iOS.
- Report account usage.
- Report plugin and connector status.
- Register notification devices.

## iOS App

The iOS app is a SwiftUI client for the gateway. It does not talk directly to provider services; it talks to the Mac gateway, and the gateway uses the active account on the Mac.

Current implementation target: `CodexPhone`.

## State

CodePilot currently keeps legacy state under:

```text
~/.codex-account-switcher/
```

This path is intentionally retained during the first public branding pass to avoid breaking existing installations.

## Future Provider Layer

The public product name is provider-neutral. Future provider support should isolate provider-specific logic behind small interfaces for:

- Auth profile discovery.
- Usage reporting.
- Turn execution.
- Thread storage.
- Connector/plugin status.

