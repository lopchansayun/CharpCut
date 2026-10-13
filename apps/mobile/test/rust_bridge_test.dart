import 'dart:convert';
import 'dart:io';

import 'package:charpcut/engine/project_session.dart';
import 'package:charpcut/engine/rust_engine.dart';
import 'package:charpcut/src/rust/frb_generated.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';

class DiskStore implements ProjectStore {
  DiskStore(this.directory);
  final Directory directory;
  File file(ProjectSlot slot) => File('${directory.path}/${slot.name}.json');
  @override
  Future<String?> read(ProjectSlot slot) async =>
      await file(slot).exists() ? file(slot).readAsString() : null;
  @override
  Future<void> write(ProjectSlot slot, String json) =>
      file(slot).writeAsString(json, flush: true);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final name = Platform.isWindows
      ? 'charpcut_editor_api.dll'
      : Platform.isMacOS
      ? 'libcharpcut_editor_api.dylib'
      : 'libcharpcut_editor_api.so';
  final library =
      Platform.environment['CHARPCUT_TEST_LIBRARY'] ??
      '../../rust/target/debug/$name';
  final available = File(library).existsSync();

  test(
    'real bridge edits persist to disk and reopen with identical project data',
    () async {
      await RustLib.init(
        externalLibrary: ExternalLibrary.open(File(library).absolute.path),
      );
      final directory = await Directory.systemTemp.createTemp(
        'charpcut_bridge_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = DiskStore(directory);
      final session = ProjectSession(const RustEditorEngine(), store);
      await session.newProject();
      await session.addClip(path: 'a.mp4', durationMs: 4000);
      await session.splitSelectedAt(1500);
      await session.trimSelected(sourceInMs: 1500, durationMs: 2000);
      await session.undo();
      await session.redo();
      final seek = await session.seek(99999);
      expect(seek.playheadMs, 3500);
      await session.setMuted(true);
      await session.moveSelected(0);
      await session.undo();
      expect((await session.getState()).clips.first.durationMs, 1500);
      await session.redo();
      await session.save();
      final saved = await store.read(ProjectSlot.saved);
      expect(jsonDecode(saved!)['version'], 2);
      await session.deleteSelected();
      expect(await store.read(ProjectSlot.saved), saved);
      await session.newProject();
      final state = await session.openProjectJson(saved);
      expect(state.lastError, null);
      expect(state.clips.map((c) => c.durationMs), [2000, 1500]);
      expect(state.mainTrackMuted, true);
      expect(state.playheadMs, 0);
      expect(jsonDecode(await session.exportProjectJson()), jsonDecode(saved));
      final before = await store.read(ProjectSlot.draft);
      expect((await session.openProjectJson('bad JSON')).lastError, isNotNull);
      final newer = jsonDecode(saved) as Map<String, dynamic>;
      newer['version'] = 999;
      expect(
        (await session.openProjectJson(jsonEncode(newer))).lastError,
        isNotNull,
      );
      expect(await store.read(ProjectSlot.draft), before);
      final legacy = jsonDecode(saved) as Map<String, dynamic>;
      legacy['version'] = 1;
      for (final track in legacy['tracks']) {
        track.remove('muted');
      }
      final migrated = await session.openProjectJson(jsonEncode(legacy));
      expect(migrated.lastError, null);
      expect(migrated.mainTrackMuted, false);
      expect(jsonDecode(await session.exportProjectJson())['version'], 2);
    },
    skip: available
        ? false
        : 'Run cargo build -p charpcut-editor-api in rust/ first',
  );
}
