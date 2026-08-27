# LED Necklace Control

A Flutter app for controlling a BLE LED necklace.

## iOS cloud builds

This repository includes `codemagic.yaml` with two iOS workflows:

- `ios_unsigned_check`: builds the iOS app on Codemagic without Apple code signing. This can be run before creating an Apple Developer account and is useful for catching Flutter, CocoaPods, and Xcode compile problems.
- `ios_testflight`: builds a signed `.ipa` and uploads it to TestFlight. This needs an Apple Developer Program membership, an App Store Connect app, a distribution signing setup, and the Codemagic App Store Connect integration.

Before running `ios_testflight`, replace the placeholder values in `codemagic.yaml`:

- `REPLACE_WITH_CODEMAGIC_APP_STORE_CONNECT_KEY_NAME`
- `com.lednecklacecontrol.app`

Also update the iOS bundle identifier in `ios/Runner.xcodeproj/project.pbxproj` from `com.lednecklacecontrol.app` to the same final bundle ID.

## Local checks

Run these before pushing:

```sh
flutter pub get
flutter analyze
flutter test
```
