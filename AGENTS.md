# AGENTS.md

Guidance for AI coding agents working on **AquaMoon (水月音)** — a cross-platform (Android / iOS / macOS / Windows / Linux / Web) music player built with Flutter. Package name is `aquamoon`; UI copy is Chinese-first with a "水墨禅意" (ink-wash Zen) aesthetic.

## Commands

```bash
flutter pub get                          # install deps
flutter analyze                          # static analysis — must report ZERO issues (CI gate)
flutter test                             # full unit test suite
flutter test test/lrc_parser_test.dart   # single file, e.g.
flutter run -d macos                     # run (also: android / ios / windows / linux / chrome)
```

CI (`.github/workflows/ci.yml`) runs `flutter analyze` + `flutter test` on every push/PR to main. Releases are triggered by pushing a tag (`git tag vX.Y.Z && git push origin vX.Y.Z`); bump `version:` in `pubspec.yaml` and add `.github/release_notes_vX.Y.Z.md`.

## Architecture & layer rules

Dependency direction: `views/` → `providers/` → (`services/` + `core/`). Never skip a layer (e.g. views must not touch Hive or the audio handler directly).

- `lib/core/audio/` — audio engine. `audio_player_handler.dart` (`SoundCraftAudioHandler`) integrates just_audio + audio_service and exposes state via streams; `audio_session_coordinator.dart` handles audio focus, call interruptions, and headphone-unplug pause.
- `lib/core/utils/` — pure Dart, no Flutter imports where possible (`lrc_parser.dart`, `metadata_extractor.dart` — hand-written ID3v1/v2 & FLAC parser). Keep these platform-independent and unit-tested.
- `lib/models/` — immutable models with `copyWith` and **manual** `toMap`/`fromMap` serialization. No Hive codegen or `TypeAdapter`s — everything is stored as plain maps in untyped boxes.
- `lib/services/storage_service.dart` — the only Hive access point (5 boxes: songs, playlists, history, settings, stats).
- `lib/providers/` — Riverpod wiring. `storageServiceProvider` and `audioHandlerProvider` are override-only: they throw `UnimplementedError` unless overridden in `main.dart`'s `ProviderScope`. Follow that pattern for any new service needing pre-`runApp` init.
- `lib/views/` — UI only. Theming lives in `lib/core/theme/app_theme.dart` (Material 3, light + dark — update both).

## Gotchas

- **Legacy "SoundCraft" naming is intentional where it touches persistence.** The app was renamed from SoundCraft, so Hive box names are `soundcraft_*` and some classes keep the prefix (e.g. `SoundCraftAudioHandler`, `SoundCraftApp`, root `soundcraft.iml`). **Never rename the box names** — that would orphan existing users' libraries. Match the existing `SoundCraft`-prefixed class names rather than introducing a third style.
- **Model schema evolution:** persisted objects are plain maps read back via `fromMap`. When adding a field to `Song` (or any stored model), also add it to `toMap` and read it in `fromMap` with a nullable cast + sensible default, so old persisted data still loads.
- `metadata_extractor.dart` must stay pure Dart (no platform channels) — it runs on all six platforms and in tests.
- Platform config is load-bearing: Android `AndroidManifest.xml` (foreground media service, `READ_MEDIA_AUDIO`), iOS `Info.plist` (`UIBackgroundModes: audio`), macOS entitlements (`network.client` for online lyrics, user-selected file read/write for import/export). Web is a build target but file-scan/metadata features are desktop/mobile-centric.
- `analysis_options.yaml` uses `flutter_lints` defaults; analyzer output must stay at zero issues (currently clean).
