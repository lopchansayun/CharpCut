import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'engine/editor_state.dart';

/// Displays and plays the source ranges from the authoritative engine snapshot.
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
  MethodChannel? _channel;
  int _revision = 0;
  int? _sentSeek;
  bool _sending = false;
  bool _pending = false;
  bool _hasFrame = false;
  String? _error;

  String _clipSignature(EditorState state) => jsonEncode([
    for (final clip in state.clips) [clip.id, clip.path, clip.startMs, clip.sourceInMs, clip.durationMs],
  ]);

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
    // Ignore callbacks from an earlier timeline/seek/transport request.
    if (data['revision'] != _revision) return;
    final error = data['error'] as String?;
    final hasFrame = data['has_frame'] == true;
    if (error != _error || hasFrame != _hasFrame) {
      setState(() { _error = error; _hasFrame = hasFrame; });
      if (error != null) widget.onError(error);
    }
    if (error == null) {
      widget.onPosition((data['position_ms'] as num).toInt(), data['playing'] == true);
    }
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
        try {
          await _channel!.invokeMethod<void>('update', {
            'revision': revision,
            'position_ms': widget.state.playheadMs,
            'seek': _sentSeek != seek,
            'playing': widget.playing,
            'muted': widget.state.mainTrackMuted,
            'clips': [for (final clip in widget.state.clips) {
              'id': clip.id, 'path': clip.path, 'start_ms': clip.startMs,
              'source_in_ms': clip.sourceInMs, 'duration_ms': clip.durationMs,
            }],
          });
          _sentSeek = seek;
        } catch (error) {
          if (mounted && revision == _revision) {
            final message = 'Could not open video preview: $error';
            setState(() => _error = message);
            widget.onError(message);
          }
        }
      }
    } finally { _sending = false; }
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return const Center(child: Text('Video preview is available on Android', textAlign: TextAlign.center));
    }
    return Stack(fit: StackFit.expand, children: [
      AndroidView(viewType: 'charpcut/video-preview', onPlatformViewCreated: _created),
      if (_error != null)
        ColoredBox(color: Colors.black, child: Center(child: Padding(
          padding: const EdgeInsets.all(16), child: Text(_error!, textAlign: TextAlign.center)))),
      if (_error == null && !_hasFrame)
        const IgnorePointer(child: Center(child: CircularProgressIndicator())),
    ]);
  }
}
