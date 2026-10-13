# CharpCut architecture

Status labels used below: **Implemented** (code and tests exist in the repository), **Partial** (some code exists, the feature is not usable), **Planned** (nothing built; see [FEATURE_ROADMAP.md](FEATURE_ROADMAP.md)).

## High-level design

Rust owns the project and its edit history. Flutter shows the latest state snapshot it was given and asks the engine for every change; it never edits the project itself.

```
Flutter screen -> EditorEngine (Dart interface) -> RustEditorEngine -> generated bridge -> Rust Engine -> timeline crate
      ^                                                                                        |
      +---------------------- new EditorState (JSON string, parsed in Dart) <------------------+
```

Preview and export (decoding, playback, rendering) are **Planned**. The approved approach (Android first with Media3, iOS later with AVFoundation) is in [decisions/0001-render-engine.md](decisions/0001-render-engine.md).

## Repository layout

| Path | Responsibility |
| --- | --- |
| `apps/mobile/` | Flutter app |
| `apps/mobile/lib/` | UI screens, theme, Dart engine layer |
| `apps/mobile/lib/engine/` | `EditorEngine` interface, `RustEditorEngine`, `EditorState` parsing |
| `apps/mobile/lib/src/rust/` | **Generated** Dart bindings. Do not edit by hand |
| `apps/mobile/test/` | Flutter tests, fake engine, JSON fixture |
| `apps/mobile/android/` | Android project (Gradle). Rust libraries are copied into `app/src/main/jniLibs/` (git-ignored) |
| `rust/crates/timeline/` | Project model, clip operations, validation, JSON save/load. Owns the saved-file format |
| `rust/crates/editor_api/` | `Engine` (selection, edits, undo/redo, snapshots) and the bridge-facing `api.rs` |
| `rust/crates/editor_api/src/frb_generated.rs` | **Generated** Rust glue. Do not edit by hand |
| `flutter_rust_bridge.yaml` | Bridge generator config (`rust_input: crate::api`, `dart_output: apps/mobile/lib/src/rust`, entrypoint class `RustLib`) |
| `scripts/` | `setup-bridge.ps1` (install generator and regenerate bindings), `build-android-lib.ps1` (build Rust for Android), `check-rust.ps1` (`cargo test`) |
| `docs/` | This documentation |

## Flutter UI (Implemented as UI; most tools are placeholders)

All files are in `apps/mobile/lib/`.

| File | Role |
| --- | --- |
| `main.dart` | Starts the app. Awaits `RustLib.init()`; on failure shows `StartupFailure`. Otherwise wraps `MaterialApp` in `EngineScope` and shows a 1.1 s `StartupScreen` before the home screen |
| `theme.dart` | Dark (editor) and light (home) themes, colour constants, `toast`, `formatClock` |
| `home_screen.dart` | Light home: hero banner, New video / Edit photo, tool grid, bottom nav (Edit, Templates, Projects, Me). No saved projects exist yet, so the recent-projects strip is hidden and Projects shows "No projects yet". Most tools show a "coming soon" message |
| `editor_screen.dart` | Dark editor (`EditorHome`): preview area, transport row, horizontally scrolling timeline with a fixed playhead (scroll offset = time, 50 dp per second), toolbar that swaps to clip tools when a clip is selected |
| `export_panel.dart` | Quality pill and drop-down settings (resolution, frame rate, optical-flow toggle, bitrate, estimated size) and `ExportSettings` |
| `export_done_screen.dart` | Simulated export progress dialog and the export-complete screen (writes no file) |

What works in the editor: add clip, select, split at the playhead, trim, delete, undo, redo, all through the engine. Local UI-only state that is not in the project: playhead position, the Mute toggle, export settings. Placeholders showing a message: audio, text, effects, overlay, captions, filters, animations, keyframes, cover, fullscreen.

## Dart engine layer (Implemented)

- `engine/editor_engine.dart` - abstract `EditorEngine` (`newProject`, `getState`, `select`, `addClip`, `splitSelectedAt`, `trimSelected`, `deleteSelected`, `undo`, `redo`, `exportProjectJson`, `openProjectJson`) and the `EngineScope` inherited widget that supplies the engine to screens.
- `engine/rust_engine.dart` - `RustEditorEngine`, calls the generated functions and parses the returned JSON.
- `engine/editor_state.dart` - `EditorState`, `EditorClip`; parses the snapshot JSON.

`EditorHome` takes the engine from `EngineScope`, so tests substitute an in-memory engine. A refused edit changes nothing and sets `lastError`, which the editor shows as a message.

## Rust engine (Implemented)

**`rust/crates/timeline`** - `Project` (id, `version`, settings, assets, tracks), `ProjectSettings`, `MediaAsset` (path, duration), `Track` (kind `Video`/`Audio`/`Overlay`, clips), `Clip` (asset, timeline start, source in, duration). Operations: add/trim/move/delete/split clips, `append_clip`, `ripple_track`, `total_duration_ms`, `find_clip`, `clip_at`, `validate`, `to_json`/`from_json`. `MIN_CLIP_MS` is 100. Saved-file `version` is `SCHEMA_VERSION` (1); a file with a newer version is rejected with a clear error, and a migration step belongs in `Project::from_json` when the version increases. Files are validated on open and before save (unique ids, clips inside their source media, no overlaps on a track). `move_clip` exists in this crate but is not exposed by the engine or the bridge yet.

**`rust/crates/editor_api/src/engine.rs`** - `Engine`: plain Rust, unit tested. Holds the project, the selected clip, and undo/redo history (capped at 100). Before each edit it takes a snapshot and restores it if the edit fails. The editor works on one gapless main video track: after every edit the engine closes gaps, so clip start times are derived and the UI never types them in. It produces `EditorSnapshot`.

**`rust/crates/editor_api/src/api.rs`** - thin functions exposed to Dart, using one shared `Engine` behind a global mutex. Every function returns the editor-state JSON, except `export_project_json` which returns the project JSON text.

| Function | What it does |
| --- | --- |
| `new_project` | Empty project, history cleared |
| `get_editor_state` | Current state |
| `select_clip(clip_id?)` | Select a clip, or clear the selection with `null` |
| `add_clip(path, duration_ms)` | Append a clip covering the whole file and select it |
| `split_selected_clip_at(timeline_ms)` | Split the selected clip at the playhead |
| `trim_selected_clip(source_in_ms, duration_ms)` | Choose which part of the source plays |
| `delete_selected_clip` | Delete the selected clip |
| `undo`, `redo` | Walk the history |
| `export_project_json` | Project as JSON for saving |
| `open_project_json(json)` | Replace the project from saved JSON |

### State JSON

`project` (saved-file shape), `main_track_id`, `selected_clip_id`, `total_duration_ms`, `can_undo`, `can_redo`, `status`, `last_error`. Field names are snake_case everywhere.

## Bridge and generated bindings

`flutter_rust_bridge` 2.13.0 reads `rust/crates/editor_api/src/api.rs` and generates `apps/mobile/lib/src/rust/*` and `rust/crates/editor_api/src/frb_generated.rs`. Both are checked in. The `editor_api` crate builds as `lib`, `cdylib` and `staticlib`; on Android the loaded library is `libcharpcut_editor_api.so`.

### Regenerating the bindings

Only needed when `api.rs` changes (function names, arguments, return types):

```powershell
.\scripts\setup-bridge.ps1
cd rust; cargo test
cd ..\apps\mobile; flutter test
```

The checked-in bindings were generated with `flutter_rust_bridge_codegen` 2.13.0 in an environment without the Flutter SDK, so the Dart formatting step was skipped. Run `dart format lib/src/rust` once and expect only whitespace changes.

### Running on Android

Nothing in the Gradle build creates the Rust library yet (**Planned**: a Gradle hook so `flutter run` builds it). Build it by hand:

```powershell
.\scripts\build-android-lib.ps1
```

It needs the Android NDK (`ANDROID_NDK_HOME`), adds the three Android Rust targets, installs `cargo-ndk`, and writes arm64-v8a, armeabi-v7a and x86_64 libraries into `apps/mobile/android/app/src/main/jniLibs/`. This script has not been confirmed to work end to end; if it fails, the output of the failing step is needed to diagnose.

### Debugging

- "CharpCut could not start ... libcharpcut_editor_api.so not found": the library is missing from the APK. Run the build script and rebuild the app.
- Compile errors after changing `api.rs`: the generated code is stale. Regenerate it.
- Never edit generated files; change `api.rs` and regenerate.

## Error handling and boundaries

- Rust: an edit that is refused (nothing selected, split outside the clip, bad file) changes nothing, adds no history, and sets `last_error` in the snapshot.
- Dart: the UI shows `last_error` / `status` as a toast; it does not interpret error text.
- Startup: if the native library cannot load, `main()` shows `StartupFailure` with the loader error.
- Project files: invalid or newer-version JSON is rejected on open.

## Testing

| Where | What | Notes |
| --- | --- | --- |
| `rust/` (`cargo test`) | 13 timeline tests (`crates/timeline/src/lib.rs`) and 19 engine tests (`crates/editor_api/src/engine.rs`): edits, refusals, history, save/open | 32 passed when run during this documentation pass |
| `apps/mobile/test/widget_test.dart` | Launch, home, editor toolbar, empty editor, add/delete/undo/redo, trim, split refusal, export panel, empty-export refusal | Use `test/support/fake_engine.dart`, an in-memory `EditorEngine`, so no native library is needed |
| `apps/mobile/test/editor_state_test.dart` | Parses `test/fixtures/editor_state.json`, a real snapshot from the Rust engine | If the state JSON changes, regenerate the fixture from the engine |
| Not covered | Calling the real bridge on a device | Run the app on Android once to confirm `RustLib.init()` loads the library |

## Where to add things

- **New edit operation:** add the operation in `rust/crates/timeline` if it changes the model; add an `Engine` method with unit tests in `engine.rs`; expose a function in `api.rs`; regenerate bindings; add it to `EditorEngine`, `RustEditorEngine` and `test/support/fake_engine.dart`; call it from `editor_screen.dart`; add a widget test.
- **New UI feature:** `apps/mobile/lib/`, reading state only from `EditorState`. Keep core editing rules out of Dart.
- **Saved-file change:** bump `SCHEMA_VERSION` and add a migration in `Project::from_json`.
- **New bridge function:** `api.rs` only, then regenerate. Never edit `src/rust/` or `frb_generated.rs`.
- **Preview / export renderer:** not started; read [decisions/0001-render-engine.md](decisions/0001-render-engine.md) first.
