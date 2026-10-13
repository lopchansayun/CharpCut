import 'dart:ui' show Color;
import 'dart:convert';

import 'package:charpcut/engine/editor_engine.dart';
import 'package:charpcut/engine/editor_state.dart';

/// In-memory stand-in for the Rust engine so widget tests run without the native
/// library. It follows the same rules the real one documents: the main track has
/// no gaps, a refused edit leaves everything unchanged, and history is undoable.
/// The real behaviour is tested in Rust (`cargo test`).
class FakeEngine implements EditorEngine {
  List<EditorClip> _clips = [];
  String? _selected;
  String? _error;
  String _status = 'New project';
  final List<(List<EditorClip>, String?, bool)> _undo = [];
  final List<(List<EditorClip>, String?, bool)> _redo = [];
  int _next = 0;
  bool _muted = false;
  int _playhead = 0;

  EditorState _state() {
    _playhead = _playhead.clamp(0, _clips.fold<int>(0, (sum, c) => sum + c.durationMs));
    return EditorState(
    mainTrackId: 'main',
    playheadMs: _playhead,
    mainTrackMuted: _muted,
    clips: List.unmodifiable(_clips),
    selectedClipId: _selected,
    totalDurationMs: _clips.fold(0, (sum, c) => sum + c.durationMs),
    canUndo: _undo.isNotEmpty,
    canRedo: _redo.isNotEmpty,
    status: _status,
    lastError: _error,
  );
  }

  EditorClip _copy(EditorClip c, {int? startMs, int? sourceInMs, int? durationMs, String? id}) => EditorClip(
    id: id ?? c.id,
    assetId: c.assetId,
    name: c.name,
    color: c.color,
    startMs: startMs ?? c.startMs,
    sourceInMs: sourceInMs ?? c.sourceInMs,
    durationMs: durationMs ?? c.durationMs,
  );

  void _ripple() {
    var cursor = 0;
    _clips = [
      for (final c in _clips)
        () {
          final moved = _copy(c, startMs: cursor);
          cursor += c.durationMs;
          return moved;
        }(),
    ];
  }

  EditorState _edit(String ok, String? Function() change) {
    final before = (List<EditorClip>.of(_clips), _selected, _muted);
    final problem = change();
    if (problem != null) {
      _clips = before.$1;
      _selected = before.$2;
      _muted = before.$3;
      _error = problem;
      return _state();
    }
    _undo.add(before);
    _redo.clear();
    _status = ok;
    _error = null;
    return _state();
  }

  @override
  Future<EditorState> newProject() async {
    _clips = [];
    _muted = false;
    _playhead = 0;
    _selected = null;
    _error = null;
    _status = 'New project';
    _undo.clear();
    _redo.clear();
    return _state();
  }

  @override
  Future<EditorState> getState() async => _state();

  @override
  Future<EditorState> seek(int timelineMs) async {
    _playhead = timelineMs;
    _error = null;
    return _state();
  }

  @override
  Future<EditorState> setMuted(bool muted) async {
    if (_muted == muted) { _error = null; return _state(); }
    return _edit(muted ? 'Track muted' : 'Track unmuted', () {
      _muted = muted;
      return null;
    });
  }

  @override
  Future<EditorState> moveSelected(int targetIndex) async {
    final index = _clips.indexWhere((c) => c.id == _selected);
    if (index < 0) { _error = 'Select a clip first'; return _state(); }
    if (targetIndex < 0 || targetIndex >= _clips.length) {
      _error = 'Clip position is outside the track';
      return _state();
    }
    if (index == targetIndex) { _error = null; return _state(); }
    return _edit('Clip moved', () {
      final clip = _clips.removeAt(index);
      _clips.insert(targetIndex, clip);
      _ripple();
      return null;
    });
  }

  @override
  Future<EditorState> select(String? clipId) async {
    if (clipId != null && !_clips.any((c) => c.id == clipId)) {
      _error = 'Clip not found';
    } else {
      _selected = clipId;
      _error = null;
    }
    return _state();
  }

  @override
  Future<EditorState> addClip({required String path, required int durationMs}) async => _edit('Clip added', () {
    if (path.trim().isEmpty) return 'Media path is empty';
    if (durationMs < 100) return 'Media is too short to add';
    final n = _next++;
    _clips.add(EditorClip(
      id: 'clip-$n',
      assetId: 'asset-$n',
      name: displayName(path),
      color: const Color(0xFF3A4F7A),
      startMs: 0,
      sourceInMs: 0,
      durationMs: durationMs,
    ));
    _ripple();
    _selected = 'clip-$n';
    return null;
  });

  @override
  Future<EditorState> splitSelectedAt(int timelineMs) async => _edit('Clip split', () {
    final clip = _clips.where((c) => c.id == _selected).firstOrNull;
    if (clip == null) return 'Select a clip first';
    final local = timelineMs - clip.startMs;
    if (local < 100 || clip.durationMs - local < 100) return 'Move the playhead inside the clip to split it';
    final i = _clips.indexOf(clip);
    final second = _copy(clip, id: 'clip-${_next++}', sourceInMs: clip.sourceInMs + local, durationMs: clip.durationMs - local);
    _clips[i] = _copy(clip, durationMs: local);
    _clips.insert(i + 1, second);
    _ripple();
    _selected = second.id;
    return null;
  });

  @override
  Future<EditorState> trimSelected({required int sourceInMs, required int durationMs}) async => _edit('Clip trimmed', () {
    final clip = _clips.where((c) => c.id == _selected).firstOrNull;
    if (clip == null) return 'Select a clip first';
    if (durationMs < 100) return 'That would make the clip too short';
    _clips[_clips.indexOf(clip)] = _copy(clip, sourceInMs: sourceInMs, durationMs: durationMs);
    _ripple();
    return null;
  });

  @override
  Future<EditorState> deleteSelected() async => _edit('Clip deleted', () {
    final clip = _clips.where((c) => c.id == _selected).firstOrNull;
    if (clip == null) return 'Select a clip first';
    _clips.remove(clip);
    _selected = null;
    _ripple();
    return null;
  });

  @override
  Future<EditorState> undo() async {
    if (_undo.isEmpty) {
      _error = 'Nothing to undo';
      return _state();
    }
    _redo.add((List.of(_clips), _selected, _muted));
    final prev = _undo.removeLast();
    _clips = prev.$1;
    _muted = prev.$3;
    _selected = prev.$2 != null && _clips.any((c) => c.id == prev.$2) ? prev.$2 : null;
    _error = null;
    return _state();
  }

  @override
  Future<EditorState> redo() async {
    if (_redo.isEmpty) {
      _error = 'Nothing to redo';
      return _state();
    }
    _undo.add((List.of(_clips), _selected, _muted));
    final next = _redo.removeLast();
    _clips = next.$1;
    _muted = next.$3;
    _selected = next.$2 != null && _clips.any((c) => c.id == next.$2) ? next.$2 : null;
    _error = null;
    return _state();
  }

  @override
  Future<String> exportProjectJson() async => jsonEncode({
    'id': 'test-project',
    'version': 2,
    'settings': {'width': 1080, 'height': 1920, 'fps_num': 30, 'fps_den': 1},
    'assets': [
      for (final id in _clips.map((c) => c.assetId).toSet())
        {
          'id': id,
          'path': '${_clips.firstWhere((c) => c.assetId == id).name}.mp4',
          'duration_ms': _clips
              .where((c) => c.assetId == id)
              .map((c) => c.sourceInMs + c.durationMs)
              .reduce((a, b) => a > b ? a : b),
        },
    ],
    'tracks': [
      {
        'id': 'main',
        'kind': 'Video',
        'muted': _muted,
        'clips': [
          for (final c in _clips)
            {
              'id': c.id,
              'asset_id': c.assetId,
              'timeline_start_ms': c.startMs,
              'source_in_ms': c.sourceInMs,
              'duration_ms': c.durationMs,
            },
        ],
      },
    ],
  });

  @override
  Future<EditorState> openProjectJson(String json) async {
    try {
      final project = jsonDecode(json) as Map<String, dynamic>;
      if (![1, 2].contains(project['version'])) {
        throw const FormatException('Unsupported project version');
      }
      final state = EditorState.fromJson(
        jsonEncode({'project': project, 'main_track_id': 'main'}),
      );
      _clips = List.of(state.clips);
      _muted = project['version'] == 1 ? false : (project['tracks'][0]['muted'] as bool);
      _playhead = 0;
      _selected = null;
      _undo.clear();
      _redo.clear();
      _error = null;
      _status = 'Project opened';
      _next = _clips.length + 100;
    } catch (error) {
      _error = 'Could not open project: $error';
    }
    return _state();
  }
}
