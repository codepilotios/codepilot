# FAQ

## Who is CodePilot for?

CodePilot is for AI coding users who already run Codex CLI on a Mac and want an iPhone companion for visibility, file uploads, turn control, usage status, and account switching.

## Is CodePilot ready for production teams?

No. The current release track is a public beta. Use it on a trusted Mac, expect rough edges, and review the security and privacy docs before exposing the gateway outside your local network.

## Does CodePilot replace Codex CLI?

No. CodePilot uses Codex on your Mac. The iPhone app talks to the CodePilot gateway, and the gateway uses the active Codex setup on that Mac.

## Does it support Claude Code or other coding agents?

Not yet. The name is provider-neutral, but the first beta is Codex-focused. Future provider work should wait until the Codex setup, gateway, and support path are stable.

## Do I need Cloudflare?

Only for access away from your local network. Same-network iPhone access can use a local gateway URL. Remote access should use HTTPS and a private gateway token.

## Does CodePilot send my Codex credentials to a hosted service?

No hosted CodePilot service is required for the current beta. Credentials stay on the Mac unless you choose to expose the local gateway through infrastructure you control, such as Cloudflare Tunnel.

## What should I avoid posting in issues?

Do not post auth files, gateway tokens, private hostnames, personal account names, local file paths, private screenshots, Apple identifiers, or logs that contain any of those values.

## Is commercial use allowed?

Not without a separate written license. See the repository license, commercial license, and notice files.
