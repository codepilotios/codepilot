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

Build Codex Phone and upload it to the Sample-only TestFlight group

### ios testflight_internal

```sh
[bundle exec] fastlane ios testflight_internal
```

Upload Codex Phone for internal TestFlight only

### ios add_configured_tester

```sh
[bundle exec] fastlane ios add_configured_tester
```

Add Sample to the configured Codex Phone external TestFlight group

### ios create_app_record

```sh
[bundle exec] fastlane ios create_app_record
```

Create the Codex Phone App Store Connect record if needed

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
