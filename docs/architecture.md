# Architecture

## Modules
- `apps/mobile` - Flutter UI (home, editor, export screens) and the Dart side of the bridge.
- `rust/crates/timeline` - UI-independent project model and timeline operations; owns the saved-file format.
- `rust/crates/editor_api` - the editing engine (selection, edits, undo/redo) and the bridge-facing API.
- `flutter_rust_bridge.yaml` - bridge generator configuration.

## Ownership
Rust owns the project and the history. Flutter holds only the latest state snapshot it was given and asks the
engine for every change. See `docs/bridge-integration.md`.

## Project file
JSON, `version` 1 (`SCHEMA_VERSION` in the timeline crate). Opening a file with a newer version fails with a
clear message; older versions get a migration step in `Project::from_json`. Every file is validated on open
and before save: unique ids, clips inside their source media, no overlaps on a track.

## Main track
The editor works on one gapless video track. After every edit the engine closes gaps, so clip start times
are always derived, never typed in by the UI.

## Decided / proposed
- Preview and export engine: see `docs/decisions/0001-render-engine.md` (proposed, needs confirmation).

## Not built yet
Media import, thumbnails, real preview, export, audio/text tracks, effects. See `docs/roadmap.md`.
