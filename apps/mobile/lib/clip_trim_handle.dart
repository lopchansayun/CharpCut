import 'package:flutter/material.dart';
import 'engine/editor_state.dart';

class ClipTrimHandle extends StatefulWidget {
  const ClipTrimHandle({
    super.key,
    required this.clip,
    required this.start,
    required this.pixelsPerSecond,
    required this.onBegin,
    required this.onPreview,
    required this.onCommit,
    required this.onCancel,
  });
  final EditorClip clip;
  final bool start;
  final double pixelsPerSecond;
  final VoidCallback onBegin;
  final VoidCallback onCancel;
  final void Function(int sourceIn, int duration) onPreview;
  final Future<void> Function(int sourceIn, int duration) onCommit;
  @override
  State<ClipTrimHandle> createState() => _ClipTrimHandleState();
}

class _ClipTrimHandleState extends State<ClipTrimHandle> {
  double _delta = 0;
  EditorClip? _original;
  bool _saving = false;
  (int, int) _range() {
    final c = _original!;
    final delta = (_delta / widget.pixelsPerSecond * 1000).round();
    if (widget.start) {
      final start = (c.sourceInMs + delta).clamp(
        0,
        c.sourceInMs + c.durationMs - 100,
      );
      return (start, c.sourceInMs + c.durationMs - start);
    }
    return (
      c.sourceInMs,
      (c.durationMs + delta).clamp(100, c.sourceDurationMs - c.sourceInMs),
    );
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.start ? 'Trim start' : 'Trim end',
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: _saving
          ? null
          : (_) {
              _original = widget.clip;
              _delta = 0;
              widget.onBegin();
            },
      onHorizontalDragUpdate: _saving
          ? null
          : (d) {
              if (_original == null) return;
              _delta += d.delta.dx;
              final range = _range();
              widget.onPreview(range.$1, range.$2);
            },
      onHorizontalDragEnd: _saving
          ? null
          : (_) async {
              if (_original == null) return;
              final range = _range();
              setState(() => _saving = true);
              try {
                await widget.onCommit(range.$1, range.$2);
              } finally {
                if (mounted)
                  setState(() {
                    _saving = false;
                    _original = null;
                  });
              }
            },
      onHorizontalDragCancel: () {
        final c = _original;
        _original = null;
        if (c != null) widget.onCancel();
      },
      child: Center(
        child: Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            color: Colors.grey,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    ),
  );
}
