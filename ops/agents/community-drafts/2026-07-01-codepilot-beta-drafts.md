# CodePilot Community Drafts - 2026-07-01

Status: draft only. Do not post publicly without explicit maintainer approval.

Last rule review: 2026-07-17.

Review method: checked public Reddit rule/sidebar/search-visible pages, moderator
announcements, removal notices, and recent promotion threads on 2026-07-17.
Re-check each target immediately before any
human-approved posting because subreddit rules and megathread formats change.

Identity: `codepilotios`

Scope:
- Transparent beta-focused community promotion for CodePilot.
- No account creation.
- No public posting.
- No paid subscription, pricing, or future commercial claims.
- No private hostnames, tokens, personal emails, or unreleased links.

## Baseline Reddit Rules

Reddit-wide rules require users to follow community rules, participate authentically, avoid spam/content manipulation, and avoid deceptive identity use: <https://redditinc.com/policies/reddit-rules>

Reddit Help says promotional content is not automatically spam, but communities may ban promotion or apply a 10% self-promotion rule: <https://support.reddithelp.com/hc/en-us/articles/28012014962580-How-do-I-keep-spam-out-of-my-community>

Legacy Reddit self-promotion guidance still captures the expected culture: do not only submit your own links, do not ask for votes, disclose affiliation, and message moderators when unsure: <https://www.reddit.com/r/reddit.com/wiki/selfpromotion/>

Operational rules for this queue:
- Use the `codepilotios` identity only after a maintainer creates or approves it.
- Always disclose: "I am the maker / creator of CodePilot."
- Post at most one CodePilot promotion per community unless the community explicitly has a recurring self-promotion thread.
- Never ask for upvotes.
- Prefer comments in approved self-promotion or feedback threads before standalone posts.
- If a subreddit rule is ambiguous, ask moderators before posting.

## Communities Researched

| Community | Fit | Rule summary | Recommendation |
| --- | --- | --- | --- |
| `r/ChatGPTCoding` | High | Sidebar/wiki guidance routes service-style promotion to the designated self-promotion thread unless sponsorship is approved by modmail. The latest search-visible official thread reviewed permits project sharing, says one promotion per project, and prohibits selling model access. Sources: <https://www.reddit.com/r/ChatGPTCoding/> and <https://www.reddit.com/r/ChatGPTCoding/comments/1seq7us/self_promotion_thread/> | Best first Reddit placement once a current thread is confirmed. Use the self-promotion thread only unless moderators approve main-feed placement. Human approval before posting. |
| `r/TestFlight` | High once the public beta link is live | Live rules require posts to concern a TestFlight app, allow only TestFlight links, require an app-name title without tags such as `[Tester]` or `[Recruiting]`, require platform flair, and ask developers not to flood the feed with repeat posts. Source: <https://www.reddit.com/r/TestFlight/> | Best direct tester-recruitment target after the public TestFlight link is verified and approved. Use `iOS` flair, keep the title to the app name plus a short message, and put later updates in comments rather than reposting. |
| `r/appledevelopers` | Medium for technical discussion, low for beta recruitment | Posts must concern Apple-platform development. Promotional content must be limited and disclose the developer relationship; the sidebar explicitly directs TestFlight apps to `r/TestFlight`. Source: <https://www.reddit.com/r/appledevelopers/about/> | Do not cross-post the tester request here. Use `r/TestFlight` for recruitment. Consider this community later only for a substantive Apple-development discussion with maintainer approval and explicit maker disclosure. |
| `r/iosapps` | Low / ineligible for this beta | Requires 10 local karma, official App Store or TestFlight distribution, infrequent promotion, disclosure, and either trust/transparency qualification or the monthly megathread. Its current rules prohibit generative-AI and AI-wrapped apps when AI is a core feature. Source: <https://www.reddit.com/r/iosapps/about/> | Do not promote CodePilot here. The beta is built specifically around Codex workflows and therefore conflicts with the current AI-app exclusion, regardless of distribution readiness. |
| `r/codex` | High | Community is specifically for OpenAI Codex tools, including Codex CLI, IDE Extension, and Codex in the Cloud. Current rules require posts to be directly related to Codex, use the right flair, avoid low-effort rants, and not use bots. Recent AMA thread required subreddit karma for comments. Sources: <https://www.reddit.com/r/codex/about/> and <https://www.reddit.com/r/codex/comments/1us9ty9/ama_with_openais_codex_team/> | Strong fit, but treat as moderator-approval first because the post is maker-authored promotion. A maintainer must post manually; use text-only feedback framing unless mods approve a beta link. |
| `r/SideProject` | Medium-high | Community is for sharing and receiving constructive feedback on side projects. Current posts show beta/product feedback asks are common, and recent discussion warns that burying links in comments may be a rule-sensitive pattern. Sources: <https://www.reddit.com/r/SideProject/> and <https://www.reddit.com/r/SideProject/comments/1t7yd6x/post_your_project_looking_for_beta_testers_for_an/> | Good standalone beta feedback post after maintainer approval. Keep it story/feedback-first, avoid engagement manipulation, and use only approved links if links are allowed. |
| `r/iOSProgramming` | Medium | App posts are Saturday-only and limited to one post per app per year. The live App Saturday guide requires `Tech Stack Used`, `Development Challenge + How You Solved It`, and `AI Disclosure` content. The live rule also asks authors not to post without previous community activity but does not state a numeric karma threshold. Sources: <https://www.reddit.com/r/iOSProgramming/about/> and <https://www.reddit.com/r/iOSProgramming/wiki/app-saturday/> | Approval required. Hold until Saturday and do not use a new/inactive `codepilotios` account. |
| `r/swift` | Medium | Self-promotion must be under 5% of the account's posts and comments in the subreddit. It is not allowed with fewer than 5 posts/comments in the sub or when the account is under 2 months old. Source: <https://www.reddit.com/r/swift/about/> | Approval required. Do not post from a new `codepilotios` account. Use only after the account age, activity, and contribution-ratio thresholds are met. |
| `r/SwiftUI` | Low-medium for technical discussion only | Posts must be specifically about SwiftUI rather than general app feedback. App promotion is permitted only when source code is also provided, preferably through GitHub; low-effort showcases and questions without relevant code are discouraged. Source: <https://www.reddit.com/r/SwiftUI/about/> | Do not use for tester recruitment. Consider only a focused SwiftUI implementation discussion after the relevant source, code excerpt, and public repository have passed launch review. Maintainer approval is still required. |
| `r/macapps` | Medium | Current front page shows active app posts with pricing/flair labels and the July 2026 App Pile megathread. Rule/sidebar snippets require 10 local karma, megathread promotion unless the account qualifies through trust/transparency, post approval, and PCP-style promotion. Recent megathreads require pricing and link fields. Sources: <https://www.reddit.com/r/macapps/> and <https://www.reddit.com/r/macapps/comments/1uknpm8/megathread_the_app_pile_july_2026/> | Hold. Current pricing/link requirements conflict with the no-pricing/no-unapproved-link launch constraint unless moderators approve a beta-feedback exception. |
| `r/OpenAI` | Medium-low | Search-visible rule text says self-promotion should stay under a 1/10 guideline, direct self-promotional project links are not allowed, and promotional project posts need context in text posts. Other current rule snippets show stricter enforcement language against solicitation/self-promotion. Sources: <https://www.reddit.com/r/OpenAI/> and <https://www.reddit.com/r/OpenAI/about/> | Approval required. Avoid direct link posts. Consider only a non-link discussion post after moderator approval. |
| `r/MacOS` | Medium | The March 2026 Developer Saturday policy permits one self-promotional post per user each Saturday from 00:00 through 23:59 UTC. It explicitly welcomes accessible GitHub repositories, which are scanned by GitHub-Guard, and requires affiliation disclosure, useful context, and more than a low-effort link drop. Source: <https://www.reddit.com/r/MacOS/comments/1rsxzup/new_policy_introducing_developer_saturday/> | Candidate Saturday placement after maintainer approval. Use a transparent, context-rich beta-feedback post and link only to an approved, accessible, security-ready repository or distribution page. |
| `r/selfhosted` | Low-medium later | Mobile apps are allowed only as companions to a self-hosted backend. Promoted apps must be production-ready and documented. Projects under 3 months old may be posted only in the current New Project Megathread; Wednesday has a separate exception for dashboards and tools that help self-hosters. Source: <https://www.reddit.com/r/selfhosted/about/> | Hold for now. CodePilot has a local gateway and user-owned tunnel, but this is not primarily a general self-hosted server product; ask moderators only after public docs and production readiness are stronger. |
| `r/ClaudeAI` | Low | Project showcases must be built with Claude/Claude Code or specifically for Claude by the poster, be free to try, explain how Claude helped, use minimal promotional language, and come from an account with more than 50 karma. Source: <https://www.reddit.com/r/ClaudeAI/about/> | Do not post CodePilot promotion because this Codex-focused beta does not meet the stated Claude-project relevance gate. Only answer organically if directly relevant and approved by a maintainer. |
| Hacker News / Show HN | Medium | Show HN is for something people can try; HN asks submitters not to use it primarily for promotion and not to post generated or AI-edited comments. Sources: <https://news.ycombinator.com/showhn.html> and <https://news.ycombinator.com/newsguidelines.html> | Human rewrite required. Prepare outline only; do not paste AI-generated text. |
| Product Hunt | Medium later | Product Hunt recommends clear product pages, maker first comment, feedback requests rather than upvote requests, and warns against spamming communities where you have not been active. Sources: <https://www.producthunt.com/launch/preparing-for-launch> and <https://www.producthunt.com/launch/sharing-your-launch> | Not a first beta move. Requires account, launch assets, and pricing/status decisions, so hold for human approval. |

## Rules That Require Approval Before Posting

- Any public Reddit post, comment, or account profile must be approved by a maintainer per the launch plan.
- `r/ChatGPTCoding`: use the self-promotion thread for this run; main-feed promotion needs modmail/sponsorship approval.
- `r/TestFlight`: hold until there is a verified, approved public TestFlight link. Use only that link, select `iOS` flair, keep the title free of recruitment tags, and avoid repeat posts; later updates belong in the original post's comments.
- `r/appledevelopers`: do not duplicate the beta-recruitment post; its rules direct TestFlight apps to `r/TestFlight`. Any later technical post must be substantive, limited, transparent, and maintainer-approved.
- `r/iosapps`: do not promote this beta while the community's AI-core-app exclusion applies.
- `r/codex`: directly relevant to Codex, but ask moderators before a maker-authored beta-feedback post with any link; new-account karma filters may apply, and the explicit no-bots rule means a maintainer must post manually.
- `r/iOSProgramming`: Saturday-only app post, one app post per year, prior activity expected, and mandatory App Saturday content sections. The live rules do not currently state a numeric karma threshold, but eligibility must still be re-checked before posting.
- `r/swift`: do not self-promote from an account under 2 months old or with fewer than 5 posts/comments in the subreddit; self-promotional content must also remain below 5% of the account's posts and comments there.
- `r/SwiftUI`: no tester-recruitment post. A later technical discussion requires a concrete SwiftUI question, relevant source code, an approved public repository if linked, and maintainer approval.
- `r/macapps`: requires 10 local karma, trust/transparency qualification or monthly megathread use, and post approval. Current App Pile PCP format expects pricing and link fields, so posting needs moderator guidance while pricing/link status is intentionally withheld.
- `r/OpenAI`: direct self-promotional project links are not allowed; ask mods before any non-link discussion that mentions CodePilot.
- `r/MacOS`: Saturday-only from 00:00 through 23:59 UTC, one promotional post per user per week, explicit developer/affiliate disclosure, useful context, and no low-effort link drop. GitHub repositories are allowed but will be scanned, so any linked repository must be approved, accessible, and security-ready.
- `r/selfhosted`: hold until CodePilot has public docs and production-ready positioning that fits the community; projects under 3 months old belong only in the current New Project Megathread, and any maker-authored mention still needs moderator and maintainer approval.
- `r/ClaudeAI`: do not promote this Codex-focused beta because it does not meet the community's Claude-built/Claude-focused showcase gate; eligible showcases also require more than 50 account karma.
- Hacker News: a maintainer should write the actual comment manually because HN asks users not to post generated or AI-edited comments.
- Product Hunt: hold until account, maker identity, screenshots, launch URL, and current beta/pricing status are approved.

## Draft Reddit Profile

Profile display name:

```text
CodePilot iOS
```

Profile bio:

```text
Creator-run beta account for CodePilot: a Mac + iPhone companion for running Codex sessions from a Mac you control. I am here to collect setup feedback from Codex, iOS, and Mac automation users. Please do not send tokens, private logs, or credentials.
```

Pinned profile post draft:

```text
Hi, I am the maker of CodePilot.

CodePilot is in beta. It connects a Mac menu bar app, a local token-protected gateway, and an iPhone companion so Codex users can check account/usage state, continue sessions from iPhone, upload files, and steer or stop active turns from a Mac they control.

This account is for transparent beta feedback only. I will disclose my relationship whenever I mention CodePilot in a community. Please do not send credentials, bearer tokens, private logs, private hostnames, or files from your projects. If you try the beta and hit setup friction, sanitized steps and screenshots are the most useful feedback.
```

## Draft 1: `r/ChatGPTCoding` Self-Promotion Thread Comment

Posting target: current or next `r/ChatGPTCoding` self-promotion thread.

Approval status: needs maintainer approval before posting.

Rule notes:
- Fits the self-promotion thread.
- Use a comment in the thread, not a main-feed post, unless moderators explicitly approve otherwise.
- Do not mention selling access to models.
- Promote once per project.
- Expect karma filtering if `codepilotios` is new.

```text
Hi, I am the maker of CodePilot.

It is a beta Mac + iPhone companion for people already running Codex on their own Mac. The Mac side watches local Codex account/usage state and runs a token-protected local gateway. The iPhone side connects through a user-owned Cloudflare Tunnel to that gateway so you can check active account state, continue a session away from the desk, upload files, and steer or stop an active turn.

I am looking for a small number of beta testers who already use Codex CLI on macOS and are willing to give blunt setup feedback. The areas I most want tested are:

- whether the Mac gateway setup is understandable
- whether the iPhone connection/token flow is clear
- whether remote session control from iPhone actually solves a real workflow problem
- what errors or recovery steps are still confusing

This is a beta feedback request, and I am not asking for upvotes. If this matches your workflow, reply here with what setup you use for Codex today, and I will share the approved beta link once it is ready for public distribution.
```

Moderator note if main-feed placement is desired later:

```text
Hi mods, I am the maker of CodePilot, a beta Mac + iPhone companion for people running Codex from a Mac they control.

I saw the self-promotion rule and the designated promotion thread. For now I plan to use only that thread. If there is a future version that would be useful as a main-feed technical discussion, should I request sponsorship/mod approval first, or should all CodePilot mentions stay in the promotion thread?
```

## Draft 2: `r/codex` Moderator-First Beta Feedback Post

Posting target: `r/codex`

Approval status: moderator approval and maintainer approval required before posting. Do not include a beta link unless moderators explicitly approve it.

Rule notes:
- Must be directly related to OpenAI Codex tools.
- Keep it high-signal and feedback-focused.
- A maintainer must post manually; the subreddit explicitly prohibits bots.
- New-account subreddit karma restrictions may block comments/posts.
- Disclose maker relationship.

Moderator note draft:

```text
Hi mods, I am the maker of CodePilot, a beta Mac + iPhone companion for people who run Codex from a Mac they control.

I saw that r/codex requires posts to be directly related to Codex. Would a text-only beta feedback post be acceptable if it focuses on Codex CLI workflow, local gateway security, and setup clarity rather than a launch link?

I would disclose my relationship, avoid pricing language, avoid asking for votes, and only include a beta link if you explicitly approve that.
```

Discussion body if approved:

```text
I am the maker of CodePilot, and I am looking for feedback from people who use Codex on macOS.

The beta is built around a simple constraint: Codex stays on the Mac where the CLI session, auth files, account state, and project files already live. CodePilot adds a Mac menu bar app, a token-protected local gateway, and an iPhone client for status, files, notifications, and turn controls.

For the current public-beta iPhone path, a user-owned Cloudflare Tunnel reaches the loopback-only gateway, and the phone still has to authenticate to it. I am trying to keep the trust boundary explicit instead of turning this into a hosted Codex proxy.

The feedback I am looking for:

- Would an iPhone companion for Codex sessions solve a real workflow problem for you?
- What would you need to verify before trusting a local gateway that touches Codex session state?
- Which setup step would make you stop: gateway token, tunnel setup, iOS pairing, file upload, or remote turn control?
- What documentation would you expect before trying a beta?

This is a beta feedback request, not an upvote request. I am trying to make the beta safer and clearer before broader distribution.
```

## Draft 3: `r/SideProject` Standalone Feedback Post

Posting target: `r/SideProject`

Approval status: needs maintainer approval before posting.

Rule notes:
- Fit is strongest when framed as a specific side-project feedback request.
- Do not ask friends, testers, or communities to upvote.
- Include only an approved public link if links are allowed at posting time; otherwise ask for replies and share the approved beta link only after maintainer approval.

Title options:

```text
I built an iPhone companion for running Codex sessions from my Mac
```

```text
Looking for feedback on CodePilot, a Mac + iPhone beta for Codex users
```

Body:

```text
I am the maker of CodePilot, and I am looking for feedback from people who already use Codex on macOS.

The problem I kept running into: coding-agent work is tied to the Mac where the CLI session, auth files, account state, and project files live. If I walk away, I still want to see whether a turn finished, check usage/account state, upload a file from my phone, or stop/steer the session without exposing the whole machine broadly.

So I built a beta with three pieces:

- a Mac menu bar app for local account/usage state and account switching
- a local token-protected Python gateway on the Mac
- an iPhone app that connects to the gateway for threads, files, status, and turn controls

The current public-beta iPhone setup uses a user-owned Cloudflare Tunnel because the Mac gateway listens on loopback by default. The iOS app talks to that gateway, not directly to provider services.

I am asking for setup feedback, not votes. I am trying to learn whether the setup is understandable and whether this solves a real problem for Codex users.

If you use Codex CLI on macOS: what would make you trust or reject a setup like this? What would you want to see before installing a beta that touches local coding-agent credentials?
```

No-link variant if link placement is unclear:

```text
I am the maker of CodePilot, a beta Mac + iPhone companion for people who run Codex on a Mac.

I am not dropping a launch link here. I am trying to pressure-test the idea before wider distribution: Codex stays on the Mac, a token-protected loopback gateway exposes narrow session/status/file endpoints, and the current public-beta iPhone path reaches that gateway through a user-owned Cloudflare Tunnel for status, file upload, and turn controls. The provider login stays on the Mac.

For people who build or use developer tools: would this solve a real workflow problem, or would the local gateway/auth-file aspect make you reject it? What would you need documented before trying a beta?
```

## Draft 4: `r/iOSProgramming` App Saturday Post

Posting target: `r/iOSProgramming`, Saturday only.

Approval status: needs maintainer approval before posting; do not post from a new or inactive account.

Posting gate: Saturday only, one post per app per year, prior community activity,
and all three required sections below. Re-check the live rules before approval.

Title:

```text
I built a SwiftUI iPhone companion for controlling Codex sessions on my Mac
```

Body:

```text
I am the maker of CodePilot, a TestFlight beta for people who run Codex on a Mac and want an iPhone companion for setup/status/session control.

Tech Stack Used

The iOS app is built with SwiftUI. It talks to a token-protected local Python gateway running on the user's Mac. The Mac app is a menu bar utility that watches local Codex account and usage state. For the current public-beta path, the iOS app reaches the loopback-only gateway through a user-owned Cloudflare Tunnel and still authenticates with a bearer token.

The iPhone client currently focuses on connection setup, gateway health, thread/session status, file uploads, usage/account status, notifications, and controls for steering or stopping active turns.

Development Challenge + How You Solved It

The hard part was making remote control feel useful without pretending the phone owns the coding-agent session. The source of truth still lives on the Mac: auth files, project files, active turns, and account state.

The solution was to keep the iOS app as a gateway client rather than a direct provider client. The gateway exposes narrow endpoints for thread state, uploads, health, account status, and turn controls. The iOS app stores only the gateway URL and token locally, then treats every setup failure as a recoverable connection state instead of a generic network error.

The biggest area where I want feedback is onboarding clarity. A beta tester has to understand what is local, what is remote, what the token protects, and why they should not paste private logs or gateway tokens into issue reports.

AI Disclosure

AI-assisted. Parts of the project planning, copy, and implementation have been assisted by coding agents. Security-sensitive flows, gateway exposure, auth files, and release materials still need human review before broader release.

I am looking for feedback from iOS/macOS developers who use coding agents: does this architecture feel understandable and reviewable? What would you need to see before trusting a beta that bridges an iPhone to a local Mac coding-agent gateway?
```

## Draft 5: `r/swift` Technical Discussion Post

Posting target: `r/swift`

Approval status: hold until `codepilotios` is at least 2 months old and has at least 5 posts/comments in `r/swift`, or moderators approve. If eligible, self-promotion must remain below 5% of the account's posts and comments in the subreddit.

Posting note: do not include a link in the first version unless mods approve. Frame as a Swift architecture question, not a launch.

Title:

```text
How would you model connection state for a SwiftUI client to a local Mac gateway?
```

Body:

```text
I am working on CodePilot, an iPhone companion for a Mac app that runs a local token-protected gateway for Codex sessions. I am the maker, so this is related to my own project; no link unless the mods say that is appropriate.

The SwiftUI side has to represent a few states cleanly:

- no gateway URL/token configured
- local network URL configured but unreachable
- remote Cloudflare URL configured but gateway down
- token rejected
- gateway healthy but Codex account/session state unavailable
- active turn running
- active turn finished with logs/notifications available

The current direction is to keep connection setup separate from session state, so the UI does not treat every failure as a generic network error. The app should show a specific recovery step: start gateway, copy current token, check tunnel, rotate token, or retry health check.

For people building SwiftUI clients around local services: would you model this as one state machine, separate observable models, or typed error states flowing through async calls? I am trying to keep the UI honest without making onboarding feel like a debugger.
```

## Draft 6: `r/macapps` Monthly Megathread Comment

Posting target: `r/macapps` monthly promotion megathread unless account qualifies for main feed.

Approval status: needs maintainer approval before posting; hold until account has 10 local karma or mods approve.

Rule notes:
- Use only official distribution links.
- No redirects, referrals, invite links, or shortened URLs.
- Disclose maker relationship.
- Do not use "Free" flair or pricing language for a beta with undecided commercial model.
- Current App Pile PCP format expects pricing and a link; because this run must not imply paid subscription details or post unapproved links, ask moderators before using a beta-feedback exception.

Moderator note draft:

```text
Hi mods, I am the maker of CodePilot, a beta Mac + iPhone companion for people running Codex from a Mac they control.

I saw the PCP format for promotion and the pricing/link requirements. CodePilot is not ready for a pricing announcement, and I do not want to imply paid details or post an unapproved link.

Would a no-link beta-feedback comment be acceptable in the monthly thread if it clearly says there is no pricing announcement, discloses that I am the maker, and asks only for setup/trust feedback from Mac users? If not, I will hold until there is an official distribution link and approved pricing language.
```

Megathread body if approved:

```text
I am the maker of CodePilot, currently in beta.

It is a Mac menu bar app plus iPhone companion for people running Codex from a Mac they control. The Mac app tracks local account/usage state and coordinates safe account switching. The local gateway lets the iPhone companion check status, browse threads, upload files, and steer or stop active turns without moving the provider login to the phone.

The current public-beta iPhone path uses a user-owned Cloudflare Tunnel because the gateway listens on loopback, and the phone still needs the gateway token. The main thing I am looking for right now is setup and trust feedback from Mac users who already work with CLI coding agents.

I am trying to learn whether the beta setup is understandable and what security/setup explanation Mac users would expect before trying it.
```

## Draft 7: `r/OpenAI` Moderator-Approval Discussion

Posting target: `r/OpenAI`

Approval status: moderator approval required before posting. Do not include a link unless mods explicitly allow it.

Moderator note draft:

```text
Hi mods, I am the maker of CodePilot, a beta Mac + iPhone companion for people running Codex on their own Mac. I saw the rule/guidance against self-promotional direct project links, so I do not want to post a launch link.

Would a text-only discussion asking Codex users what they would need before trusting an iPhone-to-local-Mac gateway setup be acceptable? I would disclose that I am the maker and avoid pricing or promotional claims.
```

Discussion body if approved:

```text
I am the maker of CodePilot, a beta Mac + iPhone companion for people running Codex on their own Mac. I am not posting a link here; I am looking for product/security feedback from Codex users.

The beta architecture is: Codex stays on the Mac, a local token-protected gateway exposes narrow session/status/file endpoints, and the current public-beta iPhone path connects through a user-owned Cloudflare Tunnel for remote status, file upload, and turn controls.

For people who use Codex CLI seriously: what would you need to see before trusting a setup like this?

- clear source/build instructions?
- documented token storage and rotation?
- gateway endpoint list?
- no remote access by default?
- security review checklist?
- something else?

I am trying to make the beta setup transparent before inviting broader testers.
```

## Draft 8: `r/selfhosted` Moderator Note Only

Posting target: `r/selfhosted`

Approval status: hold. Moderator approval and maintainer approval required before any post or comment. Do not post until public docs are ready and the beta is production-ready enough for the community's self-promotion rule.

Reason for hold:
- CodePilot includes a local gateway and a user-owned tunnel for the current public-beta iPhone path, but it is not primarily a general self-hosted server product.
- Community rules expect promoted apps to be production-ready and documented.
- A project under 3 months old may be introduced only in the current New Project Megathread; confirm project age and the live megathread before any later submission.
- A beta feedback post could read as promotion unless moderators explicitly approve it.

Moderator note draft:

```text
Hi mods, I am the maker of CodePilot, a beta Mac + iPhone companion for people running Codex from a Mac they control.

It includes a token-protected local gateway and uses a user-owned Cloudflare Tunnel for the current public-beta iPhone path, but I am not sure it is a good fit for r/selfhosted because the product is mainly for Codex workflow control rather than general self-hosting.

Would you prefer that I hold off until public docs and production readiness are stronger? If a text-only architecture/security feedback post would be acceptable later, I would disclose that I am the maker, avoid pricing language, and avoid posting a promotional link unless you approve it.
```

## Draft 9: `r/MacOS` Developer Saturday Post

Posting target: `r/MacOS`

Approval status: needs maintainer approval before posting. Saturday only from
00:00 through 23:59 UTC; maximum one promotional post per user per week. Do not
post from an automated account.

Posting gates:
- Explicitly disclose the maker relationship.
- Explain what the app does and how it helps Mac users; do not drop only a link.
- Link only to an approved, accessible, security-ready GitHub repository or
  official distribution page. GitHub links are subject to GitHub-Guard scanning.
- Re-check the live policy immediately before posting.

Title:

```text
I built a Mac + iPhone companion for checking and steering Codex sessions away from my desk
```

No-link body draft:

```text
I am the maker of CodePilot, a beta Mac menu bar app plus iPhone companion for people who run Codex from a Mac they control.

The Mac remains the source of truth for Codex auth, project files, account state, and active sessions. The menu bar app shows local account and usage state, while a token-protected loopback gateway gives the iPhone client narrow access to session status, file uploads, notifications, and controls for steering or stopping an active turn. For the current public-beta path, the user connects the phone through a Cloudflare Tunnel they control; the provider login stays on the Mac.

I am looking for setup and trust feedback, not upvotes. For Mac users who run coding agents locally: which part would make you stop during setup—the gateway token, tunnel, iPhone pairing, or the idea of remote turn control? What security or recovery documentation would you expect before trying the beta?

I have left out the link in this draft until the public repository or distribution page has passed launch review. If approved at posting time, I will add only the direct official link.
```

## Draft 10: `r/TestFlight` Beta Post

Posting target: `r/TestFlight`

Approval status: hold until a maintainer approves final posting and a public
TestFlight link has been verified. The placeholder below must never be posted.

Posting gates:
- The title must be the app name with only an optional short message; do not use
  tags such as `[Tester]` or `[Recruiting]`.
- Select the `iOS` post flair.
- Include only the direct Apple TestFlight link. Do not include the repository,
  website, redirects, or other external links.
- Keep the body and follow-up comments focused on the TestFlight app.
- Do not repost routine updates; add them as comments on the original post.
- Do not request personal information. Ask testers to use approved feedback
  channels and remind them not to share tokens, private logs, or credentials.

Title:

```text
CodePilot - iPhone companion for Codex sessions on your Mac
```

Body:

```text
I am the maker of CodePilot. This is a beta iPhone companion for people who already run Codex on a Mac they control.

The iPhone app connects to CodePilot's token-protected gateway on the Mac. It can show session and account status, browse threads, upload files, receive turn-finished notifications, and steer or stop an active turn. Codex credentials and project files remain on the Mac. For remote access in the current beta, testers use a Cloudflare Tunnel they control.

I am especially looking for feedback on:

- whether the Mac-to-iPhone connection setup is understandable
- whether token and tunnel recovery steps are clear
- whether session controls are useful away from the desk
- which setup step would make you abandon the beta

Please do not send gateway tokens, credentials, private hostnames, private logs, or project files in Reddit messages or comments. Use only sanitized reproduction steps in feedback.

TestFlight: [APPROVED_PUBLIC_TESTFLIGHT_LINK]
```

## Hacker News / Show HN Outline

Do not paste this as-is. HN guidelines ask users not to post generated or AI-edited comments. A maintainer should rewrite manually if posting.

Possible title:

```text
Show HN: CodePilot - an iPhone companion for running Codex sessions from your Mac
```

Human rewrite outline:
- One sentence: CodePilot is a Mac menu bar app, local gateway, and iPhone companion for Codex users.
- Explain the personal problem: wanting to monitor/steer a long-running Codex session away from the desk without moving credentials to a hosted service.
- Explain the architecture: Codex remains on the Mac; the current public-beta iPhone path reaches the token-protected, loopback-only gateway through a user-owned Cloudflare Tunnel.
- Be explicit that this is beta and feedback is requested on setup/security clarity.
- Do not ask for upvotes.
- Be present to answer technical questions.
- Only post when there is a public URL that lets people actually try it.

## Product Hunt Draft Inputs

Hold until a maintainer approves launch assets and current beta status. Do not fill pricing or promo fields without approval.

Name:

```text
CodePilot
```

Tagline draft:

```text
iPhone companion for Codex sessions on your Mac
```

Description draft:

```text
CodePilot connects a Mac menu bar app, local gateway, and iPhone companion so Codex users can check account/usage state, continue sessions, upload files, and steer or stop active turns from a Mac they control. Currently beta-focused; feedback wanted on setup, trust, and remote workflow clarity.
```

First comment outline:
- I am the maker.
- Built because coding-agent sessions live on the Mac, but users sometimes need status/control away from the desk.
- Explain the three pieces: Mac app, gateway, iPhone app.
- Explain security posture briefly: token-protected loopback gateway, user-owned tunnel for the current public-beta iPhone path, and no sharing of tokens or private logs.
- Ask for feedback, not upvotes.
- Avoid pricing and subscription language.

## Feedback Tracking Template

For each public reply after approved posting:

```text
Source:
Link:
Type: setup | trust/security | feature | bug | positioning | pricing-question | other
Summary:
Action:
GitHub issue needed: yes/no
Escalation needed: yes/no
```

## Escalation Status

An escalation note was created at
`ops/agents/escalations/community-drafts.md`. Draft preparation is complete, but
all public posting remains blocked on maintainer approval. The `r/TestFlight`
draft additionally requires a verified public TestFlight link.
