# CharpCut architecture

## Ownership and flow

Rust owns project data, timeline rules, undo/redo, and the versioned saved-file format. Flutter asks the `EditorEngine` interface for edits and displays the returned `EditorState`. Android owns file import, media inspection, thumbnails, and playback. The platform renderer reads validated source ranges from the Rust snapshot; it does not change the project.

```text
Flutter UI → ProjectSession → RustEditorEngine → generated bridge → Rust Engine → timeline crate
             ↕ storage                                  ↓ snapshot JSON
       Android AtomicFile ← autosave                 EditorState → Flutter UI → Media3 preview
```

The project owner accepted Phases 1–4 on an Android device, confirming Phase 4 complete on 2026-10-14. Exceptional cases such as a loaded timeline with gaps and every possible codec are not covered by that report. Real export is still planned.

## Code map

| Location | Responsibility |
| --- | --- |
| `apps/mobile/lib/main.dart` | Initializes `RustLib`, creates `ProjectSession`, shows startup errors |
| `apps/mobile/lib/home_screen.dart`, `draft_list.dart` | Home, recent drafts, project list and management |
| `apps/mobile/lib/editor_screen.dart` | Editor, timeline, transport, fullscreen controls |
| `apps/mobile/lib/engine/editor_engine.dart`, `rust_engine.dart`, `editor_state.dart` | Dart engine contract, bridge adapter, snapshot parser |
| `apps/mobile/lib/engine/project_session.dart` | Serializes engine and storage work, autosaves, migrates old slots, manages independent drafts |
| `apps/mobile/lib/engine/media_library.dart`, `media_library_screen.dart`, `media_thumbnail.dart` | Media channel, library UI, cached thumbnails and visible filmstrip tiles |
| `apps/mobile/lib/video_preview.dart` | Platform-view host, fit/zoom/pan, revisioned player commands |
| `apps/mobile/android/app/src/main/kotlin/com/example/charpcut/MainActivity.kt` | Android method channels, preview factory and lifecycle |
| `apps/mobile/android/app/src/main/kotlin/com/example/charpcut/MediaLibrary.kt` | Document picker, private copies, metadata, thumbnails and source checks |
| `apps/mobile/android/app/src/main/kotlin/com/example/charpcut/VideoPreview.kt` | Media3 player, clipped playlist, gap silence, audio focus and error reporting |
| `rust/crates/timeline/` | Versioned project model, clip operations and validation |
| `rust/crates/editor_api/` | Engine history and bridge API |
| `apps/mobile/lib/src/rust/`, `rust/crates/editor_api/src/frb_generated.rs` | Generated bindings; do not edit by hand |

## Projects and media

`ProjectSession` serializes engine calls and disk writes so an older autosave cannot replace a newer edit. Successful project edits autosave the JSON returned by Rust. Selection and playhead position are transient. Storage errors leave the successful in-memory edit visible and are surfaced to the user. Schema 5 allows overlapping secondary clips and records media type, track locks/order, and clip properties; it migrates schemas 1–4, adding default properties for older clips. Newer or invalid projects are refused by Rust.

The Android project channel writes `projects/library.charpcut.json` with `AtomicFile`. Each draft has an independent library ID, name, edit time, and complete Rust project JSON. On first access, the old `draft` and `saved` slots migrate once; those files stay as backups. New video starts a separate draft; an untouched empty editor does not create one. Save flushes the active draft. Opening another project first retries any failed autosave. Rename, duplicate, and delete update the library atomically. A duplicate copies the snapshot under a new library ID; its source files may still be shared with other drafts.

Android's document picker imports video, audio, and images into `files/media/<id>/`, with `metadata.json` beside each private source copy. The library records duration, size, dimensions, orientation, available frame rate, and audio-stream details. A missing or unreadable source is shown as unavailable. Imported files are retained when a draft or clip is deleted because other drafts may reference them. Automatic relinking and reference-aware source cleanup are not implemented.

Thumbnails are Android-decoded frames stored under `cache/media-thumbnails/`, capped at 48 MiB. Timeline filmstrips request only visible tiles plus overscan; each tile samples the clip's source range, including trim offsets. Cache files can be regenerated. Keyframe sampling means thumbnails are representative, while the player handles actual frame display.

## Preview

`EditorState` parses the Rust snapshot, including video, audio, image and image-overlay clip paths/ranges, project canvas dimensions, frame rate, playhead, and track state. Flutter sends an immutable projection of video and audio ranges and total duration to the Android platform view. Media3 plays clipped videos and separate synchronized audio playlists for overlapping lanes, seeking the audio player when it drifts from the video clock. Flutter composites video, still-image and overlay lanes in saved track order on the project canvas. Each layer applies normalized translation, scale, rotation, per-edge canvas crop, and opacity. Native video/audio players apply clip volume at playlist transitions. Valid gaps use silence sources; the missing visual layer is transparent over the black canvas. Numeric placement and delete-only can create gaps. Batch moves reject main-video overlaps but allow overlapping audio, image, and overlay clips. Secondary trim and deletion preserve neighboring positions; main-video trim and ripple delete shift later clips by the duration change; explicit clip reorder repacks its lane. Fades and crossfades require Phase 5 effect data.

Native playback positions return to Rust through the transient seek API. User scrubbing pauses playback; pending seeks settle before edits. Commands carry revisions so old native callbacks cannot replace a newer state. Exact seek is requested, while actual decoded precision depends on the media. Media3 reports buffering, aspect ratio, and errors; errors remain visible until the user retries or changes the timeline. The player pauses on backgrounding, audio interruption, or headphone disconnection, and releases its decoder when its view closes.

Fullscreen uses the same player as the editor in playback-only mode. Entering fullscreen resets inspection zoom and disables layer selection, manipulation, and viewing gestures; saved clip transforms still render. The preview fits the project canvas, with each source fitted inside it, with inspection zoom, pan, and double-tap reset available in the editor when no layer is selected. Zoom buttons, the zoom readout, and the fit/instruction text row are removed to keep the preview clear. The rotation button requests landscape or portrait; Android may restrict orientation or immersive UI on some devices. Saved properties compose inside the independent viewing transform.

The editor uses a stable preview element and a side-by-side layout on wide landscape screens. Timeline lanes scroll vertically when height is limited. Keyboard insets do not resize the project; numeric input dialogs remain top-anchored, reserve keyboard space without an inset animation, and scroll when necessary. Go-to-time, trim, and image-duration dialogs own and dispose their controllers with their route widgets, and pause playback while entering values. The Snap/keyframe control uses an in-editor long-press hint instead of a tooltip overlay.

## Bridge and Android build

`flutter_rust_bridge` 2.13.0 generates Dart and Rust bindings from `rust/crates/editor_api/src/api.rs`. Only regenerate after changing the bridge API:

```powershell
.\scripts\setup-bridge.ps1
```

The Gradle build does not rebuild Rust automatically. Build the native library with `scripts/build-android-lib.ps1`; it packages arm64-v8a, armeabi-v7a, and x86_64 outputs under the Android app's `jniLibs/`. `ANDROID_NDK_HOME` is required. A missing library shows a startup error. After Android/Kotlin changes, fully stop and rerun the app.

## Verification and remaining work

On 2026-10-14, 46 Rust tests passed (29 engine, 17 timeline). The Flutter suite now covers 46 tests, including property forms, multi-select, local playback snapshots, trim bounds and commit timing, layer dragging/locking/scaling/rotation, and keyboard anchoring. The real bridge checks saved properties, undo/redo, batch duplication, and track order across reopen. Rust tests additionally cover invalid crop/volume, overlaps, lock rejection, atomic rollback, and schema migration. Existing phone-layout and legacy-flow regressions remain covered.

The Windows test library and all three Android libraries (arm64-v8a, armeabi-v7a, x86_64) were rebuilt. Android `:app:compileDebugKotlin --offline` succeeded. Dart analysis found no errors, with existing style warnings and an `onReorder` deprecation notice. No app was launched. The owner subsequently accepted Phase 4, including preview/audio features and fullscreen behavior, on 2026-10-14. No tests or builds were rerun for this documentation-only update.

The bridge exposes `apply_timeline_edit` as a JSON command decoded to a typed Rust enum. Properties, batch shift/duplicate/delete, and track reorder validate against the entire project and commit as one undo step. Failures restore the prior project and selection and do not autosave. Multi-selection is transient Flutter state, passed as explicit distinct clip IDs; it is not project data.

The [roadmap](FEATURE_ROADMAP.md) tracks the next phases. Effects, text, cover editing, true export, and iOS parity remain. The approved [render-engine decision](decisions/0001-render-engine.md) calls for a dedicated Rust edit list and shared preview/export contract when composition and export expand.

### Direct manipulation and playback updates

`PreviewLayerControls` hit-tests visual layers in reverse compositing order and drafts position, scale and rotation locally. The layer menu can select obscured layers. Gesture release sends a single validated properties command; locked tracks suppress transform/delete handles. `ClipTrimHandle` commits one trim command on release. The preview range slider is removed, and the main video has no floating delete/transform buttons; direct canvas gestures remain available in the editor and are disabled in fullscreen.

During playback, `EditorState.atPlayhead` reuses immutable project lists. Rust receives the final playhead on pause/end or explicit seek, rather than returning a project snapshot every tick. Media3 waits for all playlists to be ready, suppresses duplicate status events, adjusts audio speed by at most two percent for small drift, and reserves seeks for large drift with a cooldown. These changes reduce bridge/decoder work; they are not a device performance measurement.

Secondary clips permit overlapping ranges in schema 5; video still rejects overlaps. Flutter packs intervals into visible timeline rows and long-press dragging commits a single shift command. The preview renders every active visual clip, with a stable native surface for the main video. Android packs non-overlapping audio clips into playlists, adding a decoder only for concurrent lanes; silence fills gaps and each lane follows the main clock. Overlap persistence, undo/redo, row packing, active visual composition, and the clean main-video controls have regression coverage. The owner accepted audible playback in device testing. Broader resource and long-project performance testing remains Phase 8 work.
