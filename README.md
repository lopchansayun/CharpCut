# CharpCut

CharpCut is an Android-first video editor built with Flutter, a Rust editing engine, and Android Media3 playback. Rust owns project data, timeline edits, undo/redo, and the saved JSON format. Flutter presents the editor; Android handles media import, thumbnails, and preview playback.

## Status

The project owner has run the app on an Android device and confirmed the working Phase 1–3 flows: project recovery and management, video/audio/image imports and a reusable media library, timeline thumbnails, and video preview with playback, seeking, fullscreen, fit, and inspection zoom. The owner performs device testing; the assistant did not run or test the recent Phase 2–3 changes.

The editor currently places **video clips** on one main timeline track. Audio and images can be imported and inspected in the library; placing and editing them on tracks belongs to later phases. Text, transitions, cover editing, saved crop/scale changes, and real export are also future work. The export screen currently writes no video file.

See the [feature roadmap](docs/FEATURE_ROADMAP.md) for the phase checklist and remaining work. The [architecture guide](docs/architecture.md) explains the implementation, and the [render-engine decision](docs/decisions/0001-render-engine.md) records the Android-first approach.

## Prerequisites

- Flutter with Dart 3.9 or newer
- Rust via [rustup](https://rustup.rs)
- Android Studio, Android SDK, and Android NDK (`ANDROID_NDK_HOME`)
- An Android device or emulator
- PowerShell for the helper scripts in `scripts/`

## Build and run

From the repository root:

```powershell
cd rust
cargo test
cd ..
.\scripts\build-android-lib.ps1
cd apps\mobile
flutter pub get
flutter test
flutter run
```

The Rust library must be built for Android before launching the app, and rebuilt after Rust source changes. Android/Kotlin changes require a full stop and `flutter run`; hot reload is insufficient. If the library is missing, the app shows a startup failure with the loader error.

When the bridge API in `rust/crates/editor_api/src/api.rs` changes, regenerate bindings with `scripts/setup-bridge.ps1`. Do not edit generated bridge files manually.
