# CharpCut architecture

## Ownership and flow

Rust owns project data, timeline rules, undo/redo, and the versioned saved-file format. Flutter asks the `EditorEngine` interface for edits and displays the returned `EditorState`. Android owns file import, media inspection, thumbnails, and playback. The platform renderer reads validated source ranges from the Rust snapshot; it does not change the project.

```text
Flutter UI → ProjectSession → RustEditorEngine → generated bridge → Rust Engine → timeline crate
             ↕ storage                                  ↓ snapshot JSON
       Android AtomicFile ← autosave                 EditorState → Flutter UI → Media3 preview
```

The first three phases have been exercised on an Android device by the project owner. Exceptional cases such as a loaded timeline with gaps and every possible codec are not covered by that report. Real export is still planned.

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

`ProjectSession` serializes engine calls and disk writes so an older autosave cannot replace a newer edit. Successful project edits autosave the JSON returned by Rust. Selection and playhead position are transient. Storage errors leave the successful in-memory edit visible and are surfaced to the user. Schema 2 persists main-track mute and migrates schema 1; newer or invalid projects are refused by Rust.

The Android project channel writes `projects/library.charpcut.json` with `AtomicFile`. Each draft has an independent library ID, name, edit time, and complete Rust project JSON. On first access, the old `draft` and `saved` slots migrate once; those files stay as backups. New video starts a separate draft; an untouched empty editor does not create one. Save flushes the active draft. Opening another project first retries any failed autosave. Rename, duplicate, and delete update the library atomically. A duplicate copies the snapshot under a new library ID; its source files may still be shared with other drafts.

Android's document picker imports video, audio, and images into `files/media/<id>/`, with `metadata.json` beside each private source copy. The library records duration, size, dimensions, orientation, available frame rate, and audio-stream details. A missing or unreadable source is shown as unavailable. Imported files are retained when a draft or clip is deleted because other drafts may reference them. Automatic relinking and reference-aware source cleanup are not implemented.

Thumbnails are Android-decoded frames stored under `cache/media-thumbnails/`, capped at 48 MiB. Timeline filmstrips request only visible tiles plus overscan; each tile samples the clip's source range, including trim offsets. Cache files can be regenerated. Keyframe sampling means thumbnails are representative, while the player handles actual frame display.

## Preview

`EditorState` parses the Rust snapshot, including clip paths/ranges, project canvas dimensions, frame rate, playhead, and mute. Flutter sends an immutable projection of those ranges and total duration to the Android platform view. Media3 plays consecutive clipped videos on one clock, with their source audio. Valid timeline gaps use silence sources and a black overlay. Current UI editing operations repack the main video track without gaps. Fades and crossfades require Phase 5 effect data.

Native playback positions return to Rust through the transient seek API. User scrubbing pauses playback; pending seeks settle before edits. Commands carry revisions so old native callbacks cannot replace a newer state. Exact seek is requested, while actual decoded precision depends on the media. Media3 reports buffering, aspect ratio, and errors; errors remain visible until the user retries or changes the timeline. The player pauses on backgrounding, audio interruption, or headphone disconnection, and releases its decoder when its view closes.

Fullscreen uses the same player as the editor. Source fit, project-canvas fit, pinch zoom, pan, zoom buttons, and reset affect viewing only. The rotation button requests landscape or portrait; Android may restrict orientation or immersive UI on some devices. Saved crop/scale changes are a separate Phase 4 feature.

## Bridge and Android build

`flutter_rust_bridge` 2.13.0 generates Dart and Rust bindings from `rust/crates/editor_api/src/api.rs`. Only regenerate after changing the bridge API:

```powershell
.\scripts\setup-bridge.ps1
```

The Gradle build does not rebuild Rust automatically. Build the native library with `scripts/build-android-lib.ps1`; it packages arm64-v8a, armeabi-v7a, and x86_64 outputs under the Android app's `jniLibs/`. `ANDROID_NDK_HOME` is required. A missing library shows a startup error. After Android/Kotlin changes, fully stop and rerun the app.

## Verification and remaining work

The project owner confirmed the Phase 1–3 user flows on Android. Earlier recorded automated results were 41 Rust tests and 33 Flutter tests, before the later Phase 2–3 changes. Those older numbers do not validate the current code; some tests still assume the prior direct-picker and two-slot storage flow. The assistant did not rerun builds or tests for these updates at the owner's request.

The [roadmap](FEATURE_ROADMAP.md) tracks the next phases. Audio/image timeline tracks, effects, text, cover editing, true export, and iOS parity are not implemented. The approved [render-engine decision](decisions/0001-render-engine.md) calls for a dedicated Rust edit list and shared preview/export contract when composition and export expand.
