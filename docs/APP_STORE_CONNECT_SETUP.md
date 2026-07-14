# App Store Connect Setup

These notes are for maintainers preparing CodePilot iOS distribution. They are not part of ordinary iOS first-run setup.

Do not run these steps in unattended public-launch audits unless a maintainer explicitly approves Apple account access and release actions.

## Local Credentials

Fastlane credentials belong in the ignored file:

```sh
ios/CodexPhone/fastlane/.env
```

Do not commit this file, Apple sessions, API keys, signing certificates, provisioning profiles, or generated logs containing account identifiers.

## App Store Record

To create an Apple web session for App Store record creation, run from the repo root:

```sh
scripts/apple-spaceauth.sh
```

Paste the generated `FASTLANE_SESSION` into `ios/CodexPhone/fastlane/.env`, then run:

```sh
scripts/create-app-store-record.sh
```

The App Store Connect API key can manage signing resources, but Apple still requires an Apple ID web session for creating a new App Store app record.

## Boundaries

Prepare metadata, release notes, screenshots, and signing changes as local files or draft pull requests first.

Do not upload TestFlight or App Store builds, submit for review, change pricing, alter legal metadata, or publish releases without explicit maintainer approval.
