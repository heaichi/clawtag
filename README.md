# ClawTag 🐾 — the pet diary that stays on your phone

<p align="center">
  <img src="docs/assets/logo.png" width="112" alt="ClawTag">
</p>

<p align="center">
  <a href="https://github.com/heaichi/clawtag/releases"><img src="https://img.shields.io/github/v/release/heaichi/clawtag?style=flat-square&label=release" alt="Release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green?style=flat-square" alt="License: MIT"></a>
  <img src="https://img.shields.io/badge/platform-Android%20%7C%20iOS-3DDC84?style=flat-square" alt="Platform: Android and iOS">
  <a href="https://flutter.dev"><img src="https://img.shields.io/badge/Flutter-3.44-02569B?style=flat-square&logo=flutter" alt="Flutter 3.44"></a>
  <a href="../../issues"><img src="https://img.shields.io/badge/PRs-welcome-brightgreen?style=flat-square" alt="PRs welcome"></a>
</p>

<p align="center"><a href="README.zh-CN.md">中文说明</a></p>

ClawTag is an offline-first pet diary for Android and iOS. It keeps the day-to-day of every animal you live with: profiles, photo and video entries, care reminders and medication courses. Flutter on the front, a local SQLite database underneath, and nothing in between.

**Yours, with no catch.** There is no account, no sign-in, no sync and no analytics. Everything ClawTag knows lives in the app's private database and file directory on your device. Nothing is uploaded, nothing is phoned home, and the only way data leaves the phone is an export you run yourself.

## Install

**Android** — download the latest APK from [Releases](https://github.com/heaichi/clawtag/releases) and install it. Android 7.0 (API 24) or newer; the published build is a single universal APK for armv7 and arm64.

**iOS** — there is no App Store build yet. Build from source (below); the Xcode project is in `ios/`.

## Quick start

1. **Add a pet** — photo, species, birthday, adoption date.
2. **Write an entry** — text, up to nine photos or videos, mood, weather, tags.
3. **Create a reminder** — pick a type such as vaccine, deworming or vet visit, then a date.
4. **Optional:** switch on *medication course* to follow a multi-day prescription and tick off each dose.

Everything you delete lands in **Recently deleted**, where it can be restored.

## What's inside

| | |
|---|---|
| 🐾 **Pet profiles** | Photos, breed, birthday, weight and adoption date, with automatic age stages for cats and dogs |
| 📝 **Photo & video diary** | Up to nine attachments per entry, plus mood, weather and tags |
| 🔔 **Care reminders** | Vaccines, deworming, grooming, vet visits or custom, on a repeating schedule |
| 💊 **Medication courses** | One medicine, several doses a day, across as many days as the prescription says |
| 🗑 **Recently deleted** | Every deletion is reversible — reminders, entries and pets |
| 🎬 **Built-in player** | Videos play inline, full screen, portrait or landscape |
| 📤 **Data export** | Write everything out to a JSON file you own |
| 🌙 **Dark mode** | Follows the system, or pick light or dark yourself |

## How it works

- **Flutter 3.44 / Dart 3.12**, single codebase for Android and iOS.
- **sqflite** — one local SQLite database. Migrations are additive only: the schema never loses a column, and upgrades backfill existing rows, so an update never costs you data.
- **Deletes are soft.** A removed record keeps its history and waits in *Recently deleted* until you restore it or delete it for good.
- **Completion is never automatic.** A reminder is only done when you say it is done; overdue items keep their real date and keep reminding you.
- **Notifications are local.** Exact alarms are requested when the system allows it and fall back to inexact scheduling when it does not — a missing permission degrades the reminder instead of breaking the app.
- **No backend.** The app never opens a socket. Third-party packages are limited to notifications, media picking, video playback and permissions.

## Privacy

- Records live in the app's private SQLite database and file directory.
- Camera, photo library and microphone are used only when you attach media.
- Notification permission is used only for the reminders you create.
- **Uninstalling removes the data.** Export a backup first if it matters to you.

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

Signing reads `android/key.properties`; the file and any `*.jks` are git-ignored, and the build falls back to the debug keystore when they are absent. Forks should change `applicationId` in `android/app/build.gradle.kts` and the bundle identifier in `ios/Runner.xcodeproj`.

## Project layout

```
lib/
├── core/        database, theme, pure utilities
├── screens/     pet, diary, reminder and settings screens
├── widgets/     reusable cards and components
└── services/    media, permissions, notification scheduling
test/            unit, database, widget and layout tests
android/ ios/    platform projects
```

## Contributing

Issues and pull requests are welcome. Before opening a PR, please make sure `flutter analyze` is clean and `flutter test` passes; the test suite covers the database invariants (soft deletes, cascades, migrations) and the layout of every card on small and large screens.

## License

[MIT](LICENSE) © heaichi
