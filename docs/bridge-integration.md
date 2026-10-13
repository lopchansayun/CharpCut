# Flutter <-> Rust bridge

The editor UI never edits the project itself. Every change is a call into the Rust engine, which returns the
new editor state as JSON.

```
Flutter screen  ->  EditorEngine (Dart interface)  ->  RustEditorEngine  ->  generated bridge  ->  Rust Engine
```

- `rust/crates/timeline` - project model, clip operations, schema version, validation, JSON save/load.
- `rust/crates/editor_api/src/engine.rs` - the `Engine`: selection, edits, undo/redo, snapshots. Plain Rust, unit tested.
- `rust/crates/editor_api/src/api.rs` - thin functions exposed to Flutter (one shared `Engine` behind a mutex).
- `apps/mobile/lib/engine/` - `EditorEngine` interface, `RustEditorEngine`, and `EditorState` (parses the JSON).
- `apps/mobile/lib/src/rust/` and `rust/crates/editor_api/src/frb_generated.rs` - **generated, do not edit**.

## API (all return the editor state JSON unless noted)
| Function | What it does |
| --- | --- |
| `new_project` | Empty project, history cleared |
| `get_editor_state` | Current state |
| `select_clip(clip_id?)` | Select a clip, or clear the selection with `null` |
| `add_clip(path, duration_ms)` | Append a clip covering the whole file and select it |
| `split_selected_clip_at(timeline_ms)` | Split the selected clip at the playhead |
| `trim_selected_clip(source_in_ms, duration_ms)` | Choose which part of the source plays |
| `delete_selected_clip` | Delete the selected clip |
| `undo`, `redo` | Walk the history (100 edits) |
| `export_project_json` | Project as JSON for saving (returns the JSON text, not a state) |
| `open_project_json(json)` | Replace the project from saved JSON |

A refused edit (nothing selected, split outside the clip, bad file...) changes nothing, adds no history and
sets `last_error` in the state. The UI shows that message as is.

## State JSON
`project` (the saved-file shape, `version` 1), `main_track_id`, `selected_clip_id`, `total_duration_ms`,
`can_undo`, `can_redo`, `status`, `last_error`. Field names are snake_case everywhere.

## Regenerating the bindings
Only needed when `api.rs` changes (function names, arguments, return types).

```powershell
.\scripts\setup-bridge.ps1
cd rust; cargo test
cd ..\apps\mobile; flutter test
```

The checked-in bindings were produced by `flutter_rust_bridge_codegen` 2.13.0 for the current `api.rs`.
They were generated in an environment without the Flutter SDK, so the Dart formatting step was skipped; run
`dart format lib/src/rust` once and expect only whitespace changes.

## Running on Android (required once, and after Rust changes)
The generated code loads `libcharpcut_editor_api.so` by name. Nothing in the Gradle build creates it yet, so build
it with:

```powershell
.\scripts\build-android-lib.ps1
```

This needs the Android NDK (`ANDROID_NDK_HOME`) and installs `cargo-ndk`. It writes the library for
arm64-v8a, armeabi-v7a and x86_64 into `apps/mobile/android/app/src/main/jniLibs/`, which Gradle packages.
This script has not been run by the author of the change. If the library is missing, the app opens a "CharpCut
could not start" screen showing the loader error. Later we can replace this script with a Gradle hook so
`flutter run` builds Rust automatically.

## Tests
- `cargo test` in `rust/` - 13 timeline tests and 19 engine tests (edits, refusals, history, save/open).
- `flutter test` in `apps/mobile` - widget tests use an in-memory engine (`test/support/fake_engine.dart`) so they
  need no native library; `editor_state_test.dart` parses a real snapshot from the Rust engine
  (`test/fixtures/editor_state.json`). If the state JSON changes, regenerate that fixture from the engine.
- Not covered yet: calling the real bridge on a device. Run the app once on Android to confirm `RustLib.init()`
  loads the library; if it fails the app shows a "could not start" screen with the error.
