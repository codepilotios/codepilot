# Screenshot Plan

No public screenshots are committed yet.

Use this checklist before adding screenshots to the repository, GitHub Pages, TestFlight, App Store metadata, README, or support docs:

- Use demo account names only, such as `Work`, `Personal`, or `Demo`.
- Use example hostnames only, such as `codepilot.example.com`.
- Use demo thread names and sample prompts that do not identify a person, company, private repository, customer, host, or unpublished product.
- Hide gateway bearer tokens and auth details.
- Hide local file paths unless the path is a generic example.
- Hide private thread names, prompts, uploads, and repository names.
- Hide Apple IDs, team IDs, bundle signing details, and TestFlight account details.
- Do not capture or publish Remote Desktop screens while that feature remains outside the supported public beta.
- Prefer clean beta flows: setup checklist, gateway status, iPhone connection, thread list, usage status, connector/plugin status, and file upload.

Recommended beta screenshot set:

- Mac menu bar status with demo account usage.
- Mac setup checklist showing ready and optional states.
- Cloudflare setup wizard using an example hostname.
- iPhone connection wizard for the public-beta Cloudflare path.
- iPhone thread list with demo thread names.
- iPhone usage and connector/plugin status with demo account names.
- File upload confirmation using non-private sample files.
- In-app local web preview from a purpose-built demo page with no source code, logs, paths, query values, or development data.

## Demo Capture Brief

Use one consistent fictional workspace across the set so the screens tell a coherent beta story:

- Account names: `Work`, `Personal`, and `Demo`.
- Gateway hostname: `codepilot.example.com`.
- Thread names: `Review parser tests`, `Improve setup copy`, and `Triage upload error`.
- Sample files: `sample-diff.txt` and `wireframe.png`, created only for the capture session.
- Connector/plugin names: use built-in product labels or clearly fictional demo labels; do not show connected personal services.

Capture only the app or simulator window. Exclude the desktop, menu bar extras outside CodePilot, browser history, notifications from other apps, device names, and unrelated windows. Keep the same appearance mode and demo state across related Mac and iPhone images.

## Acceptance Checklist

Before committing or attaching an image:

- Inspect the full-resolution image, including status bars, window chrome, menus, background edges, and reflections or overlays.
- Confirm every visible account, hostname, thread, file, repository, prompt, connector, and notification matches the fictional capture brief.
- Confirm no bearer token, auth value, QR payload, local path, Apple identifier, device name, personal service, or private desktop content is visible.
- Confirm Remote Desktop is absent from the entire set while it remains outside the supported public beta.
- Confirm any local web preview uses only the purpose-built demo page and reveals no local URL, session URL, source code, logs, paths, or query values.
- Write concise alt text that explains the beta workflow without repeating private or hidden values.
- Run `scripts/privacy-audit.sh` after adding the image files and their surrounding copy.

Create real screenshots only from sanitized demo data. Run the public presence privacy review before committing screenshots or metadata that references screenshots.
