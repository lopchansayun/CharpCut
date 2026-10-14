# CharpCut

CharpCut is an Android-first video editor built with Flutter, a Rust editing engine, and Android Media3 playback. Rust owns project data, timeline edits, undo/redo, and the saved JSON format. Flutter presents the editor; Android handles media import, thumbnails, and preview playback.

## Status

The project owner has run the app on an Android device and confirmed the working Phase 1–4 flows: project recovery and management, video/audio/image imports and a reusable media library, timeline thumbnails, and video preview with playback, seeking, fullscreen, fit, and inspection zoom. The owner performs device testing. On 2026-10-14, the automated suites passed: 46 Rust tests and 46 Flutter tests, including the desktop Rust bridge test.

**Phase 4 is complete and owner-accepted as of 2026-10-14.** It includes multi-select with atomic move/duplicate/delete operations, track reorder, and saved position, duration, scale, rotation, canvas crop, opacity, and per-clip volume. These extend clip trim/split/reorder, timeline zoom/snapping, and the video/audio/image/overlay lanes. Edits support autosave and undo/redo; schema 5 migrates schemas 1–4. The owner confirmed that Phase 4 works on the Android device. Phase 5 is next. Text, transitions, cover editing, and real export remain later work. The export screen currently writes no video file.

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
cargo build -p charpcut-editor-api
cd ..
.\scripts\build-android-lib.ps1
cd apps\mobile
flutter pub get
flutter test
flutter run
```

The Rust library must be built for Android before launching the app, and rebuilt after Rust source changes. Android/Kotlin changes require a full stop and `flutter run`; hot reload is insufficient. If the library is missing, the app shows a startup failure with the loader error.

When the bridge API in `rust/crates/editor_api/src/api.rs` changes, regenerate bindings with `scripts/setup-bridge.ps1`. Do not edit generated bridge files manually.

Before running Flutter tests after Rust changes, run `cargo build -p charpcut-editor-api` in `rust/` to refresh the host library used by the bridge test. Android library builds do not refresh this desktop test library.

Preview editing now supports selecting visible layers by touch or the layer menu, dragging their position, pinch scaling/rotation, a corner transform handle, and deletion for image/overlay layers. Main video uses direct gestures without floating delete/transform buttons. Deselect the layer to use inspection zoom. Trimming uses draggable timeline clip edges; the preview range slider has been removed. Gesture edits commit once on release and support undo/autosave. Numeric dialogs stay top-anchored above the keyboard while the editor keeps its layout. Playback ticks no longer round-trip the project through Rust; native players coordinate buffering and use gentle audio drift correction. The owner accepted the playback and gesture behavior in device testing. Fullscreen is playback-only, with editing and inspection gestures disabled. Fully stop and rerun after these Kotlin changes.

Audio, image, and overlay clips can overlap in time. Long-press and drag a secondary timeline clip horizontally to position it, or set its start in Properties. Overlaps occupy separate timeline rows. All active images/overlays compose in track order; the layer menu selects obscured items. Concurrent audio uses synchronized players, with one player per overlapping lane and per-clip volume. Trimming or deleting a secondary clip leaves neighboring clip positions unchanged. Full video export remains unimplemented.
