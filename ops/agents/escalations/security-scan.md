# CodePilot Security Maintenance Notice

Status reviewed: 2026-07-19. Public launch remains blocked on the maintainer-only items below; keep the documented fail-closed controls enabled.

Detailed security findings are intentionally not stored in the public repository. Send vulnerability details, private identifiers, logs, and credential-related evidence through the maintainers' private security channel.

Before public launch, maintainer coordination is still required for:

- Reviewing and resolving the open GitHub secret-scanning alert through the private security channel, including revocation or rotation where applicable.
- A confidential review before any currently disabled privileged remote-access feature is re-enabled.
- A credential and edge-access architecture review for the remotely reachable gateway.
- Sanitizing historical private identifiers and commit metadata, followed by coordinated clone migration.
- Enabling repository dependency alerts and reviewing the initial results.
- Shipping pending credential-storage changes through an authorized build channel and rotating affected beta credentials.

3. Remote desktop viewing/control is not consistently bound to a trusted-device lease.
   - Surface: `gateway/remote_desktop_gateway.py` forwards `/api/remote/frame` and `/api/remote/input` after gateway bearer auth; native handling is in `Sources/CodexAccountSwitcher/main.swift`.
   - Current behavior: frame capture does not require a session lease, and native input validation only rejects replayed sequence numbers for the provided session id. The iOS remote desktop view also starts with a placeholder lease id before a signed lease flow.
   - Risk: a leaked or phished gateway bearer token can expose screen contents and may allow input injection without the intended local Mac approval, trusted-device signature, and short-lived controller lease.
   - Decision needed: block public remote desktop exposure until the iOS app obtains a signed lease, the gateway requires that lease for frame/input/signaling, and the native host validates the lease against `SessionLeaseStore`.

Local hardening already applied in this branch:

- Removed public embedded private identifier patterns from the privacy audit and made local denylist patterns opt-in via `CODEPILOT_PRIVACY_PATTERNS_FILE`.
- Removed machine-specific default repository paths from local agent scripts.
- Changed gateway-created Codex app-server threads and turns to use safe approval/sandbox settings unless dangerous mode is explicitly enabled.
