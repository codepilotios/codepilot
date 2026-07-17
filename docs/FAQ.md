# FAQ

## Who is CodePilot for?

CodePilot is for AI coding users who already run Codex CLI on a Mac and want an iPhone companion for visibility, file uploads, turn control, usage status, and account switching.

## How do I access the beta?

The Mac app currently builds from source on macOS 13 or later using the repository installation guide. The iPhone companion requires iOS 17 or later and access to an approved beta build; CodePilot does not yet advertise a public TestFlight invitation or App Store download.

## Is CodePilot ready for production teams?

No. The current release track is a public beta. Use it on a trusted Mac, expect rough edges, and review the security and privacy docs before exposing the gateway outside your local network.

## Does CodePilot replace Codex CLI?

No. CodePilot uses Codex on your Mac. The iPhone app talks to the CodePilot gateway, and the gateway uses the active Codex setup on that Mac.

## Does it support Claude Code or other coding agents?

Not yet. The name is provider-neutral, but the first beta is Codex-focused. Future provider work should wait until the Codex setup, gateway, and support path are stable.

## Do I need Cloudflare?

Yes for the public beta iPhone setup path. The Mac gateway listens on local loopback by default, so the iPhone app uses a Cloudflare Tunnel URL until CodePilot provides an explicit LAN-binding mode with firewall and trust guidance.

## Is Remote Desktop included in the public beta?

No. Remote Desktop remains outside the supported public beta while its device-pairing and session-authorization enforcement is being completed and independently verified. Do not enable it in beta builds yet.

## Does CodePilot send my Codex credentials to a hosted service?

No hosted CodePilot service is required for the current beta, and Codex credentials stay on the Mac. When you use Cloudflare Tunnel, gateway traffic and connection metadata pass through Cloudflare under your Cloudflare account configuration; the gateway still requires its bearer token.

## What should I avoid posting in issues?

Do not post auth files, gateway tokens, private hostnames, personal account names, local file paths, private screenshots, Apple identifiers, or logs that contain any of those values.

Use the repository templates to [report a beta bug](https://github.com/codepilotios/codepilot/issues/new?template=bug_report.md) or [request a beta improvement](https://github.com/codepilotios/codepilot/issues/new?template=feature_request.md). Read the [security guidance](SECURITY.md) before reporting a sensitive finding.

## Is commercial use allowed?

Not without a separate written license. See the repository license, commercial license, and notice files.
