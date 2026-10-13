# CharpCut — Feature Development Roadmap

This roadmap describes the recommended order for growing CharpCut from its current Flutter + Rust foundation into a practical mobile video editor. Treat each phase as a separate, testable milestone. Preserve existing working features and verify changes on an Android device before moving to the next phase.

> **Status note:** This is a plan, not a claim that every feature is already implemented. Confirm completion by testing the feature in the actual app. The current project documentation identifies media import, real preview/playback, and real export as unfinished areas.

## Architecture at a glance

- **Flutter UI:** `apps/mobile/lib/` — screens, controls, timeline presentation, user interactions, and theme.
- **Dart engine boundary:** `apps/mobile/lib/engine/` — engine interface, Rust adapter, and Dart state parsing.
- **Flutter–Rust bridge:** `apps/mobile/lib/src/rust/`, `flutter_rust_bridge.yaml`, and generated bridge code — exposes Rust functions to Dart. Do not hand-edit generated files.
- **Rust editing API/engine:** `rust/crates/editor_api/src/` — bridge-facing commands, authoritative editing state, edit operations, history, and state snapshots.
- **Timeline data model:** `rust/crates/timeline/src/lib.rs` — project, media asset, track, clip, serialization, and timeline validation.
- **Android packaging/build:** `apps/mobile/android/` and `scripts/build-android-lib.ps1` — Android configuration and native Rust library packaging.
- **Tests:** `apps/mobile/test/` and Rust crate tests — validate UI behavior, state parsing, bridge integration, and editing rules.

## Phase 0 — Foundation and Android stability

**Goal:** Keep the app buildable and establish a reliable baseline before adding features.

- [ ] Run `cargo test` from `rust/`.
- [ ] Run `flutter test` from `apps/mobile/`.
- [ ] Build the Rust shared library for the target Android ABI(s).
- [ ] Confirm the `.so` library is packaged in the APK and loads on a real device.
- [ ] Verify create project, add clip, split, undo, redo, save, and open round-trip correctly.
- [ ] Record known limitations and the chosen media/rendering architecture.

**Acceptance criteria:** Rust and Flutter tests pass; the app launches on Android; a basic edit can be made, undone/redone, saved, and restored.

## Phase 1 — Engine integration and project persistence

**Goal:** Ensure editing commands use one authoritative project state.

- [ ] Route every editing control through `EditorEngine` and the Rust API.
- [ ] Remove duplicate/mock timeline state from production flows where applicable.
- [ ] Complete undo/redo for every supported edit operation.
- [ ] Save and reopen versioned project JSON.
- [ ] Add autosave and draft recovery.
- [ ] Add useful validation and user-facing errors for failed operations.
- [ ] Add engine and bridge integration tests.

**Likely locations:** `editor_screen.dart`, `engine/editor_engine.dart`, `engine/rust_engine.dart`, `engine/editor_state.dart`, `rust/crates/editor_api/`, and `rust/crates/timeline/`.

**Acceptance criteria:** UI state consistently matches Rust state; edits survive app restart; undo/redo is reliable.

## Phase 2 — Media import and project management

**Goal:** Let users bring their own media into projects.

- [ ] Import video from Android's system picker.
- [ ] Import audio and still images.
- [ ] Handle file permissions and persist access safely or copy media into app-managed storage when needed.
- [ ] Read duration, dimensions, orientation, frame rate, and audio-stream metadata.
- [ ] Generate thumbnails and video filmstrips.
- [ ] Show imported media in a media library.
- [ ] Create, rename, duplicate, and delete projects.
- [ ] Display recent drafts on the home screen.
- [ ] Handle moved, deleted, unsupported, or inaccessible source files.

**Acceptance criteria:** A user can import media, see its metadata and thumbnail, add it to a project, and reopen the project later.

## Phase 3 — Real preview and playback

**Goal:** Display and play the actual source media in timeline order.

- [ ] Choose and document the media decoding and rendering architecture before building advanced effects.
- [ ] Implement play/pause and accurate seeking.
- [ ] Render the clip at the current playhead position.
- [ ] Synchronize audio and video.
- [ ] Handle gaps, black frames, orientation, aspect ratios, and portrait/landscape projects.
- [ ] Support multiple consecutive clips and transitions in preview.
- [ ] Handle buffering, decoding errors, and resource cleanup.

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

**Architecture decision:** If using FFmpeg or another third-party media engine, review Android build support, codec availability, distribution/licensing obligations, and compatibility with the Rust architecture before committing.

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

## Suggested implementation updates

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

## Development rules for every update

1. Preserve existing working UI and behavior unless a change is explicitly part of the task.
2. Keep Flutter responsible for presentation and interaction; keep core editing rules and authoritative project state in Rust.
3. Do not edit generated bridge files manually. Change the Rust API and regenerate bindings.
4. Add Rust unit tests and Flutter tests for new behavior.
5. Build and test on Android after native code, bridge, or packaging changes.
6. Do not mark a feature complete because its button or mock UI exists; test the real behavior.
7. Each update should include a changelog, changed-file list, build/test commands, and any known limitations.

## Recommended next step

Start with **Update 01 / Phase 0 verification**, then finish **Phase 1 engine integration and persistence** before building media playback or effects. This reduces the risk of implementing features on top of duplicate or temporary state.
