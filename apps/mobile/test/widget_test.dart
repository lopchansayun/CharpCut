import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:charpcut/main.dart';

import 'support/fake_engine.dart';
import 'support/video_channel.dart';

/// Wraps a screen with a fresh in-memory engine.
Widget app(Widget home) => EngineScope(previewEnabled: false, engine: FakeEngine(), child: MaterialApp(home: home));

void main() {
  setUp(mockVideoPicker);
  testWidgets('launch screen shows centered CharpCut branding', (WidgetTester tester) async {
    await tester.pumpWidget(CharpCutApp(engine: FakeEngine()));

    expect(find.text('CharpCut'), findsOneWidget);

    // Advance past the 1.1-second startup timer and let the route settle.
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pumpAndSettle();

    expect(find.text('New video'), findsOneWidget);
  });

  testWidgets('home page offers new video, tools and bottom navigation', (WidgetTester tester) async {
    await tester.pumpWidget(app(const HomeScreen()));

    expect(find.text('New video'), findsOneWidget);
    expect(find.text('Edit photo'), findsOneWidget);
    expect(find.text('Trim video'), findsOneWidget);
    for (final label in ['Edit', 'Templates', 'Projects', 'Me']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('editor shows the main toolbar, timeline rows and undo redo', (WidgetTester tester) async {
    await tester.pumpWidget(app(const EditorHome()));
    await tester.pump();

    for (final label in ['Edit', 'Audio', 'Text', 'Effects', 'Overlay', 'Captions']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Add audio'), findsOneWidget);
    expect(find.text('Add text'), findsOneWidget);
    expect(find.text('Export'), findsOneWidget);
    expect(find.byTooltip('Undo'), findsOneWidget);
    expect(find.byTooltip('Redo'), findsOneWidget);
  });

  testWidgets('editor starts empty and Edit asks for a clip first', (WidgetTester tester) async {
    await tester.pumpWidget(app(const EditorHome()));
    await tester.pump();

    expect(find.text('Tap + to add a clip'), findsOneWidget);

    await tester.tap(find.text('Edit'));
    await tester.pump();
    expect(find.text('Add a clip first'), findsOneWidget);
    expect(find.text('Split'), findsNothing);
  });

  testWidgets('adding a clip selects it and swaps in the clip toolbar; back returns', (WidgetTester tester) async {
    await tester.pumpWidget(app(const EditorHome()));
    await tester.pump();

    await tester.tap(find.byTooltip('Add clip'));
    await tester.pumpAndSettle();

    expect(find.text('Split'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Animations'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chevron_left_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Split'), findsNothing);
    expect(find.text('Overlay'), findsOneWidget);
  });

  testWidgets('deleting a clip supports undo', (WidgetTester tester) async {
    await tester.pumpWidget(app(const EditorHome()));
    await tester.pump();

    await tester.tap(find.byTooltip('Add clip'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    // Deleting clears the selection, so the main toolbar is back and the timeline is empty.
    expect(find.text('Overlay'), findsOneWidget);
    expect(find.text('Tap + to add a clip'), findsOneWidget);

    // Undo brings the clip back along with its selection.
    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('Split'), findsOneWidget);
  });

  testWidgets('quality pill opens export settings with sliders', (WidgetTester tester) async {
    await tester.pumpWidget(app(const EditorHome()));
    await tester.pump();

    await tester.tap(find.text('720p'));
    await tester.pumpAndSettle();

    expect(find.text('Resolution'), findsOneWidget);
    expect(find.text('Frame rate'), findsOneWidget);
    expect(find.text('Optical flow'), findsOneWidget);
    expect(find.text('Bitrate (Mbps)'), findsOneWidget);
    expect(find.textContaining('Estimated file size'), findsOneWidget);
  });

  testWidgets('split at the playhead is refused outside the clip and the engine message is shown', (WidgetTester tester) async {
    await tester.pumpWidget(app(const EditorHome()));
    await tester.pump();

    await tester.tap(find.byTooltip('Add clip'));
    await tester.pumpAndSettle();
    // The playhead is at 0, the very start of the clip.
    await tester.tap(find.text('Split'));
    await tester.pumpAndSettle();

    expect(find.text('Move the playhead inside the clip to split it'), findsOneWidget);
    expect(find.text('3.0s'), findsOneWidget); // clip unchanged
  });

  testWidgets('trim shortens the clip through the engine', (WidgetTester tester) async {
    await tester.pumpWidget(app(const EditorHome()));
    await tester.pump();

    await tester.tap(find.byTooltip('Add clip'));
    await tester.pumpAndSettle();
    expect(find.text('3.0s'), findsOneWidget);

    await tester.tap(find.text('Trim'));
    await tester.pumpAndSettle();
    expect(find.text('2.5s'), findsOneWidget);
  });

  testWidgets('undo and redo go through the engine', (WidgetTester tester) async {
    await tester.pumpWidget(app(const EditorHome()));
    await tester.pump();

    await tester.tap(find.byTooltip('Add clip'));
    await tester.pumpAndSettle();
    expect(find.text('Tap + to add a clip'), findsNothing);

    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('Tap + to add a clip'), findsOneWidget);

    await tester.tap(find.byTooltip('Redo'));
    await tester.pumpAndSettle();
    expect(find.text('Tap + to add a clip'), findsNothing);
  });

  testWidgets('exporting an empty project is refused', (WidgetTester tester) async {
    await tester.pumpWidget(app(const EditorHome()));
    await tester.pump();

    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();
    expect(find.text('Add a clip before exporting'), findsOneWidget);
  });
}
