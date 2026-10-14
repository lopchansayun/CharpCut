import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'engine/editor_state.dart';

/// Gesture edits remain local until pointer-up, then become one engine command.
class PreviewLayerControls extends StatefulWidget {
  const PreviewLayerControls({
    super.key,
    required this.clips,
    required this.selectedId,
    required this.locked,
    required this.onSelect,
    required this.onDraft,
    required this.onCommit,
    required this.onDelete,
  });
  final List<EditorClip> clips;
  final String? selectedId;
  final Set<String> locked;
  final ValueChanged<String?> onSelect;
  final void Function(String id, ClipProperties? properties) onDraft;
  final Future<void> Function(EditorClip clip, ClipProperties properties)
  onCommit;
  final ValueChanged<EditorClip> onDelete;
  @override
  State<PreviewLayerControls> createState() => _PreviewLayerControlsState();
}

class _PreviewLayerControlsState extends State<PreviewLayerControls> {
  EditorClip? _gestureClip;
  ClipProperties? _draft;
  Offset _start = Offset.zero;
  bool _saving = false;
  EditorClip? get selected =>
      widget.clips.where((c) => c.id == widget.selectedId).firstOrNull;
  ClipProperties get effective => _draft ?? selected!.properties;
  bool get editable =>
      selected != null &&
      !widget.locked.contains(selected!.trackId) &&
      !_saving;

  void _startGesture(Offset point) {
    if (!editable) return;
    _gestureClip = selected;
    _start = point;
    _draft = selected!.properties;
  }

  void _change({double? x, double? y, double? scale, double? rotation}) {
    final clip = _gestureClip;
    if (clip == null) return;
    final values = {
      ...clip.properties.toJson(),
      if (x != null) 'x': x.clamp(-2.0, 2.0),
      if (y != null) 'y': y.clamp(-2.0, 2.0),
      if (scale != null) 'scale': scale.clamp(.1, 10.0),
      if (rotation != null) 'rotation': ((rotation + 180) % 360) - 180,
    };
    final p = ClipProperties.fromMap(values);
    setState(() => _draft = p);
    widget.onDraft(clip.id, p);
  }

  Future<void> _finish() async {
    final clip = _gestureClip;
    final p = _draft;
    _gestureClip = null;
    if (clip == null || p == null) return;
    setState(() => _saving = true);
    try {
      if (!mapEquals(p.toJson(), clip.properties.toJson()))
        await widget.onCommit(clip, p);
    } finally {
      if (mounted) {
        widget.onDraft(clip.id, null);
        setState(() {
          _draft = null;
          _saving = false;
        });
      }
    }
  }

  void _pick(Offset point, Size size) {
    if (_saving) return;
    for (final clip in widget.clips.reversed) {
      final p = clip.properties;
      if (p.opacity == 0) continue;
      final centered =
          point - Offset(size.width * (.5 + p.x), size.height * (.5 + p.y));
      final angle = -p.rotation * math.pi / 180;
      final local =
          Offset(
                centered.dx * math.cos(angle) - centered.dy * math.sin(angle),
                centered.dx * math.sin(angle) + centered.dy * math.cos(angle),
              ) /
              p.scale +
          size.center(Offset.zero);
      final crop = Rect.fromLTRB(
        size.width * p.cropLeft,
        size.height * p.cropTop,
        size.width * (1 - p.cropRight),
        size.height * (1 - p.cropBottom),
      );
      if (crop.contains(local)) {
        widget.onSelect(clip.id);
        return;
      }
    }
    widget.onSelect(null);
  }

  Offset _local(Offset global) =>
      (context.findRenderObject() as RenderBox).globalToLocal(global);

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final size = bounds.biggest;
      final clip = selected;
      final p = clip == null ? null : effective;
      final center = p == null
          ? Offset.zero
          : Offset(size.width * (.5 + p.x), size.height * (.5 + p.y));
      Offset corner(double x, double y) {
        final offset =
            Offset((x - .5) * size.width, (y - .5) * size.height) * p!.scale;
        final angle = p.rotation * math.pi / 180;
        return center +
            Offset(
              offset.dx * math.cos(angle) - offset.dy * math.sin(angle),
              offset.dx * math.sin(angle) + offset.dy * math.cos(angle),
            );
      }

      Widget handle(Offset point, Widget child) => Positioned(
        left: point.dx.clamp(22.0, math.max(22.0, size.width - 22)) - 22,
        top: point.dy.clamp(22.0, math.max(22.0, size.height - 22)) - 22,
        width: 44,
        height: 44,
        child: child,
      );
      return Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) => _pick(d.localPosition, size),
            onScaleStart: editable
                ? (d) => _startGesture(d.localFocalPoint)
                : null,
            onScaleUpdate: editable
                ? (d) {
                    final seed = _gestureClip?.properties;
                    if (seed == null || size.isEmpty) return;
                    final delta = d.localFocalPoint - _start;
                    _change(
                      x: seed.x + delta.dx / size.width,
                      y: seed.y + delta.dy / size.height,
                      scale: seed.scale * d.scale,
                      rotation: seed.rotation + d.rotation * 180 / math.pi,
                    );
                  }
                : null,
            onScaleEnd: editable ? (_) => _finish() : null,
          ),
          if (p != null)
            IgnorePointer(
              child: CustomPaint(
                painter: _SelectionPainter([
                  corner(p.cropLeft, p.cropTop),
                  corner(1 - p.cropRight, p.cropTop),
                  corner(1 - p.cropRight, 1 - p.cropBottom),
                  corner(p.cropLeft, 1 - p.cropBottom),
                ]),
              ),
            ),
          if (p != null && editable && clip!.trackKind != 'video') ...[
            handle(
              corner(1 - p.cropRight, p.cropTop),
              IconButton.filled(
                tooltip: 'Delete layer',
                onPressed: () => widget.onDelete(clip),
                icon: const Icon(Icons.close, size: 18),
              ),
            ),
            handle(
              corner(1 - p.cropRight, 1 - p.cropBottom),
              GestureDetector(
                key: const ValueKey('layer-transform-handle'),
                behavior: HitTestBehavior.opaque,
                onPanStart: (d) => _startGesture(_local(d.globalPosition)),
                onPanUpdate: (d) {
                  final seed = _gestureClip?.properties;
                  if (seed == null) return;
                  final origin = Offset(
                    size.width * (.5 + seed.x),
                    size.height * (.5 + seed.y),
                  );
                  final first = _start - origin;
                  final now = _local(d.globalPosition) - origin;
                  if (first.distance < 1) return;
                  _change(
                    scale: seed.scale * now.distance / first.distance,
                    rotation:
                        seed.rotation +
                        (now.direction - first.direction) * 180 / math.pi,
                  );
                },
                onPanEnd: (_) => _finish(),
                onPanCancel: () {
                  final id = _gestureClip?.id;
                  _gestureClip = null;
                  if (id != null) widget.onDraft(id, null);
                  setState(() => _draft = null);
                },
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.cyan,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.open_with, color: Colors.black, size: 20),
                ),
              ),
            ),
          ],
        ],
      );
    },
  );
}

class _SelectionPainter extends CustomPainter {
  _SelectionPainter(this.points);
  final List<Offset> points;
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..addPolygon(points, true);
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.cyan
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_SelectionPainter old) => !listEquals(points, old.points);
}
