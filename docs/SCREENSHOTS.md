# Screenshot Plan

No public screenshots are committed yet.

Create real screenshots only from sanitized demo data. Run `scripts/privacy-audit.sh` before committing screenshot references, then manually inspect every image because the script cannot read pixels.

## Demo Data Contract

Use only these public-safe values while capturing screenshots:

- Account names: `Work`, `Personal`, `Demo`.
- Gateway host: `codepilot.example.com`.
- Project names: `demo-ios-app`, `demo-gateway`, `demo-docs`.
- Thread names: `Fix onboarding copy`, `Review gateway status`, `Draft beta notes`.
- Upload examples: `sample-log.txt`, `demo-screenshot.png`, `release-notes.md`.

Do not show real local paths, private repository names, prompts, hostnames, account identifiers, Apple IDs, team IDs, signing details, TestFlight account details, gateway bearer tokens, auth file contents, QR secrets, or live desktop content.

## Beta Screenshot Manifest

Capture the initial public beta set with these filenames under `docs/assets/screenshots/`:

| File | Surface | Required safe state |
| --- | --- | --- |
| `mac-menu-status.png` | Mac menu bar status | Demo account usage only; no personal menu bar extras in frame. |
| `mac-setup-checklist.png` | Mac setup checklist | Ready and optional states visible; no local paths or private account details. |
| `mac-cloudflare-wizard.png` | Cloudflare wizard | Uses `codepilot.example.com`; no tunnel IDs, tokens, or dashboard account data. |
| `ios-connection-cloudflare.png` | iPhone connection setup | Cloudflare mode only for public beta; no Same Network setup path shown. |
| `ios-thread-list.png` | iPhone thread list | Demo thread and project names only. |
| `ios-file-upload.png` | File upload confirmation | Demo filenames only; no document previews with private content. |
| `ios-remote-desktop-permission.png` | Remote Desktop permission state | Pending or approval copy only; no live desktop pixels. |

## Review Checklist

Before committing or publishing screenshots:

- Confirm every image uses the manifest filename and safe state above.
- Inspect the full-resolution image, not only a thumbnail.
- Verify no private names, email addresses, hostnames, local usernames, machine names, paths, tokens, account identifiers, repositories, prompts, Apple identifiers, or private screenshots appear.
- Verify cropped windows do not expose private menu bar items, browser tabs, terminal prompts, desktop files, notifications, or status menus.
- Update README, GitHub Pages, TestFlight, or App Store metadata only after the images pass this review and maintainer approval covers that use.
