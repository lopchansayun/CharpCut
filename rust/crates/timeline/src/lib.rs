use serde::{Deserialize, Serialize};
use thiserror::Error;
use uuid::Uuid;

pub type Millis = u64;

/// Version written into every saved project. Bump when the on-disk shape changes
/// in a way older builds cannot read, and add a migration in [`Project::from_json`].
pub const SCHEMA_VERSION: u32 = 5;

/// Shortest clip the editor will create by splitting or trimming.
pub const MIN_CLIP_MS: Millis = 100;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Project {
    pub id: String,
    pub version: u32,
    pub settings: ProjectSettings,
    pub assets: Vec<MediaAsset>,
    pub tracks: Vec<Track>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ProjectSettings {
    pub width: u32,
    pub height: u32,
    pub fps_num: u32,
    pub fps_den: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct MediaAsset {
    pub id: String,
    pub path: String,
    pub duration_ms: Millis,
    pub kind: MediaKind,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
pub enum MediaKind { Video, Audio, Image }

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Track {
    pub id: String,
    pub kind: TrackKind,
    pub muted: bool,
    pub locked: bool,
    pub clips: Vec<Clip>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum TrackKind {
    Video,
    Audio,
    Image,
    Overlay,
}

/// Normalized canvas translation/crop, degrees, and unit-range opacity/volume.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ClipProperties {
    pub x: f64, pub y: f64, pub scale: f64, pub rotation: f64,
    pub crop_left: f64, pub crop_top: f64, pub crop_right: f64, pub crop_bottom: f64,
    pub opacity: f64, pub volume: f64,
}
impl Default for ClipProperties {
    fn default() -> Self { Self { x: 0.0, y: 0.0, scale: 1.0, rotation: 0.0,
        crop_left: 0.0, crop_top: 0.0, crop_right: 0.0, crop_bottom: 0.0,
        opacity: 1.0, volume: 1.0 } }
}
impl ClipProperties {
    pub fn valid(&self) -> bool {
        let values = [self.x, self.y, self.scale, self.rotation, self.crop_left,
            self.crop_top, self.crop_right, self.crop_bottom, self.opacity, self.volume];
        values.iter().all(|v| v.is_finite()) && self.x.abs() <= 2.0 && self.y.abs() <= 2.0
            && (0.1..=10.0).contains(&self.scale) && self.rotation.abs() <= 180.0
            && [self.crop_left, self.crop_top, self.crop_right, self.crop_bottom,
                self.opacity, self.volume].iter().all(|v| (0.0..=1.0).contains(v))
            && self.crop_left + self.crop_right < 1.0 && self.crop_top + self.crop_bottom < 1.0
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Clip {
    pub id: String,
    pub asset_id: String,
    pub timeline_start_ms: Millis,
    pub source_in_ms: Millis,
    pub duration_ms: Millis,
    pub properties: ClipProperties,
}

impl Clip {
    pub fn timeline_end_ms(&self) -> Millis {
        self.timeline_start_ms.saturating_add(self.duration_ms)
    }

    pub fn source_out_ms(&self) -> Millis {
        self.source_in_ms.saturating_add(self.duration_ms)
    }
}

#[derive(Debug, Error, PartialEq, Eq)]
pub enum TimelineError {
    #[error("track was not found")]
    TrackNotFound,
    #[error("clip was not found")]
    ClipNotFound,
    #[error("duration must be greater than zero")]
    InvalidDuration,
    #[error("requested source range is outside the media asset")]
    SourceRangeOutOfBounds,
    #[error("split position must be inside the clip")]
    InvalidSplitPosition,
    #[error("asset was not found")]
    AssetNotFound,
    #[error("project file uses schema version {0}, which this build cannot open")]
    UnsupportedVersion(u32),
    #[error("invalid project: {0}")]
    InvalidProject(String),
    #[error("project data could not be read: {0}")]
    Json(String),
}

impl Project {
    pub fn new(width: u32, height: u32, fps_num: u32, fps_den: u32) -> Self {
        Self {
            id: Uuid::new_v4().to_string(),
            version: SCHEMA_VERSION,
            settings: ProjectSettings { width, height, fps_num, fps_den },
            assets: Vec::new(),
            tracks: Vec::new(),
        }
    }

    pub fn add_track(&mut self, kind: TrackKind) -> String {
        let id = Uuid::new_v4().to_string();
        self.tracks.push(Track { id: id.clone(), kind, muted: false, locked: false, clips: Vec::new() });
        id
    }

    pub fn add_asset(&mut self, path: impl Into<String>, duration_ms: Millis) -> String {
        let id = Uuid::new_v4().to_string();
        self.assets.push(MediaAsset { id: id.clone(), path: path.into(), duration_ms, kind: MediaKind::Video });
        id
    }

    pub fn add_media_asset(&mut self, path: impl Into<String>, duration_ms: Millis, kind: MediaKind) -> String {
        let id = Uuid::new_v4().to_string();
        self.assets.push(MediaAsset { id: id.clone(), path: path.into(), duration_ms, kind });
        id
    }

    pub fn add_clip(
        &mut self,
        track_id: &str,
        asset_id: &str,
        timeline_start_ms: Millis,
        source_in_ms: Millis,
        duration_ms: Millis,
    ) -> Result<String, TimelineError> {
        if duration_ms == 0 {
            return Err(TimelineError::InvalidDuration);
        }

        let asset = self.assets.iter().find(|a| a.id == asset_id)
            .ok_or(TimelineError::AssetNotFound)?;

        if source_in_ms.saturating_add(duration_ms) > asset.duration_ms {
            return Err(TimelineError::SourceRangeOutOfBounds);
        }

        let track = self.tracks.iter_mut().find(|t| t.id == track_id)
            .ok_or(TimelineError::TrackNotFound)?;
        if track.locked { return Err(TimelineError::InvalidProject("track is locked".into())); }
        let compatible = matches!((&track.kind, asset.kind),
            (TrackKind::Video, MediaKind::Video) | (TrackKind::Audio, MediaKind::Audio) |
            (TrackKind::Image, MediaKind::Image) | (TrackKind::Overlay, MediaKind::Image));
        if !compatible { return Err(TimelineError::InvalidProject("media type does not match track".into())); }

        let id = Uuid::new_v4().to_string();
        track.clips.push(Clip {
            id: id.clone(),
            asset_id: asset_id.to_string(),
            timeline_start_ms,
            source_in_ms,
            duration_ms,
            properties: ClipProperties::default(),
        });
        track.clips.sort_by_key(|c| c.timeline_start_ms);
        Ok(id)
    }

    pub fn trim_clip(
        &mut self,
        track_id: &str,
        clip_id: &str,
        new_source_in_ms: Millis,
        new_duration_ms: Millis,
    ) -> Result<(), TimelineError> {
        if new_duration_ms < MIN_CLIP_MS {
            return Err(TimelineError::InvalidDuration);
        }

        let track = self.tracks.iter_mut().find(|t| t.id == track_id)
            .ok_or(TimelineError::TrackNotFound)?;
        if track.locked { return Err(TimelineError::InvalidProject("track is locked".into())); }
        let clip = track.clips.iter_mut().find(|c| c.id == clip_id)
            .ok_or(TimelineError::ClipNotFound)?;
        let asset = self.assets.iter().find(|a| a.id == clip.asset_id)
            .ok_or(TimelineError::AssetNotFound)?;

        if new_source_in_ms.saturating_add(new_duration_ms) > asset.duration_ms {
            return Err(TimelineError::SourceRangeOutOfBounds);
        }

        clip.source_in_ms = new_source_in_ms;
        clip.duration_ms = new_duration_ms;
        Ok(())
    }

    pub fn move_clip(
        &mut self,
        track_id: &str,
        clip_id: &str,
        new_timeline_start_ms: Millis,
    ) -> Result<(), TimelineError> {
        let track = self.tracks.iter_mut().find(|t| t.id == track_id)
            .ok_or(TimelineError::TrackNotFound)?;
        if track.locked { return Err(TimelineError::InvalidProject("track is locked".into())); }
        let clip = track.clips.iter_mut().find(|c| c.id == clip_id)
            .ok_or(TimelineError::ClipNotFound)?;
        clip.timeline_start_ms = new_timeline_start_ms;
        track.clips.sort_by_key(|c| c.timeline_start_ms);
        Ok(())
    }

    /// Reorders a clip to a final index and repacks this track without gaps.
    pub fn reorder_clip(&mut self, track_id: &str, clip_id: &str, target_index: usize) -> Result<(), TimelineError> {
        let track = self.tracks.iter_mut().find(|t| t.id == track_id)
            .ok_or(TimelineError::TrackNotFound)?;
        if track.locked { return Err(TimelineError::InvalidProject("track is locked".into())); }
        let index = track.clips.iter().position(|c| c.id == clip_id)
            .ok_or(TimelineError::ClipNotFound)?;
        if target_index >= track.clips.len() {
            return Err(TimelineError::InvalidProject("clip position is outside the track".into()));
        }
        if index == target_index { return Ok(()); }
        let clip = track.clips.remove(index);
        track.clips.insert(target_index, clip);
        let mut cursor: Millis = 0;
        for clip in &mut track.clips {
            clip.timeline_start_ms = cursor;
            cursor = cursor.checked_add(clip.duration_ms)
                .ok_or_else(|| TimelineError::InvalidProject("timeline duration is too large".into()))?;
        }
        Ok(())
    }

    pub fn delete_clip(&mut self, track_id: &str, clip_id: &str) -> Result<Clip, TimelineError> {
        let track = self.tracks.iter_mut().find(|t| t.id == track_id)
            .ok_or(TimelineError::TrackNotFound)?;
        if track.locked { return Err(TimelineError::InvalidProject("track is locked".into())); }
        let index = track.clips.iter().position(|c| c.id == clip_id)
            .ok_or(TimelineError::ClipNotFound)?;
        Ok(track.clips.remove(index))
    }

    /// Inserts an independent copy immediately after a clip and closes the track.
    pub fn duplicate_clip(&mut self, track_id: &str, clip_id: &str) -> Result<String, TimelineError> {
        let track = self.tracks.iter_mut().find(|t| t.id == track_id)
            .ok_or(TimelineError::TrackNotFound)?;
        if track.locked { return Err(TimelineError::InvalidProject("track is locked".into())); }
        let index = track.clips.iter().position(|c| c.id == clip_id)
            .ok_or(TimelineError::ClipNotFound)?;
        let mut copy = track.clips[index].clone();
        copy.id = Uuid::new_v4().to_string();
        let id = copy.id.clone();
        copy.timeline_start_ms = copy.timeline_start_ms.checked_add(copy.duration_ms)
            .ok_or_else(|| TimelineError::InvalidProject("timeline too long".into()))?;
        for later in &mut track.clips[index + 1..] {
            if track.kind != TrackKind::Video { break; }
            later.timeline_start_ms = later.timeline_start_ms.checked_add(copy.duration_ms)
                .ok_or_else(|| TimelineError::InvalidProject("timeline too long".into()))?;
        }
        track.clips.insert(index + 1, copy);
        Ok(id)
    }

    pub fn split_clip(
        &mut self,
        track_id: &str,
        clip_id: &str,
        split_offset_ms: Millis,
    ) -> Result<(String, String), TimelineError> {
        let track = self.tracks.iter_mut().find(|t| t.id == track_id)
            .ok_or(TimelineError::TrackNotFound)?;
        if track.locked { return Err(TimelineError::InvalidProject("track is locked".into())); }
        let index = track.clips.iter().position(|c| c.id == clip_id)
            .ok_or(TimelineError::ClipNotFound)?;
        let original = track.clips[index].clone();

        if split_offset_ms < MIN_CLIP_MS || original.duration_ms.saturating_sub(split_offset_ms) < MIN_CLIP_MS {
            return Err(TimelineError::InvalidSplitPosition);
        }

        let first = Clip {
            duration_ms: split_offset_ms,
            ..original.clone()
        };
        let second = Clip {
            id: Uuid::new_v4().to_string(),
            timeline_start_ms: original.timeline_start_ms + split_offset_ms,
            source_in_ms: original.source_in_ms + split_offset_ms,
            duration_ms: original.duration_ms - split_offset_ms,
            ..original
        };

        track.clips[index] = first;
        track.clips.insert(index + 1, second.clone());
        Ok((track.clips[index].id.clone(), second.id))
    }

    /// Splits a clip at an absolute timeline position instead of an offset into the clip.
    pub fn split_clip_at(
        &mut self,
        track_id: &str,
        clip_id: &str,
        timeline_ms: Millis,
    ) -> Result<(String, String), TimelineError> {
        let track = self.tracks.iter().find(|t| t.id == track_id)
            .ok_or(TimelineError::TrackNotFound)?;
        let clip = track.clips.iter().find(|c| c.id == clip_id)
            .ok_or(TimelineError::ClipNotFound)?;
        if timeline_ms <= clip.timeline_start_ms {
            return Err(TimelineError::InvalidSplitPosition);
        }
        let offset = timeline_ms - clip.timeline_start_ms;
        self.split_clip(track_id, clip_id, offset)
    }

    /// Appends a clip after the last clip on the track.
    pub fn append_clip(
        &mut self,
        track_id: &str,
        asset_id: &str,
        source_in_ms: Millis,
        duration_ms: Millis,
    ) -> Result<String, TimelineError> {
        let start = self.tracks.iter().find(|t| t.id == track_id)
            .ok_or(TimelineError::TrackNotFound)?
            .end_ms();
        self.add_clip(track_id, asset_id, start, source_in_ms, duration_ms)
    }

    /// Re-packs a track so its clips follow each other with no gaps, keeping their order.
    /// The main video track uses this after every edit.
    pub fn ripple_track(&mut self, track_id: &str) -> Result<(), TimelineError> {
        let track = self.tracks.iter_mut().find(|t| t.id == track_id)
            .ok_or(TimelineError::TrackNotFound)?;
        if track.locked { return Err(TimelineError::InvalidProject("track is locked".into())); }
        track.clips.sort_by_key(|c| c.timeline_start_ms);
        let mut cursor = 0;
        for clip in &mut track.clips {
            clip.timeline_start_ms = cursor;
            cursor += clip.duration_ms;
        }
        Ok(())
    }

    /// Length of the whole project: the end of the last clip on any track.
    pub fn total_duration_ms(&self) -> Millis {
        self.tracks.iter().map(Track::end_ms).max().unwrap_or(0)
    }

    /// Finds a clip anywhere in the project and the id of the track that holds it.
    pub fn find_clip(&self, clip_id: &str) -> Option<(&Track, &Clip)> {
        self.tracks.iter().find_map(|t| t.clips.iter().find(|c| c.id == clip_id).map(|c| (t, c)))
    }

    /// The clip playing at a timeline position, if any.
    pub fn clip_at(&self, track_id: &str, timeline_ms: Millis) -> Option<&Clip> {
        self.tracks.iter().find(|t| t.id == track_id)?
            .clips.iter()
            .find(|c| timeline_ms >= c.timeline_start_ms && timeline_ms < c.timeline_end_ms())
    }

    /// Checks the invariants every saved or loaded project must hold.
    pub fn validate(&self) -> Result<(), TimelineError> {
        let bad = |msg: String| Err(TimelineError::InvalidProject(msg));
        let mut seen = std::collections::HashSet::new();

        if self.settings.width == 0 || self.settings.height == 0
            || self.settings.fps_num == 0 || self.settings.fps_den == 0
        {
            return bad("project size and frame rate must be non-zero".into());
        }
        for asset in &self.assets {
            if !seen.insert(asset.id.as_str()) {
                return bad(format!("duplicate id {}", asset.id));
            }
            if asset.path.trim().is_empty() {
                return bad(format!("asset {} has no path", asset.id));
            }
        }
        for track in &self.tracks {
            if !seen.insert(track.id.as_str()) {
                return bad(format!("duplicate id {}", track.id));
            }
            let mut previous_end = 0;
            for clip in &track.clips {
                if !seen.insert(clip.id.as_str()) {
                    return bad(format!("duplicate id {}", clip.id));
                }
                let Some(asset) = self.assets.iter().find(|a| a.id == clip.asset_id) else {
                    return bad(format!("clip {} points at a missing asset", clip.id));
                };
                let compatible = matches!((&track.kind, asset.kind),
                    (TrackKind::Video, MediaKind::Video) | (TrackKind::Audio, MediaKind::Audio) |
                    (TrackKind::Image, MediaKind::Image) | (TrackKind::Overlay, MediaKind::Image));
                if !compatible { return bad(format!("clip {} has media on the wrong track", clip.id)); }
                if !clip.properties.valid() { return bad("invalid clip properties".into()); }
                if clip.timeline_start_ms.checked_add(clip.duration_ms).is_none()
                    || clip.source_in_ms.checked_add(clip.duration_ms).is_none() {
                    return bad("clip duration is too large".into());
                }
                if clip.duration_ms == 0 || clip.source_out_ms() > asset.duration_ms {
                    return bad(format!("clip {} is outside its source media", clip.id));
                }
                if track.kind == TrackKind::Video && clip.timeline_start_ms < previous_end {
                    return bad(format!("clip {} overlaps the previous clip", clip.id));
                }
                previous_end = clip.timeline_end_ms();
            }
        }
        Ok(())
    }

    /// Serialises the project for saving.
    pub fn to_json(&self) -> Result<String, TimelineError> {
        serde_json::to_string(self).map_err(|e| TimelineError::Json(e.to_string()))
    }

    /// Reads a saved project, checking the schema version and invariants.
    pub fn from_json(json: &str) -> Result<Self, TimelineError> {
        // Read the version first so a newer file gives a clear error instead of a field error.
        #[derive(Deserialize)]
        struct Probe {
            version: u32,
        }
        let probe: Probe = serde_json::from_str(json).map_err(|e| TimelineError::Json(e.to_string()))?;
        if probe.version == 0 || probe.version > SCHEMA_VERSION {
            return Err(TimelineError::UnsupportedVersion(probe.version));
        }
        let mut value: serde_json::Value = serde_json::from_str(json).map_err(|e| TimelineError::Json(e.to_string()))?;
        if probe.version == 1 {
            // v1 did not persist mute. Always migrate to the historical unmuted default.
            if let Some(tracks) = value["tracks"].as_array_mut() {
                for track in tracks { track["muted"] = serde_json::Value::Bool(false); }
            }
        }
        if probe.version < 3 {
            if let Some(assets) = value["assets"].as_array_mut() {
                for asset in assets { asset["kind"] = serde_json::Value::String("Video".into()); }
            }
            if let Some(tracks) = value["tracks"].as_array_mut() {
                for track in tracks { track["locked"] = serde_json::Value::Bool(false); }
            }
            value["version"] = serde_json::Value::from(SCHEMA_VERSION);
        }
        if probe.version < 4 {
            if let Some(tracks) = value["tracks"].as_array_mut() {
                for track in tracks {
                    if let Some(clips) = track["clips"].as_array_mut() {
                        for clip in clips { clip["properties"] = serde_json::to_value(ClipProperties::default()).unwrap(); }
                    }
                }
            }
            value["version"] = serde_json::Value::from(SCHEMA_VERSION);
        }
        value["version"] = serde_json::Value::from(SCHEMA_VERSION);
        let project: Project = serde_json::from_value(value).map_err(|e| TimelineError::Json(e.to_string()))?;
        project.validate()?;
        Ok(project)
    }
}

impl Track {
    /// End of the last clip on this track.
    pub fn end_ms(&self) -> Millis {
        self.clips.iter().map(Clip::timeline_end_ms).max().unwrap_or(0)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn version_one_migrates_to_unmuted_current_schema() {
        let (p, _, _, _) = sample();
        let mut value = serde_json::to_value(&p).unwrap();
        value["version"] = 1.into();
        value["tracks"][0].as_object_mut().unwrap().remove("muted");
        let migrated = Project::from_json(&value.to_string()).unwrap();
        assert_eq!(migrated.version, SCHEMA_VERSION);
        assert!(!migrated.tracks[0].muted);
        assert_eq!(migrated.tracks[0].clips, p.tracks[0].clips);
    }

    #[test]
    fn current_schema_requires_a_valid_mute_field() {
        let (p, _, _, _) = sample();
        let mut value = serde_json::to_value(&p).unwrap();
        value["tracks"][0].as_object_mut().unwrap().remove("muted");
        assert!(Project::from_json(&value.to_string()).is_err());
        value["tracks"][0]["muted"] = "yes".into();
        assert!(Project::from_json(&value.to_string()).is_err());
    }

    #[test]
    fn reorder_preserves_source_ranges_and_repacks_track() {
        let (mut p, track, asset, first) = sample();
        let second = p.append_clip(&track, &asset, 6_000, 2_000).unwrap();
        p.reorder_clip(&track, &second, 0).unwrap();
        assert_eq!(p.tracks[0].clips[0].id, second);
        assert_eq!(p.tracks[0].clips[0].source_in_ms, 6_000);
        assert_eq!(p.tracks[0].clips[0].timeline_start_ms, 0);
        assert_eq!(p.tracks[0].clips[1].id, first);
        assert_eq!(p.tracks[0].clips[1].timeline_start_ms, 2_000);
        assert_eq!(p.total_duration_ms(), 7_000);
        p.validate().unwrap();
    }

    #[test]
    fn invalid_reorder_does_not_modify_project() {
        let (mut p, track, _, clip) = sample();
        let before = p.clone();
        assert!(p.reorder_clip(&track, &clip, 1).is_err());
        assert_eq!(p, before);
    }

    fn sample() -> (Project, String, String, String) {
        let mut p = Project::new(1080, 1920, 30, 1);
        let track = p.add_track(TrackKind::Video);
        let asset = p.add_asset("sample.mp4", 10_000);
        let clip = p.add_clip(&track, &asset, 0, 1_000, 5_000).unwrap();
        (p, track, asset, clip)
    }

    #[test]
    fn split_preserves_source_continuity() {
        let (mut p, track, _asset, clip) = sample();
        let (first_id, second_id) = p.split_clip(&track, &clip, 2_000).unwrap();
        let t = p.tracks.iter().find(|t| t.id == track).unwrap();
        let first = t.clips.iter().find(|c| c.id == first_id).unwrap();
        let second = t.clips.iter().find(|c| c.id == second_id).unwrap();

        assert_eq!(first.duration_ms, 2_000);
        assert_eq!(second.duration_ms, 3_000);
        assert_eq!(second.source_in_ms, first.source_out_ms());
        assert_eq!(second.timeline_start_ms, first.timeline_end_ms());
    }

    #[test]
    fn rejects_clip_outside_source_asset() {
        let mut p = Project::new(1920, 1080, 30, 1);
        let track = p.add_track(TrackKind::Video);
        let asset = p.add_asset("sample.mp4", 5_000);
        assert_eq!(
            p.add_clip(&track, &asset, 0, 4_000, 2_000),
            Err(TimelineError::SourceRangeOutOfBounds)
        );
    }

    #[test]
    fn delete_returns_removed_clip() {
        let (mut p, track, _asset, clip) = sample();
        let removed = p.delete_clip(&track, &clip).unwrap();
        assert_eq!(removed.id, clip);
        assert!(p.tracks.iter().find(|t| t.id == track).unwrap().clips.is_empty());
    }

    #[test]
    fn move_clip_updates_timeline_position() {
        let (mut p, track, _asset, clip) = sample();
        p.move_clip(&track, &clip, 3_000).unwrap();
        let moved = p.tracks.iter().find(|t| t.id == track).unwrap().clips[0].clone();
        assert_eq!(moved.timeline_start_ms, 3_000);
    }

    #[test]
    fn split_rejects_parts_shorter_than_minimum() {
        let (mut p, track, _asset, clip) = sample();
        assert_eq!(p.split_clip(&track, &clip, 50), Err(TimelineError::InvalidSplitPosition));
        assert_eq!(p.split_clip(&track, &clip, 4_950), Err(TimelineError::InvalidSplitPosition));
    }

    #[test]
    fn split_at_timeline_position_uses_clip_start() {
        let (mut p, track, _asset, clip) = sample();
        p.move_clip(&track, &clip, 1_000).unwrap();
        let (first, second) = p.split_clip_at(&track, &clip, 3_000).unwrap();
        let t = &p.tracks[0];
        assert_eq!(t.clips.iter().find(|c| c.id == first).unwrap().duration_ms, 2_000);
        assert_eq!(t.clips.iter().find(|c| c.id == second).unwrap().timeline_start_ms, 3_000);
        assert_eq!(p.split_clip_at(&track, &first, 1_000), Err(TimelineError::InvalidSplitPosition));
    }

    #[test]
    fn ripple_closes_gaps_and_keeps_order() {
        let mut p = Project::new(1920, 1080, 30, 1);
        let track = p.add_track(TrackKind::Video);
        let asset = p.add_asset("a.mp4", 10_000);
        let a = p.add_clip(&track, &asset, 0, 0, 2_000).unwrap();
        let b = p.add_clip(&track, &asset, 5_000, 0, 3_000).unwrap();
        p.ripple_track(&track).unwrap();
        let clips = &p.tracks[0].clips;
        assert_eq!(clips[0].id, a);
        assert_eq!(clips[1].id, b);
        assert_eq!(clips[1].timeline_start_ms, 2_000);
        assert_eq!(p.total_duration_ms(), 5_000);
    }

    #[test]
    fn append_clip_goes_after_the_last_clip() {
        let (mut p, track, asset, _clip) = sample();
        let id = p.append_clip(&track, &asset, 0, 1_000).unwrap();
        let (_, appended) = p.find_clip(&id).unwrap();
        assert_eq!(appended.timeline_start_ms, 5_000);
    }

    #[test]
    fn clip_at_uses_half_open_ranges() {
        let (p, track, _asset, clip) = sample();
        assert_eq!(p.clip_at(&track, 0).map(|c| c.id.clone()), Some(clip));
        assert!(p.clip_at(&track, 5_000).is_none());
    }

    #[test]
    fn json_round_trip_preserves_the_project() {
        let (p, _t, _a, _c) = sample();
        let restored = Project::from_json(&p.to_json().unwrap()).unwrap();
        assert_eq!(restored, p);
    }

    #[test]
    fn newer_schema_versions_are_rejected_clearly() {
        let (mut p, _t, _a, _c) = sample();
        p.version = SCHEMA_VERSION + 1;
        let json = serde_json::to_string(&p).unwrap();
        assert_eq!(Project::from_json(&json), Err(TimelineError::UnsupportedVersion(SCHEMA_VERSION + 1)));
    }

    #[test]
    fn garbage_and_inconsistent_files_are_rejected() {
        assert!(matches!(Project::from_json("not json"), Err(TimelineError::Json(_))));

        let (mut p, _t, _a, _c) = sample();
        p.tracks[0].clips[0].asset_id = "missing".into();
        let json = serde_json::to_string(&p).unwrap();
        assert!(matches!(Project::from_json(&json), Err(TimelineError::InvalidProject(_))));
    }

    #[test]
    fn validate_catches_overlapping_clips() {
        let (mut p, track, asset, _clip) = sample();
        p.add_clip(&track, &asset, 2_000, 0, 1_000).unwrap();
        assert!(matches!(p.validate(), Err(TimelineError::InvalidProject(_))));
    }
}
