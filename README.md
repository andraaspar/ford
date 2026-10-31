# ford

Parallel translation editor. The plan is in [plan.md](plan.md).

## Requirements

- Flutter SDK (stable, 3.47)
- JDK 17
- Android SDK with `platform-tools`, which provides `adb`
- On the phone: USB debugging turned on, with this computer allowed

`flutter` and `adb` have to be on your `PATH`. If they aren't, they are in the `bin` folder of the Flutter SDK and in `platform-tools` in the Android SDK.

## Build and install on the phone

Connect the phone over USB and check that it's listed:

```sh
adb devices
```

Build the release APK and install it, replacing the installed version:

```sh
flutter build apk --release
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

`-r` keeps the app's settings: the root folder, the last chapter and the reading positions. Your translations aren't affected either way, because they live in the root folder, outside the app.

The first time the app opens, it asks for "All files access". Allow it, then choose the root folder.

The release build is signed with the debug key for now, so it can only be installed over builds signed with the same key. If `adb install` fails with `INSTALL_FAILED_UPDATE_INCOMPATIBLE`, remove the old version first, which also clears the app's settings:

```sh
adb uninstall hu.parditka.ford
```

## Run while developing

Find the phone's ID, then run on it with hot reload:

```sh
flutter devices
flutter run -d <device-id>
```

To run on the desktop instead, use `flutter run -d linux`.

## Test

```sh
flutter test
flutter analyze
```
