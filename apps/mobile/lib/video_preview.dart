import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'engine/editor_state.dart';

/// Read-only renderer of Rust snapshot ranges. Zoom and fit affect viewing only.
class VideoPreview extends StatefulWidget {
  const VideoPreview({super.key, required this.state, required this.playing,
    required this.seekSerial, required this.onPosition, required this.onError});
  final EditorState state;
  final bool playing;
  final int seekSerial;
  final void Function(int positionMs, bool playing) onPosition;
  final ValueChanged<String> onError;

  @override
  State<VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<VideoPreview> {
  final _transform = TransformationController();
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
  bool _sourceFit = true;
  double _sourceAspect = 0;
  String? _error;

  String _clipSignature(EditorState state) => jsonEncode({
    'duration': state.totalDurationMs,
    'clips': [for (final clip in state.clips)
      [clip.id, clip.path, clip.startMs, clip.sourceInMs, clip.durationMs]],
  });

  @override
  void didUpdateWidget(VideoPreview old) {
    super.didUpdateWidget(old);
    final changed = _clipSignature(old.state) != _clipSignature(widget.state);
    if (changed) { _hasFrame = false; _error = null; }
    if (changed || old.seekSerial != widget.seekSerial || old.playing != widget.playing ||
        old.state.mainTrackMuted != widget.state.mainTrackMuted) {
      _revision++;
      _scheduleUpdate();
    }
  }

  void _created(int id) {
    _channel = MethodChannel('charpcut/preview/$id')..setMethodCallHandler(_nativeEvent);
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
    if (error != _error || hasFrame != _hasFrame || buffering != _buffering ||
        gap != _gap || (aspect > 0 && aspect != _sourceAspect)) {
      final newError = error != null && error != _error;
      setState(() {
        _error = error; _hasFrame = hasFrame; _buffering = buffering; _gap = gap;
        if (aspect.isFinite && aspect > 0) _sourceAspect = aspect;
      });
      if (newError) widget.onError(error!);
    }
    if (error == null) {
      widget.onPosition((data['position_ms'] as num).toInt(), data['playing'] == true);
    }
  }

  void _retry() {
    setState(() { _error = null; _hasFrame = false; _buffering = true; });
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
            'revision': revision, 'duration_ms': widget.state.totalDurationMs,
            'position_ms': widget.state.playheadMs,
            'seek': _sentSeek != seek, 'retry': retryRequested,
            'playing': widget.playing, 'muted': widget.state.mainTrackMuted,
            'clips': [for (final clip in widget.state.clips) {
              'id': clip.id, 'path': clip.path, 'start_ms': clip.startMs,
              'source_in_ms': clip.sourceInMs, 'duration_ms': clip.durationMs,
            }],
          });
          _sentSeek = seek;
          _sentRetry = retry;
        } catch (error) {
          if (mounted && revision == _revision) {
            final message = error is PlatformException
                ? error.message ?? 'Could not load preview' : 'Could not load preview: $error';
            setState(() => _error = message);
            widget.onError(message);
          }
        }
      }
    } finally { _sending = false; }
  }

  void _zoom(double amount, Size size) {
    final scale = (_transform.value.getMaxScaleOnAxis() + amount).clamp(1.0, 4.0).toDouble();
    _transform.value = Matrix4.diagonal3Values(scale, scale, 1)
      ..setTranslationRaw((1 - scale) * size.width / 2, (1 - scale) * size.height / 2, 0);
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
      return const Center(child: Text('Video preview is available on Android', textAlign: TextAlign.center));
    }
    return Column(children: [
      Expanded(child: LayoutBuilder(builder: (context, bounds) {
        final aspect = _sourceFit && !_gap && _sourceAspect > 0
            ? _sourceAspect : widget.state.projectAspectRatio;
        final width = bounds.maxWidth < bounds.maxHeight * aspect ? bounds.maxWidth : bounds.maxHeight * aspect;
        final size = Size(width, width / aspect);
        return Stack(fit: StackFit.expand, children: [
          Center(child: SizedBox(width: size.width, height: size.height,
            child: ClipRect(child: GestureDetector(
              onDoubleTap: () { _transform.value = Matrix4.identity(); },
              child: InteractiveViewer(
                transformationController: _transform, minScale: 1, maxScale: 4,
                child: Stack(fit: StackFit.expand, children: [
                  IgnorePointer(child: AndroidView(viewType: 'charpcut/video-preview', onPlatformViewCreated: _created)),
                  if (_gap) const ColoredBox(color: Colors.black),
                ]),
              ),
            )),
          )),
          if (_error != null) ColoredBox(color: Colors.black, child: Center(child: SingleChildScrollView(
            child: Padding(padding: const EdgeInsets.all(16), child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.error_outline, color: Colors.white70),
              const SizedBox(height: 8),
              Text(_error!, textAlign: TextAlign.center),
              TextButton.icon(onPressed: _retry, icon: const Icon(Icons.refresh), label: const Text('Retry preview')),
            ])),
          ))),
          if (_error == null && (_buffering || (!_hasFrame && !_gap)))
            const IgnorePointer(child: Center(child: CircularProgressIndicator())),
          if (_error == null) Positioned(right: 4, bottom: 4, child: DecoratedBox(
            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(tooltip: 'Zoom out', onPressed: () => _zoom(-.5, size), icon: const Icon(Icons.remove)),
              ValueListenableBuilder<Matrix4>(valueListenable: _transform, builder: (context, value, _) =>
                Tooltip(message: 'Reset zoom', child: TextButton(onPressed: () { _transform.value = Matrix4.identity(); },
                  child: Text('${value.getMaxScaleOnAxis().toStringAsFixed(1)}x')))),
              IconButton(tooltip: 'Zoom in', onPressed: () => _zoom(.5, size), icon: const Icon(Icons.add)),
            ]),
          )),
        ]);
      })),
      SizedBox(height: 36, child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        PopupMenuButton<bool>(
          tooltip: 'Preview fit', initialValue: _sourceFit,
          onSelected: (value) {
            _transform.value = Matrix4.identity();
            setState(() { _sourceFit = value; });
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: true, child: Text('Fit source video')),
            PopupMenuItem(value: false, child: Text('Fit project canvas')),
          ],
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(_sourceFit ? 'Source fit' : 'Project canvas')),
        ),
        const Flexible(child: Text('Pinch to zoom / drag to pan', style: TextStyle(fontSize: 11, color: Colors.white54))),
      ])),
    ]);
  }
}
