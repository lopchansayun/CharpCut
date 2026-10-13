import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'engine/media_library.dart';

class MediaThumbnail extends StatefulWidget {
  const MediaThumbnail({super.key, required this.path, this.positionMs = 0,
    this.kind = 'video', this.enabled = true});
  final String path;
  final int positionMs;
  final String kind;
  final bool enabled;
  @override
  State<MediaThumbnail> createState() => _MediaThumbnailState();
}

class _MediaThumbnailState extends State<MediaThumbnail> {
  Future<String?>? _image;
  @override
  void initState() { super.initState(); _load(); }
  @override
  void didUpdateWidget(MediaThumbnail old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path || old.positionMs != widget.positionMs ||
        old.enabled != widget.enabled || old.kind != widget.kind) _load();
  }
  void _load() {
    _image = widget.enabled && widget.path.isNotEmpty && widget.kind != 'audio'
        ? MediaLibrary().thumbnail(widget.path, widget.positionMs) : null;
  }
  Widget _fallback({bool broken = false}) => ColoredBox(
    color: const Color(0xFF303644),
    child: Center(child: Icon(broken ? Icons.broken_image_outlined
        : widget.kind == 'audio' ? Icons.audiotrack : Icons.movie_outlined,
        color: Colors.white70, size: 22)),
  );
  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
    future: _image,
    builder: (context, snapshot) {
      if (snapshot.hasError) return Tooltip(message: 'Preview unavailable', child: _fallback(broken: true));
      final path = snapshot.data;
      if (path == null) return _fallback();
      return Image.file(File(path), fit: BoxFit.cover, gaplessPlayback: true,
          cacheWidth: 320, errorBuilder: (_, _, _) => _fallback(broken: true));
    },
  );
}

/// Decode only the visible portion of a clip, with one tile of overscan.
/// Each tile requests a source timestamp, so trim/split reuse the right frames.
class MediaFilmstrip extends StatelessWidget {
  const MediaFilmstrip({super.key, required this.path, required this.sourceInMs,
    required this.durationMs, required this.timelineStartMs, required this.scroll,
    required this.pixelsPerSecond, required this.enabled});
  final String path;
  final int sourceInMs;
  final int durationMs;
  final int timelineStartMs;
  final ScrollController scroll;
  final double pixelsPerSecond;
  final bool enabled;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
    return AnimatedBuilder(animation: scroll, builder: (context, _) {
      const tileWidth = 50.0;
      final viewport = MediaQuery.sizeOf(context).width;
      final contentLeft = viewport / 2 + timelineStartMs / 1000 * pixelsPerSecond;
      final offset = scroll.hasClients ? scroll.offset : 0.0;
      final count = (constraints.maxWidth / tileWidth).ceil();
      final first = math.max(0, ((offset - contentLeft) / tileWidth).floor() - 1);
      final end = math.min(count, ((offset + viewport - contentLeft) / tileWidth).ceil() + 1);
      return ColoredBox(color: const Color(0xFF303644), child: Stack(children: [
        for (var i = first; i < end; i++)
          Positioned(key: ValueKey('$path:$sourceInMs:$i'), left: i * tileWidth,
            width: tileWidth, top: 0, bottom: 0,
            child: MediaThumbnail(path: path, enabled: enabled,
              positionMs: sourceInMs + math.min(durationMs - 1,
                  (i * tileWidth / pixelsPerSecond * 1000).round())),
          ),
      ]));
    });
  });
}
