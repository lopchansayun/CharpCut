# Phase 1 controls update — 2026-10-13

The remaining Phase 1 implementation is in place. Final video-picker and force-stop/restart acceptance checks must still be performed on Android before declaring the phase complete. The owner confirmed that the preceding persistence update works correctly.

## Changelog

- Rust owns the playhead. Seeking clamps to the current duration, adds no history, and performs no autosave. Edits and undo/redo clamp the current position. Opening a project resets selection, playhead and history.
- Mute is a saved, undoable setting on the main video track. The UI reads its value from the engine snapshot. There is no real audio renderer yet, so this update persists the setting without claiming audible playback.
- The selected-clip toolbar adds **Move**. Choose the desired final position; Rust repacks the gapless track, preserving source ranges, clip identity and selection. Move and mute participate in undo/redo, autosave and explicit Save/Open.
- No-op mute/reorder and seek preserve redo and do not add undo history. Every successful project mutation is validated; refused operations restore the original project and selection.
- Saved-file schema is now 2. Existing version-1 projects migrate with unmuted tracks; malformed version-2 mute fields and newer versions are refused without replacing recovery data.
- The add button no longer inserts a fixed sample. A minimal Android document picker selects a video, copies it into app-private storage, validates its video stream and measures duration. Cancel changes nothing; failed imports remove partial copies and report the error. See the official [document picker](https://developer.android.com/training/data-storage/shared/documents-files) and [metadata API](https://developer.android.com/reference/android/media/MediaMetadataRetriever) documentation. Full Phase 2 media-library functionality is still pending.
- Regenerated the bridge with `flutter_rust_bridge_codegen` 2.13.0 and formatted generated output with Dart/rustfmt; no generated logic was edited by hand. Regenerated the actual Rust snapshot fixture with the new example command.
- Added desktop tests and an Android integration suite. The storage device test temporarily writes a test project and restores the pre-existing draft in `finally`; no explicit saved snapshot is changed. Back up the draft before device testing.

## Changed files

- Rust project model and migration: `rust/crates/timeline/src/lib.rs`.
- Rust engine and bridge API: `rust/crates/editor_api/src/engine.rs`, `api.rs`.
- Generated bridge: `rust/crates/editor_api/src/frb_generated.rs`, `apps/mobile/lib/src/rust/{api,frb_generated,frb_generated.io,frb_generated.web}.dart`.
- Snapshot fixture generator: `rust/crates/editor_api/examples/editor_snapshot.rs`.
- Dart engine boundary: `apps/mobile/lib/engine/{editor_engine,editor_state,rust_engine,project_session,video_importer}.dart`.
- Editor controls/import UI: `apps/mobile/lib/editor_screen.dart`.
- Android picker, copy and metadata: `apps/mobile/android/app/src/main/kotlin/com/example/charpcut/MainActivity.kt`.
- Test support/fixtures: `apps/mobile/test/support/{fake_engine,video_channel}.dart`, `test/fixtures/editor_state.json`.
- Tests: `apps/mobile/test/{engine_controls_test,editor_state_test,widget_test,project_session_test,rust_bridge_test}.dart`, `apps/mobile/integration_test/phase1_test.dart`.
- Integration-test SDK dependency: `apps/mobile/pubspec.yaml`, `pubspec.lock`.
- Documentation: README, roadmap, architecture and this changelog.

## Build and test commands

From the repository root, regenerate whenever the Rust API changes:

```powershell
.\scripts\setup-bridge.ps1
cd rust
cargo test
cargo build -p charpcut-editor-api
# Optional fixture regeneration:
cargo run --quiet -p charpcut-editor-api --example editor_snapshot |
  Set-Content ../apps/mobile/test/fixtures/editor_state.json -Encoding utf8
cd ..
.\scripts\build-android-lib.ps1
cd apps/mobile
flutter pub get
flutter test
dart analyze --format machine lib test integration_test
flutter build apk --debug
flutter test integration_test/phase1_test.dart -d <android-device-id>
flutter run -d <android-device-id>
```

Verified locally: **41 Rust tests**, **33 desktop Flutter tests**, and Android Rust libraries for **arm64-v8a, armeabi-v7a and x86_64**. The desktop bridge test exercises the regenerated native library, mute/reorder save/open, playhead and version-1 migration. Static analysis retains one pre-existing unused `badge` parameter warning in the editor.

Android device-suite and final APK results are recorded below after the checks finish.

## Remaining acceptance checks and limits

- On the device, pick a real video; confirm the imported duration and preserved file access after restart. Pick a second video, Move it, Mute, undo and redo, then Save. Force-stop and relaunch; resume the draft and open the explicit saved snapshot. Confirm order, source ranges and mute survive. The playhead intentionally restarts at zero.
- Test cancel, unsupported video and insufficient-storage paths in the native picker/copy flow. Desktop tests cover Dart cancellation/error handling; they do not validate every Android provider.
- Preview and simulated transport still use placeholders. Real decoding, audible mute and video export are later phases.
- Imported files remain in app-private storage even when a clip is deleted; media garbage collection, deduplication and storage management remain Phase 2/8. App uninstall or clearing app data removes local projects and media.
- Audio/image import, dimensions/orientation/frame-rate/audio metadata, thumbnails and the multi-project library remain Phase 2.
