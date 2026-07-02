# CodePilot Continuous Agents

The preferred implementation is Codex recurring automations attached to this thread, because those can escalate in the same conversation.

On 2026-07-01, the automation creation backend hung twice while creating the first job. No automation files were created.

This repository therefore includes a disabled local LaunchAgent fallback:

```sh
scripts/install-codepilot-local-agents.sh
```

The installer prints the limitation and exits unless called with:

```sh
scripts/install-codepilot-local-agents.sh --install
```

## Limitation

Local LaunchAgents cannot ping the current Codex thread. They write:

- logs to `~/Library/Logs/CodePilotAgents`
- escalation notes to `ops/agents/escalations`

Use this fallback only if file/GitHub-based escalation is acceptable. Otherwise, wait until Codex recurring automation creation works and create the jobs from `docs/superpowers/plans/2026-07-01-codepilot-launch-agent-system.md`.

