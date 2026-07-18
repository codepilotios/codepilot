# CodePilot Security Maintenance Notice

Status reviewed: 2026-07-18. Public launch remains blocked on the maintainer-only items below; keep the documented fail-closed controls enabled.

Detailed security findings are intentionally not stored in the public repository. Send vulnerability details, private identifiers, logs, and credential-related evidence through the maintainers' private security channel.

Before public launch, maintainer coordination is still required for:

- Reviewing and resolving the open GitHub secret-scanning alert through the private security channel, including revocation or rotation where applicable.
- A confidential review before any currently disabled privileged remote-access feature is re-enabled.
- A credential and edge-access architecture review for the remotely reachable gateway.
- Sanitizing historical private identifiers and commit metadata, followed by coordinated clone migration.
- Enabling repository dependency alerts and reviewing the initial results.
- Shipping pending credential-storage changes through an authorized build channel and rotating affected beta credentials.

Keep fail-closed controls enabled until the corresponding private review is complete. Do not copy private findings into public issues or pull requests.
