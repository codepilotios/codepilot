# Beta-Focused Draft Posts and Comments

All copy below is unposted. Bracketed values must be replaced and verified during
final approval. Every draft uses the public `codepilotios` identity.

## r/TestFlight

**Status:** Preferred first post after `[TESTFLIGHT_URL]` is publicly reachable.

**Title**

> CodePilot — iPhone companion for Codex CLI

**Link target**

> [TESTFLIGHT_URL]

**First comment**

> Disclosure: this is the CodePilot project account, and we build the app.
>
> CodePilot is a public beta for people who already run Codex CLI on a Mac and
> want to check threads, usage status, and account state from an iPhone. The beta
> also supports file uploads, turn controls where available, and turn-finished
> notifications through a gateway running on your own Mac.
>
> The current setup uses a user-controlled Cloudflare Tunnel for iPhone access.
> It is still a beta, so please use a trusted Mac and read the security and privacy
> notes before exposing the gateway.
>
> The feedback that would help most:
>
> - Where did setup become unclear?
> - Did the first iPhone connection work without recovery steps?
> - Which thread or turn control felt unreliable?
>
> Please do not share gateway URLs, tokens, account names, private screenshots,
> or unsanitized logs in public replies. The public issue tracker is
> [PUBLIC_REPOSITORY_URL]/issues.

## r/ChatGPTCoding self-promotion thread

**Status:** Use only as one comment in the current designated promotion thread.

> Disclosure: we build CodePilot; this is its project account.
>
> We are preparing a public beta of an iPhone companion for people who already
> use Codex CLI on a Mac. CodePilot keeps the coding-agent process and credentials
> on the user's Mac, then exposes threads, usage status, file uploads, turn
> controls, and notifications to the iPhone app through a local gateway.
>
> We are looking for feedback on setup clarity and connection reliability, not a
> polished-launch verdict. If that workflow matches how you use coding agents,
> the beta is here: [TESTFLIGHT_URL]
>
> Technical details and beta limitations: [PUBLIC_REPOSITORY_URL]
>
> Please keep tokens, hostnames, account names, private screenshots, and raw logs
> out of public feedback.

## r/Codex moderator approval request

**Status:** Draft modmail only. A maintainer must approve sending it, and a human
must send it. Do not automate.

**Subject**

> Permission to share a transparent CodePilot TestFlight beta post?

**Body**

> Hello moderators,
>
> We maintain CodePilot, a Mac menu-bar app, local gateway, and iPhone companion
> for existing Codex CLI users. We would like to ask before sharing a single,
> clearly disclosed beta post requesting feedback on setup and reliability.
>
> The post would link to the public TestFlight beta and public source-available
> repository, make no pricing claims, and explicitly warn testers not to share
> credentials, gateway URLs, private screenshots, or unsanitized logs. We would
> use the CodePilot project identity and would not automate the post or repeat it.
>
> Is that appropriate for r/Codex? If so, which flair and format should we use?

### r/Codex post, only if moderators approve

**Title**

> We built an iPhone companion for Codex CLI and are looking for beta setup feedback

**Body**

> Disclosure: we build CodePilot; this is the project's account.
>
> CodePilot is a Mac menu-bar app, local gateway, and iPhone companion for people
> who already run Codex CLI on a Mac. The current beta lets you inspect threads
> and usage status, upload files, steer or stop turns where supported, and receive
> turn-finished notifications from an iPhone.
>
> It does not replace Codex CLI. The coding-agent process and credentials remain
> on the Mac. Remote access currently uses a user-controlled Cloudflare Tunnel,
> so this is for testers who are comfortable reviewing the setup and security
> notes.
>
> We would especially value feedback on three things:
>
> 1. Can you connect the iPhone within five minutes after Mac setup?
> 2. Are connection and authentication failures actionable?
> 3. Which remote control feels least dependable?
>
> TestFlight: [TESTFLIGHT_URL]
>
> Technical details and known beta limits: [PUBLIC_REPOSITORY_URL]
>
> Please do not post gateway URLs, tokens, account names, private screenshots, or
> unsanitized logs. We will be here to answer technical questions and collect
> reproducible feedback.

## r/iOSProgramming App Saturday

**Status:** Use only on Saturday after confirming genuine prior participation and
that the account has not used the once-per-year app allowance.

**Title**

> Building an iPhone control surface for a coding agent running on a Mac

**Body**

> Disclosure: we build CodePilot; this is the project's account.
>
> We have been working on a public beta that pairs a Swift iPhone app with a
> coding-agent gateway running on the user's Mac. The interesting iOS problem was
> less about chat UI and more about making remote state understandable: active
> turns, stale authentication, file-transfer progress, background notifications,
> and controls that may or may not be supported by the current agent state.
>
> The product boundary is deliberately explicit. Codex CLI and its credentials
> stay on the Mac. The phone talks to a local gateway, with remote access currently
> routed through a user-controlled Cloudflare Tunnel. The UI has to distinguish a
> tunnel failure, an unreachable gateway, and rejected authentication without
> collapsing them into a generic connection error.
>
> We are now testing whether the onboarding explains that architecture clearly
> enough for someone who did not build it. If you test developer tools on both a
> Mac and iPhone, we would value feedback on:
>
> - connection-state wording;
> - recovery actions after an auth or gateway failure;
> - whether remote turn controls communicate their limits clearly.
>
> TestFlight: [TESTFLIGHT_URL]
>
> Source and architecture notes: [PUBLIC_REPOSITORY_URL]
>
> It is an early beta. Please do not put tokens, hostnames, account names, private
> screenshots, or unsanitized logs in public feedback.

## r/MacApps monthly megathread

**Status:** Hold until the account meets local-karma and approval requirements.
Adapt to the current mandatory template before approval.

> Disclosure: we build CodePilot; this is the project's account.
>
> CodePilot is a Mac menu-bar app and iPhone companion for people who already run
> Codex CLI on a Mac. The Mac app manages saved account profiles, shows usage
> status, and coordinates a local gateway so the iPhone can inspect threads,
> upload files, control turns where supported, and receive notifications.
>
> The public beta is aimed at technical testers who are comfortable reviewing its
> setup, privacy, and security documentation. We are looking specifically for Mac
> first-run and menu-bar feedback.
>
> Project and build instructions: [PUBLIC_REPOSITORY_URL]
> TestFlight companion: [TESTFLIGHT_URL]

## r/SideProject build-story draft

**Status:** Optional later post; do not publish alongside the focused beta posts.

**Title**

> The hard part of an iPhone coding-agent companion was explaining where everything runs

**Body**

> Disclosure: we build CodePilot; this is the project's account.
>
> We expected the hard part of an iPhone companion for Codex CLI to be remote chat.
> In practice, the harder problem was making the system boundary legible.
>
> The agent and credentials stay on the user's Mac. A local gateway exposes the
> selected threads and controls. The iPhone is a client. Remote access currently
> uses infrastructure controlled by the tester. When something fails, the app has
> to say whether the tunnel, gateway, authentication, or active turn is the actual
> blocker.
>
> That changed our beta goal from “more features” to a measurable setup question:
> can a new tester connect the phone and send a first prompt within five minutes,
> without private support?
>
> We are preparing a public beta now. For people who have shipped a tool with a
> local service plus mobile client: what explanation or diagnostic made that
> architecture click for users?
>
> Technical context: [PUBLIC_REPOSITORY_URL]

## Show HN

**Status:** Hold until a maintainer confirms the beta is directly usable and can
remain present to answer questions.

**Title**

> Show HN: CodePilot – control Codex CLI sessions from an iPhone

**Submission URL**

> [PUBLIC_REPOSITORY_URL]

**Opening comment**

> We built CodePilot because Codex CLI sessions often keep running on a Mac while
> the person using them steps away. It is a Mac menu-bar app, local Python gateway,
> and Swift iPhone client for inspecting threads and usage, uploading files,
> steering or stopping turns where supported, and receiving completion
> notifications.
>
> The core design constraint is that Codex and its credentials remain on the Mac.
> The current remote path uses a user-controlled Cloudflare Tunnel. That makes the
> architecture inspectable, but setup and failure recovery are still rough enough
> that we are calling this a beta.
>
> The repository includes build instructions, architecture, security notes, and
> current limitations. We would value feedback on whether the trust boundary is
> understandable and whether the setup diagnostics are specific enough.
>
> Disclosure: this is the CodePilot project account, and we built it.

