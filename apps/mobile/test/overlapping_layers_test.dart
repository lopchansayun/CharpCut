import 'package:charpcut/engine/editor_state.dart';
import 'package:charpcut/timeline_layers.dart';
import 'package:charpcut/preview_layer_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

EditorClip c(String id, int start, int duration, {String kind = 'image'}) =>
    EditorClip(
      id: id,
      assetId: id,
      name: id,
      color: Colors.blue,
      startMs: start,
      sourceInMs: 0,
      durationMs: duration,
      sourceDurationMs: 10000,
      trackKind: kind,
      kind: kind,
    );

void main() {
  test(
    'overlap rows handle nesting, touching boundaries, and unsorted input',
    () {
      expect(
        clipRows([
          c('a', 0, 5000),
          c('c', 2000, 1000),
          c('b', 1000, 1000),
          c('d', 5000, 1000),
        ]),
        {'a': 0, 'b': 1, 'c': 1, 'd': 0},
      );
    },
  );
  test(
    'all overlapping visuals compose in track order and expire independently',
    () {
      final state = EditorState(
        tracks: const [
          EditorTrack('v', 'video', false),
          EditorTrack('i', 'image', false),
        ],
        clips: [c('v', 0, 5000, kind: 'video')],
        imageClips: [c('a', 0, 4000), c('b', 1000, 2000)],
        playheadMs: 2000,
        totalDurationMs: 5000,
      );
      expect(activeVisualClips(state).map((c) => c.id), ['v', 'a', 'b']);
      expect(activeVisualClips(state.atPlayhead(3000)).map((c) => c.id), [
        'v',
        'a',
      ]);
      expect(previewLayers(const EditorState(), []), [null]);
    },
  );
  testWidgets('main video keeps direct manipulation without floating buttons', (
    tester,
  ) async {
    final video = c('video', 0, 3000, kind: 'video');
    ClipProperties? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 300,
            height: 300,
            child: PreviewLayerControls(
              clips: [video],
              selectedId: video.id,
              locked: const {},
              onSelect: (_) {},
              onDraft: (_, __) {},
              onDelete: (_) {},
              onCommit: (_, p) async => saved = p,
            ),
          ),
        ),
      ),
    );
    expect(find.byTooltip('Delete layer'), findsNothing);
    expect(find.byKey(const ValueKey('layer-transform-handle')), findsNothing);
    await tester.drag(find.byType(PreviewLayerControls), const Offset(80, 30));
    await tester.pumpAndSettle();
    expect(saved, isNotNull);
    expect(saved!.x, greaterThan(0));
  });
}
