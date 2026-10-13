import 'dart:convert';

import 'package:charpcut/engine/project_session.dart';
import 'package:charpcut/engine/video_importer.dart';
import 'package:charpcut/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_engine.dart';
import 'support/video_channel.dart';

class Store implements ProjectStore {
  final data = <ProjectSlot, String>{};
  int writes = 0;
  @override
  Future<String?> read(ProjectSlot slot) async => data[slot];
  @override
  Future<void> write(ProjectSlot slot, String json) async {
    data[slot] = json;
    writes++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(mockVideoPicker);

  test(
    'mute and move autosave with undo/redo; seek has no history or IO',
    () async {
      final store = Store();
      final session = ProjectSession(FakeEngine(), store);
      await session.addClip(path: 'a.mp4', durationMs: 4000);
      await session.addClip(path: 'b.mp4', durationMs: 3000);
      await session.setMuted(true);
      await session.moveSelected(0);
      final writes = store.writes;
      final seek = await session.seek(99999);
      expect(seek.playheadMs, 7000);
      expect(store.writes, writes);
      await session.undo();
      expect((await session.getState()).clips.first.name, 'A');
      await session.redo();
      await session.save();
      final restored = ProjectSession(FakeEngine(), store);
      final state = await restored.openProjectJson(
        store.data[ProjectSlot.saved]!,
      );
      expect(state.mainTrackMuted, true);
      expect(state.clips.map((c) => c.name), ['B', 'A']);
      expect(state.playheadMs, 0);
    },
  );

  test('version 1 fake fixture opens with historical mute default', () async {
    final fake = FakeEngine();
    await fake.addClip(path: 'a.mp4', durationMs: 4000);
    final project = jsonDecode(await fake.exportProjectJson());
    project['version'] = 1;
    project['tracks'][0].remove('muted');
    expect(
      (await fake.openProjectJson(jsonEncode(project))).mainTrackMuted,
      false,
    );
  });

  testWidgets('Mute updates engine state and Undo restores it', (tester) async {
    final fake = FakeEngine();
    await tester.pumpWidget(
      EngineScope(previewEnabled: false,
        engine: fake,
        child: const MaterialApp(home: EditorHome()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mute'));
    await tester.pumpAndSettle();
    expect((await fake.getState()).mainTrackMuted, true);
    expect(find.text('Unmute'), findsOneWidget);
    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect((await fake.getState()).mainTrackMuted, false);
  });

  testWidgets('Move reorders the selected clip and Undo restores order', (
    tester,
  ) async {
    var picks = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          VideoImporter.channel,
          (_) async => {
            'path': '${picks++ == 0 ? 'a' : 'b'}.mp4',
            'duration_ms': 3000,
          },
        );
    final fake = FakeEngine();
    await tester.pumpWidget(
      EngineScope(previewEnabled: false,
        engine: fake,
        child: const MaterialApp(home: EditorHome()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add clip'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add clip'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Position 1: A'));
    await tester.pumpAndSettle();
    expect((await fake.getState()).clips.map((c) => c.name), ['B', 'A']);
    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect((await fake.getState()).clips.map((c) => c.name), ['A', 'B']);
  });

  testWidgets('picker cancellation and import errors leave project empty', (
    tester,
  ) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      VideoImporter.channel,
      (_) async => null,
    );
    final fake = FakeEngine();
    await tester.pumpWidget(
      EngineScope(previewEnabled: false,
        engine: fake,
        child: const MaterialApp(home: EditorHome()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add clip'));
    await tester.pumpAndSettle();
    expect((await fake.getState()).clips, isEmpty);
    messenger.setMockMethodCallHandler(
      VideoImporter.channel,
      (_) async => throw PlatformException(
        code: 'video_import',
        message: 'Storage full',
      ),
    );
    await tester.tap(find.byTooltip('Add clip'));
    await tester.pumpAndSettle();
    expect((await fake.getState()).clips, isEmpty);
    expect(find.textContaining('Could not import video'), findsOneWidget);
  });

  testWidgets(
    'timeline scroll seeks Rust state and split uses the confirmed playhead',
    (tester) async {
      final fake = FakeEngine();
      await tester.pumpWidget(
        EngineScope(previewEnabled: false,
          engine: fake,
          child: const MaterialApp(home: EditorHome()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add clip'));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(-75, 0),
      );
      await tester.pumpAndSettle();
      final position = (await fake.getState()).playheadMs;
      expect(position, greaterThan(100));
      expect(position, lessThan(2900));
      await tester.tap(find.text('Split'));
      await tester.pumpAndSettle();
      final state = await fake.getState();
      expect(state.clips, hasLength(2));
      expect(state.clips.first.durationMs, position);
    },
  );

  test('picker validates real metadata and refuses invalid results', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      VideoImporter.channel,
      (_) async => {'path': '/media/real.mp4', 'duration_ms': 9123},
    );
    final picked = await VideoImporter().pickVideo();
    expect(picked!.durationMs, 9123);
    expect(picked.path, '/media/real.mp4');
    messenger.setMockMethodCallHandler(
      VideoImporter.channel,
      (_) async => {'path': '', 'duration_ms': 10},
    );
    await expectLater(VideoImporter().pickVideo(), throwsFormatException);
  });
}
