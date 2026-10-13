import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'engine/editor_engine.dart';
import 'engine/editor_state.dart';
import 'export_done_screen.dart';
import 'export_panel.dart';
import 'theme.dart';

/// Width in logical pixels of one second on the timeline.
const double _pps = 50;
const double _trackTop = 36;
const double _trackHeight = 50;
const double _timelineHeight = 196;

/// Extra room either side of the clip lane so a selected clip's handles stay hit-testable.
const double _laneInset = 22;

class EditorHome extends StatefulWidget {
  /// Opens this saved project instead of starting an empty one.
  const EditorHome({super.key, this.projectJson});
  final String? projectJson;

  @override
  State<EditorHome> createState() => _EditorHomeState();
}

class _EditorHomeState extends State<EditorHome> with SingleTickerProviderStateMixin {
  late final EditorEngine _engine;

  /// Everything about the project comes from the Rust engine; this is its latest answer.
  EditorState _state = EditorState.empty;

  final ScrollController _scroll = ScrollController();
  late final Ticker _ticker;
  double _startOffset = 0;
  bool _playing = false;
  bool _muted = false;
  bool _snap = true;

  final ExportSettings _exportSettings = ExportSettings();
  bool _exportOpen = false;

  @override
  void initState() {
    super.initState();
    _engine = context.getInheritedWidgetOfExactType<EngineScope>()!.engine;
    final json = widget.projectJson;
    _run(() => json == null ? _engine.newProject() : _engine.openProjectJson(json), announce: false);
    _ticker = createTicker(_onTick);
    _scroll.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Derived state
  // -------------------------------------------------------------------------

  List<EditorClip> get _clips => _state.clips;

  EditorClip? get _selected => _state.selectedClip;

  double get _totalSeconds => _state.totalSeconds;

  double get _playhead {
    if (!_scroll.hasClients || !_scroll.position.hasPixels) return 0;
    return (_scroll.offset / _pps).clamp(0.0, _totalSeconds).toDouble();
  }

  double _startOf(EditorClip clip) => clip.startMs / 1000;

  EditorClip? _clipAt(double seconds) => _state.clipAt((seconds * 1000).round());

  // -------------------------------------------------------------------------
  // Playback
  // -------------------------------------------------------------------------

  void _togglePlay() => _playing ? _pause() : _play();

  void _play() {
    if (!_scroll.hasClients || _clips.isEmpty) return;
    if (_scroll.offset >= _scroll.position.maxScrollExtent - 1) _scroll.jumpTo(0);
    _startOffset = _scroll.offset;
    setState(() => _playing = true);
    _ticker.start();
  }

  void _pause() {
    if (_ticker.isActive) _ticker.stop();
    if (_playing && mounted) setState(() => _playing = false);
  }

  void _onTick(Duration elapsed) {
    if (!_scroll.hasClients) return;
    final max = _scroll.position.maxScrollExtent;
    final next = _startOffset + elapsed.inMicroseconds / 1e6 * _pps;
    if (next >= max) {
      _scroll.jumpTo(max);
      _pause();
    } else {
      _scroll.jumpTo(next);
    }
  }

  void _seekAfterLayout(double seconds) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final target = (seconds * _pps).clamp(0.0, _scroll.position.maxScrollExtent).toDouble();
      _scroll.animateTo(target, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    });
  }

  // -------------------------------------------------------------------------
  // Editing: every change is a call into the Rust engine
  // -------------------------------------------------------------------------

  /// Runs an engine call, shows the result, and reports a refused edit.
  Future<void> _run(Future<EditorState> Function() call, {bool announce = true}) async {
    final EditorState next;
    try {
      next = await call();
    } catch (error) {
      if (mounted) _message('The editing engine failed: $error');
      return;
    }
    if (!mounted) return;
    setState(() => _state = next);
    final error = next.lastError;
    if (error != null) {
      _message(error);
    } else if (announce && next.status.isNotEmpty) {
      _message(next.status);
    }
  }

  void _undoEdit() => _run(_engine.undo, announce: false);

  void _redoEdit() => _run(_engine.redo, announce: false);

  /// Splits the selected clip at the playhead.
  void _split() {
    if (_selected == null) return;
    _run(() => _engine.splitSelectedAt((_playhead * 1000).round()));
  }

  void _trim() {
    final clip = _selected;
    if (clip == null) return;
    if (clip.durationMs <= 1000) return _message('Clip is at minimum duration');
    _run(() => _engine.trimSelected(sourceInMs: clip.sourceInMs, durationMs: clip.durationMs - 500));
  }

  void _delete() {
    if (_selected == null) return;
    _run(_engine.deleteSelected);
  }

  /// Adds a stand-in clip until media import (Phase 1) can pick real files.
  Future<void> _addClip() async {
    final start = _totalSeconds;
    await _run(() => _engine.addClip(path: 'placeholder://sample.mp4', durationMs: 3000));
    _seekAfterLayout(start);
  }

  void _selectClip(String? id) => _run(() => _engine.select(id), announce: false);

  void _openEdit() {
    final clip = _clipAt(_playhead);
    if (clip == null) return _message('Add a clip first');
    _selectClip(clip.id);
  }

  /// Messages float above the bottom toolbar instead of covering it.
  void _message(String value) =>
      toast(context, value, bottomInset: 68 + MediaQuery.of(context).padding.bottom + 10);

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
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const EditorHome()));
    }
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final selected = _selected;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: editorBg,
        body: Stack(
          children: [
            Column(
              children: [
                SizedBox(height: media.padding.top),
                _topBar(),
                Expanded(child: _preview(selected != null)),
                _controls(selected != null),
                _timeline(),
                const SizedBox(height: 6),
                _toolbar(selected != null),
              ],
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
    );
  }

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
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          IconButton(
            tooltip: 'Search',
            icon: const Icon(Icons.search_rounded, size: 28),
            onPressed: () => _message('Search is not available yet'),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => setState(() => _exportOpen = true),
            child: Container(
              height: 34,
              padding: const EdgeInsets.only(left: 14, right: 8),
              decoration: BoxDecoration(color: editorSurface, borderRadius: BorderRadius.circular(10)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_exportSettings.pillLabel, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
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

  Widget _preview(bool clipSelected) {
    final clip = _clipAt(_playhead);
    return LayoutBuilder(
      builder: (context, box) {
        final pw = math.min(box.maxWidth, box.maxHeight * 4 / 3);
        return Center(
          child: Container(
            width: pw,
            height: pw * 3 / 4,
            foregroundDecoration: clipSelected
                ? BoxDecoration(border: Border.all(color: selectionTeal, width: 2))
                : null,
            decoration: clip == null
                ? const BoxDecoration(color: Colors.black)
                : BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color.lerp(clip.color, Colors.black, .35)!, Color.lerp(clip.color, Colors.black, .85)!],
                    ),
                  ),
            child: Center(
              child: clip == null
                  ? const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.video_library_outlined, size: 34, color: Colors.white38),
                        SizedBox(height: 10),
                        Text('Tap + to add a clip', style: TextStyle(fontSize: 13, color: Colors.white54)),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.movie_creation_outlined, size: 34, color: Colors.white54),
                        const SizedBox(height: 10),
                        Text(clip.name, style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 2, fontSize: 15)),
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }

  // --- Transport row --------------------------------------------------------

  Widget _controls(bool clipSelected) => SizedBox(
    height: 48,
    child: Row(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 6),
              child: IconButton(
                tooltip: 'Fullscreen',
                icon: const Icon(Icons.fullscreen_rounded, size: 28),
                onPressed: () => _message('Fullscreen preview is planned'),
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: _playing ? 'Pause' : 'Play',
          iconSize: 36,
          icon: Icon(_playing ? Icons.pause_outlined : Icons.play_arrow_outlined),
          onPressed: _togglePlay,
        ),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              clipSelected
                  ? IconButton(
                      tooltip: 'Add keyframe',
                      icon: const _KeyframeIcon(),
                      onPressed: () => _message('Keyframes are planned'),
                    )
                  : IconButton(
                      tooltip: 'Snap',
                      icon: _SnapIcon(on: _snap),
                      onPressed: () => setState(() => _snap = !_snap),
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
          final trackW = total * _pps;
          final rowW = math.max(trackW, half - 16);
          final selected = _selected;
          final ordered = [
            for (final c in _clips)
              if (c.id != selected?.id) c,
            if (selected != null) selected,
          ];

          return Stack(
            children: [
              NotificationListener<ScrollStartNotification>(
                onNotification: (n) {
                  if (n.dragDetails != null && _playing) _pause();
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
                          child: GestureDetector(behavior: HitTestBehavior.translucent, onTap: () => _selectClip(null)),
                        ),
                        Positioned(
                          left: half,
                          top: 0,
                          width: trackW,
                          height: 28,
                          child: IgnorePointer(child: CustomPaint(painter: _RulerPainter(total.ceil()))),
                        ),
                        // Left cluster: mute, cover, and the audio / text track buttons.
                        Positioned(
                          left: half - 25 - 50 - 6 - 44,
                          top: _trackTop,
                          width: 44,
                          height: _trackHeight,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => setState(() => _muted = !_muted),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(_muted ? Icons.volume_off_outlined : Icons.volume_up_outlined, size: 20),
                                  const SizedBox(height: 2),
                                  Text(
                                    _muted ? 'Unmute' : 'Mute',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 11, height: 1.1),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: half - 25 - 50,
                          top: _trackTop,
                          width: 50,
                          height: _trackHeight,
                          child: GestureDetector(
                            onTap: () => _message('Cover editing is coming soon'),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [Color.lerp(cover, Colors.black, .35)!, Color.lerp(cover, Colors.black, .7)!],
                                ),
                              ),
                              child: const FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.edit_outlined, size: 18),
                                    SizedBox(height: 2),
                                    Text('Cover', style: TextStyle(fontSize: 11, height: 1.1)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: half - 25 - 30,
                          top: 95,
                          child: _TrackButton(icon: Icons.music_note_outlined, onTap: () => _message('Audio tools are planned')),
                        ),
                        Positioned(
                          left: half - 25 - 30,
                          top: 134,
                          child: _TrackButton(icon: Icons.title_rounded, onTap: () => _message('Text tools are planned')),
                        ),
                        // Audio and text placeholder tracks.
                        Positioned(
                          left: half,
                          top: 95,
                          width: rowW,
                          height: 30,
                          child: _AddTrackRow(label: 'Add audio', onTap: () => _message('Audio tools are planned')),
                        ),
                        Positioned(
                          left: half,
                          top: 134,
                          width: rowW,
                          height: 30,
                          child: _AddTrackRow(label: 'Add text', onTap: () => _message('Text tools are planned')),
                        ),
                        // Video clips; the selected one is painted last so its handles overlap neighbours.
                        Positioned(
                          left: half - _laneInset,
                          top: 0,
                          width: trackW + _laneInset * 2,
                          height: _timelineHeight,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [for (final c in ordered) _clipWidget(c, selected?.id == c.id)],
                          ),
                        ),
                      ],
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
                child: ColoredBox(
                  color: editorBg,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: formatClock(_playhead), style: const TextStyle(color: Colors.white)),
                            TextSpan(text: ' / ${formatClock(total)}', style: const TextStyle(color: editorMuted)),
                          ],
                        ),
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
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
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(1)),
                  ),
                ),
              ),
              // Pinned "add clip" button.
              Positioned(
                right: 12,
                top: _trackTop + (_trackHeight - 30) / 2,
                width: 30,
                height: 30,
                child: GestureDetector(
                  onTap: _addClip,
                  child: Tooltip(
                    message: 'Add clip',
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6)),
                      child: const Icon(Icons.add_rounded, color: Colors.black, size: 22),
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

  /// A clip on the track. [Positioned] coordinates are relative to the clip lane.
  Widget _clipWidget(EditorClip clip, bool selected) {
    final left = _startOf(clip) * _pps + _laneInset;
    final width = math.max(clip.durationMs / 1000 * _pps - 2, 8.0);
    final stripHeight = selected ? _trackHeight - 4 : _trackHeight;

    final strip = ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: width,
        height: stripHeight,
        child: Stack(
          children: [
            for (var i = 0; i * 50 < width; i++)
              Positioned(left: i * 50.0, top: 0, bottom: 0, width: 50, child: _FrameTile(color: clip.color, seed: i)),
            if (selected)
              Positioned(
                left: 6,
                top: 4,
                child: Text(
                  '${(clip.durationMs / 1000).toStringAsFixed(1)}s',
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
        top: _trackTop,
        width: width,
        height: _trackHeight,
        child: GestureDetector(onTap: () => _selectClip(clip.id), child: strip),
      );
    }

    return Positioned(
      key: ValueKey(clip.id),
      left: left - _laneInset,
      top: _trackTop,
      width: width + _laneInset * 2,
      height: _trackHeight,
      child: GestureDetector(
        onTap: () {},
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6))),
            ),
            Positioned(left: 22, top: 2, child: strip),
            const Positioned(left: 9, top: 16, width: 4, height: 18, child: _Handle()),
            const Positioned(right: 9, top: 16, width: 4, height: 18, child: _Handle()),
          ],
        ),
      ),
    );
  }

  // --- Bottom toolbar -------------------------------------------------------

  Widget _toolbar(bool clipSelected) {
    final bottom = MediaQuery.of(context).padding.bottom;
    final itemW = MediaQuery.of(context).size.width * 133 / 900;
    final items = clipSelected
        ? <Widget>[
            Padding(
              padding: const EdgeInsets.only(left: 10, right: 6),
              child: Center(
                child: GestureDetector(
                  onTap: () => _selectClip(null),
                  child: Container(
                    width: 32,
                    height: 46,
                    decoration: BoxDecoration(color: editorSurfaceHigh, borderRadius: BorderRadius.circular(6)),
                    child: const Icon(Icons.chevron_left_rounded, size: 26),
                  ),
                ),
              ),
            ),
            _ToolItem(width: itemW, icon: Icons.vertical_split_outlined, label: 'Split', onTap: _split),
            _ToolItem(width: itemW, icon: Icons.timer_outlined, label: 'Trim', onTap: _trim),
            _ToolItem(width: itemW, icon: Icons.play_circle_outline_rounded, label: 'Animations', onTap: () => _message('Animations are planned')),
            _ToolItem(width: itemW, icon: Icons.stars_outlined, label: 'Effects', onTap: () => _message('Effects are planned')),
            _ToolItem(width: itemW, icon: Icons.delete_outline_rounded, label: 'Delete', onTap: _delete),
          ]
        : <Widget>[
            const SizedBox(width: 8),
            _ToolItem(width: itemW, icon: Icons.content_cut_rounded, label: 'Edit', onTap: _openEdit),
            _ToolItem(width: itemW, icon: Icons.music_note_outlined, label: 'Audio', onTap: () => _message('Audio tools are planned')),
            _ToolItem(width: itemW, icon: Icons.title_rounded, label: 'Text', onTap: () => _message('Text tools are planned')),
            _ToolItem(width: itemW, icon: Icons.stars_outlined, label: 'Effects', onTap: () => _message('Effects are planned')),
            _ToolItem(width: itemW, icon: Icons.filter_frames_outlined, label: 'Overlay', onTap: () => _message('Overlays are planned')),
            _ToolItem(width: itemW, icon: Icons.subtitles_outlined, label: 'Captions', onTap: () => _message('Captions are planned')),
            _ToolItem(width: itemW, icon: Icons.workspaces_outlined, label: 'Filters', onTap: () => _message('Filters are planned')),
          ];

    return Container(
      color: editorBg,
      padding: EdgeInsets.only(bottom: bottom),
      height: 68 + bottom,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 160),
        child: ListView(
          key: ValueKey(clipSelected),
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
  const _ToolItem({required this.width, required this.icon, required this.label, required this.onTap, this.badge});
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
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5)),
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
      decoration: BoxDecoration(color: editorSurface, borderRadius: BorderRadius.circular(6)),
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
      decoration: BoxDecoration(color: editorSurface, borderRadius: BorderRadius.circular(4)),
      padding: const EdgeInsets.only(left: 10),
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.add_rounded, size: 18, color: Color(0xFFB5B5BA)),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 14, color: Color(0xFFB5B5BA))),
        ],
      ),
    ),
  );
}

class _Handle extends StatelessWidget {
  const _Handle();
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(color: const Color(0xFFB0B0B5), borderRadius: BorderRadius.circular(2)),
  );
}

/// One "frame" of the clip filmstrip. There is no media decoding yet, so these
/// are tinted gradient swatches that read as a thumbnail strip.
class _FrameTile extends StatelessWidget {
  const _FrameTile({required this.color, required this.seed});
  final Color color;
  final int seed;
  @override
  Widget build(BuildContext context) {
    final lift = (seed % 3) * .06;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: seed.isEven ? Alignment.topLeft : Alignment.topRight,
          end: Alignment.bottomCenter,
          colors: [Color.lerp(color, Colors.white, .12 + lift)!, Color.lerp(color, Colors.black, .6)!],
        ),
        border: const Border(right: BorderSide(color: Colors.black38, width: .5)),
      ),
    );
  }
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
        const Positioned(left: 1, top: 0, child: Icon(Icons.filter_center_focus_rounded, size: 24)),
        Positioned(
          right: -2,
          bottom: -1,
          child: Text(
            on ? 'ON' : 'OFF',
            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: on ? accentCyan : editorMuted),
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
        Positioned(left: 3, top: 3, child: Icon(Icons.timeline_rounded, size: 24)),
        Positioned(left: -2, top: -2, child: Icon(Icons.add_rounded, size: 13)),
      ],
    ),
  );
}

/// Paints the ruler above the tracks: a label every two seconds, a dot between.
class _RulerPainter extends CustomPainter {
  _RulerPainter(this.seconds);
  final int seconds;

  @override
  void paint(Canvas canvas, Size size) {
    final dot = Paint()..color = editorMuted;
    for (var s = 0; s <= seconds; s++) {
      final x = s * _pps;
      if (s.isEven) {
        final tp = TextPainter(
          text: TextSpan(text: formatClock(s.toDouble()), style: const TextStyle(color: editorMuted, fontSize: 12)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x - tp.width / 2, (size.height - tp.height) / 2));
      } else {
        canvas.drawCircle(Offset(x, size.height / 2), 1.5, dot);
      }
    }
  }

  @override
  bool shouldRepaint(_RulerPainter old) => old.seconds != seconds;
}
