import 'dart:convert';
import 'dart:ui' show Color;

class ClipProperties {
  const ClipProperties({
    this.x = 0,
    this.y = 0,
    this.scale = 1,
    this.rotation = 0,
    this.cropLeft = 0,
    this.cropTop = 0,
    this.cropRight = 0,
    this.cropBottom = 0,
    this.opacity = 1,
    this.volume = 1,
  });
  final double x,
      y,
      scale,
      rotation,
      cropLeft,
      cropTop,
      cropRight,
      cropBottom,
      opacity,
      volume;
  factory ClipProperties.fromMap(Map<String, dynamic> value) => ClipProperties(
    x: (value['x'] as num?)?.toDouble() ?? 0,
    y: (value['y'] as num?)?.toDouble() ?? 0,
    scale: (value['scale'] as num?)?.toDouble() ?? 1,
    rotation: (value['rotation'] as num?)?.toDouble() ?? 0,
    cropLeft: (value['crop_left'] as num?)?.toDouble() ?? 0,
    cropTop: (value['crop_top'] as num?)?.toDouble() ?? 0,
    cropRight: (value['crop_right'] as num?)?.toDouble() ?? 0,
    cropBottom: (value['crop_bottom'] as num?)?.toDouble() ?? 0,
    opacity: (value['opacity'] as num?)?.toDouble() ?? 1,
    volume: (value['volume'] as num?)?.toDouble() ?? 1,
  );
  Map<String, double> toJson() => {
    'x': x,
    'y': y,
    'scale': scale,
    'rotation': rotation,
    'crop_left': cropLeft,
    'crop_top': cropTop,
    'crop_right': cropRight,
    'crop_bottom': cropBottom,
    'opacity': opacity,
    'volume': volume,
  };
}

class EditorTrack {
  const EditorTrack(this.id, this.kind, this.locked);
  final String id, kind;
  final bool locked;
}

/// A clip on an editable timeline track, as the UI needs it.
class EditorClip {
  const EditorClip({
    required this.id,
    required this.assetId,
    required this.name,
    required this.color,
    required this.startMs,
    required this.sourceInMs,
    required this.durationMs,
    this.sourceDurationMs = 0,
    this.path = '',
    this.trackId = '',
    this.kind = 'video',
    this.trackKind = 'video',
    this.properties = const ClipProperties(),
  });

  final String id;
  final String assetId;
  final String name;
  final String path;
  final String trackId;
  final String kind;
  final String trackKind;
  final ClipProperties properties;

  /// Stand-in tint for the filmstrip until real thumbnails exist.
  final Color color;
  final int startMs;
  final int sourceInMs;
  final int durationMs;
  final int sourceDurationMs;

  int get endMs => startMs + durationMs;
}

/// What the editor shows. It is parsed from the JSON snapshot the Rust engine
/// returns after every call; the UI never edits it directly.
class EditorState {
  const EditorState({
    this.tracks = const [],
    this.projectWidth = 1080,
    this.projectHeight = 1920,
    this.projectFps = 30,
    this.mainTrackId = '',
    this.clips = const [],
    this.audioClips = const [],
    this.imageClips = const [],
    this.overlayClips = const [],
    this.selectedClipId,
    this.totalDurationMs = 0,
    this.playheadMs = 0,
    this.mainTrackMuted = false,
    this.mainTrackLocked = false,
    this.audioTrackLocked = false,
    this.imageTrackLocked = false,
    this.overlayTrackLocked = false,
    this.canUndo = false,
    this.canRedo = false,
    this.status = '',
    this.lastError,
  });

  static const empty = EditorState();

  final List<EditorTrack> tracks;
  final int projectWidth;
  final int projectHeight;
  final double projectFps;
  double get projectAspectRatio =>
      projectHeight > 0 ? projectWidth / projectHeight : 9 / 16;

  final String mainTrackId;
  final List<EditorClip> clips;
  final List<EditorClip> audioClips;
  final List<EditorClip> imageClips;
  final List<EditorClip> overlayClips;
  List<EditorClip> get allClips => [
    ...clips,
    ...audioClips,
    ...imageClips,
    ...overlayClips,
  ];
  bool get hasMedia => allClips.isNotEmpty;
  final String? selectedClipId;
  final int totalDurationMs;
  final int playheadMs;
  final bool mainTrackMuted;
  final bool mainTrackLocked;
  final bool audioTrackLocked;
  final bool imageTrackLocked;
  final bool overlayTrackLocked;
  final bool canUndo;
  final bool canRedo;

  /// Message for the last successful edit.
  final String status;

  /// Set when the last call was refused. The project is unchanged in that case.
  final String? lastError;

  double get totalSeconds => totalDurationMs / 1000;

  /// Playback ticks share the immutable project instead of reparsing a Rust snapshot.
  EditorState atPlayhead(int ms) => EditorState(
    tracks: tracks,
    projectWidth: projectWidth,
    projectHeight: projectHeight,
    projectFps: projectFps,
    mainTrackId: mainTrackId,
    clips: clips,
    audioClips: audioClips,
    imageClips: imageClips,
    overlayClips: overlayClips,
    selectedClipId: selectedClipId,
    totalDurationMs: totalDurationMs,
    playheadMs: ms.clamp(0, totalDurationMs),
    mainTrackMuted: mainTrackMuted,
    mainTrackLocked: mainTrackLocked,
    audioTrackLocked: audioTrackLocked,
    imageTrackLocked: imageTrackLocked,
    overlayTrackLocked: overlayTrackLocked,
    canUndo: canUndo,
    canRedo: canRedo,
    status: status,
    lastError: lastError,
  );

  EditorClip? get selectedClip {
    final id = selectedClipId;
    if (id == null) return null;
    for (final c in allClips) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// The clip playing at [ms], or the last clip when [ms] is at or past the end.
  EditorClip? clipAt(int ms) {
    if (clips.isEmpty) return null;
    for (final c in clips) {
      if (ms >= c.startMs && ms < c.endMs) return c;
    }
    return ms >= totalDurationMs ? clips.lastOrNull : null;
  }

  /// Reads the snapshot JSON from `EditorSnapshot` in the Rust `editor_api` crate.
  factory EditorState.fromJson(String source) {
    final root = jsonDecode(source);
    if (root is! Map<String, dynamic>) {
      throw const FormatException('Editor state is not a JSON object');
    }
    final project = root['project'];
    if (project is! Map<String, dynamic>) {
      // The engine could not produce a state; surface its message.
      return EditorState(
        lastError:
            (root['last_error'] as String?) ??
            'Could not read the editor state',
      );
    }

    final assetPaths = <String, String>{
      for (final a in (project['assets'] as List? ?? const []))
        (a as Map<String, dynamic>)['id'] as String: a['path'] as String,
    };
    final assetDurations = <String, int>{
      for (final a in (project['assets'] as List? ?? const []))
        (a as Map<String, dynamic>)['id'] as String: (a['duration_ms'] as num)
            .toInt(),
    };
    final assetKinds = <String, String>{
      for (final a in (project['assets'] as List? ?? const []))
        (a as Map<String, dynamic>)['id'] as String:
            ((a['kind'] as String?) ?? 'Video').toLowerCase(),
    };

    final trackId = root['main_track_id'] as String? ?? '';
    var mainTrackLocked = false;
    var audioTrackLocked = false;
    var imageTrackLocked = false;
    var overlayTrackLocked = false;
    final clips = <EditorClip>[];
    final audioClips = <EditorClip>[];
    final imageClips = <EditorClip>[];
    final overlayClips = <EditorClip>[];
    for (final t in (project['tracks'] as List? ?? const [])) {
      final track = t as Map<String, dynamic>;
      final kind = (track['kind'] as String? ?? '').toLowerCase();
      final locked = track['locked'] == true;
      if (track['id'] == trackId) mainTrackLocked = locked;
      if (kind == 'audio') audioTrackLocked = locked;
      if (kind == 'image') imageTrackLocked = locked;
      if (kind == 'overlay') overlayTrackLocked = locked;
      final output = track['id'] == trackId
          ? clips
          : kind == 'audio'
          ? audioClips
          : kind == 'image'
          ? imageClips
          : kind == 'overlay'
          ? overlayClips
          : null;
      if (output == null) continue;
      for (final c in (track['clips'] as List? ?? const [])) {
        final clip = c as Map<String, dynamic>;
        final assetId = clip['asset_id'] as String;
        output.add(
          EditorClip(
            properties: ClipProperties.fromMap(
              clip['properties'] as Map<String, dynamic>? ?? {},
            ),
            id: clip['id'] as String,
            assetId: assetId,
            trackId: track['id'] as String,
            kind: assetKinds[assetId] ?? 'video',
            trackKind: kind,
            name: displayName(assetPaths[assetId] ?? ''),
            path: assetPaths[assetId] ?? '',
            color: tintFor(assetId),
            startMs: (clip['timeline_start_ms'] as num).toInt(),
            sourceInMs: (clip['source_in_ms'] as num).toInt(),
            durationMs: (clip['duration_ms'] as num).toInt(),
            sourceDurationMs: assetDurations[assetId] ?? 0,
          ),
        );
      }
    }

    final settings = project['settings'] as Map<String, dynamic>? ?? const {};
    final fpsNum = (settings['fps_num'] as num?)?.toDouble() ?? 30.0;
    final fpsDen = (settings['fps_den'] as num?)?.toDouble() ?? 1.0;
    return EditorState(
      tracks: [
        for (final t in (project['tracks'] as List? ?? []))
          EditorTrack(
            t['id'] as String,
            (t['kind'] as String).toLowerCase(),
            t['locked'] == true,
          ),
      ],
      projectWidth: (settings['width'] as num?)?.toInt() ?? 1080,
      projectHeight: (settings['height'] as num?)?.toInt() ?? 1920,
      projectFps: fpsDen > 0 ? fpsNum / fpsDen : 30.0,
      mainTrackId: trackId,
      clips: List.unmodifiable(clips),
      audioClips: List.unmodifiable(audioClips),
      imageClips: List.unmodifiable(imageClips),
      overlayClips: List.unmodifiable(overlayClips),
      selectedClipId: root['selected_clip_id'] as String?,
      totalDurationMs: (root['total_duration_ms'] as num? ?? 0).toInt(),
      playheadMs: (root['playhead_ms'] as num? ?? 0).toInt(),
      mainTrackMuted: root['main_track_muted'] as bool? ?? false,
      mainTrackLocked: mainTrackLocked,
      audioTrackLocked: audioTrackLocked,
      imageTrackLocked: imageTrackLocked,
      overlayTrackLocked: overlayTrackLocked,
      canUndo: root['can_undo'] as bool? ?? false,
      canRedo: root['can_redo'] as bool? ?? false,
      status: root['status'] as String? ?? '',
      lastError: root['last_error'] as String?,
    );
  }
}

/// "content://media/IMG_0042.mp4" -> "IMG_0042".
String displayName(String path) {
  var name =
      path.split(RegExp(r'[\\/]')).where((p) => p.isNotEmpty).lastOrNull ??
      path;
  final dot = name.lastIndexOf('.');
  if (dot > 0) name = name.substring(0, dot);
  return name.toUpperCase();
}

const _tints = [
  Color(0xFF3A4F7A),
  Color(0xFF7A6A52),
  Color(0xFF3F6B73),
  Color(0xFF6B4F7A),
  Color(0xFF55607A),
  Color(0xFF5E7A4F),
];

/// A stable colour per asset, so clips from the same file look alike.
Color tintFor(String assetId) {
  var h = 0;
  for (final unit in assetId.codeUnits) {
    h = (h * 31 + unit) & 0x7fffffff;
  }
  return _tints[h % _tints.length];
}
