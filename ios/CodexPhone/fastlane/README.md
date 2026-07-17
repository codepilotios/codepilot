fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios build

```sh
[bundle exec] fastlane ios build
```



### ios testflight

```sh
[bundle exec] fastlane ios testflight
```

Build CodePilot and upload it to the configured TestFlight group

### ios testflight_internal

```sh
[bundle exec] fastlane ios testflight_internal
```

Upload CodePilot for internal TestFlight only

### ios distribute_latest

```sh
[bundle exec] fastlane ios distribute_latest
```

Distribute an already uploaded CodePilot build to the configured external TestFlight group

### ios add_configured_tester

```sh
[bundle exec] fastlane ios add_configured_tester
```

Add the configured tester to the configured CodePilot external TestFlight group

### ios create_app_record

```sh
[bundle exec] fastlane ios create_app_record
```

Create the CodePilot App Store Connect record if needed

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
