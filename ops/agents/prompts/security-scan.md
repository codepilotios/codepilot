# CodePilot Security Scan

Scan CodePilot for secrets, private data, unsafe remote access, auth token exposure, public repo leaks, and gateway risks.

Follow `docs/superpowers/plans/2026-07-01-codepilot-launch-agent-system.md`.

Rules:
- Treat secrets, auth tokens, remote desktop access, uploads, and public endpoints as high risk.
- Create draft PRs for hardening when safe.
- Do not disclose secrets in public issues.
- If intervention is needed, write a concise escalation note to `ops/agents/escalations/security-scan.md`.

Report:
- Scope scanned.
- Findings by severity.
- Fixes or private escalations.
