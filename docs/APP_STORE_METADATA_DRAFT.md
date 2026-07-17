# App Store Metadata Draft

This draft is for TestFlight and App Store Connect preparation only. Do not submit it for review without maintainer approval for privacy, legal, pricing, age rating, export compliance, and final public positioning.

## App Name

CodePilot

## Subtitle

Codex companion for your Mac

## Promotional Text

Public beta for Codex CLI users who want iPhone access to thread status, file uploads, turn controls, notifications, and coding-agent sessions on their own Mac.

Character count: 160 of 170.

## Description

CodePilot is a Mac menu bar app, local gateway, and iPhone companion for AI coding users who already run Codex CLI on a Mac.

Use the iPhone app to check active account status, follow threads, upload files, steer or stop supported turns, receive turn-finished notifications, and connect through your own Cloudflare Tunnel setup. The Mac stays in your control, and the current beta does not require a hosted CodePilot account service.

The beta is focused on setup clarity, connection reliability, privacy-safe diagnostics, and practical remote workflows for existing Codex CLI users. Some internals still use Codex-specific names while the public CodePilot product surface is prepared for broader provider support later.

CodePilot handles local coding-agent credentials and gateway access. Review the privacy, security, install, and support docs before exposing the gateway outside your local network.

## Keywords

Codex,coding agent,developer tools,Mac,iPhone,remote coding,AI coding,gateway,Cloudflare

Character count: 88 of 100.

## What To Test

Install CodePilot on a Mac that already runs Codex CLI, create a saved account profile, start the gateway, connect the iPhone app with the gateway URL and token, and verify thread visibility, file upload, turn control, notifications, and setup recovery messages.

Please report whether Cloudflare Tunnel setup, gateway connection, or token entry was the step that failed. Remove account names, gateway URLs, tokens, hostnames, local paths, private prompts, screenshots, and logs containing private data before sharing feedback.

## Support URL

Requires maintainer approval before TestFlight external testing or App Store submission. Candidate destination after GitHub Pages is enabled and verified: `https://codepilotios.github.io/codepilot/SUPPORT.html`.

## Privacy URL

Requires maintainer approval before TestFlight external testing or App Store submission. Candidate destination after GitHub Pages is enabled and verified: `https://codepilotios.github.io/codepilot/PRIVACY.html`, generated from [Privacy](PRIVACY.md).

## Screenshot Requirements

Use only sanitized demo data:

- Demo account names such as `Work`, `Personal`, or `Demo`.
- Example hostnames such as `codepilot.example.com`.
- No tokens, auth details, private prompts, local paths, Apple identifiers, personal account names, private screenshots, or live desktop contents.

See the [App Store screenshot checklist](../metadata/screenshots/README.md).

## Approval Gates

- Final public positioning.
- Privacy policy and support URL.
- App Store privacy labels.
- Age rating.
- Export compliance.
- TestFlight external testing and App Store review submission.
- Pricing, subscription, or commercial-use claims.
