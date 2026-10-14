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

  testWidgets('project picker cancellation preserves the active draft', (tester) async {
    final store = MemoryStore();
    final session = ProjectSession(FakeEngine(), store);
    await session.addClip(path: 'a.mp4', durationMs: 4000);
    final id = (await session.listDrafts()).single.id;
    await session.addClip(path: 'b.mp4', durationMs: 3000);
    final original = (await session.listDrafts()).single;
    await phoneSurface(tester);
    await tester.pumpWidget(EngineScope(previewEnabled: false, engine: session,
      child: MaterialApp(home: EditorHome(draftId: id))));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Project'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open project'));
    await tester.pumpAndSettle();
    expect(find.text('Open project'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('Open project'), findsNothing);
    expect((await session.listDrafts()).single.id, original.id);
    expect((await session.listDrafts()).single.json, original.json);
    expect((await session.getState()).totalDurationMs, 7000);
  });

  testWidgets('editor still shows a successful edit when autosave fails', (
    tester,
  ) async {
    final store = MemoryStore();
    final session = ProjectSession(FakeEngine(), store);
    await phoneSurface(tester);
    await tester.pumpWidget(
      EngineScope(previewEnabled: false,
        engine: session,
        child: const MaterialApp(home: EditorHome()),
      ),
    );
    await tester.pumpAndSettle();
    store.fail = true;
    await addVideo(tester);
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
      final draft = (await session.listDrafts()).single;
      final saved = draft.json;
      expect(jsonDecode(saved)['version'], 5);
      await session.deleteSelected();
      expect((await session.listDrafts()).single.id, draft.id);
      expect((await session.listDrafts()).single.json, isNot(saved));
      await session.undo();
      expect((await session.listDrafts()).single.json, saved);
      await session.redo();
      final reopened = ProjectSession(FakeEngine(), store);
      final state = await reopened.openDraft(draft.id);
      expect(state.clips.single.durationMs, 1500);
      expect(state.canUndo, false);
      final explicit = await reopened.openProjectJson(saved);
      expect(explicit.clips.map((c) => c.durationMs), [1500, 2500]);
      expect(await reopened.listDrafts(), hasLength(2));
    },
  );

  test(
    'refused edits and corrupt or newer projects do not overwrite recovery',
    () async {
      final store = MemoryStore();
      final session = ProjectSession(FakeEngine(), store);
      await session.addClip(path: 'a.mp4', durationMs: 4000);
      final draft = store.data[ProjectSlot.library];
      final writes = store.writes;
      await session.splitSelectedAt(0);
      await session.openProjectJson('not JSON');
      await session.openProjectJson('{"version":999}');
      expect(store.writes, writes);
      expect(store.data[ProjectSlot.library], draft);
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
      final state = await recovered.openDraft((await recovered.listDrafts()).single.id);
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
      final previous = store.data[ProjectSlot.library];
      store.fail = true;
      final state = await session.addClip(path: 'a.mp4', durationMs: 4000);
      expect(state.clips, hasLength(1));
      expect(session.storageError, contains('Autosave failed'));
      expect(store.data[ProjectSlot.library], previous);
      await expectLater(session.save(), throwsA(isA<Exception>()));
      store.fail = false;
      await session.save();
      expect(session.storageError, null);
      expect((await session.listDrafts()).single.json, await session.exportProjectJson());
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
      await phoneSurface(tester);
    await tester.pumpWidget(
        EngineScope(previewEnabled: false,
          engine: fresh,
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('A').first);
      await tester.pumpAndSettle();
      expect((await fresh.getState()).totalDurationMs, 4000);
      await tester.tap(find.byTooltip('Project'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save project'));
      await tester.pumpAndSettle();
      expect((await fresh.listDrafts()).single.json, await fresh.exportProjectJson());
      expect(find.text('Project saved on this device'), findsOneWidget);
    },
  );
}
