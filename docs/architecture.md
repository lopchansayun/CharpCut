# CharpCut architecture

Status labels used below: **Implemented** (code and tests exist in the repository), **Partial** (some code exists, the feature is not usable), **Planned** (nothing built; see [FEATURE_ROADMAP.md](FEATURE_ROADMAP.md)).

## High-level design

Rust owns the project and its edit history. Flutter shows the latest state snapshot it was given and asks the engine for every change; it never edits the project itself.

```
Flutter screen -> EditorEngine (Dart interface) -> RustEditorEngine -> generated bridge -> Rust Engine -> timeline crate
      ^                                                                                        |
      +---------------------- new EditorState (JSON string, parsed in Dart) <------------------+
```

Android preview is now **Partial**: Media3 code renders and plays the main track, but the preview fix has not been built or tested, at the owner's request. Export is **Planned**. The approved Android-first approach is in [decisions/0001-render-engine.md](decisions/0001-render-engine.md); current preview scope is in [VIDEO_PREVIEW_FIX.md](VIDEO_PREVIEW_FIX.md).

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
| `home_screen.dart` | Light home: hero banner, New video / Edit photo, tool grid, bottom nav (Edit, Templates, Projects, Me). New video offers to recover the draft; Projects opens the draft or saved snapshot. The Phase 2 recent-projects strip is still hidden. Most tools show a "coming soon" message |
| `editor_screen.dart` | Dark editor (`EditorHome`): preview area, transport row, horizontally scrolling timeline with a fixed playhead (scroll offset = time, 50 dp per second), toolbar that swaps to clip tools when a clip is selected, folder menu for Save/Open |
| `export_panel.dart` | Quality pill and drop-down settings (resolution, frame rate, optical-flow toggle, bitrate, estimated size) and `ExportSettings` |
| `export_done_screen.dart` | Simulated export progress dialog and the export-complete screen (writes no file) |

Supported editor operations: add video, select, seek, split, trim, delete, mute, reorder, undo and redo. Rust owns project edits and the transient playhead. Scroll gestures and native player position events send seek commands; Flutter displays the confirmed position. Rapid seeks are coalesced to at most one in-flight bridge call. The simulated transport clock and filename-only preview are replaced by a Media3 player. The player's clipped playlist uses only source paths and ranges from the validated Rust snapshot; native rendering does not edit project data. Mute controls the player's audio volume. Export settings and transport-running status remain UI state. This preview change awaits manual verification.

## Dart engine layer (Implemented)

- `engine/editor_engine.dart` - abstract `EditorEngine` (`newProject`, `getState`, `select`, `seek`, `setMuted`, `moveSelected`, `addClip`, `splitSelectedAt`, `trimSelected`, `deleteSelected`, `undo`, `redo`, `exportProjectJson`, `openProjectJson`) and `EngineScope`.
- `engine/rust_engine.dart` - `RustEditorEngine`, calls the generated functions and parses the returned JSON.
- `engine/editor_state.dart` - `EditorState`, `EditorClip`; parses the snapshot JSON.
- `engine/project_session.dart` - production adapter around `RustEditorEngine`. Serializes engine operations and JSON storage; autosaves successful project changes (including undo/redo) but not selection/refused operations. `AndroidProjectStore` calls `charpcut/projects`; Android uses app-private `AtomicFile` writes on a background executor. Independent drafts are stored in a versioned atomic library envelope with stable IDs, display names, and edit dates; the old draft/saved slots migrate once. Home and Projects show the library with rename/delete controls. This update awaits manual verification; see [MULTI_DRAFTS.md](MULTI_DRAFTS.md). Storage errors leave the successful engine state available to the UI. See [PHASE1_PERSISTENCE.md](PHASE1_PERSISTENCE.md) for recovery flows and limits.
- `engine/video_importer.dart` - minimal `charpcut/media` channel. Android's document picker chooses one video. A background task copies it into `files/media/<unique-id>/<filename>`, syncs the file, validates a video stream and reads duration via `MediaMetadataRetriever`. Rust receives the copied path and actual duration. Cancel returns null; failed imports remove partial copies. Broader media metadata, thumbnails and media-library management remain Phase 2.
- `video_preview.dart` - Android platform-view host and per-view control channel. `VideoPreview.kt` renders a Media3 clipped playlist; native position events update Rust's playhead without seeking the player back to each acknowledged position. Revision IDs reject callbacks for old commands. The player pauses in the background and releases its decoder when the view closes. `EngineScope.previewEnabled` lets existing widget tests disable the native decoder. No tests were executed for this fix.

`EditorHome` takes the engine from `EngineScope`, so tests substitute an in-memory engine. A refused edit changes nothing and sets `lastError`, which the editor shows as a message.

## Rust engine (Implemented)

**`rust/crates/timeline`** - project settings, assets, tracks and clips, plus add/trim/move/reorder/delete/split, gap closing, lookup, validation and JSON. `Track` now persists `muted`. Schema version is 2: version 1 migrates with unmuted tracks; version 2 requires a boolean mute field; newer versions are refused. `reorder_clip` moves a clip to a final index and derives gapless start times without changing its source range. The engine exposes this operation rather than sparse `move_clip`, because its main video track is gapless. Files are validated on open, save and after engine edits.

**`rust/crates/editor_api/src/engine.rs`** - `Engine`: plain Rust, unit tested. Holds the project, the selected clip, and undo/redo history (capped at 100). Before each edit it takes a snapshot and restores it if the edit fails. The editor works on one gapless main video track: after every edit the engine closes gaps, so clip start times are derived and the UI never types them in. It produces `EditorSnapshot`.

**`rust/crates/editor_api/src/api.rs`** - thin functions exposed to Dart, using one shared `Engine` behind a global mutex. Every function returns the editor-state JSON, except `export_project_json` which returns the project JSON text.

| Function | What it does |
| --- | --- |
| `new_project` | Empty project, history cleared |
| `get_editor_state` | Current state |
| `select_clip(clip_id?)` | Select a clip, or clear the selection with `null` |
| `seek_playhead(timeline_ms)` | Set/clamp the transient playhead; no undo or disk write |
| `set_main_track_muted(muted)` | Saved, undoable video-track mute setting |
| `move_selected_clip(target_index)` | Reorder the selected clip to its final zero-based index and close gaps |
| `add_clip(path, duration_ms)` | Append a clip covering the whole file and select it |
| `split_selected_clip_at(timeline_ms)` | Split the selected clip at the playhead |
| `trim_selected_clip(source_in_ms, duration_ms)` | Choose which part of the source plays |
| `delete_selected_clip` | Delete the selected clip |
| `undo`, `redo` | Walk the history |
| `export_project_json` | Project as JSON for saving |
| `open_project_json(json)` | Replace the project from saved JSON |

### State JSON

`project` (saved-file shape), `main_track_id`, `selected_clip_id`, `total_duration_ms`, `playhead_ms`, `main_track_muted`, `can_undo`, `can_redo`, `status`, `last_error`. Field names are snake_case everywhere. Selection, playhead and history reset on reopen; mute is in the project and survives reopen.

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

It needs the Android NDK (`ANDROID_NDK_HOME`), adds the three Android Rust targets, installs `cargo-ndk`, and writes arm64-v8a, armeabi-v7a and x86_64 libraries into `apps/mobile/android/app/src/main/jniLibs/`. The project owner reported on 2026-10-13 that it builds without errors and the app loads the library on a device.

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
| `rust/` (`cargo test`) | 17 timeline + 24 engine tests: edits, refusals, history, save/open, mute, reorder, seek and schema migration | 41 passed in the controls update |
| `apps/mobile/test/widget_test.dart` | Launch, home, editor toolbar, empty editor, add/delete/undo/redo, trim, split refusal, export panel, empty-export refusal | Use `test/support/fake_engine.dart`, an in-memory `EditorEngine`, so no native library is needed |
| `apps/mobile/test/editor_state_test.dart` | Parses `test/fixtures/editor_state.json`, a real snapshot from the Rust engine | If the state JSON changes, regenerate the fixture from the engine |
| `apps/mobile/test/project_session_test.dart` | Recovery, Save/Open, undo/redo autosave, serialization, storage errors, channel arguments and UI | In-memory store and fake engine; mocked Android channel |
| `apps/mobile/test/engine_controls_test.dart` | Mute/Move UI and history, confirmed playhead split, importer cancellation/errors/metadata, autosave | Included in the 33 desktop Flutter tests |
| `apps/mobile/integration_test/phase1_test.dart` | Packaged Android bridge controls/migration and real atomic storage round-trip | Preserves the existing recovery draft in a finally block; storage test requires a pre-existing draft. See controls update for device results |
| `apps/mobile/test/rust_bridge_test.dart` | Real native bridge edits, versioned JSON, disk save/reopen, corrupt/newer-file refusal | Build the desktop library with `cargo build -p charpcut-editor-api` first; skipped explicitly if absent |
| Not covered in the persistence update | Android atomic storage and app restart/recovery on a device | Debug APK builds; no Android device was connected. Run the acceptance checklist in `PHASE1_PERSISTENCE.md` |

## Where to add things

- **New edit operation:** add the operation in `rust/crates/timeline` if it changes the model; add an `Engine` method with unit tests in `engine.rs`; expose a function in `api.rs`; regenerate bindings; add it to `EditorEngine`, `RustEditorEngine` and `test/support/fake_engine.dart`; call it from `editor_screen.dart`; add a widget test.
- **New UI feature:** `apps/mobile/lib/`, reading state only from `EditorState`. Keep core editing rules out of Dart.
- **Saved-file change:** bump `SCHEMA_VERSION` and add a migration in `Project::from_json`.
- **New bridge function:** `api.rs` only, then regenerate. Never edit `src/rust/` or `frb_generated.rs`.
- **Preview / export renderer:** not started; read [decisions/0001-render-engine.md](decisions/0001-render-engine.md) first.

## Phase 2 media boundary

`MediaLibrary.kt` owns Android file imports, read-only source metadata, atomic catalog sidecars and bounded thumbnail cache. `engine/media_library.dart` exposes it to the library screen and visible filmstrip tiles. Timeline edits still use Rust; no schema or bridge changes are needed to browse imported media. Audio/image imports are library assets until later track support. Draft duplication copies the engine snapshot into an independently identified library document. See [PHASE2_MEDIA.md](PHASE2_MEDIA.md) for limits and manual acceptance; this update was not built or tested by the assistant.
