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

- Working: home/editor/export settings screens (UI). Editing, mute, clip reorder and playhead use Rust. Android project storage includes autosave, draft recovery and Save/Open from the editor folder menu; Projects opens the draft or saved snapshot. The add button selects a real video, copies it into private storage and reads its duration. Schema-1 projects migrate to schema 2.
- New, awaiting manual verification: Android video preview/playback via Media3, including seeking, trimmed/split/reordered clips and audible mute. The previous filename-only preview has been replaced. See [the preview fix](docs/VIDEO_PREVIEW_FIX.md).
- Phase 2 media library, video/audio/image imports, metadata, thumbnails/filmstrips and project duplication are implemented, awaiting owner acceptance. Audio/image track placement, text/effects, real export and sharing remain future work. The export flow writes no video file. See [Phase 2 notes](docs/PHASE2_MEDIA.md).
- Verified locally: 41 Rust tests, 33 Flutter tests including a real desktop Rust-bridge disk round-trip, and Android native builds for all three ABIs. The owner confirmed that initial persistence works correctly. Final Android acceptance for this update is tracked in [the controls update](docs/PHASE1_CONTROLS.md); the earlier [persistence update](docs/PHASE1_PERSISTENCE.md) records its own verification.

## Documentation

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) - how the app is structured, the Flutter-Rust bridge, testing, and where to add code
- [docs/FEATURE_ROADMAP.md](docs/FEATURE_ROADMAP.md) - phased feature plan and progress (single source of truth)
- [docs/decisions/0001-render-engine.md](docs/decisions/0001-render-engine.md) - preview and export engine decision (approved: Android first, iOS later)

Multiple drafts, rename/delete, and home-screen draft lists have been implemented but not run or tested, per the owner’s request. See [draft storage notes](docs/MULTI_DRAFTS.md).

Phase 1 is now verified complete by the owner. Phase 2 changes have not been built, run, analyzed or tested by the assistant, as requested.
