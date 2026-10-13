# CharpCut

A free mobile video editor. The UI is built with Flutter and the editing engine (project model, edits, undo/redo, saved-file format) is written in Rust.

CharpCut aims to be a practical editor with no paywall: import clips, edit them on a timeline, preview, and export a real video file. Most of that is still planned; see [Current status](#current-status).

## Tech stack

Verified against the repository files:

| Part | Technology |
| --- | --- |
| Mobile UI | Flutter, Dart SDK `>=3.9.0 <4.0.0` (`apps/mobile/pubspec.yaml`), Material 3 |
| Editing engine | Rust, edition 2021, Cargo workspace in `rust/` (crates `charpcut-timeline`, `charpcut-editor-api`) |
| Bridge | `flutter_rust_bridge` 2.13.0 (Dart package and Rust crate; code generator installed by `scripts/setup-bridge.ps1`) |
| Android native build | `cargo-ndk` and the Android NDK, via `scripts/build-android-lib.ps1` |

## Prerequisites

- Flutter (stable) with Dart 3.9 or newer
- Rust via [rustup](https://rustup.rs)
- Android Studio with the Android SDK and the NDK (SDK Manager > SDK Tools > NDK). Set `ANDROID_NDK_HOME` to the NDK folder.
- A real Android device or emulator
- Windows PowerShell for the helper scripts in `scripts/` (they are `.ps1` files; on other systems run the equivalent commands inside them by hand)

## Setup and run

From the repository root:

```powershell
# 1. Run the Rust tests
cd rust
cargo test

# 2. Build the Rust library for Android (needed once, and after every change under rust/)
cd ..
.\scripts\build-android-lib.ps1

# 3. Run the Flutter tests and the app
cd apps\mobile
flutter pub get
flutter test
flutter run
```

If `libcharpcut_editor_api.so` was not built, the app opens a "CharpCut could not start" screen instead of the editor. Build the library (step 2) and run again.

Only when `rust/crates/editor_api/src/api.rs` changes, regenerate the bridge bindings with `.\scripts\setup-bridge.ps1` (details in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md#regenerating-the-bindings)). `.\scripts\check-rust.ps1` runs `cargo test` for the Rust workspace.

## Current status

- Working: home screen, editor screen, export settings panel and export-complete screen (UI). The editor starts empty and every edit (add, select, split, trim, delete, undo, redo) goes through the Rust engine.
- Placeholders: media import (the add button inserts a 3-second placeholder clip), real preview and playback, thumbnails, audio and text tools, effects, saving projects to disk, real export and sharing. The export flow only plays the screens; it writes no file.
- Verified: `cargo test` in `rust/` (19 engine + 13 timeline tests pass). The project owner reports that `flutter test` passes, the Android library builds, and add, trim, split, undo and redo work on a device. Next: Phase 1 in the roadmap.

## Documentation

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) - how the app is structured, the Flutter-Rust bridge, testing, and where to add code
- [docs/FEATURE_ROADMAP.md](docs/FEATURE_ROADMAP.md) - phased feature plan and progress (single source of truth)
- [docs/decisions/0001-render-engine.md](docs/decisions/0001-render-engine.md) - preview and export engine decision (approved: Android first, iOS later)
