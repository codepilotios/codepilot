# Public Profile and Response Library

These are drafts for the `codepilotios` identity. Do not create or modify an
account, profile, post, or comment without explicit maintainer approval.

## Profile bio

> Official project account for CodePilot, a Mac and iPhone companion for Codex
> CLI. Sharing transparent public-beta updates and collecting technical feedback.
> Built by the CodePilot maintainers.

## Short disclosure

> Disclosure: we build CodePilot; this is the project's account.

Use the disclosure in every post or comment that mentions or links CodePilot,
even when someone else asks for a recommendation.

## Reusable replies

### What does it replace?

> It does not replace Codex CLI. Codex continues to run on your Mac. CodePilot adds
> a menu-bar app, a local gateway, and an iPhone client for remote visibility and
> controls. Disclosure: we build CodePilot.

### Where do credentials go?

> The current beta does not require a hosted CodePilot service. Codex credentials
> remain on the Mac. The iPhone authenticates to the user's gateway. Remote testers
> should review the security notes before exposing that gateway. Disclosure: we
> build CodePilot.

### Why does the beta use Cloudflare Tunnel?

> The Mac gateway listens on local loopback by default. The current public-beta
> setup uses a tunnel controlled by the tester so the iPhone can reach it without
> opening an inbound port. It adds setup complexity, which is one of the areas we
> are actively testing. Disclosure: we build CodePilot.

### Is it open source?

> It is source-available for noncommercial use, but it is not OSI open source
> because commercial use is restricted. The repository includes the exact license
> terms. Disclosure: we build CodePilot.

### Does it support other coding agents?

> Not in the first beta. The public name is provider-neutral, but the current
> implementation is focused on Codex CLI. We do not want to promise broader
> provider support before the Codex setup and reliability work is stable.
> Disclosure: we build CodePilot.

### How should a tester report a problem?

> Please include the step that failed, what you expected, what happened, and the
> app/build version. Do not post gateway URLs, bearer tokens, account names,
> private screenshots, local paths, or raw logs. Sanitize first, then use the
> public issue tracker at [PUBLIC_REPOSITORY_URL]/issues. Disclosure: we build
> CodePilot.

### What kind of feedback is useful?

> The most useful beta feedback is concrete: where setup became unclear, whether
> recovery text led to a fix, and which thread or turn action did not match your
> expectation. Reproduction steps help much more than a general rating.
> Disclosure: we build CodePilot.

### What will it cost?

> The current community outreach is only about the public beta and product
> reliability. We are not making pricing claims here. Disclosure: we build
> CodePilot.

## Moderation-safe response principles

- Answer the question before mentioning CodePilot.
- Mention CodePilot only when it is directly relevant; never hijack another
  developer's post or an unrelated support thread.
- Disclose the relationship every time.
- Do not debate removals in public. If moderators request a change, stop and ask
  a maintainer to review it.
- Do not ask for upvotes, coordinated comments, referrals, or private contact.
- Do not repeat a link after someone declines or expresses disinterest.
- Turn reproducible product feedback into a GitHub issue only after removing all
  private information.
