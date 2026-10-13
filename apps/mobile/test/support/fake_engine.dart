import 'dart:ui' show Color;

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
  final List<(List<EditorClip>, String?)> _undo = [];
  final List<(List<EditorClip>, String?)> _redo = [];
  int _next = 0;

  EditorState _state() => EditorState(
    mainTrackId: 'main',
    clips: List.unmodifiable(_clips),
    selectedClipId: _selected,
    totalDurationMs: _clips.fold(0, (sum, c) => sum + c.durationMs),
    canUndo: _undo.isNotEmpty,
    canRedo: _redo.isNotEmpty,
    status: _status,
    lastError: _error,
  );

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
    final before = (List<EditorClip>.of(_clips), _selected);
    final problem = change();
    if (problem != null) {
      _clips = before.$1;
      _selected = before.$2;
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
    _redo.add((List.of(_clips), _selected));
    final prev = _undo.removeLast();
    _clips = prev.$1;
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
    _undo.add((List.of(_clips), _selected));
    final next = _redo.removeLast();
    _clips = next.$1;
    _selected = next.$2 != null && _clips.any((c) => c.id == next.$2) ? next.$2 : null;
    _error = null;
    return _state();
  }

  @override
  Future<String> exportProjectJson() async => '{}';

  @override
  Future<EditorState> openProjectJson(String json) => newProject();
}
