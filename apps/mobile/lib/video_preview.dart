import 'dart:math' as math;
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'engine/editor_state.dart';
import 'preview_layer_controls.dart';
import 'timeline_layers.dart';

/// Renders Rust snapshot ranges with local gesture drafts committed on release.
class VideoPreview extends StatefulWidget {
  const VideoPreview({
    super.key,
    required this.state,
    required this.playing,
    this.playbackOnly = false,
    required this.seekSerial,
    required this.onPosition,
    required this.onError,
    required this.onSelect,
    required this.onCommit,
    required this.onDelete,
  });
  final EditorState state;
  final bool playing;
  final bool playbackOnly;
  final int seekSerial;
  final void Function(int positionMs, bool playing) onPosition;
  final ValueChanged<String> onError;
  final ValueChanged<String?> onSelect;
  final Future<void> Function(EditorClip clip, ClipProperties properties)
  onCommit;
  final ValueChanged<EditorClip> onDelete;
  @override
  State<VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<VideoPreview> {
  final _transform = TransformationController();
  final _drafts = <String, ClipProperties>{};
  MethodChannel? _channel;
  int _revision = 0;
  int? _sentSeek;
  int _retrySerial = 0;
  int _sentRetry = 0;
  bool _sending = false;
  bool _pending = false;
  bool _hasFrame = false;
  bool _buffering = false;
  bool _gap = false;
  double _sourceAspect = 0;
  String? _error;

  String _clipSignature(EditorState state) => jsonEncode({
    'duration': state.totalDurationMs,
    'clips': [
      for (final clip in state.clips)
        [clip.id, clip.path, clip.startMs, clip.sourceInMs, clip.durationMs],
    ],
    'audio': [
      for (final clip in state.audioClips)
        [clip.id, clip.path, clip.startMs, clip.sourceInMs, clip.durationMs],
    ],
    'images': [
      for (final clip in state.imageClips)
        [clip.id, clip.path, clip.startMs, clip.durationMs],
    ],
    'overlays': [
      for (final clip in state.overlayClips)
        [clip.id, clip.path, clip.startMs, clip.durationMs],
    ],
  });

  @override
  void didUpdateWidget(VideoPreview old) {
    super.didUpdateWidget(old);
    if (widget.playbackOnly && !old.playbackOnly) {
      _transform.value = Matrix4.identity();
      _drafts.clear();
    }
    final sameProject =
        identical(old.state.clips, widget.state.clips) &&
        identical(old.state.audioClips, widget.state.audioClips) &&
        identical(old.state.imageClips, widget.state.imageClips) &&
        identical(old.state.overlayClips, widget.state.overlayClips);
    final changed =
        !sameProject &&
        _clipSignature(old.state) != _clipSignature(widget.state);
    if (changed) {
      _hasFrame = false;
      _error = null;
      _sourceAspect = 0;
    }
    if (changed ||
        old.seekSerial != widget.seekSerial ||
        old.playing != widget.playing ||
        old.state.mainTrackMuted != widget.state.mainTrackMuted ||
        (!sameProject &&
            jsonEncode([
                  for (final c in old.state.allClips) c.properties.volume,
                ]) !=
                jsonEncode([
                  for (final c in widget.state.allClips) c.properties.volume,
                ]))) {
      _revision++;
      _scheduleUpdate();
    }
  }

  void _created(int id) {
    _channel = MethodChannel('charpcut/preview/$id')
      ..setMethodCallHandler(_nativeEvent);
    _revision++;
    _scheduleUpdate();
  }

  Future<void> _nativeEvent(MethodCall call) async {
    if (!mounted || call.method != 'state') return;
    final data = Map<Object?, Object?>.from(call.arguments as Map);
    if (data['revision'] != _revision) return;
    final error = data['error'] as String?;
    final hasFrame = data['has_frame'] == true;
    final buffering = data['buffering'] == true;
    final gap = data['gap'] == true;
    final aspect = (data['aspect_ratio'] as num?)?.toDouble() ?? 0;
    if (error != _error ||
        hasFrame != _hasFrame ||
        buffering != _buffering ||
        gap != _gap ||
        (aspect > 0 && aspect != _sourceAspect)) {
      final newError = error != null && error != _error;
      setState(() {
        _error = error;
        _hasFrame = hasFrame;
        _buffering = buffering;
        _gap = gap;
        if (aspect.isFinite && aspect > 0) _sourceAspect = aspect;
      });
      if (newError) widget.onError(error);
    }
    if (error == null) {
      widget.onPosition(
        (data['position_ms'] as num).toInt(),
        data['playing'] == true,
      );
    }
  }

  void _retry() {
    setState(() {
      _error = null;
      _hasFrame = false;
      _buffering = true;
    });
    _retrySerial++;
    _revision++;
    _scheduleUpdate();
  }

  void _scheduleUpdate() {
    _pending = true;
    if (!_sending && _channel != null) _sendUpdates();
  }

  Future<void> _sendUpdates() async {
    _sending = true;
    try {
      while (mounted && _pending && _channel != null) {
        _pending = false;
        final revision = _revision;
        final seek = widget.seekSerial;
        final retry = _retrySerial;
        final retryRequested = retry != _sentRetry;
        _sentRetry = retry;
        try {
          await _channel!.invokeMethod<void>('update', {
            'revision': revision,
            'duration_ms': widget.state.totalDurationMs,
            'position_ms': widget.state.playheadMs,
            'seek': _sentSeek != seek,
            'retry': retryRequested,
            'playing': widget.playing,
            'muted': widget.state.mainTrackMuted,
            'clip_volumes': {
              for (final c in widget.state.clips) c.id: c.properties.volume,
            },
            'audio_volumes': {
              for (final c in widget.state.audioClips)
                c.id: c.properties.volume,
            },
            'clips': [
              for (final clip in widget.state.clips)
                {
                  'id': clip.id,
                  'path': clip.path,
                  'start_ms': clip.startMs,
                  'source_in_ms': clip.sourceInMs,
                  'duration_ms': clip.durationMs,
                },
            ],
            'audio_clips': [
              for (final clip in widget.state.audioClips)
                {
                  'id': clip.id,
                  'path': clip.path,
                  'start_ms': clip.startMs,
                  'source_in_ms': clip.sourceInMs,
                  'duration_ms': clip.durationMs,
                },
            ],
          });
          _sentSeek = seek;
          _sentRetry = retry;
        } catch (error) {
          if (mounted && revision == _revision) {
            final message = error is PlatformException
                ? error.message ?? 'Could not load preview'
                : 'Could not load preview: $error';
            setState(() => _error = message);
            widget.onError(message);
          }
        }
      }
    } finally {
      _sending = false;
    }
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return const Center(
        child: Text(
          'Video preview is available on Android',
          textAlign: TextAlign.center,
        ),
      );
    }
    final visualClips = activeVisualClips(widget.state);
    final hasStill = visualClips.any((c) => c.kind == 'image');
    final selectedVisible =
        !widget.playbackOnly &&
        !widget.playing &&
        visualClips.any((c) => c.id == widget.state.selectedClipId);
    return LayoutBuilder(
      builder: (context, bounds) {
        final aspect = widget.state.projectAspectRatio;
        final width = bounds.maxWidth < bounds.maxHeight * aspect
            ? bounds.maxWidth
            : bounds.maxHeight * aspect;
        final size = Size(width, width / aspect);
        return Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: ClipRect(
                  child: GestureDetector(
                    onDoubleTap: widget.playbackOnly
                        ? null
                        : () {
                            _transform.value = Matrix4.identity();
                          },
                    child: InteractiveViewer(
                      transformationController: _transform,
                      minScale: 1,
                      maxScale: 4,
                      panEnabled: !widget.playbackOnly && !selectedVisible,
                      scaleEnabled: !widget.playbackOnly && !selectedVisible,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          // Keep the platform view mounted even during a gap.
                          for (final layer in previewLayers(
                            widget.state,
                            visualClips,
                          ))
                            ClipVisual(
                              key: ValueKey(
                                layer == null || layer.trackKind == 'video'
                                    ? 'main-video'
                                    : layer.id,
                              ),
                              properties:
                                  _drafts[layer?.id] ??
                                  layer?.properties ??
                                  const ClipProperties(),
                              visible:
                                  layer != null &&
                                  (layer.trackKind != 'video' || !_gap),
                              child: layer == null || layer.trackKind == 'video'
                                  ? Center(
                                      child: AspectRatio(
                                        aspectRatio: _sourceAspect > 0
                                            ? _sourceAspect
                                            : aspect,
                                        child: IgnorePointer(
                                          child: AndroidView(
                                            key: const ValueKey('main-video'),
                                            viewType: 'charpcut/video-preview',
                                            onPlatformViewCreated: _created,
                                          ),
                                        ),
                                      ),
                                    )
                                  : Image.file(
                                      File(layer.path),
                                      fit: BoxFit.contain,
                                      cacheWidth: widget.state.projectWidth
                                          .clamp(1, 2048)
                                          .toInt(),
                                      errorBuilder: (_, error, __) => Center(
                                        child: Text(
                                          'Could not show image: $error',
                                        ),
                                      ),
                                    ),
                            ),
                          if (!widget.playbackOnly)
                            PreviewLayerControls(
                              clips: visualClips,
                              selectedId: selectedVisible
                                  ? widget.state.selectedClipId
                                  : null,
                              locked: widget.state.tracks
                                  .where((t) => t.locked)
                                  .map((t) => t.id)
                                  .toSet(),
                              onSelect: widget.onSelect,
                              onCommit: widget.onCommit,
                              onDelete: widget.onDelete,
                              onDraft: (id, p) => setState(() {
                                if (p == null) {
                                  _drafts.remove(id);
                                } else {
                                  _drafts[id] = p;
                                }
                              }),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (!widget.playbackOnly)
              Positioned(
                top: 0,
                right: 0,
                child: PopupMenuButton<String>(
                  tooltip: 'Select layer',
                  icon: const Icon(Icons.layers_outlined),
                  onSelected: (id) => widget.onSelect(id.isEmpty ? null : id),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: '', child: Text('Deselect')),
                    for (final c in visualClips.reversed)
                      PopupMenuItem(
                        value: c.id,
                        child: Text('${c.trackKind}: ${c.name}'),
                      ),
                  ],
                ),
              ),
            if (_error != null)
              ColoredBox(
                color: Colors.black,
                child: Center(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: Colors.white70,
                          ),
                          const SizedBox(height: 8),
                          Text(_error!, textAlign: TextAlign.center),
                          TextButton.icon(
                            onPressed: _retry,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Retry preview'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (_error == null &&
                (_buffering || (!_hasFrame && !_gap && !hasStill)))
              const IgnorePointer(
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        );
      },
    );
  }
}

/// Saved canvas edits are applied inside the independent pinch-zoom viewport.
class ClipVisual extends StatelessWidget {
  const ClipVisual({
    super.key,
    required this.properties,
    required this.child,
    this.visible = true,
  });
  final ClipProperties properties;
  final Widget child;
  final bool visible;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final p = properties;
      return Opacity(
        opacity: visible ? p.opacity : 0,
        child: Transform.translate(
          offset: Offset(p.x * bounds.maxWidth, p.y * bounds.maxHeight),
          child: Transform.rotate(
            angle: p.rotation * math.pi / 180,
            child: Transform.scale(
              scale: p.scale,
              child: ClipRect(
                clipper: _CanvasCrop(p),
                child: SizedBox.expand(child: child),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _CanvasCrop extends CustomClipper<Rect> {
  _CanvasCrop(this.p);
  final ClipProperties p;
  @override
  Rect getClip(Size size) => Rect.fromLTRB(
    size.width * p.cropLeft,
    size.height * p.cropTop,
    size.width * (1 - p.cropRight),
    size.height * (1 - p.cropBottom),
  );
  @override
  bool shouldReclip(_CanvasCrop old) => old.p != p;
}
