# CodePilot Security Maintenance Notice

Status reviewed: 2026-07-20. Public launch remains blocked on the maintainer-only items below; keep the documented fail-closed controls enabled.

Detailed security findings are intentionally not stored in the public repository. Send vulnerability details, private identifiers, logs, and credential-related evidence through the maintainers' private security channel.

Before public launch, maintainer coordination is still required for:

- A confidential review before any currently disabled privileged remote-access feature is re-enabled.
- A credential and edge-access architecture review for the remotely reachable gateway.
- Sanitizing historical private identifiers and commit metadata, followed by coordinated clone migration.
- Protecting the default branch with required reviews and passing checks.
- Enabling dependency alerts and security updates, plus non-provider secret patterns and validity checks, then reviewing new results and dispositioning the outstanding code-scanning findings.
- Shipping pending credential-storage changes through an authorized build channel and rotating affected beta credentials.
- Shipping the pending HTTPS-only gateway-client hardening through the authorized OTA channel; this unattended scan may build locally but may not publish an OTA update.

Keep fail-closed controls enabled until the corresponding private review is complete. Do not copy private findings into public issues or pull requests.
