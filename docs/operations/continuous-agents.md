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

## Usage, anonymity, and publication controls

Routine jobs run with medium reasoning. Security and release-readiness jobs run
with high reasoning. Set `CODEPILOT_AGENT_REASONING_EFFORT` only when a manual
run needs a different level.

Unattended agents run in launch-autonomous mode by default. They use the public
CodePilot identity, not a personal identity, and must keep private names, email
addresses, hosts, paths, tokens, and screenshots out of commits, issues, pull
requests, docs, metadata, logs, and escalations.

Agents may inspect public systems, create local draft files, commit to local
worktree branches, push `agent/*` branches, create GitHub issues, and open draft
GitHub pull requests when that directly advances public launch readiness. The
runner injects this policy into every prompt and places guarded commands first on
`PATH`; allowed public writes run the privacy audit first.

Agents must not merge pull requests, publish releases, submit App Store review,
upload TestFlight/App Store builds, alter pricing or legal metadata, create
accounts, post publicly on social/community sites, change credentials, or mutate
non-GitHub external systems. These still require maintainer action.

Logs are written to:

- logs to `~/Library/Logs/CodePilotAgents`
- worktrees to `~/.codex-account-switcher/agents/worktrees`
- escalation notes to `ops/agents/escalations`

Use this fallback until Codex recurring automation creation works. If native recurring automations become reliable, migrate the same prompt files to native jobs and unload the LaunchAgents.
