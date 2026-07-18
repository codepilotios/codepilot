# FAQ

## Who is CodePilot for?

CodePilot is for AI coding users who already run Codex CLI on a Mac and want an iPhone companion for visibility, file uploads, turn control, usage status, and account switching.

## How do I access the beta?

The Mac app currently builds from source on macOS 13 or later using the repository installation guide. The iPhone companion requires iOS 17 or later and access to an approved beta build; CodePilot does not yet advertise a public TestFlight invitation or App Store download.

## How do I update the beta?

For the Mac source build, finish active turns, pull the latest approved branch, rebuild the app, and rerun the menu bar and gateway installers. The gateway installer waits rather than interrupting an active phone turn. Follow the [Mac update steps](INSTALL_MAC.md#update-a-source-build) and review the [changelog](CHANGELOG.md) for setup changes.

Install iPhone updates only through the approved beta distribution channel you already use. This repository does not advertise a public TestFlight invitation or App Store download yet.

## Is CodePilot ready for production teams?

No. The current release track is a public beta. Use it on a trusted Mac, expect rough edges, and review the security and privacy docs before exposing the gateway outside your local network.

## Does CodePilot replace Codex CLI?

No. CodePilot uses Codex on your Mac. The iPhone app talks to the CodePilot gateway, and the gateway uses the active Codex setup on that Mac.

## Does it support Claude Code or other coding agents?

Not yet. The name is provider-neutral, but the first beta is Codex-focused. Future provider work should wait until the Codex setup, gateway, and support path are stable.

## Do I need Cloudflare?

Yes for the public beta iPhone setup path. The Mac gateway listens on local loopback by default, so the iPhone app uses a Cloudflare Tunnel URL until CodePilot provides an explicit LAN-binding mode with firewall and trust guidance.

## Does my Mac need to stay awake and online?

Yes. The CodePilot gateway, Codex CLI, and Cloudflare Tunnel run from your Mac. The iPhone companion cannot reach sessions while that Mac is asleep, offline, or no longer running the gateway or tunnel. The current beta does not provide a hosted relay or wake the Mac remotely.

## What happens to files I upload from iPhone?

Uploads pass through your Cloudflare Tunnel and are saved under the CodePilot state directory on the Mac. They are not removed automatically after a turn. Delete files you no longer need, and remember that a selected attachment can be sent to Codex and OpenAI when you use it in a turn. See [Privacy](PRIVACY.md) for the full beta data flow.

One turn can include up to eight attachments, with a 25 MB limit per file and a 50 MB combined limit. These are request limits, not an automatic cleanup policy.

## Can CodePilot switch accounts while a turn is running?

Automatic switching waits for active turns to finish. Avoid manually changing Codex auth files while turns are running; use CodePilot's account controls so a new profile is applied safely to later turns.

## Are notifications required?

No. Turn-finished notifications and Live Activities are optional. Background delivery requires APNs to be configured for the gateway, and notification permission and Live Activities are separate iOS controls.

If notifications do not arrive, confirm notification permission is enabled for CodePilot, the Mac gateway and Cloudflare Tunnel are still reachable, and APNs is configured for the gateway. See [Troubleshooting](TROUBLESHOOTING.md#turn-finished-notifications-do-not-arrive).

## Is Remote Desktop included in the public beta?

No. Remote Desktop remains outside the supported public beta while its device-pairing and session-authorization enforcement is being completed and independently verified. Do not enable it in beta builds yet.

## Does CodePilot send my Codex credentials to a hosted service?

No hosted CodePilot service is required for the current beta, and Codex credentials stay on the Mac. When you use Cloudflare Tunnel, gateway traffic and connection metadata pass through Cloudflare under your Cloudflare account configuration; the gateway still requires its bearer token.

## Does all coding data stay on my Mac?

No. CodePilot runs its gateway on your Mac, but Codex is still an online coding service. Prompts, conversation context, and selected attachments can be sent to OpenAI through Codex according to your Codex account and configuration. Cloudflare processes gateway traffic when you use the supported remote iPhone path, and Apple processes notification or Live Activity data when those features are enabled. See [Privacy](PRIVACY.md) for the beta data-flow summary.

## What should I avoid posting in issues?

Do not post auth files, gateway tokens, private hostnames, personal account names, local file paths, private screenshots, Apple identifiers, or logs that contain any of those values.

Use the repository templates to [report a beta bug](https://github.com/codepilotios/codepilot/issues/new?template=bug_report.md) or [request a beta improvement](https://github.com/codepilotios/codepilot/issues/new?template=feature_request.md). Read the [security guidance](SECURITY.md) before reporting a sensitive finding.

## Is commercial use allowed?

Not without a separate written license. See the repository license, commercial license, and notice files.
