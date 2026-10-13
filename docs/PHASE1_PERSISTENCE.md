# Phase 1 persistence update — 2026-10-13

Phase 1 has started; this update implements project persistence. It does not complete the entire phase.

## Changelog

- Added `ProjectSession`, which serializes engine calls and storage writes. Rust remains the authoritative project model; Dart writes the versioned JSON returned by the engine without changing its saved-file schema.
- Autosave follows every successful project edit, new/open, undo and redo. Selection does not write a file; rejected edits and invalid project files do not replace the recovery draft.
- Android stores JSON in app-private `files/projects/` using `AtomicFile` on a background executor. No storage permission or extra dependency is needed.
- The editor folder menu offers **Save project** and **Open saved project**. Save keeps one explicit snapshot separately from the rotating draft. Projects offers **Resume draft** and **Open saved project**. New video offers to resume an existing draft or start fresh. Replacing a different draft with a saved snapshot requires confirmation.
- Autosave failures keep the successful edit visible and show a retry message. Save retries persistence. Read/open errors are shown without silently resetting the current project.
- Added tests for recovery in a new session, explicit snapshot isolation, undo/redo persistence, refused edits, corrupt/newer files, write ordering, storage failures, replacement cancellation, UI recovery, and a real Rust bridge disk round-trip.

## Changed files

- `apps/mobile/lib/engine/project_session.dart`: persistence boundary, serialized engine adapter, Android channel.
- `apps/mobile/lib/main.dart`: production engine wrapped in the persistent session.
- `apps/mobile/lib/editor_screen.dart`: Save/Open menu and storage errors.
- `apps/mobile/lib/home_screen.dart`: recovery and saved-project entry points.
- `apps/mobile/android/app/src/main/kotlin/com/example/charpcut/MainActivity.kt`: native atomic storage channel.
- `apps/mobile/test/support/fake_engine.dart`: test project JSON save/open support.
- `apps/mobile/test/project_session_test.dart`: session, channel and widget tests.
- `apps/mobile/test/rust_bridge_test.dart`: real native bridge plus disk persistence test.
- `README.md`, `docs/ARCHITECTURE.md`, `docs/FEATURE_ROADMAP.md`, this file: implementation status and verification.

## Build and tests

From the repository root:

```powershell
cd rust
cargo test
cargo build -p charpcut-editor-api
cd ../apps/mobile
flutter test
dart analyze --format machine lib test
flutter build apk --debug
```

Verified in this update: 32 Rust tests, 26 Flutter tests (including the actual Windows DLL bridge test), and a successful Android debug APK build. No Rust API or generated binding changed, so regenerating bindings or rebuilding the Android Rust libraries was unnecessary; the build used the existing packaged libraries. The bridge test skips with a reason when the desktop library has not been built. `CHARPCUT_TEST_LIBRARY` can point to an alternate desktop library.

Static analysis reports one existing warning: the unused optional `badge` parameter in `editor_screen.dart`. There are no new analysis findings.

The sandbox test runner required writable Flutter/tool caches and local networking. Its temporary directory was redirected into the session workspace. These are environment permissions, not application dependencies.

## Android acceptance check still required

No Android device or emulator was connected during this update. On a device, add several clips, trim/split, save, then edit/delete and undo/redo. Close and force-stop the app; relaunch and resume the draft. Confirm the latest edit survives. Open the saved snapshot and confirm the state from Save is restored. Cancel replacement once to confirm the draft is kept. Verify that a storage failure reports an error and permits a later Save retry.

## Limits and remaining Phase 1 work

- One recovery draft and one saved snapshot on this device. Saved projects are lost when app data is cleared or the app is uninstalled. External JSON import/export and a named multi-project library are not part of this update.
- Reopening restores the project; undo/redo history and selection restart empty, as in the existing Rust open API.
- Playhead and Mute remain local UI state. Move/reorder is not exposed through the engine/bridge yet. These remain Phase 1 engine-integration work.
- The three-second sample clip remains until Phase 2 media import. Preview, real playback and video export remain placeholders.
- Android native atomic-write recovery and full app-restart behavior still require device verification. Desktop bridge tests and an APK build do not establish that acceptance criterion.
