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

  setUpAll(() async {
    if (available)
      await RustLib.init(
        externalLibrary: ExternalLibrary.open(File(library).absolute.path),
      );
  });

  test(
    'overlapping audio and images survive real bridge autosave and reopen',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'charpcut_overlap_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final session = ProjectSession(
        const RustEditorEngine(),
        DiskStore(directory),
      );
      await session.newProject();
      for (final kind in ['audio', 'image', 'overlay']) {
        await session.addTimelineMedia(
          path: '$kind-one',
          durationMs: 4000,
          kind: kind,
        );
        var state = await session.addTimelineMedia(
          path: '$kind-two',
          durationMs: 4000,
          kind: kind,
        );
        final id = state.selectedClipId!;
        state = await session.applyTimelineEdit({
          'action': 'shift',
          'clip_ids': [id],
          'delta_ms': -3000,
        });
        expect(state.lastError, isNull);
        expect(state.selectedClip!.startMs, 1000);
      }
      final saved = await session.exportProjectJson();
      final state = await session.openProjectJson(saved);
      expect(state.lastError, isNull);
      expect(state.audioClips.map((c) => c.startMs), [0, 1000]);
      expect(state.imageClips.map((c) => c.startMs), [0, 1000]);
      expect(state.overlayClips.map((c) => c.startMs), [0, 1000]);
    },
    skip: !available,
  );

  test(
    'Phase 4 properties, batch edits, and track order save and undo through the real bridge',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'charpcut_phase4_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final session = ProjectSession(
        const RustEditorEngine(),
        DiskStore(directory),
      );
      await session.newProject();
      await session.addClip(path: 'a.mp4', durationMs: 4000);
      final draft = (await session.listDrafts()).single.id;
      var state = await session.getState();
      state = await session.applyTimelineEdit({
        'action': 'properties',
        'clip_id': state.clips.single.id,
        'start_ms': 1000,
        'duration_ms': 4000,
        'properties': {
          ...state.clips.single.properties.toJson(),
          'scale': 1.5,
          'rotation': 45.0,
          'opacity': .6,
          'volume': .3,
        },
      });
      expect(state.lastError, null);
      expect(state.clips.single.startMs, 1000);
      expect(state.clips.single.properties.scale, 1.5);
      expect(state.clips.single.properties.rotation, 45);
      expect(state.clips.single.properties.opacity, .6);
      expect(state.clips.single.properties.volume, .3);
      await session.undo();
      expect((await session.getState()).clips.single.properties.scale, 1);
      await session.redo();
      final saved = (await session.listDrafts()).single.json;
      state = await session.openDraft(draft);
      expect(state.clips.single.properties.scale, 1.5);
      final id = state.clips.single.id;
      state = await session.applyTimelineEdit({
        'action': 'duplicate',
        'clip_ids': [id],
      });
      expect(state.clips, hasLength(2));
      expect(state.clips.last.properties.volume, .3);
      await session.undo();
      expect((await session.listDrafts()).single.json, saved);
      await session.addTimelineMedia(
        path: 'overlay.png',
        durationMs: 3000,
        kind: 'overlay',
      );
      state = await session.getState();
      final order = state.tracks.reversed.map((t) => t.id).toList();
      state = await session.applyTimelineEdit({
        'action': 'reorder_tracks',
        'track_ids': order,
      });
      expect(state.tracks.first.kind, 'overlay');
      await session.save();
      expect((await session.openDraft(draft)).tracks.first.kind, 'overlay');
    },
    skip: !available,
  );

  test(
    'real bridge edits persist to disk and reopen with identical project data',
    () async {
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
      final saved = (await session.listDrafts()).single.json;
      expect(jsonDecode(saved)['version'], 5);
      await session.deleteSelected();
      expect((await session.listDrafts()).single.json, isNot(saved));
      await session.newProject();
      final state = await session.openProjectJson(saved);
      expect(state.lastError, null);
      expect(state.clips.map((c) => c.durationMs), [2000, 1500]);
      expect(state.mainTrackMuted, true);
      expect(state.playheadMs, 0);
      expect(jsonDecode(await session.exportProjectJson()), jsonDecode(saved));
      final before = await store.read(ProjectSlot.library);
      expect((await session.openProjectJson('bad JSON')).lastError, isNotNull);
      final newer = jsonDecode(saved) as Map<String, dynamic>;
      newer['version'] = 999;
      expect(
        (await session.openProjectJson(jsonEncode(newer))).lastError,
        isNotNull,
      );
      expect(await store.read(ProjectSlot.library), before);
      final legacy = jsonDecode(saved) as Map<String, dynamic>;
      legacy['version'] = 1;
      for (final track in legacy['tracks']) {
        track.remove('muted');
      }
      final migrated = await session.openProjectJson(jsonEncode(legacy));
      expect(migrated.lastError, null);
      expect(migrated.mainTrackMuted, false);
      expect(jsonDecode(await session.exportProjectJson())['version'], 5);
    },
    skip: available
        ? false
        : 'Run cargo build -p charpcut-editor-api in rust/ first',
  );
}
