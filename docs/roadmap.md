# CharpCut roadmap

## Phase 0 - Foundation
- [x] Rust project model with a versioned, validated JSON file format
- [x] Editing engine in Rust: empty project, add/split/trim/delete, undo/redo, save/open
- [x] Bridge API redesigned around the engine and bindings regenerated (no demo project)
- [x] Flutter editor reads all state from Rust through an `EditorEngine` interface; tests use an in-memory engine
- [x] Render-engine decision written down (`docs/decisions/0001-render-engine.md`)
- [ ] Confirm the render-engine decision (Android first?)
- [ ] Build the Rust library for Android (`scripts/build-android-lib.ps1`), then run on a device: confirm the native library loads and edits round-trip through Rust

## Phase 1 - Media import and projects
Media picker, durations, thumbnails, save/load/autosave drafts, real drafts on the home screen.

## Phase 2 - Preview and playback
## Phase 3 - Core editing (drag trim, reorder, speed, volume, zoom, snapping)
## Phase 4 - Export (render, progress, save to gallery, share, GIF)
## Phase 5 - Audio and text
## Phase 6 - Visual effects
## Phase 7 - Photo editing, polish and release
