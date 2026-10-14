import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'engine/editor_engine.dart';
import 'engine/editor_state.dart';
import 'engine/project_session.dart';
import 'draft_list.dart';
import 'engine/media_library.dart';
import 'media_library_screen.dart';
import 'media_thumbnail.dart';
import 'export_done_screen.dart';
import 'export_panel.dart';
import 'theme.dart';
import 'time_input_dialog.dart';
import 'video_preview.dart';
import 'clip_trim_handle.dart';
import 'timeline_layers.dart';

const double _trackHeight = 50;

/// Extra room either side of the clip lane so a selected clip's handles stay hit-testable.
const double _laneInset = 22;

class EditorHome extends StatefulWidget {
  /// Opens this saved project instead of starting an empty one.
  const EditorHome({super.key, this.projectJson, this.draftId});
  final String? draftId;
  final String? projectJson;

  @override
  State<EditorHome> createState() => _EditorHomeState();
}

class _EditorHomeState extends State<EditorHome> with WidgetsBindingObserver {
  late final EditorEngine _engine;

  /// Everything about the project comes from the Rust engine; this is its latest answer.
  EditorState _state = EditorState.empty;

  final ScrollController _scroll = ScrollController();
  int _previewSeekSerial = 0;
  bool _fullScreen = false;
  bool _landscapePreview = false;
  bool _playing = false;
  bool _syncingScroll = false;
  bool _importing = false;
  String? _checkedMediaPaths;
  String? _mediaWarning;
  int? _pendingSeek;
  bool _pendingSeekFromPlayback = false;
  Future<void>? _seekFuture;
  bool _snap = true;
  Set<String>? _batchIds;
  (String, int, int)? _trimPreview;
  bool _timelineDragged = false;
  double _pixelsPerSecond = 50;

  final ExportSettings _exportSettings = ExportSettings();
  bool _exportOpen = false;

  @override
  void initState() {
    super.initState();
    _engine = context.getInheritedWidgetOfExactType<EngineScope>()!.engine;
    WidgetsBinding.instance.addObserver(this);
    final json = widget.projectJson;
    _run(() {
      final engine = _engine;
      if (widget.draftId != null && engine is ProjectSession) {
        return engine.openDraft(widget.draftId!);
      }
      return json == null ? engine.newProject() : engine.openProjectJson(json);
    }, announce: false);
    _scroll.addListener(() {
      if (!_syncingScroll && mounted) {
        _requestSeek((_scroll.offset / _pixelsPerSecond * 1000).round());
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scroll.dispose();
    if (_fullScreen || _landscapePreview) _restoreSystemUi();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _pause();
    } else {
      _checkedMediaPaths = null;
      _checkMediaFiles();
    }
  }

  // -------------------------------------------------------------------------
  // Derived state
  // -------------------------------------------------------------------------

  List<EditorClip> get _clips => _state.clips;

  EditorClip? get _selected => _state.selectedClip;

  double get _totalSeconds => _state.totalSeconds;

  double get _playhead => _state.playheadMs / 1000;

  List<String> get _laneOrder => {
    ..._state.tracks.map((t) => t.kind),
    'video',
    'audio',
    'image',
    'overlay',
  }.toList();
  Map<String, int> _rows(String kind) =>
      clipRows(_state.allClips.where((c) => c.trackKind == kind).toList());
  double _laneHeight(String kind) => kind == 'video'
      ? 58
      : math.max(
                  1,
                  _rows(kind).values.fold<int>(0, (a, b) => math.max(a, b + 1)),
                ) *
                44.0 +
            14;
  double get _timelineHeight =>
      46 + _laneOrder.fold<double>(0, (h, k) => h + _laneHeight(k));
  double _laneTop(String kind) =>
      36 +
      _laneOrder
          .takeWhile((k) => k != kind)
          .fold<double>(0, (h, k) => h + _laneHeight(k));
  (String, int)? _moveDraft;
  int _moveStart = 0;
  Future<void> _finishMove(EditorClip clip) async {
    final draft = _moveDraft;
    if (draft == null) return;
    await _run(
      () => _engine.applyTimelineEdit({
        'action': 'shift',
        'clip_ids': [clip.id],
        'delta_ms': draft.$2 - clip.startMs,
      }),
      announce: false,
    );
    if (mounted) setState(() => _moveDraft = null);
  }

  Future<void> _commitTrim(EditorClip clip, int sourceIn, int duration) async {
    await _run(() async {
      final selection = await _engine.select(clip.id);
      if (selection.lastError != null) return selection;
      return _engine.trimSelected(sourceInMs: sourceIn, durationMs: duration);
    }, announce: false);
    if (mounted) setState(() => _trimPreview = null);
  }

  Widget _trimHandle(EditorClip clip, bool start) => ClipTrimHandle(
    key: ValueKey('${clip.id}:$start'),
    clip: clip,
    start: start,
    pixelsPerSecond: _pixelsPerSecond,
    onBegin: _pause,
    onCancel: () => setState(() => _trimPreview = null),
    onPreview: (sourceIn, duration) =>
        setState(() => _trimPreview = (clip.id, sourceIn, duration)),
    onCommit: (sourceIn, duration) => _commitTrim(clip, sourceIn, duration),
  );
  bool _canTrim(EditorClip clip) =>
      _batchIds == null &&
      !_state.tracks.any((t) => t.id == clip.trackId && t.locked);

  Future<void> _commitVisual(EditorClip c, ClipProperties p) => _run(
    () => _engine.applyTimelineEdit({
      'action': 'properties',
      'clip_id': c.id,
      'start_ms': c.startMs,
      'duration_ms': c.durationMs,
      'properties': p.toJson(),
    }),
    announce: false,
    refreshPreview: false,
  );

  Future<void> _properties() async {
    final c = _selected;
    if (c == null) return;
    _pause();
    final p = c.properties;
    final audio = c.kind == 'audio';
    final result = await showDialog<List<double>>(
      context: context,
      builder: (_) => TimeInputDialog(
        title: 'Clip properties',
        labels: [
          'Start (seconds)',
          'Duration (seconds)',
          if (!audio) ...[
            'X (canvas pixels)',
            'Y (canvas pixels)',
            'Scale (%)',
            'Rotation (degrees)',
            'Crop left (%)',
            'Crop top (%)',
            'Crop right (%)',
            'Crop bottom (%)',
            'Opacity (%)',
          ],
          if (c.kind != 'image') 'Volume (%)',
        ],
        values: [
          c.startMs / 1000,
          c.durationMs / 1000,
          if (!audio) ...[
            p.x * _state.projectWidth,
            p.y * _state.projectHeight,
            p.scale * 100,
            p.rotation,
            p.cropLeft * 100,
            p.cropTop * 100,
            p.cropRight * 100,
            p.cropBottom * 100,
            p.opacity * 100,
          ],
          if (c.kind != 'image') p.volume * 100,
        ],
        validate: (v) {
          if (v[0] < 0 ||
              v[1] < .1 ||
              v[1] * 1000 + c.sourceInMs > c.sourceDurationMs) {
            return 'Enter a non-negative start and a duration within the source (minimum 0.100 s)';
          }
          if (!audio &&
              (v[2].abs() > _state.projectWidth * 2 ||
                  v[3].abs() > _state.projectHeight * 2 ||
                  v[4] < 10 ||
                  v[4] > 1000 ||
                  v[5].abs() > 180 ||
                  v.sublist(6, 11).any((n) => n < 0 || n > 100) ||
                  v[6] + v[8] >= 100 ||
                  v[7] + v[9] >= 100)) {
            return 'Use scale 10–1000%, rotation ±180°, crop/opacity 0–100%; crop must leave visible content';
          }
          if (c.kind != 'image' && (v.last < 0 || v.last > 100))
            return 'Volume must be 0–100%';
          return null;
        },
      ),
    );
    if (result == null || !mounted) return;
    final v = result;
    final props = audio
        ? {...p.toJson(), 'volume': v.last / 100}
        : {
            'x': v[2] / _state.projectWidth,
            'y': v[3] / _state.projectHeight,
            'scale': v[4] / 100,
            'rotation': v[5],
            'crop_left': v[6] / 100,
            'crop_top': v[7] / 100,
            'crop_right': v[8] / 100,
            'crop_bottom': v[9] / 100,
            'opacity': v[10] / 100,
            'volume': c.kind == 'image' ? p.volume : v.last / 100,
          };
    await _run(
      () => _engine.applyTimelineEdit({
        'action': 'properties',
        'clip_id': c.id,
        'start_ms': (v[0] * 1000).round(),
        'duration_ms': (v[1] * 1000).round(),
        'properties': props,
      }),
    );
  }

  Future<void> _selectMany() async {
    _pause();
    final ids = <String>{...?_batchIds, if (_selected != null) _selected!.id};
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Select clips'),
          content: SizedBox(
            width: 360,
            height: 320,
            child: ListView(
              children: [
                for (final c in _state.allClips)
                  CheckboxListTile(
                    title: Text(c.name),
                    subtitle: Text(
                      '${c.trackKind} • ${(c.startMs / 1000).toStringAsFixed(3)} s',
                    ),
                    value: ids.contains(c.id),
                    onChanged: (value) => update(() {
                      if (value == true) {
                        ids.add(c.id);
                      } else {
                        ids.remove(c.id);
                      }
                    }),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: ids.isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, ids),
              child: const Text('Select'),
            ),
          ],
        ),
      ),
    );
    if (result != null && mounted) setState(() => _batchIds = result);
  }

  Future<void> _batchEdit(String action, {bool ripple = true}) async {
    final ids = _batchIds?.toList() ?? [if (_selected != null) _selected!.id];
    if (ids.isEmpty) return;
    final edit = <String, dynamic>{'action': action, 'clip_ids': ids};
    if (action == 'delete') edit['ripple'] = ripple;
    if (action == 'shift') {
      _pause();
      final result = await showDialog<List<double>>(
        context: context,
        builder: (_) => TimeInputDialog(
          title: 'Move selected clips',
          labels: const ['Offset (seconds; negative moves earlier)'],
          values: const [0],
          validate: (_) => null,
        ),
      );
      if (result == null || !mounted) return;
      edit['delta_ms'] = (result.first * 1000).round();
    }
    await _run(() => _engine.applyTimelineEdit(edit));
    if (mounted && _state.lastError == null) setState(() => _batchIds = null);
  }

  Future<void> _reorderTracks() async {
    _pause();
    final tracks = _state.tracks.toList();
    final result = await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Track order'),
          content: SizedBox(
            width: 360,
            height: 300,
            child: ReorderableListView(
              buildDefaultDragHandles: false,
              onReorder: (oldIndex, newIndex) => update(() {
                if (newIndex > oldIndex) newIndex--;
                tracks.insert(newIndex, tracks.removeAt(oldIndex));
              }),
              children: [
                for (var i = 0; i < tracks.length; i++)
                  ReorderableDragStartListener(
                    key: ValueKey(tracks[i].id),
                    index: i,
                    enabled: !tracks[i].locked,
                    child: ListTile(
                      title: Text(tracks[i].kind.toUpperCase()),
                      subtitle: Text(
                        i == tracks.length - 1
                            ? 'Front layer'
                            : 'Behind layers below',
                      ),
                      trailing: Icon(
                        tracks[i].locked ? Icons.lock : Icons.drag_handle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                tracks.map((t) => t.id).toList(),
              ),
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
    if (result != null && mounted)
      await _run(
        () => _engine.applyTimelineEdit({
          'action': 'reorder_tracks',
          'track_ids': result,
        }),
      );
  }

  // Coalesce drag/player updates while keeping Rust's playhead authoritative.
  void _requestSeek(int ms, {bool fromPlayback = false}) {
    if (!fromPlayback) _pause();
    _pendingSeek = ms;
    _pendingSeekFromPlayback = fromPlayback;
    _seekFuture ??= _drainSeeks();
  }

  Future<void> _drainSeeks() async {
    try {
      while (mounted && _pendingSeek != null) {
        final target = _pendingSeek!;
        final fromPlayback = _pendingSeekFromPlayback;
        _pendingSeek = null;
        final next = await _engine.seek(target);
        if (mounted) {
          setState(() {
            _state = next;
            if (!fromPlayback) _previewSeekSerial++;
          });
          if (fromPlayback) _syncScrollToEngine();
        }
      }
    } catch (error) {
      if (mounted) _message('Could not seek: $error');
    } finally {
      _seekFuture = null;
    }
  }

  void _syncScrollToEngine() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final target = (_playhead * _pixelsPerSecond)
          .clamp(0.0, _scroll.position.maxScrollExtent)
          .toDouble();
      _syncingScroll = true;
      _scroll.jumpTo(target);
      _syncingScroll = false;
    });
  }

  double _startOf(EditorClip clip) => clip.startMs / 1000;

  EditorClip? _clipAt(double seconds) =>
      _state.clipAt((seconds * 1000).round());

  // -------------------------------------------------------------------------
  // Playback
  // -------------------------------------------------------------------------

  void _togglePlay() {
    if (_playing) {
      _pause();
    } else {
      _play();
    }
  }

  Future<void> _play() async {
    if (!_state.hasMedia) return;
    if (defaultTargetPlatform != TargetPlatform.android) {
      return _message('Video preview is available on Android');
    }
    await _seekFuture;
    if (!mounted) return;
    if (_state.playheadMs >= _state.totalDurationMs) {
      await _run(() => _engine.seek(0), announce: false);
    }
    if (mounted) setState(() => _playing = true);
  }

  void _pause() {
    if (_playing && mounted) {
      setState(() => _playing = false);
      _requestSeek(_state.playheadMs, fromPlayback: true);
    }
  }

  void _onPreviewPosition(int ms, bool playing) {
    if (!mounted || !_playing) return;
    setState(() {
      _state = _state.atPlayhead(ms);
      _playing = playing;
    });
    _syncScrollToEngine();
    if (!playing) _requestSeek(ms, fromPlayback: true);
  }

  void _onPreviewError(String message) {
    if (!mounted) return;
    _pause();
    _message(message);
  }

  void _seekAfterLayout(double seconds) {
    _run(() => _engine.seek((seconds * 1000).round()), announce: false);
  }

  // -------------------------------------------------------------------------
  // Editing: every change is a call into the Rust engine
  // -------------------------------------------------------------------------

  /// Runs an engine call, shows the result, and reports a refused edit.
  Future<void> _run(
    Future<EditorState> Function() call, {
    bool announce = true,
    bool refreshPreview = true,
  }) async {
    _pause();
    await _seekFuture;
    if (!mounted) return;
    final EditorState next;
    try {
      next = await call();
    } catch (error) {
      if (mounted) _message('The editing engine failed: $error');
      return;
    }
    if (!mounted) return;
    setState(() {
      _state = next;
      if (refreshPreview) _previewSeekSerial++;
      _batchIds?.retainWhere((id) => next.allClips.any((c) => c.id == id));
      if (_batchIds?.isEmpty == true) _batchIds = null;
    });
    _syncScrollToEngine();
    _checkMediaFiles();
    final engine = _engine;
    final error = next.lastError;
    if (error != null) {
      _message(error);
    } else if (engine is ProjectSession && engine.storageError != null) {
      _message(engine.storageError!);
    } else if (announce && next.status.isNotEmpty) {
      _message(next.status);
    }
  }

  void _undoEdit() => _run(_engine.undo, announce: false);

  void _redoEdit() => _run(_engine.redo, announce: false);

  /// Splits the selected clip at the playhead.
  Future<void> _split() async {
    if (_selected == null) return;
    _pause();
    await _seekFuture;
    if (!mounted) return;
    await _run(() => _engine.splitSelectedAt(_state.playheadMs));
  }

  Future<void> _trim() async {
    final clip = _selected;
    if (clip == null) return;
    _pause();
    if (clip.kind == 'image') {
      final result = await showDialog<List<double>>(
        context: context,
        builder: (_) => TimeInputDialog(
          title: 'Image duration',
          labels: const ['Duration (seconds)'],
          values: [clip.durationMs / 1000],
          validate: (values) =>
              values.first < .1 ||
                  values.first >
                      (clip.sourceDurationMs - clip.sourceInMs) / 1000
              ? 'Enter a valid duration of at least 0.100 s'
              : null,
        ),
      );
      if (result != null && mounted) {
        await _run(
          () => _engine.trimSelected(
            sourceInMs: clip.sourceInMs,
            durationMs: (result.first * 1000).round(),
          ),
        );
      }
      return;
    }
    final range = await showDialog<List<double>>(
      context: context,
      builder: (_) => TimeInputDialog(
        title: 'Trim clip',
        labels: const ['Start (seconds)', 'End (seconds)'],
        values: [
          clip.sourceInMs / 1000,
          (clip.sourceInMs + clip.durationMs) / 1000,
        ],
        hint:
            'Source length: ${(clip.sourceDurationMs / 1000).toStringAsFixed(3)} s. Minimum clip length: 0.100 s.',
        validate: (values) =>
            values[0] < 0 ||
                values[1] - values[0] < .1 ||
                values[1] > clip.sourceDurationMs / 1000
            ? 'Enter a valid source range'
            : null,
      ),
    );
    if (range == null || !mounted) return;
    final start = (range[0] * 1000).round();
    final end = (range[1] * 1000).round();
    await _run(
      () => _engine.trimSelected(sourceInMs: start, durationMs: end - start),
    );
  }

  void _zoomTimeline(double factor) {
    setState(
      () => _pixelsPerSecond = (_pixelsPerSecond * factor)
          .clamp(20.0, 240.0)
          .toDouble(),
    );
    _syncScrollToEngine();
  }

  void _snapTimeline() {
    if (!_timelineDragged || !_scroll.hasClients) return;
    _timelineDragged = false;
    if (!_snap) return;
    final current = (_scroll.offset / _pixelsPerSecond * 1000).round();
    final points = <int>{0, _state.totalDurationMs};
    for (final clip in _state.allClips) {
      points.add(clip.startMs);
      points.add(clip.endMs);
    }
    if (points.isEmpty) return;
    final nearest = points.reduce(
      (a, b) => (a - current).abs() <= (b - current).abs() ? a : b,
    );
    if ((nearest - current).abs() > 12 / _pixelsPerSecond * 1000) return;
    _scroll.animateTo(
      nearest / 1000 * _pixelsPerSecond,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
    );
  }

  Future<void> _seekPrecisely() async {
    _pause();
    final result = await showDialog<List<double>>(
      context: context,
      builder: (_) => TimeInputDialog(
        title: 'Go to time',
        labels: const ['Seconds'],
        values: [_playhead],
        action: 'Go',
        hint: '0 to ${_totalSeconds.toStringAsFixed(3)}',
        validate: (values) => values.first < 0 || values.first > _totalSeconds
            ? 'Enter a time within the project'
            : null,
      ),
    );
    if (result != null && mounted) _seekAfterLayout(result.first);
  }

  void _delete() {
    if (_selected == null) return;
    _run(_engine.deleteSelected);
  }

  void _toggleTrackLock(String kind) {
    final locked = kind == 'audio'
        ? _state.audioTrackLocked
        : kind == 'image'
        ? _state.imageTrackLocked
        : kind == 'overlay'
        ? _state.overlayTrackLocked
        : _state.mainTrackLocked;
    _run(() => _engine.setTrackLocked(kind, !locked));
  }

  Future<void> _checkMediaFiles() async {
    if (!mounted || !EngineScope.previewEnabledOf(context)) return;
    final paths = _state.allClips.map((c) => c.path).toSet().toList()..sort();
    final signature = paths.join('\n');
    if (_checkedMediaPaths == signature) return;
    _checkedMediaPaths = signature;
    try {
      final missing = await MediaLibrary().unavailablePaths(paths);
      if (!mounted || _checkedMediaPaths != signature) return;
      setState(
        () => _mediaWarning = missing.isEmpty
            ? null
            : '${missing.length} source file(s) unavailable. ${missing.first}',
      );
    } catch (error) {
      if (mounted && _checkedMediaPaths == signature) {
        setState(
          () => _mediaWarning =
              'Could not check source files. Reopen the project to retry.',
        );
      }
    }
  }

  Future<void> _addTimelineMedia(String kind) async {
    if (_importing) return;
    _pause();
    setState(() => _importing = true);
    try {
      final item = await Navigator.of(context).push<LibraryMedia>(
        MaterialPageRoute(
          builder: (_) => MediaLibraryScreen(
            selectKind: kind == 'overlay' ? 'image' : kind,
          ),
        ),
      );
      _checkedMediaPaths = null;
      if (item == null || !mounted) return;
      final duration = kind == 'image' || kind == 'overlay'
          ? 5000
          : item.durationMs;
      await _run(
        () => _engine.addTimelineMedia(
          path: item.path,
          durationMs: duration,
          kind: kind,
        ),
      );
      if (mounted && _state.lastError == null && _selected != null) {
        _seekAfterLayout(_selected!.startMs / 1000);
      }
    } catch (error) {
      if (mounted) _message('Could not add $kind: $error');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  /// Reuses an imported video or imports a new file, then asks Rust to append it.
  Future<void> _addClip() async {
    if (_importing) return;
    _pause();
    setState(() => _importing = true);
    try {
      final video = await Navigator.of(context).push<LibraryMedia>(
        MaterialPageRoute(
          builder: (_) => const MediaLibraryScreen(selectVideo: true),
        ),
      );
      _checkedMediaPaths = null;
      if (video == null || !mounted) return;
      final start = _totalSeconds;
      await _run(
        () => _engine.addClip(path: video.path, durationMs: video.durationMs),
      );
      if (mounted && _state.lastError == null) _seekAfterLayout(start);
    } catch (error) {
      if (mounted) _message('Could not import video: $error');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _move() async {
    _pause();
    if (_selected == null) return;
    final lane = _selected!.trackKind == 'audio'
        ? _state.audioClips
        : _selected!.trackKind == 'image'
        ? _state.imageClips
        : _selected!.trackKind == 'overlay'
        ? _state.overlayClips
        : _clips;
    final target = await showModalBottomSheet<int>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Move clip')),
            for (var index = 0; index < lane.length; index++)
              ListTile(
                title: Text('Position ${index + 1}: ${lane[index].name}'),
                onTap: () => Navigator.pop(context, index),
              ),
          ],
        ),
      ),
    );
    if (target == null || !mounted) return;
    await _run(() => _engine.moveSelected(target));
    if (mounted && _state.lastError == null && _selected != null) {
      _seekAfterLayout(_selected!.startMs / 1000);
    }
  }

  void _selectClip(String? id) {
    if (_batchIds != null) {
      if (id != null)
        setState(() {
          if (!_batchIds!.remove(id)) _batchIds!.add(id);
        });
      return;
    }
    _run(() => _engine.select(id), announce: false, refreshPreview: false);
  }

  Future<void> _projectAction(String action) async {
    _pause();
    final engine = _engine;
    if (engine is! ProjectSession) {
      return _message('Project storage is unavailable');
    }
    try {
      if (action == 'save') {
        await _seekFuture;
        await engine.save();
        if (mounted) _message('Project saved on this device');
      } else {
        // Flush before switching so a previous autosave failure cannot discard edits.
        await engine.save();
        if (!mounted) return;
        final id = await pickDraft(context, engine);
        if (id != null && mounted) {
          _checkedMediaPaths = null;
          await _run(() => engine.openDraft(id));
          _seekAfterLayout(0);
        }
      }
    } catch (error) {
      if (mounted) {
        _message(
          'Could not ${action == 'save' ? 'save' : 'open'} project: $error',
        );
      }
    }
  }

  void _openEdit() {
    final clip = _clipAt(_playhead);
    if (clip == null) return _message('Add a clip first');
    _selectClip(clip.id);
  }

  /// Messages float above the bottom toolbar instead of covering it.
  void _message(String value) => toast(
    context,
    value,
    bottomInset: 68 + MediaQuery.viewPaddingOf(context).bottom + 10,
  );

  // -------------------------------------------------------------------------
  // Export
  // -------------------------------------------------------------------------

  Future<void> _startExport() async {
    if (_clips.isEmpty) {
      setState(() => _exportOpen = false);
      return _message('Add a clip before exporting');
    }
    _pause();
    setState(() => _exportOpen = false);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const ExportProgressDialog(),
    );
    if (!mounted) return;
    final result = await Navigator.of(context).push<ExportDoneResult>(
      MaterialPageRoute(builder: (_) => const ExportDoneScreen()),
    );
    if (!mounted) return;
    if (result == ExportDoneResult.openSettings) {
      setState(() => _exportOpen = true);
    } else if (result == ExportDoneResult.newProject) {
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const EditorHome()));
    }
  }

  Future<void> _restoreSystemUi() async {
    await SystemChrome.setPreferredOrientations([]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  Future<void> _setFullScreen(bool value) async {
    setState(() {
      _fullScreen = value;
    });
    if (value) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      _landscapePreview = false;
      await _restoreSystemUi();
      if (mounted) _syncScrollToEngine();
    }
  }

  Future<void> _rotatePreview() async {
    _landscapePreview = !_landscapePreview;
    await SystemChrome.setPreferredOrientations(
      _landscapePreview
          ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
          : [DeviceOrientation.portraitUp],
    );
  }

  void _stepPreview(int direction) {
    final fps = _state.projectFps > 0 ? _state.projectFps : 30.0;
    final target =
        (_state.playheadMs + direction * math.max(1, (1000 / fps).round()))
            .clamp(0, _state.totalDurationMs)
            .toInt();
    _run(() => _engine.seek(target), announce: false);
  }

  Widget _fullScreenHeader() => SizedBox(
    height: 48,
    child: Row(
      children: [
        IconButton(
          tooltip: 'Exit fullscreen',
          onPressed: () => _setFullScreen(false),
          icon: const Icon(Icons.fullscreen_exit),
        ),
        const Expanded(child: Text('Preview')),
        IconButton(
          tooltip: 'Rotate preview',
          onPressed: _rotatePreview,
          icon: const Icon(Icons.screen_rotation),
        ),
      ],
    ),
  );

  Widget _fullScreenTransport() => SizedBox(
    height: 48,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          tooltip: 'Back 5 seconds',
          onPressed: () => _seekAfterLayout(
            (_playhead - 5).clamp(0, _totalSeconds).toDouble(),
          ),
          icon: const Icon(Icons.replay_5),
        ),
        IconButton(
          tooltip: 'Previous project frame',
          onPressed: () => _stepPreview(-1),
          icon: const Icon(Icons.skip_previous),
        ),
        IconButton(
          tooltip: _playing ? 'Pause' : 'Play',
          onPressed: !_state.hasMedia ? null : _togglePlay,
          iconSize: 36,
          icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
        ),
        IconButton(
          tooltip: 'Next project frame',
          onPressed: () => _stepPreview(1),
          icon: const Icon(Icons.skip_next),
        ),
        IconButton(
          tooltip: 'Forward 5 seconds',
          onPressed: () => _seekAfterLayout(
            (_playhead + 5).clamp(0, _totalSeconds).toDouble(),
          ),
          icon: const Icon(Icons.forward_5),
        ),
        IconButton(
          tooltip: _state.mainTrackMuted ? 'Unmute' : 'Mute',
          onPressed: () => _run(() => _engine.setMuted(!_state.mainTrackMuted)),
          icon: Icon(
            _state.mainTrackMuted ? Icons.volume_off : Icons.volume_up,
          ),
        ),
      ],
    ),
  );

  Widget _fullScreenScrubber() => Padding(
    padding: EdgeInsets.fromLTRB(
      16,
      0,
      16,
      MediaQuery.viewPaddingOf(context).bottom + 8,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Slider(
          value: _state.playheadMs.clamp(0, _state.totalDurationMs).toDouble(),
          min: 0,
          max: math.max(1, _state.totalDurationMs).toDouble(),
          onChanged: _state.totalDurationMs == 0
              ? null
              : (value) => _requestSeek(value.round()),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(formatClock(_playhead)),
            Text(formatClock(_totalSeconds)),
          ],
        ),
      ],
    ),
  );

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final selected = _selected;
    return PopScope(
      canPop: !_fullScreen,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _fullScreen) _setFullScreen(false);
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: editorBg,
          resizeToAvoidBottomInset: false,
          body: Stack(
            children: [
              // Dialog routes receive the real IME insets; the project stays stable.
              MediaQuery(
                data: media.copyWith(
                  viewInsets: EdgeInsets.zero,
                  padding: media.viewPadding,
                ),
                child: SafeArea(
                  bottom: false,
                  maintainBottomViewPadding: true,
                  child: Column(
                    children: [
                      _fullScreen ? _fullScreenHeader() : _topBar(),
                      Expanded(
                        child: _workspace(
                          selected != null,
                          media.viewPadding.bottom,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_exportOpen)
                Positioned.fill(
                  child: ExportPanel(
                    settings: _exportSettings,
                    durationSeconds: _totalSeconds,
                    onClose: () => setState(() => _exportOpen = false),
                    onExport: _startExport,
                    onChanged: () => setState(() {}),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _workspace(bool selected, double bottom) => LayoutBuilder(
    builder: (context, box) {
      final sideBySide =
          !_fullScreen && box.maxWidth >= 650 && box.maxWidth > box.maxHeight;
      final panelWidth = sideBySide
          ? math.max(350.0, box.maxWidth * .55)
          : box.maxWidth;
      final panelLeft = box.maxWidth - panelWidth;
      final toolbarHeight = _fullScreen ? 0.0 : 68.0 + bottom;
      final timelineHeight = _fullScreen
          ? 80.0 + bottom
          : math.min(
              278.0,
              math.max(
                0.0,
                box.maxHeight - toolbarHeight - 48 - (sideBySide ? 6 : 126),
              ),
            );
      final controlsTop = math.max(
        0.0,
        box.maxHeight - toolbarHeight - timelineHeight - 48,
      );
      return Stack(
        children: [
          // Keep the player at the same element position through layout changes.
          Positioned(
            left: 0,
            top: 0,
            width: sideBySide ? panelLeft : box.maxWidth,
            height: sideBySide
                ? math.max(0.0, box.maxHeight - bottom)
                : controlsTop,
            child: _preview(selected),
          ),
          Positioned(
            left: panelLeft,
            right: 0,
            top: controlsTop,
            height: 48,
            child: _fullScreen ? _fullScreenTransport() : _controls(selected),
          ),
          Positioned(
            left: panelLeft,
            right: 0,
            top: controlsTop + 48,
            height: timelineHeight,
            child: SingleChildScrollView(
              primary: false,
              child: _fullScreen ? _fullScreenScrubber() : _timeline(),
            ),
          ),
          Positioned(
            left: panelLeft,
            right: 0,
            bottom: 0,
            height: toolbarHeight,
            child: _fullScreen ? const SizedBox.shrink() : _toolbar(selected),
          ),
        ],
      );
    },
  );

  // --- Top bar --------------------------------------------------------------

  Widget _topBar() => SizedBox(
    height: 56,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close_rounded, size: 28),
            onPressed: () {
              _pause();
              Navigator.of(context).maybePop();
            },
          ),
          PopupMenuButton<String>(
            tooltip: 'Project',
            icon: const Icon(Icons.folder_outlined, size: 28),
            onSelected: _projectAction,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'save', child: Text('Save project')),
              PopupMenuItem(value: 'open', child: Text('Open project')),
            ],
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => setState(() => _exportOpen = true),
            child: Container(
              height: 34,
              padding: const EdgeInsets.only(left: 14, right: 8),
              decoration: BoxDecoration(
                color: editorSurface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _exportSettings.pillLabel,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down_rounded, size: 22),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          ExportButton(onTap: _startExport),
          const SizedBox(width: 8),
        ],
      ),
    ),
  );

  // --- Preview --------------------------------------------------------------

  Widget _preview(bool clipSelected) => DecoratedBox(
    position: DecorationPosition.foreground,
    decoration: BoxDecoration(
      border: clipSelected && !_fullScreen
          ? Border.all(color: selectionTeal, width: 2)
          : null,
    ),
    child: ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (!_state.hasMedia)
            const Center(
              child: Text(
                'Tap + to add a clip',
                style: TextStyle(color: Colors.white54),
              ),
            )
          else if (!EngineScope.previewEnabledOf(context))
            Center(child: Text(_clipAt(_playhead)?.name ?? ''))
          else
            VideoPreview(
              playbackOnly: _fullScreen,
              state: _state,
              playing: _playing,
              seekSerial: _previewSeekSerial,
              onPosition: _onPreviewPosition,
              onError: _onPreviewError,
              onSelect: _selectClip,
              onCommit: _commitVisual,
              onDelete: (c) => _run(
                () => _engine.applyTimelineEdit({
                  'action': 'delete',
                  'clip_ids': [c.id],
                  'ripple': false,
                }),
              ),
            ),
          if (_mediaWarning != null)
            Align(
              alignment: Alignment.topCenter,
              child: Container(
                color: Colors.black87,
                padding: const EdgeInsets.all(8),
                child: Text(
                  _mediaWarning!,
                  style: const TextStyle(color: Colors.amber, fontSize: 12),
                ),
              ),
            ),
        ],
      ),
    ),
  );

  // --- Transport row --------------------------------------------------------

  Widget _controls(bool clipSelected) => LayoutBuilder(
    builder: (context, box) => SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: math.max(350.0, box.maxWidth),
        height: 48,
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Fullscreen',
                    icon: const Icon(Icons.fullscreen_rounded, size: 27),
                    onPressed: () => _setFullScreen(true),
                  ),
                  IconButton(
                    tooltip: 'Zoom timeline out',
                    icon: const Icon(Icons.remove_circle_outline, size: 23),
                    onPressed: () => _zoomTimeline(1 / 1.5),
                  ),
                  IconButton(
                    tooltip: 'Zoom timeline in',
                    icon: const Icon(Icons.add_circle_outline, size: 23),
                    onPressed: () => _zoomTimeline(1.5),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: _playing ? 'Pause' : 'Play',
              iconSize: 36,
              icon: Icon(
                _playing ? Icons.pause_outlined : Icons.play_arrow_outlined,
              ),
              onPressed: _togglePlay,
            ),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Semantics(
                    label: clipSelected ? 'Add keyframe' : 'Snap',
                    child: GestureDetector(
                      onLongPress: () => _message(
                        clipSelected
                            ? 'Keyframes are planned'
                            : 'Snap to clip boundaries: ${_snap ? "on" : "off"}',
                      ),
                      child: IconButton(
                        icon: clipSelected
                            ? const _KeyframeIcon()
                            : _SnapIcon(on: _snap),
                        onPressed: () {
                          if (clipSelected) {
                            _message('Keyframes are planned');
                          } else {
                            setState(() => _snap = !_snap);
                          }
                        },
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Undo',
                    icon: const Icon(Icons.undo_rounded, size: 26),
                    onPressed: _state.canUndo ? _undoEdit : null,
                  ),
                  IconButton(
                    tooltip: 'Redo',
                    icon: const Icon(Icons.redo_rounded, size: 26),
                    onPressed: _state.canRedo ? _redoEdit : null,
                  ),
                  const SizedBox(width: 6),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  // --- Timeline -------------------------------------------------------------

  Widget _timeline() {
    final cover = _clips.isEmpty ? const Color(0xFF3A3A3D) : _clips.first.color;
    return SizedBox(
      height: _timelineHeight,
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth;
          final half = w / 2;
          final total = _totalSeconds;
          final trackW = total * _pixelsPerSecond;
          final rowW = math.max(trackW, half - 16);
          final selected = _selected?.trackKind == 'video' ? _selected : null;
          final ordered = [
            for (final c in _clips)
              if (c.id != selected?.id) c,
            if (selected != null) selected,
          ];

          return Stack(
            children: [
              NotificationListener<ScrollStartNotification>(
                onNotification: (n) {
                  if (n.dragDetails != null) {
                    _timelineDragged = true;
                    if (_playing) _pause();
                  }
                  return false;
                },
                child: NotificationListener<ScrollEndNotification>(
                  onNotification: (n) {
                    _snapTimeline();
                    return false;
                  },
                  child: SingleChildScrollView(
                    controller: _scroll,
                    scrollDirection: Axis.horizontal,
                    physics: const ClampingScrollPhysics(),
                    child: SizedBox(
                      width: w + trackW,
                      height: _timelineHeight,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned.fill(
                            child: GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onTap: () => _selectClip(null),
                            ),
                          ),
                          Positioned(
                            left: half,
                            top: 0,
                            width: trackW,
                            height: 28,
                            child: IgnorePointer(
                              child: CustomPaint(
                                painter: _RulerPainter(
                                  total.ceil(),
                                  _pixelsPerSecond,
                                ),
                              ),
                            ),
                          ),
                          // Left cluster: mute, cover, and the audio / text track buttons.
                          Positioned(
                            left: half - 158,
                            top: _laneTop('video') + 10,
                            child: _TrackButton(
                              icon: _state.mainTrackLocked
                                  ? Icons.lock
                                  : Icons.lock_open,
                              onTap: () => _toggleTrackLock('video'),
                            ),
                          ),
                          Positioned(
                            left: half - 25 - 50 - 6 - 44,
                            top: _laneTop('video'),
                            width: 44,
                            height: _trackHeight,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => _run(
                                () => _engine.setMuted(!_state.mainTrackMuted),
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _state.mainTrackMuted
                                          ? Icons.volume_off_outlined
                                          : Icons.volume_up_outlined,
                                      size: 20,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _state.mainTrackMuted ? 'Unmute' : 'Mute',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        height: 1.1,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: half - 25 - 50,
                            top: _laneTop('video'),
                            width: 50,
                            height: _trackHeight,
                            child: GestureDetector(
                              onTap: () =>
                                  _message('Cover editing is coming soon'),
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Color.lerp(cover, Colors.black, .35)!,
                                      Color.lerp(cover, Colors.black, .7)!,
                                    ],
                                  ),
                                ),
                                child: const FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.edit_outlined, size: 18),
                                      SizedBox(height: 2),
                                      Text(
                                        'Cover',
                                        style: TextStyle(
                                          fontSize: 11,
                                          height: 1.1,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: half - 25 - 30,
                            top: _laneTop('audio'),
                            child: _TrackButton(
                              icon: Icons.music_note_outlined,
                              onTap: () => _addTimelineMedia('audio'),
                            ),
                          ),
                          if (_state.audioClips.isNotEmpty)
                            Positioned(
                              left: half - 85,
                              top: _laneTop('audio'),
                              child: _TrackButton(
                                icon: _state.audioTrackLocked
                                    ? Icons.lock
                                    : Icons.lock_open,
                                onTap: () => _toggleTrackLock('audio'),
                              ),
                            ),
                          Positioned(
                            left: half - 25 - 30,
                            top: _laneTop('image'),
                            child: _TrackButton(
                              icon: Icons.image_outlined,
                              onTap: () => _addTimelineMedia('image'),
                            ),
                          ),
                          if (_state.imageClips.isNotEmpty)
                            Positioned(
                              left: half - 85,
                              top: _laneTop('image'),
                              child: _TrackButton(
                                icon: _state.imageTrackLocked
                                    ? Icons.lock
                                    : Icons.lock_open,
                                onTap: () => _toggleTrackLock('image'),
                              ),
                            ),
                          Positioned(
                            left: half - 55,
                            top: _laneTop('overlay'),
                            child: _TrackButton(
                              icon: Icons.layers_outlined,
                              onTap: () => _addTimelineMedia('overlay'),
                            ),
                          ),
                          if (_state.overlayClips.isNotEmpty)
                            Positioned(
                              left: half - 85,
                              top: _laneTop('overlay'),
                              child: _TrackButton(
                                icon: _state.overlayTrackLocked
                                    ? Icons.lock
                                    : Icons.lock_open,
                                onTap: () => _toggleTrackLock('overlay'),
                              ),
                            ),
                          // Audio, still-image and overlay tracks.
                          Positioned(
                            left: half,
                            top: _laneTop('audio'),
                            width: rowW,
                            height: 30,
                            child: _AddTrackRow(
                              label: 'Add audio',
                              onTap: () => _addTimelineMedia('audio'),
                            ),
                          ),
                          Positioned(
                            left: half,
                            top: _laneTop('image'),
                            width: rowW,
                            height: 30,
                            child: _AddTrackRow(
                              label: 'Add image',
                              onTap: () => _addTimelineMedia('image'),
                            ),
                          ),
                          Positioned(
                            left: half,
                            top: _laneTop('overlay'),
                            width: rowW,
                            height: 30,
                            child: _AddTrackRow(
                              label: 'Add overlay',
                              onTap: () => _addTimelineMedia('overlay'),
                            ),
                          ),
                          for (final clip in _state.audioClips)
                            _secondaryClipWidget(clip, half, _laneTop('audio')),
                          for (final clip in _state.imageClips)
                            _secondaryClipWidget(clip, half, _laneTop('image')),
                          for (final clip in _state.overlayClips)
                            _secondaryClipWidget(
                              clip,
                              half,
                              _laneTop('overlay'),
                            ),
                          // Video clips; the selected one is painted last so its handles overlap neighbours.
                          Positioned(
                            left: half - _laneInset,
                            top: 0,
                            width: trackW + _laneInset * 2,
                            height: _timelineHeight,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                for (final c in ordered)
                                  _clipWidget(
                                    c,
                                    (_batchIds?.contains(c.id) ??
                                        (selected?.id == c.id)),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // Fixed time readout; opaque so the ruler slides underneath it.
              Positioned(
                left: 0,
                top: 0,
                width: 124,
                height: 28,
                child: GestureDetector(
                  onTap: _seekPrecisely,
                  child: ColoredBox(
                    color: editorBg,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: formatClock(_playhead),
                                style: const TextStyle(color: Colors.white),
                              ),
                              TextSpan(
                                text: ' / ${formatClock(total)}',
                                style: const TextStyle(color: editorMuted),
                              ),
                            ],
                          ),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Playhead.
              Positioned(
                left: half - 1,
                top: 24,
                bottom: 0,
                width: 2,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
              ),
              // Pinned "add clip" button.
              Positioned(
                right: 12,
                top: _laneTop('video') + (_trackHeight - 30) / 2,
                width: 30,
                height: 30,
                child: GestureDetector(
                  onTap: _addClip,
                  child: Tooltip(
                    message: 'Add clip',
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(
                        Icons.add_rounded,
                        color: Colors.black,
                        size: 22,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _secondaryClipWidget(EditorClip clip, double origin, double top) {
    final selected =
        _batchIds?.contains(clip.id) ?? (_state.selectedClipId == clip.id);
    final duration = _trimPreview?.$1 == clip.id
        ? _trimPreview!.$3
        : clip.durationMs;
    final width = math.max(duration / 1000 * _pixelsPerSecond - 2, 36.0);
    final handles = selected && _canTrim(clip);
    return Positioned(
      key: ValueKey(clip.id),
      left:
          origin +
          (_moveDraft?.$1 == clip.id ? _moveDraft!.$2 : clip.startMs) /
              1000 *
              _pixelsPerSecond -
          (handles ? 18 : 0),
      top: top + (_rows(clip.trackKind)[clip.id] ?? 0) * 44.0,
      width: width + (handles ? 36 : 0),
      height: 36,
      child: Stack(
        children: [
          Positioned(
            left: handles ? 18 : 0,
            right: handles ? 18 : 0,
            top: 0,
            bottom: 0,
            child: GestureDetector(
              onTap: () => _selectClip(clip.id),
              onLongPressStart: !_canTrim(clip)
                  ? null
                  : (_) {
                      _pause();
                      _moveStart = clip.startMs;
                      setState(() => _moveDraft = (clip.id, clip.startMs));
                    },
              onLongPressMoveUpdate: !_canTrim(clip)
                  ? null
                  : (d) {
                      final start = math.max(
                        0,
                        _moveStart +
                            (d.offsetFromOrigin.dx / _pixelsPerSecond * 1000)
                                .round(),
                      );
                      setState(() => _moveDraft = (clip.id, start));
                    },
              onLongPressEnd: !_canTrim(clip) ? null : (_) => _finishMove(clip),
              onLongPressCancel: () => setState(() => _moveDraft = null),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                decoration: BoxDecoration(
                  color: clip.trackKind == 'audio'
                      ? const Color(0xFF27566B)
                      : clip.trackKind == 'overlay'
                      ? const Color(0xFF4B6B51)
                      : const Color(0xFF674A70),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(
                    color: selected ? Colors.white : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: Center(
                  child: Text(
                    clip.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10),
                  ),
                ),
              ),
            ),
          ),
          if (handles) ...[
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 18,
              child: _trimHandle(clip, true),
            ),
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: 18,
              child: _trimHandle(clip, false),
            ),
          ],
        ],
      ),
    );
  }

  /// A clip on the track. [Positioned] coordinates are relative to the clip lane.
  Widget _clipWidget(EditorClip clip, bool selected) {
    final left = _startOf(clip) * _pixelsPerSecond + _laneInset;
    final duration = _trimPreview?.$1 == clip.id
        ? _trimPreview!.$3
        : clip.durationMs;
    final width = math.max(duration / 1000 * _pixelsPerSecond - 2, 8.0);
    final stripHeight = selected ? _trackHeight - 4 : _trackHeight;

    final strip = ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: width,
        height: stripHeight,
        child: Stack(
          children: [
            Positioned.fill(
              child: MediaFilmstrip(
                path: clip.path,
                sourceInMs: clip.sourceInMs,
                durationMs: clip.durationMs,
                timelineStartMs: clip.startMs,
                scroll: _scroll,
                pixelsPerSecond: _pixelsPerSecond,
                enabled: EngineScope.previewEnabledOf(context),
              ),
            ),
            if (selected)
              Positioned(
                left: 6,
                top: 4,
                child: Text(
                  '${(duration / 1000).toStringAsFixed(1)}s',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    shadows: [Shadow(color: Colors.black87, blurRadius: 3)],
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    if (!selected) {
      return Positioned(
        key: ValueKey(clip.id),
        left: left,
        top: _laneTop('video'),
        width: width,
        height: _trackHeight,
        child: GestureDetector(onTap: () => _selectClip(clip.id), child: strip),
      );
    }

    return Positioned(
      key: ValueKey(clip.id),
      left: left - _laneInset,
      top: _laneTop('video'),
      width: width + _laneInset * 2,
      height: _trackHeight,
      child: GestureDetector(
        onTap: () => _selectClip(clip.id),
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
            Positioned(left: 22, top: 2, child: strip),
            if (_canTrim(clip)) ...[
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 22,
                child: _trimHandle(clip, true),
              ),
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: 22,
                child: _trimHandle(clip, false),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // --- Bottom toolbar -------------------------------------------------------

  Widget _toolbar(bool clipSelected) {
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    final itemW = MediaQuery.of(context).size.width * 133 / 900;
    final items = _batchIds != null
        ? <Widget>[
            _ToolItem(
              width: itemW,
              icon: Icons.close,
              label: '${_batchIds!.length} selected',
              onTap: () => setState(() => _batchIds = null),
            ),
            _ToolItem(
              width: itemW,
              icon: Icons.checklist,
              label: 'Select',
              onTap: _selectMany,
            ),
            _ToolItem(
              width: itemW,
              icon: Icons.swap_horiz,
              label: 'Move',
              onTap: () => _batchEdit('shift'),
            ),
            _ToolItem(
              width: itemW,
              icon: Icons.copy,
              label: 'Duplicate',
              onTap: () => _batchEdit('duplicate'),
            ),
            _ToolItem(
              width: itemW,
              icon: Icons.delete_outline,
              label: 'Delete only',
              onTap: () => _batchEdit('delete', ripple: false),
            ),
            _ToolItem(
              width: itemW,
              icon: Icons.delete_sweep,
              label: 'Ripple delete',
              onTap: () => _batchEdit('delete'),
            ),
          ]
        : clipSelected
        ? <Widget>[
            Padding(
              padding: const EdgeInsets.only(left: 10, right: 6),
              child: Center(
                child: GestureDetector(
                  onTap: () => _selectClip(null),
                  child: Container(
                    width: 32,
                    height: 46,
                    decoration: BoxDecoration(
                      color: editorSurfaceHigh,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.chevron_left_rounded, size: 26),
                  ),
                ),
              ),
            ),
            _ToolItem(
              width: itemW,
              icon: Icons.vertical_split_outlined,
              label: 'Split',
              onTap: _split,
            ),
            _ToolItem(
              width: itemW,
              icon: Icons.timer_outlined,
              label: 'Trim',
              onTap: _trim,
            ),
            _ToolItem(
              width: itemW,
              icon: Icons.tune,
              label: 'Properties',
              onTap: _properties,
            ),
            _ToolItem(
              width: itemW,
              icon: Icons.copy_outlined,
              label: 'Duplicate',
              onTap: () => _run(_engine.duplicateSelected),
            ),
            _ToolItem(
              width: itemW,
              icon: Icons.play_circle_outline_rounded,
              label: 'Animations',
              onTap: () => _message('Animations are planned'),
            ),
            _ToolItem(
              width: itemW,
              icon: Icons.stars_outlined,
              label: 'Effects',
              onTap: () => _message('Effects are planned'),
            ),
            _ToolItem(
              width: itemW,
              icon: Icons.delete_outline_rounded,
              label: 'Delete',
              onTap: _delete,
            ),
            _ToolItem(
              width: itemW,
              icon: Icons.swap_horiz_rounded,
              label: 'Move',
              onTap: _move,
            ),
            _ToolItem(
              width: itemW,
              icon: Icons.delete_forever_outlined,
              label: 'Delete only',
              onTap: () => _batchEdit('delete', ripple: false),
            ),
            _ToolItem(
              width: itemW,
              icon: Icons.checklist,
              label: 'Select',
              onTap: _selectMany,
            ),
            _ToolItem(
              width: itemW,
              icon: Icons.reorder,
              label: 'Tracks',
              onTap: _reorderTracks,
            ),
          ]
        : <Widget>[
            const SizedBox(width: 8),
            _ToolItem(
              width: itemW,
              icon: Icons.content_cut_rounded,
              label: 'Edit',
              onTap: _openEdit,
            ),
            _ToolItem(
              width: itemW,
              icon: Icons.music_note_outlined,
              label: 'Audio',
              onTap: () => _addTimelineMedia('audio'),
            ),
            _ToolItem(
              width: itemW,
              icon: Icons.title_rounded,
              label: 'Text',
              onTap: () => _message('Text tools are planned'),
            ),
            _ToolItem(
              width: itemW,
              icon: Icons.stars_outlined,
              label: 'Effects',
              onTap: () => _message('Effects are planned'),
            ),
            _ToolItem(
              width: itemW,
              icon: Icons.image_outlined,
              label: 'Image',
              onTap: () => _addTimelineMedia('image'),
            ),
            _ToolItem(
              width: itemW,
              icon: Icons.layers_outlined,
              label: 'Overlay',
              onTap: () => _addTimelineMedia('overlay'),
            ),
            _ToolItem(
              width: itemW,
              icon: Icons.subtitles_outlined,
              label: 'Captions',
              onTap: () => _message('Captions are planned'),
            ),
            _ToolItem(
              width: itemW,
              icon: Icons.workspaces_outlined,
              label: 'Filters',
              onTap: () => _message('Filters are planned'),
            ),
            _ToolItem(
              width: itemW,
              icon: Icons.checklist,
              label: 'Select',
              onTap: _selectMany,
            ),
            _ToolItem(
              width: itemW,
              icon: Icons.reorder,
              label: 'Tracks',
              onTap: _reorderTracks,
            ),
          ];

    return Container(
      color: editorBg,
      padding: EdgeInsets.only(bottom: bottom),
      height: 68 + bottom,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 160),
        child: ListView(
          key: ValueKey((_batchIds != null, clipSelected)),
          scrollDirection: Axis.horizontal,
          children: items,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small widgets
// ---------------------------------------------------------------------------

class _ToolItem extends StatelessWidget {
  const _ToolItem({
    required this.width,
    required this.icon,
    required this.label,
    required this.onTap,
    this.badge,
  });
  final double width;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Widget? badge;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: SizedBox(
      width: width,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(icon, size: 26),
              if (badge != null) Positioned(top: -3, right: -6, child: badge!),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11.5),
          ),
        ],
      ),
    ),
  );
}

class _TrackButton extends StatelessWidget {
  const _TrackButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: editorSurface,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(icon, size: 18, color: editorMuted),
    ),
  );
}

class _AddTrackRow extends StatelessWidget {
  const _AddTrackRow({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      decoration: BoxDecoration(
        color: editorSurface,
        borderRadius: BorderRadius.circular(4),
      ),
      padding: const EdgeInsets.only(left: 10),
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.add_rounded, size: 18, color: Color(0xFFB5B5BA)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, color: Color(0xFFB5B5BA)),
            ),
          ),
        ],
      ),
    ),
  );
}

class _SnapIcon extends StatelessWidget {
  const _SnapIcon({required this.on});
  final bool on;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 30,
    height: 30,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        const Positioned(
          left: 1,
          top: 0,
          child: Icon(Icons.filter_center_focus_rounded, size: 24),
        ),
        Positioned(
          right: -2,
          bottom: -1,
          child: Text(
            on ? 'ON' : 'OFF',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: on ? accentCyan : editorMuted,
            ),
          ),
        ),
      ],
    ),
  );
}

class _KeyframeIcon extends StatelessWidget {
  const _KeyframeIcon();
  @override
  Widget build(BuildContext context) => const SizedBox(
    width: 30,
    height: 30,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 3,
          top: 3,
          child: Icon(Icons.timeline_rounded, size: 24),
        ),
        Positioned(left: -2, top: -2, child: Icon(Icons.add_rounded, size: 13)),
      ],
    ),
  );
}

/// Paints the ruler above the tracks: a label every two seconds, a dot between.
class _RulerPainter extends CustomPainter {
  _RulerPainter(this.seconds, this.pixelsPerSecond);
  final int seconds;
  final double pixelsPerSecond;

  @override
  void paint(Canvas canvas, Size size) {
    final dot = Paint()..color = editorMuted;
    for (var s = 0; s <= seconds; s++) {
      final x = s * pixelsPerSecond;
      final labelStep = pixelsPerSecond < 35
          ? 5
          : pixelsPerSecond < 75
          ? 2
          : 1;
      if (s % labelStep == 0) {
        final tp = TextPainter(
          text: TextSpan(
            text: formatClock(s.toDouble()),
            style: const TextStyle(color: editorMuted, fontSize: 12),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          Offset(x - tp.width / 2, (size.height - tp.height) / 2),
        );
      } else {
        canvas.drawCircle(Offset(x, size.height / 2), 1.5, dot);
      }
    }
  }

  @override
  bool shouldRepaint(_RulerPainter old) =>
      old.seconds != seconds || old.pixelsPerSecond != pixelsPerSecond;
}
