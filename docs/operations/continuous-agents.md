# CodePilot Continuous Agents

The preferred implementation is Codex recurring automations attached to this thread, because those can escalate in the same conversation.

On 2026-07-01, the automation creation backend hung twice while creating the first job. No automation files were created.

This repository therefore includes a local LaunchAgent scheduler fallback:

```sh
scripts/install-codepilot-local-agents.sh
```

The installer exits unless called with:

```sh
scripts/install-codepilot-local-agents.sh --install
```

## Escalation

The installer stores the current Codex thread id in:

```text
~/.codex-account-switcher/agents/thread-id
```

When an agent writes or changes `ops/agents/escalations/<job>.md`, the runner sends that escalation back into the configured thread with:

```sh
codex exec resume <thread-id>
```

The scheduler runs every 15 minutes and starts at most one due agent per tick. This avoids spending usage on seven concurrent Codex turns.

## Usage and publication controls

Routine jobs run with medium reasoning. Security and release-readiness jobs run
with high reasoning. Set `CODEPILOT_AGENT_REASONING_EFFORT` only when a manual
run needs a different level.

Unattended agents may inspect public systems, create local draft files, and
commit to their local worktree branches. They may not publish changes. The
runner injects this policy into every prompt and places guarded `gh` and `git`
commands first on `PATH`; mutating GitHub commands and `git push` are rejected.
Publishing an issue, pull request, release, store record, website update, or
social post requires maintainer action.

Logs are written to:

- logs to `~/Library/Logs/CodePilotAgents`
- worktrees to `~/.codex-account-switcher/agents/worktrees`
- escalation notes to `ops/agents/escalations`

Use this fallback until Codex recurring automation creation works. If native recurring automations become reliable, migrate the same prompt files to native jobs and unload the LaunchAgents.
