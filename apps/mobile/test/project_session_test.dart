import 'dart:async';
import 'dart:convert';

import 'package:charpcut/engine/project_session.dart';
import 'package:charpcut/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_engine.dart';
import 'support/video_channel.dart';

class MemoryStore implements ProjectStore {
  final data = <ProjectSlot, String>{};
  int writes = 0;
  bool fail = false;
  Completer<void>? gate;

  @override
  Future<String?> read(ProjectSlot slot) async => data[slot];
  @override
  Future<void> write(ProjectSlot slot, String json) async {
    writes++;
    await gate?.future;
    if (fail) throw const FileSystemExceptionForTest();
    data[slot] = json;
  }
}

class FileSystemExceptionForTest implements Exception {
  const FileSystemExceptionForTest();
  @override
  String toString() => 'Storage full';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(mockVideoPicker);

  testWidgets(
    'opening a saved project can be cancelled without losing the draft',
    (tester) async {
      final store = MemoryStore();
      final session = ProjectSession(FakeEngine(), store);
      await session.addClip(path: 'a.mp4', durationMs: 4000);
      await session.save();
      await session.addClip(path: 'b.mp4', durationMs: 3000);
      final draft = store.data[ProjectSlot.draft];
      await tester.pumpWidget(
        EngineScope(previewEnabled: false,
          engine: session,
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      await tester.tap(find.text('Projects').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open saved project'));
      await tester.pumpAndSettle();
      expect(find.text('Replace recovery draft?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(store.data[ProjectSlot.draft], draft);
      expect((await session.getState()).totalDurationMs, 7000);
    },
  );

  testWidgets('editor still shows a successful edit when autosave fails', (
    tester,
  ) async {
    final store = MemoryStore();
    final session = ProjectSession(FakeEngine(), store);
    await tester.pumpWidget(
      EngineScope(previewEnabled: false,
        engine: session,
        child: const MaterialApp(home: EditorHome()),
      ),
    );
    await tester.pumpAndSettle();
    store.fail = true;
    await tester.tap(find.byTooltip('Add clip'));
    await tester.pumpAndSettle();
    expect(find.text('Split'), findsOneWidget);
    expect(find.textContaining('Autosave failed.'), findsOneWidget);
    await tester.tap(find.text('Split'));
    await tester.pumpAndSettle();
    expect(
      find.text('Move the playhead inside the clip to split it'),
      findsOneWidget,
    );
  });

  test(
    'save survives a new session; draft tracks edits, undo and redo',
    () async {
      final store = MemoryStore();
      final session = ProjectSession(FakeEngine(), store);
      await session.newProject();
      await session.addClip(path: 'a.mp4', durationMs: 4000);
      await session.splitSelectedAt(1500);
      await session.save();
      final saved = store.data[ProjectSlot.saved]!;
    expect(jsonDecode(saved)['version'], 2);
      await session.deleteSelected();
      expect(store.data[ProjectSlot.saved], saved);
      expect(store.data[ProjectSlot.draft], isNot(saved));
      await session.undo();
      expect(store.data[ProjectSlot.draft], saved);
      await session.redo();
      final reopened = ProjectSession(FakeEngine(), store);
      final state = await reopened.openProjectJson(
        (await reopened.readSlot(ProjectSlot.draft))!,
      );
      expect(state.clips.single.durationMs, 1500);
      expect(state.canUndo, false);
      final explicit = await reopened.openProjectJson(saved);
      expect(explicit.clips.map((c) => c.durationMs), [1500, 2500]);
    },
  );

  test(
    'refused edits and corrupt or newer projects do not overwrite recovery',
    () async {
      final store = MemoryStore();
      final session = ProjectSession(FakeEngine(), store);
      await session.addClip(path: 'a.mp4', durationMs: 4000);
      final draft = store.data[ProjectSlot.draft];
      final writes = store.writes;
      await session.splitSelectedAt(0);
      await session.openProjectJson('not JSON');
      await session.openProjectJson('{"version":999}');
      expect(store.writes, writes);
      expect(store.data[ProjectSlot.draft], draft);
      expect((await session.getState()).clips.single.durationMs, 4000);
    },
  );

  test(
    'selection does not save; concurrent edits cannot race a slow write',
    () async {
      final store = MemoryStore()..gate = Completer<void>();
      final session = ProjectSession(FakeEngine(), store);
      final first = session.addClip(path: 'a.mp4', durationMs: 4000);
      final second = session.addClip(path: 'b.mp4', durationMs: 3000);
      await Future<void>.delayed(Duration.zero);
      expect(store.writes, 1);
      store.gate!.complete();
      await Future.wait([first, second]);
      final recovered = ProjectSession(FakeEngine(), store);
      final state = await recovered.openProjectJson(
        store.data[ProjectSlot.draft]!,
      );
      expect(state.totalDurationMs, 7000);
      final writes = store.writes;
      await session.select(null);
      expect(store.writes, writes);
    },
  );

  test(
    'autosave failure preserves edit and previous draft; Save retries',
    () async {
      final store = MemoryStore();
      final session = ProjectSession(FakeEngine(), store);
      await session.newProject();
      final previous = store.data[ProjectSlot.draft];
      store.fail = true;
      final state = await session.addClip(path: 'a.mp4', durationMs: 4000);
      expect(state.clips, hasLength(1));
      expect(session.storageError, contains('Autosave failed'));
      expect(store.data[ProjectSlot.draft], previous);
      await expectLater(session.save(), throwsA(isA<Exception>()));
      store.fail = false;
      await session.save();
      expect(session.storageError, null);
      expect(store.data[ProjectSlot.draft], await session.exportProjectJson());
    },
  );

  test(
    'Android channel passes versioned JSON unchanged and surfaces IO errors',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(AndroidProjectStore.channel, (
        call,
      ) async {
        calls.add(call);
        if (call.method == 'read') return '{"version":1}';
        throw PlatformException(code: 'project_io', message: 'Storage full');
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          AndroidProjectStore.channel,
          null,
        ),
      );
      final store = AndroidProjectStore();
      expect(await store.read(ProjectSlot.saved), '{"version":1}');
      await expectLater(
        store.write(ProjectSlot.draft, '{"version":1}'),
        throwsA(isA<PlatformException>()),
      );
      expect(calls.last.arguments, {'slot': 'draft', 'json': '{"version":1}'});
    },
  );

  testWidgets(
    'home resumes recovery in a fresh engine and editor saves to disk',
    (tester) async {
      final store = MemoryStore();
      final old = ProjectSession(FakeEngine(), store);
      await old.addClip(path: 'a.mp4', durationMs: 4000);
      final fresh = ProjectSession(FakeEngine(), store);
      await tester.pumpWidget(
        EngineScope(previewEnabled: false,
          engine: fresh,
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      await tester.tap(find.text('New video'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Resume draft').last);
      await tester.pumpAndSettle();
      expect((await fresh.getState()).totalDurationMs, 4000);
      await tester.tap(find.byTooltip('Project'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save project'));
      await tester.pumpAndSettle();
      expect(store.data[ProjectSlot.saved], store.data[ProjectSlot.draft]);
      expect(find.text('Project saved on this device'), findsOneWidget);
    },
  );
}
