# Beta-Focused Draft Posts and Comments

All copy below is unposted. Bracketed values must be replaced and verified during
final approval. Every draft uses the public `codepilotios` identity.

## r/GenAiApps

**Status:** Preferred first placement. Use the `iOS` flair and keep the post
link-free until a public beta URL is separately verified and approved.

**Title**

> I built an iPhone companion for Codex sessions running on your Mac — looking for beta workflow feedback

**Body**

> Disclosure: we build CodePilot; this is the project's account.
>
> CodePilot is a beta Mac + iPhone companion for people who already run Codex on
> a Mac they control.
>
> The idea is to leave the coding-agent session, credentials, and project files
> on the Mac while giving the iPhone a focused view of session status, threads,
> file uploads, notifications, and controls to steer or stop an active turn. The
> Mac runs a token-protected local gateway; remote access in the current beta
> uses a Cloudflare Tunnel controlled by the tester.
>
> We are trying to learn whether this solves a real generative-AI workflow
> problem or just moves a terminal-shaped problem onto a smaller screen. The
> feedback that would help most is:
>
> - when you would actually check or control a coding-agent session from your phone;
> - which remote actions feel useful versus risky;
> - whether the Mac gateway and iPhone connection model is understandable; and
> - what trust or setup concern would stop you from trying the beta.
>
> This is a feedback request, not an upvote request. Please do not share
> credentials, gateway tokens, private hostnames, private logs, screenshots, or
> project files. We will add an approved beta link only when public distribution
> is ready.

## r/BetaTests

**Status:** Use only after a maintainer confirms the identity is at least 24
hours old with at least 2 combined karma. Keep the post link-free until a direct
public beta URL is verified and approved.

**Title**

> Looking for setup feedback on CodePilot, an iPhone companion for Codex sessions on a Mac

**Body**

> Disclosure: we build CodePilot; this is the project's account.
>
> We are looking for a small number of beta testers who already run Codex on
> macOS and can give specific setup feedback.
>
> CodePilot leaves the Codex session, credentials, and project files on the Mac.
> A token-protected local gateway gives the iPhone companion narrow access to
> session status, threads, file uploads, notifications, and controls to steer or
> stop an active turn. For the current public-beta remote path, the tester
> connects through a Cloudflare Tunnel they control.
>
> The beta questions we most need answered are:
>
> - Is the Mac gateway and iPhone pairing flow understandable without live help?
> - Is it clear what the gateway token protects and how to recover from a rejected token?
> - Does checking or steering a coding-agent turn from a phone solve a real workflow problem?
> - Which trust or setup concern would make you stop testing?
>
> This is a feedback request, not an upvote request. Please do not share
> credentials, gateway tokens, private hostnames, private logs, screenshots
> containing private project data, or project files in replies.

## r/alphaandbetausers

**Status:** Use only after a same-day review of the live rules and recent
removals. Do not promise reciprocal testing or incentives. Keep the post
link-free until a direct public beta URL is verified and approved.

**Title**

> Looking for Mac-based Codex users to test an iPhone companion setup

**Body**

> Disclosure: we build CodePilot; this is the project's account.
>
> We are looking for a small number of beta testers who already run Codex on
> macOS and can give specific feedback on a Mac-to-iPhone setup.
>
> CodePilot keeps the Codex session, credentials, and project files on the Mac.
> A token-protected local gateway gives the iPhone companion narrow access to
> session status, threads, file uploads, notifications, and controls to steer or
> stop an active turn. For remote access in the current beta, testers use a
> Cloudflare Tunnel they control.
>
> The questions we most need answered are:
>
> - Can you complete the Mac gateway and iPhone connection flow without live help?
> - Is it clear what the gateway token protects and how to recover from a rejected connection?
> - Does checking or steering a coding-agent turn from a phone solve a real workflow problem?
> - Which setup or trust concern would make you stop testing?
>
> This is a feedback request, not an upvote request. Please do not share
> credentials, gateway tokens, private hostnames, private logs, screenshots
> containing private project data, or project files in replies.

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

**Status:** Use only on Saturday after confirming genuine prior participation,
current account eligibility, and that the account has not used the once-per-year
app allowance. Keep all three labeled sections below; current automated
moderation removes App Saturday posts that omit any of them.

**Title**

> Building an iPhone control surface for a coding agent running on a Mac

**Body**

> Disclosure: we build CodePilot; this is the project's account.
>
> **Tech Stack**
>
> The iPhone app is built with SwiftUI. It talks to a token-protected local
> gateway running on the user's Mac. A Mac menu-bar app surfaces local Codex
> account and usage state. For remote access in the current beta, the iPhone
> reaches the gateway through a user-controlled Cloudflare Tunnel and still
> authenticates with a bearer token.
>
> The client focuses on connection setup, gateway health, thread and session
> status, file uploads, usage and account state, notifications, and supported
> controls for steering or stopping active turns.
>
> **Development Challenge**
>
> The hard part was making remote control useful without pretending the phone
> owns the coding-agent session. The source of truth still lives on the Mac:
> credentials, project files, active turns, and account state. The UI also has
> to distinguish a tunnel failure, an unreachable gateway, and rejected
> authentication instead of collapsing them into one generic connection error.
>
> We kept the iPhone app as a narrow gateway client and modeled each setup
> failure as a recoverable connection state. We are now testing whether someone
> who did not build the system can understand what stays local, what is remote,
> what the token protects, and which recovery action to take.
>
> **AI Disclosure**
>
> AI-assisted. Coding agents have assisted with parts of the planning, copy, and
> implementation. Security-sensitive flows, gateway exposure, authentication,
> and release materials remain subject to human review.
>
> We would value feedback from iOS and macOS developers on whether this
> architecture and its connection states are understandable. It is an early
> beta; please do not put tokens, hostnames, account names, private screenshots,
> or unsanitized logs in public feedback.

## r/MacApps App Pile megathread

**Status:** Hold until the account has 10 genuine local karma, the 30-day
allowance is unused, and a maintainer has verified the current App Pile thread
and required format. Do not disclose a private identity to qualify for the main
feed.

> Disclosure: we build CodePilot; this is the project's account.
>
> **Answer:** CodePilot is a Mac menu-bar app and iPhone companion for people who
> already run Codex CLI on a Mac and want to check or control a session while
> away from the computer.
>
> **Better:** The coding-agent process and credentials stay on the user's Mac.
> The app adds saved account profiles, usage status, a local gateway, iPhone
> thread visibility, file uploads, supported turn controls, and notifications.
> The public beta is aimed at technical testers who are comfortable reviewing
> its setup, privacy, and security documentation.
>
> **Cost:** This draft is for beta testing only; no future pricing details are
> being announced. Project and build instructions: [PUBLIC_REPOSITORY_URL]
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
