import 'dart:convert';
import 'dart:ui' show Color;

/// A clip on the main video track, as the UI needs it.
class EditorClip {
  const EditorClip({
    required this.id,
    required this.assetId,
    required this.name,
    required this.color,
    required this.startMs,
    required this.sourceInMs,
    required this.durationMs,
  });

  final String id;
  final String assetId;
  final String name;

  /// Stand-in tint for the filmstrip until real thumbnails exist.
  final Color color;
  final int startMs;
  final int sourceInMs;
  final int durationMs;

  int get endMs => startMs + durationMs;
}

/// What the editor shows. It is parsed from the JSON snapshot the Rust engine
/// returns after every call; the UI never edits it directly.
class EditorState {
  const EditorState({
    this.mainTrackId = '',
    this.clips = const [],
    this.selectedClipId,
    this.totalDurationMs = 0,
    this.canUndo = false,
    this.canRedo = false,
    this.status = '',
    this.lastError,
  });

  static const empty = EditorState();

  final String mainTrackId;
  final List<EditorClip> clips;
  final String? selectedClipId;
  final int totalDurationMs;
  final bool canUndo;
  final bool canRedo;

  /// Message for the last successful edit.
  final String status;

  /// Set when the last call was refused. The project is unchanged in that case.
  final String? lastError;

  double get totalSeconds => totalDurationMs / 1000;

  EditorClip? get selectedClip {
    final id = selectedClipId;
    if (id == null) return null;
    for (final c in clips) {
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
    return clips.last;
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
      return EditorState(lastError: (root['last_error'] as String?) ?? 'Could not read the editor state');
    }

    final assetPaths = <String, String>{
      for (final a in (project['assets'] as List? ?? const []))
        (a as Map<String, dynamic>)['id'] as String: a['path'] as String,
    };

    final trackId = root['main_track_id'] as String? ?? '';
    final clips = <EditorClip>[];
    for (final t in (project['tracks'] as List? ?? const [])) {
      final track = t as Map<String, dynamic>;
      if (track['id'] != trackId) continue;
      for (final c in (track['clips'] as List? ?? const [])) {
        final clip = c as Map<String, dynamic>;
        final assetId = clip['asset_id'] as String;
        clips.add(EditorClip(
          id: clip['id'] as String,
          assetId: assetId,
          name: displayName(assetPaths[assetId] ?? ''),
          color: tintFor(assetId),
          startMs: (clip['timeline_start_ms'] as num).toInt(),
          sourceInMs: (clip['source_in_ms'] as num).toInt(),
          durationMs: (clip['duration_ms'] as num).toInt(),
        ));
      }
    }

    return EditorState(
      mainTrackId: trackId,
      clips: List.unmodifiable(clips),
      selectedClipId: root['selected_clip_id'] as String?,
      totalDurationMs: (root['total_duration_ms'] as num? ?? 0).toInt(),
      canUndo: root['can_undo'] as bool? ?? false,
      canRedo: root['can_redo'] as bool? ?? false,
      status: root['status'] as String? ?? '',
      lastError: root['last_error'] as String?,
    );
  }
}

/// "content://media/IMG_0042.mp4" -> "IMG_0042".
String displayName(String path) {
  var name = path.split(RegExp(r'[\\/]')).where((p) => p.isNotEmpty).lastOrNull ?? path;
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
