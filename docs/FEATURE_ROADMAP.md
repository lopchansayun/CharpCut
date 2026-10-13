# CharpCut — Feature Development Roadmap

This roadmap describes the recommended order for growing CharpCut from its current Flutter + Rust foundation into a practical mobile video editor. Treat each phase as a separate, testable milestone. Preserve existing working features and verify changes on an Android device before moving to the next phase.

> **This file is the single source of truth for feature planning and progress.** It is a plan, not a claim that every feature is implemented. Confirm completion by testing the real behaviour in the app.

## Status legend

- `[x]` Completed and verified (code exists and a test or run confirmed it)
- `[ ]` Planned or incomplete
- `[!]` Blocked or needs investigation

## Current phase

**Phase 1 is complete, verified by the project owner.** The owner confirmed that all Phase 1 behavior works, including persistence and multiple drafts. This is user-reported Android verification; the assistant did not rerun the app or tests.

**Phase 2 implementation is now in place and awaits owner acceptance.** New code adds video/audio/image imports, a persisted media library, metadata, thumbnails/filmstrips, project duplication, and missing-media reporting. See [PHASE2_MEDIA.md](PHASE2_MEDIA.md) for changes, limits, and manual acceptance steps. No build, analyzer, app run, or test execution was performed for this update, following the owner's instruction.

Audio/image timeline placement, text/effects, advanced preview controls, export and sharing remain later phases. The initial Android preview exists; fuller Phase 3 behavior is still incomplete.

## Where things live

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full layout. Short version: UI in `apps/mobile/lib/`, Dart engine boundary in `apps/mobile/lib/engine/`, generated bindings in `apps/mobile/lib/src/rust/` (do not edit), engine in `rust/crates/editor_api/src/`, project model in `rust/crates/timeline/src/lib.rs`, Android packaging in `apps/mobile/android/` and `scripts/build-android-lib.ps1`, tests in `apps/mobile/test/` and the Rust crates.

## Phase 0 — Foundation and Android stability

**Goal:** Keep the app buildable and establish a reliable baseline before adding features.

Built so far:

- [x] Rust project model with a versioned, validated JSON file format (`rust/crates/timeline`)
- [x] Editing engine in Rust: empty project, add/split/trim/delete, undo/redo, save/open (`rust/crates/editor_api/src/engine.rs`)
- [x] Bridge API built around the engine, bindings generated, no demo project (`api.rs`, `src/rust/`)
- [x] Flutter editor reads its state from Rust through the `EditorEngine` interface; widget tests use an in-memory engine
- [x] Render-engine decision written down and approved by the project owner on 2026-10-13: Android first, iOS later ([decisions/0001-render-engine.md](decisions/0001-render-engine.md))
- [x] `cargo test` from `rust/` passes (13 timeline + 19 engine tests; run during the documentation cleanup)

Verified by the project owner on 2026-10-13 (reported, not re-run by the assistant):

- [x] `flutter test` from `apps/mobile/` passes
- [x] `scripts/build-android-lib.ps1` builds the Rust shared library without errors
- [x] The library loads on a real device (no startup-failure screen) and add clip, trim, split, undo and redo work through Rust

Still open:

- [x] Verify save and open round-trip on Android after app restart (confirmed by the project owner with the Phase 1 acceptance report).
- [x] Render-engine decision approved: the first release is Android-only; iOS is a later, separate task (see [decisions/0001-render-engine.md](decisions/0001-render-engine.md))


**Acceptance criteria:** Rust and Flutter tests pass; the app launches on Android without the startup-failure screen; a basic edit can be made, undone and redone on the device; a project exported with `export_project_json` and reopened with `open_project_json` matches the original.

## Phase 1 — Engine integration and project persistence

**Goal:** Ensure editing commands use one authoritative project state.

- [x] Route every supported editing control through `EditorEngine` and Rust, including Mute, playhead and clip Move. Seeking is transient session state; mute and reorder are saved edits.
- [x] Remove duplicate/mock timeline state from production flows. The add button uses Android's system video picker and measured duration. Real filmstrip code has now been added in Phase 2 and awaits manual acceptance.
- [x] Complete undo/redo for all supported edits, including mute and reorder. No-op controls and seek preserve history and redo; failed operations restore the previous project.
- [x] Save/reopen versioned project JSON; schema 2 persists mute and migrates schema 1. Initial persistence confirmed working by the owner; extended real bridge tests cover mute and reordered clips.
- [x] Add autosave and draft recovery. Successful edits including mute/reorder and undo/redo are saved. Initial features confirmed working by the owner; the owner subsequently confirmed all Phase 1 checks passed.
- [x] Add validation and user-facing errors for refused edits, corrupt/newer files, storage failures, picker failures and invalid video metadata. Rust validates the project after every successful mutation.
- [x] Add engine and bridge integration tests. (Rust engine tests, Flutter session/storage/widget tests, and `test/rust_bridge_test.dart` calling the actual native Rust bridge. Run `cargo build -p charpcut-editor-api` before Flutter tests to enable the desktop bridge test.)

**Likely locations:** `editor_screen.dart`, `engine/editor_engine.dart`, `engine/rust_engine.dart`, `engine/editor_state.dart`, `rust/crates/editor_api/`, and `rust/crates/timeline/`.

**Acceptance criteria:** UI state consistently matches Rust state; edits survive app restart; undo/redo is reliable. The owner confirmed all Phase 1 checks passed, including the previously requested restart and edit checks.

## Phase 2 — Media import and project management

**Goal:** Let users bring their own media into projects.

- [ ] Import video from Android's system picker. (Expanded media-import implementation added; acceptance pending.)
- [ ] Import audio and still images. (Implemented into the reusable library; audio/image timeline tracks remain Phase 4.)
- [ ] Handle file permissions and persist access safely or copy media into app-managed storage when needed. (All three media types are copied into private storage.)
- [ ] Read duration, dimensions, orientation, frame rate, and audio-stream metadata. (Implemented; unavailable metadata is labeled, average frame-rate fallback is identified.)
- [ ] Generate thumbnails and video filmstrips. (Implemented with a bounded disk cache and visible timeline tiles.)
- [ ] Show imported media in a media library. (Implemented with type filters, search, details and video reuse.)
- [ ] Create, rename, duplicate, and delete projects. (Create/rename/delete confirmed by the owner; independent duplication now implemented, pending acceptance.)
- [x] Display recent drafts on the home screen. (Owner verified drafts; newly added first-frame thumbnails await Phase 2 acceptance.)
- [ ] Handle moved, deleted, unsupported, or inaccessible source files. (Private copies survive external moves; import validation, unavailable library entries, and editor source warnings implemented. Automatic relinking is not included.)

**Acceptance criteria:** A user can import media, see its metadata and thumbnail, add it to a project, and reopen the project later.

## Phase 3 — Real preview and playback

**Goal:** Display and play the actual source media in timeline order.

- [ ] Choose and document the media decoding and rendering architecture before building advanced effects. (Approved: Android Media3. Initial preview consumes source ranges from Rust's validated snapshot; a separate Rust renderer edit-list API remains future work.)
- [ ] Implement play/pause and accurate seeking. (Code added in the preview fix; intentionally not built or tested, per owner request.)
- [ ] Render the clip at the current playhead position. (Media3 platform-view code replaces the filename-only preview; manual verification pending.)
- [ ] Synchronize audio and video. (Native player renders source audio and video together; manual verification pending.)
- [ ] Handle gaps, black frames, orientation, aspect ratios, and portrait/landscape projects.
- [ ] Support multiple consecutive clips and transitions in preview. (Clipped playlist code added; transitions remain planned and playlist behavior awaits manual verification.)
- [ ] Handle buffering, decoding errors, and resource cleanup. (Code added for buffering, errors, background pause and view-disposal cleanup; manual verification pending.)

**Acceptance criteria:** Preview playback reflects the timeline edits and remains synchronized during seeking and playback.

## Phase 4 — Essential timeline editing

**Goal:** Make timeline operations useful with real media.

- [ ] Split, trim start/end, move, reorder, delete, duplicate, and ripple-delete clips.
- [ ] Add timeline zoom, horizontal scrolling, a time ruler, snapping, and precise playhead control.
- [ ] Support video, audio, image, and overlay tracks.
- [ ] Add clip selection, multi-select, track lock, and track reorder.
- [ ] Add position, duration, scale, rotation, crop, opacity, and volume properties.
- [ ] Keep undo/redo and saved projects consistent for every operation.

**Acceptance criteria:** Editing operations update both the timeline and preview, and remain correct after save/reopen and undo/redo.

## Phase 5 — Text, transitions, overlays, and visual effects

**Goal:** Add common creative editing tools.

- [ ] Text overlays, titles, fonts, colors, alignment, and positioning.
- [ ] Basic fade and crossfade transitions.
- [ ] Brightness, contrast, saturation, blur, and basic filters.
- [ ] Image overlays, stickers, borders, and picture-in-picture.
- [ ] Keyframe animation for position, scale, rotation, and opacity.
- [ ] Reusable effect and transition presets.

**Implementation note:** Effects must be represented in project data and implemented by the preview renderer and export renderer. Saving effect settings alone is not enough.

**Acceptance criteria:** Effects are visible in preview and are represented in saved projects.

## Phase 6 — Audio editing

**Goal:** Provide a dependable multi-track audio workflow.

- [ ] Add music and sound effects.
- [ ] Record or import voiceovers.
- [ ] Display waveforms.
- [ ] Control clip and track volume; mute and solo tracks.
- [ ] Add fade-in and fade-out.
- [ ] Mix multiple audio tracks and synchronize them with video.
- [ ] Prevent clipping and handle audio/video drift.
- [ ] Add optional ducking and basic audio cleanup.

**Acceptance criteria:** Audio tracks play in sync and sound consistent in preview and exported files.

## Phase 7 — Rendering and export

**Goal:** Produce a real playable output file from the complete project timeline.

- [ ] Implement a rendering/export pipeline that uses the project timeline and supported effects.
- [ ] Export MP4 with H.264 video and AAC audio where supported.
- [ ] Offer sensible resolution presets such as 480p, 720p, and 1080p, plus supported frame-rate and bitrate options.
- [ ] Show progress, estimated status, completion, and failure states.
- [ ] Support cancellation and safe cleanup of temporary files.
- [ ] Let users choose an output destination and save/share the completed video.
- [ ] Handle insufficient storage, unsupported codecs, and export failures.
- [ ] Validate output duration, playback, and audio/video synchronization.

**Architecture decision:** See [decisions/0001-render-engine.md](decisions/0001-render-engine.md), which proposes platform media stacks and rejects FFmpeg for now. If using FFmpeg or another third-party media engine, review Android build support, codec availability, distribution/licensing obligations, and compatibility with the Rust architecture before committing.

**Acceptance criteria:** An exported file exists, plays in a standard player, includes all supported timeline edits, and has synchronized audio/video.

## Phase 8 — Advanced tools and release quality

- [ ] Speed changes and speed ramps.
- [ ] Chroma key, masks, stabilization, and advanced blur/tracking where feasible.
- [ ] Subtitle/SRT import and export; automatic captions as a separately scoped feature.
- [ ] Templates and reusable project presets.
- [ ] Crash recovery, project backups, and autosave reliability.
- [ ] Thumbnail/cache management, background work, and memory limits.
- [ ] Hardware acceleration where supported.
- [ ] Accessibility, localization, onboarding, and clear error messages.
- [ ] Release signing, device compatibility checks, and performance testing on long projects.

AI features such as background removal, automatic captions, and beat detection should be separately scoped because they may require models, significant device resources, or network services.

## Phase dependencies and risks

- Phase 0 verification (done) gated everything: the Rust library now loads on a device.
- Phase 3 (preview) and Phase 7 (export) depend on the render-engine decision. The decision proposes Android first through Media3, with Rust producing an edit list the renderer consumes; iOS roughly doubles both phases.
- Phase 2 (import) must come before Phase 3 and Phase 7: previewing and exporting need real media paths, not the placeholder clip.
- Phase 4 properties (scale, rotation, opacity, volume, speed) and the Phase 5 and Phase 6 features need new fields in the project format, so bump `SCHEMA_VERSION` and add migrations.
- Phase 5 and Phase 6 effects need both a preview and an export implementation (see the implementation note in Phase 5).
- Risks: native build setup on Windows (NDK, `cargo-ndk`), Android storage permissions and moved files, audio/video sync, and memory use with long projects.

## Suggested implementation updates

Each update corresponds roughly to the phases above. Phase 1 is owner-verified; the Phase 2 additions await manual acceptance.

| Update | Scope | Completion check |
|---|---|---|
| 01 | Android/native build and engine baseline | App launches and Rust bridge calls work on a device |
| 02 | Engine integration, undo/redo, project persistence | Edits save, reopen, undo, and redo correctly |
| 03 | Media import and metadata | Video/audio/image files can be imported and inspected |
| 04 | Thumbnails and media library | Imported media has usable thumbnails and appears in the library |
| 05 | Preview and playback | Actual media plays and seeking works |
| 06 | Timeline editing improvements | Edits affect playback and survive save/reopen |
| 07 | Multiple tracks and clip properties | Layered timeline edits work correctly |
| 08 | Text, transitions, and filters | Supported effects appear in preview |
| 09 | Audio tools | Multiple audio sources play in sync |
| 10 | Export engine | A valid video file can be exported and played |
| 11 | Advanced effects | Selected advanced features pass tests |
| 12 | Performance and release | Stress tests pass and release build is stable |

## Note on phase numbering

An earlier, shorter roadmap used different numbers (its Phase 1 media import and drafts = Phase 2 here; its Phase 2 preview = Phase 3; its Phase 3 core editing = Phase 4; its Phase 4 export = Phase 7; its Phase 5 audio and text = Phases 5 and 6; its Phase 6 effects = Phase 5; its Phase 7 photo editing and release = Phase 8). This file's numbering is the one to use. Photo editing (the "Edit photo" entry on the home screen) is not covered by any phase above and needs a decision on scope.

## Development rules for every update

1. Preserve existing working UI and behavior unless a change is explicitly part of the task.
2. Keep Flutter responsible for presentation and interaction; keep core editing rules and authoritative project state in Rust.
3. Do not edit generated bridge files manually. Change the Rust API and regenerate bindings.
4. Add Rust unit tests and Flutter tests for new behavior.
5. Build and test on Android after native code, bridge, or packaging changes.
6. Do not mark a feature complete because its button or mock UI exists; test the real behavior.
7. Each update should include a changelog, changed-file list, build/test commands, and any known limitations.

## Recommended next step

Manually verify **Phase 2 media import and project management** using [PHASE2_MEDIA.md](PHASE2_MEDIA.md). Phase 1 is confirmed complete. After Phase 2 acceptance, continue with Phase 3 preview behavior.
