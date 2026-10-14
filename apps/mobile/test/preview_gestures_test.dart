import 'package:charpcut/clip_trim_handle.dart';
import 'package:charpcut/preview_layer_controls.dart';
import 'package:charpcut/time_input_dialog.dart';
import 'package:charpcut/engine/editor_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const clip = EditorClip(
  id: 'image',
  assetId: 'asset',
  name: 'Layer',
  color: Colors.blue,
  startMs: 0,
  sourceInMs: 1000,
  durationMs: 3000,
  sourceDurationMs: 6000,
  trackId: 'track',
  kind: 'image',
  trackKind: 'image',
);

void main() {
  test('playback snapshots reuse project data and clamp the playhead', () {
    final state = EditorState(
      clips: [clip],
      totalDurationMs: 3000,
      selectedClipId: clip.id,
      canUndo: true,
    );
    final next = state.atPlayhead(9999);
    expect(next.playheadMs, 3000);
    expect(identical(state.clips, next.clips), isTrue);
    expect(next.selectedClipId, clip.id);
    expect(next.canUndo, isTrue);
  });

  for (final start in [true, false]) {
    testWidgets(
      'trim ${start ? 'start' : 'end'} clamps and commits only on release',
      (tester) async {
        final commits = <(int, int)>[];
        (int, int)? preview;
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: SizedBox(
                width: 40,
                height: 40,
                child: ClipTrimHandle(
                  clip: clip,
                  start: start,
                  pixelsPerSecond: 100,
                  onBegin: () {},
                  onCancel: () {},
                  onPreview: (a, b) => preview = (a, b),
                  onCommit: (a, b) async => commits.add((a, b)),
                ),
              ),
            ),
          ),
        );
        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(ClipTrimHandle)),
        );
        await gesture.moveBy(const Offset(25, 0));
        await gesture.moveBy(const Offset(700, 0));
        await tester.pump();
        expect(commits, isEmpty);
        expect(preview, start ? (3900, 100) : (1000, 5000));
        await gesture.up();
        await tester.pumpAndSettle();
        expect(commits, [preview]);
      },
    );
  }

  testWidgets(
    'layer gestures commit once and locked layers cannot transform or delete',
    (tester) async {
      final commits = <ClipProperties>[];
      String? deleted;
      Widget controls(Set<String> locked) => MaterialApp(
        home: Center(
          child: SizedBox(
            width: 300,
            height: 300,
            child: PreviewLayerControls(
              clips: const [clip],
              selectedId: clip.id,
              locked: locked,
              onSelect: (_) {},
              onDraft: (_, __) {},
              onCommit: (_, p) async => commits.add(p),
              onDelete: (c) => deleted = c.id,
            ),
          ),
        ),
      );
      await tester.pumpWidget(controls({}));
      final g = await tester.startGesture(
        tester.getCenter(find.byType(PreviewLayerControls)),
      );
      await g.moveBy(const Offset(25, 0));
      await g.moveBy(const Offset(50, 30));
      await tester.pump();
      expect(commits, isEmpty);
      await g.up();
      await tester.pumpAndSettle();
      expect(commits, hasLength(1));
      expect(commits.single.x, greaterThan(0));
      expect(commits.single.y, greaterThan(0));
      await tester.tap(find.byTooltip('Delete layer'));
      expect(deleted, clip.id);
      await tester.pumpWidget(controls({'track'}));
      expect(find.byTooltip('Delete layer'), findsNothing);
      expect(
        find.byKey(const ValueKey('layer-transform-handle')),
        findsNothing,
      );
      await tester.drag(
        find.byType(PreviewLayerControls),
        const Offset(70, 30),
      );
      await tester.pumpAndSettle();
      expect(commits, hasLength(1));
    },
  );

  testWidgets('corner gesture scales and rotates the selected layer', (
    tester,
  ) async {
    ClipProperties? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 300,
            height: 300,
            child: PreviewLayerControls(
              clips: const [clip],
              selectedId: clip.id,
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
    final handle = find.byKey(const ValueKey('layer-transform-handle'));
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await gesture.moveBy(const Offset(-25, 0));
    await gesture.moveBy(const Offset(-65, -10));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(saved, isNotNull);
    expect(saved!.scale, lessThan(1));
    expect(saved!.rotation.abs(), greaterThan(1));
  });

  testWidgets('dialog title stays anchored when keyboard appears', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            resizeToAvoidBottomInset: false,
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => TimeInputDialog(
                  title: 'Trim',
                  labels: const ['Start'],
                  values: const [0],
                  validate: (_) => null,
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final before = tester.getTopLeft(find.text('Trim'));
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Trim')), before);
    await tester.enterText(find.byType(TextField), '1');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
