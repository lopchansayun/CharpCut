//! Functions exposed to Flutter. Each call locks the one shared [`Engine`], applies
//! a change and returns the new editor state as JSON (see `EditorSnapshot`).
//! Keep this file thin: the logic and its tests live in `engine.rs`.

use std::sync::{Mutex, MutexGuard, OnceLock};

use crate::engine::Engine;

static ENGINE: OnceLock<Mutex<Engine>> = OnceLock::new();

fn engine() -> MutexGuard<'static, Engine> {
    // A panic in an earlier call must not brick the editor, so recover a poisoned lock.
    ENGINE
        .get_or_init(|| Mutex::new(Engine::new()))
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
}

/// Bridge integers are signed; negative values are treated as zero.
fn millis(value: i64) -> u64 {
    u64::try_from(value).unwrap_or(0)
}

/// Starts an empty project and returns its state.
pub fn new_project() -> String {
    let mut e = engine();
    e.new_project();
    e.snapshot_json()
}

/// Returns the current editor state.
pub fn get_editor_state() -> String {
    engine().snapshot_json()
}

/// Clamps the session playhead to the current project duration, without history.
pub fn seek_playhead(timeline_ms: i64) -> String {
    let mut e = engine();
    e.seek(millis(timeline_ms));
    e.snapshot_json()
}

/// Sets the main video track's saved, undoable mute flag.
pub fn set_main_track_muted(muted: bool) -> String {
    let mut e = engine();
    e.set_main_track_muted(muted);
    e.snapshot_json()
}

/// Moves the selected clip to a final zero-based index on the gapless track.
pub fn move_selected_clip(target_index: i64) -> String {
    let mut e = engine();
    e.move_selected(target_index);
    e.snapshot_json()
}

/// Selects a clip, or clears the selection when `clip_id` is `None`.
pub fn select_clip(clip_id: Option<String>) -> String {
    let mut e = engine();
    e.select(clip_id.as_deref());
    e.snapshot_json()
}

/// Appends a clip covering a whole media file and selects it.
pub fn add_clip(path: String, duration_ms: i64) -> String {
    let mut e = engine();
    e.add_clip(&path, millis(duration_ms));
    e.snapshot_json()
}

/// Splits the selected clip at a position on the timeline (the playhead).
pub fn split_selected_clip_at(timeline_ms: i64) -> String {
    let mut e = engine();
    e.split_selected(millis(timeline_ms));
    e.snapshot_json()
}

/// Sets the source start and length of the selected clip.
pub fn trim_selected_clip(source_in_ms: i64, duration_ms: i64) -> String {
    let mut e = engine();
    e.trim_selected(millis(source_in_ms), millis(duration_ms));
    e.snapshot_json()
}

/// Deletes the selected clip.
pub fn delete_selected_clip() -> String {
    let mut e = engine();
    e.delete_selected();
    e.snapshot_json()
}

/// Undoes the last edit.
pub fn undo() -> String {
    let mut e = engine();
    e.undo();
    e.snapshot_json()
}

/// Redoes the last undone edit.
pub fn redo() -> String {
    let mut e = engine();
    e.redo();
    e.snapshot_json()
}

/// The project as JSON, ready to be written to a file. Empty if it could not be produced.
pub fn export_project_json() -> String {
    engine().save_json().unwrap_or_default()
}

/// Replaces the project with one read from saved JSON. A bad file leaves the current
/// project alone and is reported in `last_error`.
pub fn open_project_json(json: String) -> String {
    let mut e = engine();
    e.open_json(&json);
    e.snapshot_json()
}
