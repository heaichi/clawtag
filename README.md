<div align="center">

# ClawTag · 爪札

**A local-first, fully offline pet diary for Android and iOS.**

Your data stays on your phone — no account, no cloud, no tracking.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Release](https://img.shields.io/github/v/release/heaichi/clawtag)](https://github.com/heaichi/clawtag/releases)
[![Flutter](https://img.shields.io/badge/Flutter-3.44-02569B.svg)](https://flutter.dev)

[中文说明](README.zh-CN.md)

</div>

---

## Features

- **Pet profiles** — photos, breed, birthday, weight and adoption date, with automatic age stages for cats and dogs.
- **Photo & video diary** — up to nine attachments per entry, plus mood, weather and tags.
- **Smart reminders** — vaccines, deworming, grooming, vet visits or custom, with reliable local notifications.
- **Medication courses** — follow a multi-day course and check off every dose as you give it.
- **Recently deleted** — undo a deletion and restore reminders, diary entries or pets.
- **Data export** — export everything to a JSON file you own.
- **Dark mode** and a small, dependency-light codebase.

## Install

Download the latest APK from the [Releases](https://github.com/heaichi/clawtag/releases) page and install it on your device. Android 7.0 (API 24) or newer.

## Build from source

```bash
flutter pub get
flutter analyze          # must report 0 issues
flutter test             # unit, database, widget and layout tests
flutter run -d <device>  # debug build with hot reload
```

Release builds:

```bash
scripts/build.bat        # arm64 only (fastest)
scripts/build.bat full   # universal APK: armv7 + arm64
```

Release signing reads `android/key.properties`; the file and any `*.jks` are git-ignored. Without them the build falls back to the debug keystore.

## Tech stack

| | |
|---|---|
| Framework | Flutter 3.44 / Dart 3.12 |
| Storage | sqflite (SQLite) with versioned, additive migrations |
| State | Provider |
| Platform | flutter_local_notifications, image_picker, video_player, permission_handler |

No backend, no analytics, no third-party network calls.

## Privacy

- All records live in the app's private SQLite database and file directory on your device.
- Camera, photo library and microphone access are used only when you attach media.
- Notification permission is used only for the reminders you create.
- Uninstalling the app removes its data, so export a backup first.

## Project layout

```
lib/
├── core/        database, theme, pure utilities
├── screens/     pet, diary, reminder, settings screens
├── widgets/     reusable cards and components
└── services/    media, permissions, notification scheduling
test/            unit, database, widget and layout tests
```

## Contributing

Issues and pull requests are welcome. Please keep `flutter analyze` clean and `flutter test` green.

## License

[MIT](LICENSE)
