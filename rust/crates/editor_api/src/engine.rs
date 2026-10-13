//! The editing engine behind the bridge. It owns the project, the selection and
//! the undo/redo history, and is plain Rust so it can be unit-tested without
//! Flutter. `api.rs` wraps one shared instance for the app.

use charpcut_timeline::{Millis, Project, TimelineError, TrackKind, MIN_CLIP_MS};
use serde::Serialize;

/// How many edits can be undone.
const UNDO_LIMIT: usize = 100;

const DEFAULT_WIDTH: u32 = 1080;
const DEFAULT_HEIGHT: u32 = 1920;
const DEFAULT_FPS: u32 = 30;

/// State captured before each edit so it can be restored.
#[derive(Debug, Clone)]
struct Snapshot {
    project: Project,
    selected_clip_id: Option<String>,
}

/// What the UI reads after every call. Field names stay snake_case, the same as
/// the project file, so Dart only deals with one naming style.
#[derive(Debug, Clone, Serialize)]
pub struct EditorSnapshot {
    pub project: Project,
    /// The gapless video track the editor works on.
    pub main_track_id: String,
    pub selected_clip_id: Option<String>,
    pub total_duration_ms: Millis,
    pub playhead_ms: Millis,
    pub main_track_muted: bool,
    pub can_undo: bool,
    pub can_redo: bool,
    /// Short message for the last successful edit.
    pub status: String,
    /// Set when the last call was refused; the project is unchanged in that case.
    pub last_error: Option<String>,
}

#[derive(Debug)]
pub struct Engine {
    project: Project,
    main_track_id: String,
    selected_clip_id: Option<String>,
    playhead_ms: Millis,
    undo: Vec<Snapshot>,
    redo: Vec<Snapshot>,
    status: String,
    last_error: Option<String>,
}

impl Default for Engine {
    fn default() -> Self {
        Self::new()
    }
}

impl Engine {
    /// An empty project with one video track.
    pub fn new() -> Self {
        let (project, main_track_id) = blank_project();
        Self {
            project,
            main_track_id,
            selected_clip_id: None,
            playhead_ms: 0,
            undo: Vec::new(),
            redo: Vec::new(),
            status: "New project".into(),
            last_error: None,
        }
    }

    // ----- project lifecycle -------------------------------------------------

    pub fn new_project(&mut self) {
        *self = Self::new();
    }

    /// Replaces the project with one read from saved JSON. A bad file is refused
    /// and the current project is left alone.
    pub fn open_json(&mut self, json: &str) {
        match Project::from_json(json) {
            Ok(mut project) => {
                let main_track_id = match project.tracks.iter().find(|t| t.kind == TrackKind::Video) {
                    Some(track) => track.id.clone(),
                    None => project.add_track(TrackKind::Video),
                };
                self.project = project;
                self.main_track_id = main_track_id;
                self.selected_clip_id = None;
                self.playhead_ms = 0;
                self.undo.clear();
                self.redo.clear();
                self.succeed("Project opened");
            }
            Err(error) => self.fail(error.to_string()),
        }
    }

    /// The project as JSON for saving. Fails only if the project is invalid.
    pub fn save_json(&self) -> Result<String, String> {
        self.project.validate().map_err(|e| e.to_string())?;
        self.project.to_json().map_err(|e| e.to_string())
    }

    // ----- selection (not an edit, so it is not undoable) ------------------------

    pub fn select(&mut self, clip_id: Option<&str>) {
        match clip_id {
            None => {
                self.selected_clip_id = None;
                self.last_error = None;
            }
            Some(id) if self.project.find_clip(id).is_some() => {
                self.selected_clip_id = Some(id.to_string());
                self.last_error = None;
            }
            Some(_) => self.fail("Clip not found".into()),
        }
    }

    // ----- edits -------------------------------------------------------------

    /// Seeking is session state, not an undoable project edit.
    pub fn seek(&mut self, timeline_ms: Millis) {
        self.playhead_ms = timeline_ms.min(self.project.total_duration_ms());
        self.last_error = None;
    }

    pub fn set_main_track_muted(&mut self, muted: bool) {
        let track = self.main_track_id.clone();
        self.edit(if muted { "Track muted" } else { "Track unmuted" }, move |project, _| {
            project.tracks.iter_mut().find(|t| t.id == track)
                .ok_or("Video track not found")?.muted = muted;
            Ok(())
        });
    }

    pub fn move_selected(&mut self, target_index: i64) {
        let track = self.main_track_id.clone();
        self.edit("Clip moved", move |project, selected| {
            let clip = selected.as_deref().ok_or("Select a clip first")?;
            let index = usize::try_from(target_index).map_err(|_| "Clip position must not be negative")?;
            project.reorder_clip(&track, clip, index).map_err(describe)
        });
    }

    /// Appends a clip covering the whole of a media file and selects it.
    pub fn add_clip(&mut self, path: &str, duration_ms: Millis) {
        let track = self.main_track_id.clone();
        let path = path.to_string();
        self.edit("Clip added", move |project, selected| {
            if path.trim().is_empty() {
                return Err("Media path is empty".into());
            }
            if duration_ms < MIN_CLIP_MS {
                return Err("Media is too short to add".into());
            }
            let asset = project.add_asset(path, duration_ms);
            let clip = project.append_clip(&track, &asset, 0, duration_ms).map_err(describe)?;
            *selected = Some(clip);
            Ok(())
        });
    }

    /// Splits the selected clip at an absolute timeline position and selects the second half.
    pub fn split_selected(&mut self, timeline_ms: Millis) {
        let track = self.main_track_id.clone();
        self.edit("Clip split", move |project, selected| {
            let clip = selected.clone().ok_or("Select a clip first")?;
            let (_, second) = project.split_clip_at(&track, &clip, timeline_ms).map_err(describe)?;
            *selected = Some(second);
            Ok(())
        });
    }

    /// Sets which part of the source the selected clip plays. The track closes up afterwards.
    pub fn trim_selected(&mut self, source_in_ms: Millis, duration_ms: Millis) {
        let track = self.main_track_id.clone();
        self.edit("Clip trimmed", move |project, selected| {
            let clip = selected.clone().ok_or("Select a clip first")?;
            project.trim_clip(&track, &clip, source_in_ms, duration_ms).map_err(describe)?;
            project.ripple_track(&track).map_err(describe)?;
            Ok(())
        });
    }

    pub fn delete_selected(&mut self) {
        let track = self.main_track_id.clone();
        self.edit("Clip deleted", move |project, selected| {
            let clip = selected.take().ok_or("Select a clip first")?;
            project.delete_clip(&track, &clip).map_err(describe)?;
            project.ripple_track(&track).map_err(describe)?;
            Ok(())
        });
    }

    // ----- history -----------------------------------------------------------

    pub fn undo(&mut self) {
        let Some(previous) = self.undo.pop() else {
            return self.fail("Nothing to undo".into());
        };
        self.redo.push(self.capture());
        self.restore(previous);
        self.succeed("Undid last edit");
    }

    pub fn redo(&mut self) {
        let Some(next) = self.redo.pop() else {
            return self.fail("Nothing to redo".into());
        };
        self.undo.push(self.capture());
        self.restore(next);
        self.succeed("Redid edit");
    }

    // ----- reading -----------------------------------------------------------

    pub fn snapshot(&self) -> EditorSnapshot {
        EditorSnapshot {
            project: self.project.clone(),
            main_track_id: self.main_track_id.clone(),
            selected_clip_id: self.selected_clip_id.clone(),
            total_duration_ms: self.project.total_duration_ms(),
            playhead_ms: self.playhead_ms,
            main_track_muted: self.project.tracks.iter().find(|t| t.id == self.main_track_id).is_some_and(|t| t.muted),
            can_undo: !self.undo.is_empty(),
            can_redo: !self.redo.is_empty(),
            status: self.status.clone(),
            last_error: self.last_error.clone(),
        }
    }

    pub fn snapshot_json(&self) -> String {
        serde_json::to_string(&self.snapshot())
            .unwrap_or_else(|_| r#"{"last_error":"Could not read the editor state"}"#.to_string())
    }

    // ----- internals ---------------------------------------------------------

    /// Runs one edit. If it fails the project and selection are exactly as before and
    /// nothing is added to the history; if it succeeds the previous state becomes undoable.
    fn edit(
        &mut self,
        success: &str,
        change: impl FnOnce(&mut Project, &mut Option<String>) -> Result<(), String>,
    ) {
        let before = self.capture();
        let result = change(&mut self.project, &mut self.selected_clip_id)
            .and_then(|_| self.project.validate().map_err(describe));
        match result {
            Ok(()) => {
                if self.project != before.project {
                    self.undo.push(before);
                    if self.undo.len() > UNDO_LIMIT {
                        self.undo.remove(0);
                    }
                    self.redo.clear();
                }
                self.playhead_ms = self.playhead_ms.min(self.project.total_duration_ms());
                self.succeed(success);
            }
            Err(message) => {
                self.restore(before);
                self.fail(message);
            }
        }
    }

    fn capture(&self) -> Snapshot {
        Snapshot { project: self.project.clone(), selected_clip_id: self.selected_clip_id.clone() }
    }

    fn restore(&mut self, snapshot: Snapshot) {
        self.project = snapshot.project;
        self.playhead_ms = self.playhead_ms.min(self.project.total_duration_ms());
        self.selected_clip_id = snapshot
            .selected_clip_id
            .filter(|id| self.project.find_clip(id).is_some());
    }

    fn succeed(&mut self, status: &str) {
        self.status = status.to_string();
        self.last_error = None;
    }

    fn fail(&mut self, message: String) {
        self.last_error = Some(message);
    }
}

fn blank_project() -> (Project, String) {
    let mut project = Project::new(DEFAULT_WIDTH, DEFAULT_HEIGHT, DEFAULT_FPS, 1);
    let track = project.add_track(TrackKind::Video);
    (project, track)
}

/// Turns timeline errors into messages the UI can show as they are.
fn describe(error: TimelineError) -> String {
    match error {
        TimelineError::InvalidSplitPosition => "Move the playhead inside the clip to split it".into(),
        TimelineError::InvalidDuration => "That would make the clip too short".into(),
        TimelineError::SourceRangeOutOfBounds => "That is outside the original media".into(),
        other => other.to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mute_is_undoable_and_survives_save_open() {
        let mut e = engine_with_clip(4_000);
        e.set_main_track_muted(true);
        assert!(e.snapshot().main_track_muted);
        let saved = e.save_json().unwrap();
        e.undo();
        assert!(!e.snapshot().main_track_muted);
        e.redo();
        assert!(e.snapshot().main_track_muted);
        e.open_json(&saved);
        assert!(e.snapshot().main_track_muted);
    }

    #[test]
    fn move_is_gapless_undoable_and_keeps_selection() {
        let mut e = engine_with_clip(4_000);
        e.add_clip("b.mp4", 3_000);
        let selected = e.snapshot().selected_clip_id;
        e.move_selected(0);
        assert_eq!(clips(&e), vec![(0, 0, 3_000), (3_000, 0, 4_000)]);
        assert_eq!(e.snapshot().selected_clip_id, selected);
        e.undo();
        assert_eq!(clips(&e), vec![(0, 0, 4_000), (4_000, 0, 3_000)]);
        e.redo();
        assert_eq!(clips(&e), vec![(0, 0, 3_000), (3_000, 0, 4_000)]);
        let saved = e.save_json().unwrap();
        e.open_json(&saved);
        assert_eq!(clips(&e), vec![(0, 0, 3_000), (3_000, 0, 4_000)]);
    }

    #[test]
    fn invalid_move_preserves_project_history_and_selection() {
        let mut e = engine_with_clip(4_000);
        let before = e.save_json().unwrap();
        let selected = e.snapshot().selected_clip_id;
        for index in [-1, 1, i64::MAX] {
            e.move_selected(index);
            assert!(e.snapshot().last_error.is_some());
            assert_eq!(e.save_json().unwrap(), before);
            assert_eq!(e.snapshot().selected_clip_id, selected);
        }
        e.undo();
        assert_eq!(e.snapshot().total_duration_ms, 0);
        assert!(!e.snapshot().can_undo);
    }

    #[test]
    fn no_op_controls_and_seek_preserve_redo_and_do_not_add_history() {
        let mut e = engine_with_clip(4_000);
        e.set_main_track_muted(true);
        e.undo();
        e.set_main_track_muted(false);
        e.move_selected(0);
        e.seek(2_000);
        assert!(e.snapshot().can_redo);
        e.redo();
        assert!(e.snapshot().main_track_muted);
        e.undo();
        e.undo();
        assert_eq!(e.snapshot().total_duration_ms, 0);
        assert!(!e.snapshot().can_undo);
    }

    #[test]
    fn playhead_clamps_after_edits_and_history_and_resets_on_open() {
        let mut e = engine_with_clip(4_000);
        e.seek(10_000);
        assert_eq!(e.snapshot().playhead_ms, 4_000);
        e.trim_selected(0, 2_000);
        assert_eq!(e.snapshot().playhead_ms, 2_000);
        e.undo();
        assert_eq!(e.snapshot().playhead_ms, 2_000);
        e.seek(3_000);
        e.redo();
        assert_eq!(e.snapshot().playhead_ms, 2_000);
        e.delete_selected();
        assert_eq!(e.snapshot().playhead_ms, 0);
        e.undo();
        e.seek(1_000);
        let saved = e.save_json().unwrap();
        e.open_json(&saved);
        assert_eq!(e.snapshot().playhead_ms, 0);
    }

    fn engine_with_clip(duration: Millis) -> Engine {
        let mut e = Engine::new();
        e.add_clip("a.mp4", duration);
        e
    }

    fn clips(e: &Engine) -> Vec<(Millis, Millis, Millis)> {
        // (timeline_start, source_in, duration)
        e.snapshot().project.tracks[0]
            .clips
            .iter()
            .map(|c| (c.timeline_start_ms, c.source_in_ms, c.duration_ms))
            .collect()
    }

    #[test]
    fn a_new_project_is_empty_and_has_no_history() {
        let s = Engine::new().snapshot();
        assert_eq!(s.total_duration_ms, 0);
        assert!(s.project.assets.is_empty());
        assert_eq!(s.project.tracks.len(), 1);
        assert!(!s.can_undo && !s.can_redo);
        assert_eq!(s.selected_clip_id, None);
    }

    #[test]
    fn add_clip_appends_and_selects() {
        let mut e = engine_with_clip(4_000);
        e.add_clip("b.mp4", 3_000);
        assert_eq!(clips(&e), vec![(0, 0, 4_000), (4_000, 0, 3_000)]);
        let s = e.snapshot();
        assert_eq!(s.total_duration_ms, 7_000);
        assert!(s.selected_clip_id.is_some());
        assert!(s.can_undo);
    }

    #[test]
    fn add_clip_rejects_empty_path_and_tiny_media() {
        let mut e = Engine::new();
        e.add_clip("  ", 3_000);
        assert!(e.snapshot().last_error.is_some());
        e.add_clip("a.mp4", 10);
        assert!(e.snapshot().last_error.is_some());
        assert!(e.snapshot().project.assets.is_empty());
        assert!(!e.snapshot().can_undo);
    }

    #[test]
    fn split_at_playhead_keeps_source_continuity() {
        let mut e = engine_with_clip(4_000);
        e.split_selected(1_500);
        assert_eq!(clips(&e), vec![(0, 0, 1_500), (1_500, 1_500, 2_500)]);
        // The second half is selected.
        let s = e.snapshot();
        let selected = s.selected_clip_id.unwrap();
        assert_eq!(s.project.tracks[0].clips[1].id, selected);
    }

    #[test]
    fn failed_split_changes_nothing_and_adds_no_history() {
        let mut e = engine_with_clip(4_000);
        e.split_selected(0);
        let s = e.snapshot();
        assert_eq!(s.last_error.as_deref(), Some("Move the playhead inside the clip to split it"));
        assert_eq!(clips(&e), vec![(0, 0, 4_000)]);
        assert!(s.selected_clip_id.is_some());
        // Only the add is on the history: one undo empties the project.
        e.undo();
        assert!(clips(&e).is_empty());
        assert!(!e.snapshot().can_undo);
    }

    #[test]
    fn edits_need_a_selection() {
        let mut e = engine_with_clip(4_000);
        e.select(None);
        e.delete_selected();
        assert_eq!(e.snapshot().last_error.as_deref(), Some("Select a clip first"));
        e.split_selected(1_000);
        assert_eq!(e.snapshot().last_error.as_deref(), Some("Select a clip first"));
    }

    #[test]
    fn trim_closes_the_gap_after_it() {
        let mut e = engine_with_clip(4_000);
        e.add_clip("b.mp4", 3_000);
        let first = e.snapshot().project.tracks[0].clips[0].id.clone();
        e.select(Some(&first));
        e.trim_selected(500, 2_000);
        assert_eq!(clips(&e), vec![(0, 500, 2_000), (2_000, 0, 3_000)]);
    }

    #[test]
    fn trim_outside_the_media_is_refused() {
        let mut e = engine_with_clip(4_000);
        e.trim_selected(3_000, 2_000);
        assert_eq!(e.snapshot().last_error.as_deref(), Some("That is outside the original media"));
        assert_eq!(clips(&e), vec![(0, 0, 4_000)]);
    }

    #[test]
    fn delete_removes_the_clip_clears_selection_and_closes_the_gap() {
        let mut e = engine_with_clip(4_000);
        e.add_clip("b.mp4", 3_000);
        let first = e.snapshot().project.tracks[0].clips[0].id.clone();
        e.select(Some(&first));
        e.delete_selected();
        assert_eq!(clips(&e), vec![(0, 0, 3_000)]);
        assert_eq!(e.snapshot().selected_clip_id, None);
    }

    #[test]
    fn the_last_clip_can_be_deleted() {
        let mut e = engine_with_clip(4_000);
        e.delete_selected();
        assert_eq!(e.snapshot().total_duration_ms, 0);
    }

    #[test]
    fn undo_and_redo_walk_through_edits_and_restore_selection() {
        let mut e = engine_with_clip(4_000);
        e.split_selected(1_000);
        e.delete_selected();
        assert_eq!(clips(&e), vec![(0, 0, 1_000)]);

        e.undo();
        assert_eq!(clips(&e), vec![(0, 0, 1_000), (1_000, 1_000, 3_000)]);
        assert!(e.snapshot().selected_clip_id.is_some());
        e.undo();
        assert_eq!(clips(&e), vec![(0, 0, 4_000)]);
        e.undo();
        assert!(clips(&e).is_empty());
        assert!(!e.snapshot().can_undo);

        e.undo();
        assert_eq!(e.snapshot().last_error.as_deref(), Some("Nothing to undo"));

        e.redo();
        e.redo();
        e.redo();
        assert_eq!(clips(&e), vec![(0, 0, 1_000)]);
        assert!(!e.snapshot().can_redo);
    }

    #[test]
    fn a_new_edit_clears_the_redo_history() {
        let mut e = engine_with_clip(4_000);
        e.split_selected(1_000);
        e.undo();
        assert!(e.snapshot().can_redo);
        e.trim_selected(0, 3_000);
        assert!(!e.snapshot().can_redo);
    }

    #[test]
    fn history_is_capped() {
        let mut e = Engine::new();
        for _ in 0..(UNDO_LIMIT + 20) {
            e.add_clip("a.mp4", 1_000);
        }
        let mut undone = 0;
        while e.snapshot().can_undo {
            e.undo();
            undone += 1;
        }
        assert_eq!(undone, UNDO_LIMIT);
    }

    #[test]
    fn save_and_open_round_trip() {
        let mut e = engine_with_clip(4_000);
        e.split_selected(1_000);
        let json = e.save_json().unwrap();

        let mut other = Engine::new();
        other.open_json(&json);
        let s = other.snapshot();
        assert_eq!(s.last_error, None);
        assert_eq!(clips(&other), vec![(0, 0, 1_000), (1_000, 1_000, 3_000)]);
        assert_eq!(s.selected_clip_id, None);
        assert!(!s.can_undo);
    }

    #[test]
    fn opening_a_bad_file_keeps_the_current_project() {
        let mut e = engine_with_clip(4_000);
        e.open_json("not json");
        assert!(e.snapshot().last_error.is_some());
        assert_eq!(clips(&e), vec![(0, 0, 4_000)]);
        assert!(e.snapshot().can_undo);
    }

    #[test]
    fn a_file_without_a_video_track_gets_one() {
        let mut p = Project::new(1920, 1080, 30, 1);
        p.add_track(TrackKind::Audio);
        let mut e = Engine::new();
        e.open_json(&p.to_json().unwrap());
        e.add_clip("a.mp4", 2_000);
        assert_eq!(e.snapshot().last_error, None);
        assert_eq!(e.snapshot().total_duration_ms, 2_000);
    }

    #[test]
    fn selecting_an_unknown_clip_is_an_error() {
        let mut e = engine_with_clip(4_000);
        e.select(Some("nope"));
        assert_eq!(e.snapshot().last_error.as_deref(), Some("Clip not found"));
    }

    #[test]
    fn new_project_resets_everything() {
        let mut e = engine_with_clip(4_000);
        e.new_project();
        let s = e.snapshot();
        assert_eq!(s.total_duration_ms, 0);
        assert!(!s.can_undo);
    }

    #[test]
    fn snapshot_json_has_the_fields_dart_reads() {
        let e = engine_with_clip(2_000);
        let v: serde_json::Value = serde_json::from_str(&e.snapshot_json()).unwrap();
        for key in ["project", "main_track_id", "selected_clip_id", "total_duration_ms", "can_undo", "can_redo", "status", "last_error"] {
            assert!(v.get(key).is_some(), "missing {key}");
        }
        assert_eq!(v["project"]["version"], charpcut_timeline::SCHEMA_VERSION);
        assert_eq!(v["project"]["tracks"][0]["clips"][0]["duration_ms"], 2_000);
    }
}
