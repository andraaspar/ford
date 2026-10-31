# ford

Ford is an editor for translating long texts, such as books, one paragraph at a time. Each paragraph of the original sits side by side with its translation, so you can read and edit the two together. It's made mainly for Android phones, and also runs on the Linux desktop.

Your work is stored as plain text files in a folder you choose, not inside the app. You can back them up, sync them between devices, or edit them with other programs.

## What it does

- **Rows:** a chapter is a list of rows, each holding a source paragraph, its translation and an optional remark. Rows can be split, merged, inserted, deleted, and moved within a chapter or to another one.
- **Editing:** tap text to edit it. Changes are saved automatically, with undo and redo.
- **Chapters and folders:** chapters can be organized in nested folders, which you can create, rename, reorder, move and delete in the app. A chapter's first row is its title, and a folder is named after the first row of its first file.
- **Search:** exact text search, optionally matching case, across the source, the translation or the remarks. It can cover one chapter, a folder or a selection, and tapping a result jumps to the highlighted match.
- **Reading position:** the app remembers the last chapter and your place in each chapter on each device.
- **Changes from elsewhere:** the app notices when a file changes on disk and reloads it. If that change meets edits you haven't saved, it lets you keep yours, take the other version, or save yours as a copy. A banner points out any conflict copies left in the folder by a sync tool.

## Chapter files

A chapter is a `.txt` file with one block per row, separated by blank lines:

```
@ k3f9a
< Source paragraph.
> Translated paragraph.
! A remark. This line is optional and can repeat.
```

`@` is the row's ID, which stays with it through edits. `<` is the source, `>` is the translation and `!` is a remark. Lines starting with `#` are comments and are ignored.

## Importing from Obsidian

Chapters kept as Obsidian Markdown files, each with a three-column table of source, translation and remark, can be converted from the command line. The app itself has no import screen. Without a target folder, this only prints a report and writes nothing:

```sh
dart run tool/import_obsidian.dart <source-folder> [<target-folder>]
```

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

## App icon

The icon is drawn by `tool/generate_icon.dart`. To change it, edit the design in that script and run it from the project root. It rewrites the Android, Windows and Linux icon files, and `assets/icon/app_icon.svg`:

```sh
dart run tool/generate_icon.dart
```
