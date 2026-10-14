# CharpCut feature roadmap

This is the single source of truth for feature planning. `[x]` means the feature is implemented and accepted in the owner's Android testing; `[ ]` means work or targeted verification remains. The owner confirmed Phase 4 complete on 2026-10-14 after Android testing. Automated checks from implementation are recorded in the architecture guide; this documentation update did not rerun them.

## Current status

- **Phase 1: complete.** Rust-driven editing, undo/redo, autosave and project persistence work on the owner's device.
- **Phase 2: complete.** Video/audio/image import, media metadata, thumbnails, library and project management work on the owner's device.
- **Phase 3: interactive preview accepted.** The owner ran the app and confirmed playback, seeking, fullscreen and zoom/pan work. A gap fixture and decoder-failure paths still need targeted checks because normal editing does not produce gaps.
- **Phase 4: complete.** The owner accepted timeline editing, multi-select, track reorder, saved properties, preview composition, overlapping audio/image/overlay clips, and playback-only fullscreen on 2026-10-14.

## Phase 0 — Foundation and Android stability

- [x] Versioned Rust project model and validated JSON save/open.
- [x] Rust editing engine and generated Flutter bridge load on Android.
- [x] Android-first Media3 decision recorded in [0001-render-engine.md](decisions/0001-render-engine.md).
- [x] App launches and basic edits work on the owner's device.
- [ ] Automate the Rust Android library build in Gradle; for now use `scripts/build-android-lib.ps1` after Rust changes.

## Phase 1 — Engine integration and project persistence

- [x] Route supported controls through Rust: add, select, seek, split, trim, delete, mute, reorder, undo and redo.
- [x] Keep one authoritative state, with playhead/selection transient and saved edits undoable.
- [x] Save/reopen schema 2 project JSON; migrate schema 1 and reject corrupt/newer files.
- [x] Autosave, multiple independent drafts, recovery, and visible storage errors.
- [x] Owner-confirmed edit, reopen, restart and history flows on Android.

## Phase 2 — Media import and project management

- [x] Import video, audio and still images through Android's document picker into app-private storage.
- [x] Inspect available duration, dimensions, orientation, frame rate, audio streams and file details.
- [x] Show a searchable, filtered media library; reuse an imported video in another project.
- [x] Generate thumbnail previews and filmstrip tiles from imported video ranges.
- [x] Create, rename, duplicate, delete and resume drafts from Home and Projects.
- [x] Report missing, inaccessible and unsupported media. Private imports remain usable when the external original moves.

Audio and image files are library assets in this phase. Adding them to editable tracks belongs to Phases 4 and 6. Imported source cleanup and automatic relinking remain future reliability work.

## Phase 3 — Real preview and playback

- [x] Use the approved Android Media3 renderer with source ranges supplied from the validated Rust snapshot.
- [x] Play/pause, seek, scrub, frame-time steps and five-second skips in one player.
- [x] Preview consecutive clips, source audio, mute, trim/split/reorder edits and the playhead position.
- [x] Support fullscreen, orientation requests, source/project fit and viewing-only zoom/pan/reset.
- [x] Display buffering and decoder errors, explicit retry, and pause/release on lifecycle and audio interruptions.
- [x] Implement black/silent playback for leading, intermediate and trailing gaps in a loaded timeline.
- [ ] Exercise gap playback with a valid fixture and decoder-failure recovery on a device; the normal editor packs clips without gaps.

Consecutive clips currently use hard cuts. Fade and crossfade authoring/rendering belong to Phase 5. Viewing zoom is transient; Phase 4 Properties saves canvas crop and scale independently. A dedicated Rust renderer edit list and shared preview/export interface remain planned before the composition/export pipeline grows.

## Phase 4 — Essential timeline editing

Direct preview layer selection, move/scale/rotate/delete controls, timeline trim handles, and overlapping audio/image/overlay clips are implemented. Numeric dialogs stay anchored when the keyboard opens. Playback synchronization and tick processing have been optimized; the owner accepted gesture behavior and audio playback on the device.


**Status:** Complete — owner acceptance recorded on 2026-10-14.

**Goal:** Make timeline operations useful with real media.

- [x] Split, trim start/end, move, reorder, delete, duplicate, and ripple-delete clips.
- [x] Add timeline zoom, horizontal scrolling, a time ruler, snapping, and precise playhead control.
- [x] Support video, audio, image, and overlay tracks.
- [x] Add clip selection, multi-select, track lock, and track reorder.
- [x] Add position, duration, scale, rotation, crop, opacity, and volume properties.
- [x] Keep undo/redo and saved projects consistent for every operation.

**Acceptance criteria:** Editing operations update both the timeline and preview, and remain correct after save/reopen and undo/redo.

**Current implementation:** Each listed operation is implemented. Select multiple clips with **Select**, then move by a signed time offset, duplicate, delete while retaining gaps, or ripple-delete in one undo step. **Tracks** reorders existing lanes and the visual layer stack; the last lane is the front layer. Locked tracks cannot be edited or moved, including indirectly by reordering another lane.

**Properties** edits timeline start/duration, canvas X/Y position, scale (10–1000%), rotation (±180°), per-edge canvas crop, opacity, and video/audio volume (0–100%). Overlaps on the main video track and invalid ranges are rejected atomically; audio, image, and overlay clips may overlap. Visual transforms compose in project-canvas coordinates; pinch gestures transform a selected layer in the editor, or adjust inspection zoom when no layer is selected. Fullscreen disables these gestures. Secondary clip trimming and deletion preserve neighboring positions. Main-video trim and ripple delete shift later clips by the duration change. Explicit clip reorder repacks its lane.

Schema 5 preserves properties and track order and migrates schemas 1–4 with default properties. Android preview applies per-clip volume to video and audio playlists; Flutter renders visual properties and layer order. Tests cover persistence, undo/redo, lock rejection, batch atomicity, migration, and property-form/multi-select commands. The owner has accepted Phase 4 on the device; this phase is closed.

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
- [ ] Extract audio from a video into an independently editable audio clip.
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

## Dependencies and implementation rules

- Phases 4–6 need new saved project fields. Bump `SCHEMA_VERSION`, add migrations, update the Rust API, and regenerate bridge bindings when it changes.
- Effects and audio edits need both preview and export support. A UI control or stored parameter alone does not complete a feature.
- Android is the first release target; iOS requires a separate AVFoundation implementation. The approved design is in [0001-render-engine.md](decisions/0001-render-engine.md).
- Keep Rust responsible for editing rules and Flutter responsible for presentation. Do not edit generated bindings by hand.
- Verify new behavior on Android. The project owner currently runs device and test checks manually.

## Recommended next step

Phase 5 is next: text, transitions between clips (fade/crossfade), and visual effects. Audio extraction remains planned for Phase 6. Targeted gap/error preview fixtures remain a separate reliability follow-up.

Main video preview keeps direct touch transforms without the blue range slider or floating delete/transform handles. Secondary clips can be long-press-dragged to overlap and remain separately selectable.

Fullscreen preview is playback-only: no layer selection, transform handles, drag, pinch scale/rotation, or viewing zoom. Entering fullscreen resets inspection zoom while retaining saved composition transforms.
