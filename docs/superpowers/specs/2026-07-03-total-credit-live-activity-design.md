# Total Credit Live Activity Design

## Goal

Add an optional CodePilot Live Activity that shows aggregate Codex credit across all configured accounts. It must remain useful while the iOS app is backgrounded and must never interfere with account switching, turns, or ordinary notifications.

## User Experience

- Settings contains a `Total Credit Live Activity` toggle.
- Enabling the toggle starts one Live Activity immediately.
- Disabling the toggle ends and removes all CodePilot credit activities.
- Tapping the Live Activity opens CodePilot at the main thread list.
- The app prevents duplicate activities and restores the enabled behavior after relaunch.

### Lock Screen

Use the approved informative layout:

- `CodePilot credit` title
- aggregate remaining percentage
- progress bar using the same status color as the in-app credit bar
- usable-account count
- freshness text

When no credit remains, replace the percentage presentation with `Refilling credit` and show the next allowance countdown. When every account requires authentication, show `Auth refresh needed`. Do not display a fabricated percentage when usage is unavailable.

### Dynamic Island

- Compact and minimal regions show the CodePilot bolt and aggregate percentage.
- Expanded presentation shows the progress bar and usable-account count.
- The expanded bottom region uses an 8-point horizontal inset so its progress bar and account count remain clear of the Dynamic Island's curved edges.
- Refill and authentication states use concise equivalents of the Lock Screen labels.

## Architecture

Use a hybrid update model:

1. The iOS app owns ActivityKit authorization, activity lifecycle, local reconciliation, and deep-link handling.
2. A widget extension renders the Lock Screen and Dynamic Island presentation from shared ActivityKit attributes.
3. The gateway stores Live Activity push tokens separately from ordinary APNs device tokens.
4. The gateway sends Live Activity APNs updates whenever its account-usage snapshot materially changes.
5. The app also reconciles the activity whenever it launches, enters the foreground, manually refreshes usage, or changes the setting.

The shared content state is provider-neutral and contains only display data:

- aggregate status kind
- percentage and normalized progress when available
- usable and reported account counts
- next refresh time and label when refilling
- generated timestamp

No account credentials, gateway bearer tokens, account identifiers, or private paths are included in ActivityKit payloads.

## State Mapping

The Live Activity must derive its state from the same aggregate-credit calculation used by `AggregateCreditBar`.

- `available`: at least one reported allowance has remaining credit.
- `refilling`: no reported allowance has credit and a future reset is known.
- `authenticationRequired`: all otherwise usable accounts have stale authentication.
- `unavailable`: no reliable allowance or reset data is available.

Shared calculation code must return presentation-neutral values. SwiftUI colors, symbols, and strings remain in their respective app or widget views.

## Lifecycle

- Enabling requests Live Activity authorization if needed and starts one activity.
- Existing CodePilot credit activities are reused or stale duplicates are ended.
- The activity push token is registered with the authenticated gateway endpoint.
- Token changes replace the previous registration.
- Turning the feature off ends local activities and unregisters their gateway tokens.
- If iOS ends an activity or invalidates its token, the gateway removes the unusable registration after the corresponding APNs response.
- If the preference remains enabled but no activity exists, CodePilot creates a replacement on the next foreground reconciliation.

ActivityKit system duration limits are respected. CodePilot does not claim the activity will remain indefinitely without the app being opened again.

## Gateway API

Add authenticated endpoints for registering and unregistering Live Activity push tokens. Registrations are scoped by activity identifier and APNs environment. Ordinary notification device registrations remain unchanged.

Usage-state publication should be deduplicated by a stable content-state fingerprint so polling does not create unnecessary APNs traffic. A push failure must not fail usage refresh, account switching, or turn processing.

## Deep Link

The widget uses a CodePilot URL that routes to the root thread list. Opening the URL dismisses any presented settings or status flow rather than opening a particular thread.

## Error Handling

- Unsupported or disabled Live Activities: keep the setting off and show concise explanatory text in Settings.
- Activity creation failure: leave normal app operation untouched and expose a recoverable Settings error.
- Gateway registration failure: keep the local activity, retry on the next reconciliation, and mark freshness honestly.
- Invalid or expired APNs token: remove it from gateway storage.
- Missing usage data: show `Credit unavailable`, never `0%`.
- Missed gateway push: local reconciliation corrects state when the app next becomes active.

## Testing

### iOS Unit Tests

- aggregate usage maps to every Live Activity state correctly
- payload values are bounded and omit private account data
- enabling creates one activity and repeated reconciliation does not duplicate it
- disabling ends activities and unregisters tokens
- stale and changed push tokens are handled correctly
- deep link resolves to the thread-list destination

ActivityKit system calls should sit behind a narrow protocol so lifecycle behavior can be tested without running a real Live Activity.

### Gateway Tests

- token registration requires gateway authentication
- token records remain separate from ordinary notification registrations
- unchanged state does not send duplicate pushes
- changed state sends the expected APNs event payload
- terminal APNs responses remove invalid registrations
- push errors do not interrupt account status or switching workflows

### Build Verification

- iOS unit tests
- gateway test suite
- simulator build for the app and widget extension
- physical-device check of Lock Screen, compact island, expanded island, toggle, and deep link
- required CodePilot OTA build, manifest check, and IPA reachability check

## Out Of Scope

- Starting or steering Codex turns from the Live Activity
- Per-account controls in the Live Activity
- Replacing ordinary turn-finished notifications
- Claiming continuous updates beyond ActivityKit and APNs lifecycle guarantees
