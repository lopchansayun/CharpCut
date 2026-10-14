import 'dart:math' as math;
import 'engine/editor_state.dart';

/// Pack overlapping intervals into separate visible rows. Touching ends share a row.
Map<String, int> clipRows(List<EditorClip> clips) {
  final ordered = [...clips]..sort((a, b) => a.startMs.compareTo(b.startMs));
  final ends = <int>[];
  final rows = <String, int>{};
  for (final c in ordered) {
    var row = ends.indexWhere((end) => end <= c.startMs);
    if (row < 0) {
      row = ends.length;
      ends.add(c.endMs);
    } else {
      ends[row] = c.endMs;
    }
    rows[c.id] = row;
  }
  return rows;
}

List<EditorClip> activeVisualClips(EditorState state) {
  final position = state.playheadMs == state.totalDurationMs
      ? math.max(0, state.playheadMs - 1)
      : state.playheadMs;
  final order = {
    ...state.tracks.map((t) => t.kind),
    'video',
    'image',
    'overlay',
  };
  return [
    for (final kind in order)
      if (kind != 'audio')
        for (final c in state.allClips)
          if (c.trackKind == kind &&
              c.startMs <= position &&
              position < c.endMs)
            c,
  ];
}

/// Null reserves a mounted video surface when the video lane has no active clip.
List<EditorClip?> previewLayers(EditorState state, List<EditorClip> active) {
  final order = {
    ...state.tracks.map((t) => t.kind),
    'video',
    'image',
    'overlay',
  };
  return [
    for (final kind in order) ...[
      if (kind == 'video' && !active.any((c) => c.trackKind == 'video')) null,
      ...active.where((c) => c.trackKind == kind),
    ],
  ];
}
