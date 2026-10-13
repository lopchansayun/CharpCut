import 'dart:convert';

import 'package:charpcut/engine/project_session.dart';
import 'package:charpcut/engine/rust_engine.dart';
import 'package:charpcut/src/rust/frb_generated.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => RustLib.init());

  testWidgets(
    'packaged Android bridge supports mute, move, seek, undo, redo and migration',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('Checking Phase 1'))),
      );
      const engine = RustEditorEngine();
      await engine.newProject();
      await engine.addClip(path: 'test://a.mp4', durationMs: 4000);
      await engine.addClip(path: 'test://b.mp4', durationMs: 3000);
      await engine.setMuted(true);
      await engine.moveSelected(0);
      var state = await engine.seek(99999);
      expect(state.playheadMs, 7000);
      expect(state.mainTrackMuted, true);
      expect(state.clips.map((c) => c.name), ['B', 'A']);
      await engine.undo();
      expect((await engine.getState()).clips.first.name, 'A');
      await engine.redo();
      final saved = await engine.exportProjectJson();
      state = await engine.openProjectJson(saved);
      expect(state.mainTrackMuted, true);
      expect(state.clips.first.name, 'B');
      expect(state.playheadMs, 0);
      final legacy = jsonDecode(saved);
      legacy['version'] = 1;
      for (final track in legacy['tracks']) {
        track.remove('muted');
      }
      state = await engine.openProjectJson(jsonEncode(legacy));
      expect(state.lastError, null);
      expect(state.mainTrackMuted, false);
      expect(jsonDecode(await engine.exportProjectJson())['version'], 2);
    },
  );

  testWidgets(
    'Android atomic storage saves and reopens edited data, then restores the user draft',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Text('Checking project storage')),
        ),
      );
      final store = AndroidProjectStore();
      final original = await store.read(ProjectSlot.draft);
      if (original == null) {
        markTestSkipped(
          'Create a draft first; this test restores the existing file after verification',
        );
        return;
      }
      const engine = RustEditorEngine();
      try {
        await engine.newProject();
        await engine.addClip(path: 'test://storage.mp4', durationMs: 4000);
        await engine.setMuted(true);
        final saved = await engine.exportProjectJson();
        await store.write(ProjectSlot.draft, saved);
        expect(await store.read(ProjectSlot.draft), saved);
        await engine.newProject();
        final state = await engine.openProjectJson(
          (await store.read(ProjectSlot.draft))!,
        );
        expect(state.mainTrackMuted, true);
        expect(state.totalDurationMs, 4000);
        expect(jsonDecode(await engine.exportProjectJson()), jsonDecode(saved));
      } finally {
        await store.write(ProjectSlot.draft, original);
      }
      expect(await store.read(ProjectSlot.draft), original);
    },
  );
}
