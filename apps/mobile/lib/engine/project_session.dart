import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'editor_engine.dart';
import 'editor_state.dart';

enum ProjectSlot { draft, saved, library }

class ProjectDraft {
  const ProjectDraft({required this.id, required this.name, required this.updatedAt, required this.json});
  final String id;
  final String name;
  final DateTime updatedAt;
  final String json;

  /// Read-only display metadata. Malformed drafts can still be listed/deleted.
  (String, int)? get firstFrame {
    try {
      final project = jsonDecode(json) as Map<String, dynamic>;
      final tracks = project['tracks'] as List;
      final clips = tracks.expand((t) => (t as Map)['clips'] as List);
      if (clips.isEmpty) return null;
      final clip = clips.first as Map;
      final asset = (project['assets'] as List).cast<Map>()
          .firstWhere((a) => a['id'] == clip['asset_id']);
      return (asset['path'] as String, (clip['source_in_ms'] as num).toInt());
    } catch (_) { return null; }
  }

  Map<String, Object> toJson() => {
    'id': id, 'name': name, 'updated_at': updatedAt.toIso8601String(), 'project': json,
  };

  factory ProjectDraft.fromJson(Map<String, dynamic> value) => ProjectDraft(
    id: value['id'] as String, name: value['name'] as String,
    updatedAt: DateTime.parse(value['updated_at'] as String),
    json: value['project'] as String,
  );
}

abstract class ProjectStore {
  Future<String?> read(ProjectSlot slot);
  Future<void> write(ProjectSlot slot, String json);
}

/// Android stores engine-produced JSON in private storage using AtomicFile.
class AndroidProjectStore implements ProjectStore {
  static const channel = MethodChannel('charpcut/projects');

  @override
  Future<String?> read(ProjectSlot slot) =>
      channel.invokeMethod<String>('read', {'slot': slot.name});

  @override
  Future<void> write(ProjectSlot slot, String json) =>
      channel.invokeMethod<void>('write', {'slot': slot.name, 'json': json});
}

/// Serializes engine calls and disk writes together. A slow autosave can never
/// overwrite a newer edit. Disk failures leave the successful engine edit visible.
class ProjectSession implements EditorEngine {
  ProjectSession(this.engine, this.store);

  final EditorEngine engine;
  final ProjectStore store;
  String? storageError;
  final libraryRevision = ValueNotifier<int>(0);
  List<ProjectDraft>? _drafts;
  String? _activeId;

  String _newId() => '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';

  Future<void> _loadLibrary() async {
    if (_drafts != null) return;
    final source = await store.read(ProjectSlot.library);
    if (source != null) {
      final value = jsonDecode(source) as Map<String, dynamic>;
      if (value['version'] != 1) throw const FormatException('Unsupported draft library version');
      final drafts = (value['drafts'] as List)
          .map((item) => ProjectDraft.fromJson(item as Map<String, dynamic>)).toList();
      if (drafts.map((d) => d.id).toSet().length != drafts.length) {
        throw const FormatException('Duplicate draft identifiers');
      }
      _drafts = drafts;
      return;
    }
    // Migrate once. Keep old files untouched as backups; an empty library is
    // still authoritative, so deleting the last draft never resurrects them.
    final legacyDraft = await store.read(ProjectSlot.draft);
    final legacySaved = await store.read(ProjectSlot.saved);
    final migrated = <ProjectDraft>[];
    if (legacyDraft != null) {
      migrated.add(ProjectDraft(id: _newId(), name: 'Recovered draft',
          updatedAt: DateTime.now(), json: legacyDraft));
    }
    if (legacySaved != null && legacySaved != legacyDraft) {
      migrated.add(ProjectDraft(id: _newId(), name: 'Previously saved project',
          updatedAt: DateTime.now(), json: legacySaved));
    }
    await _writeLibrary(migrated);
  }

  Future<void> _writeLibrary(List<ProjectDraft> drafts) async {
    await store.write(ProjectSlot.library, jsonEncode({
      'version': 1, 'drafts': drafts.map((d) => d.toJson()).toList(),
    }));
    _drafts = drafts;
    libraryRevision.value++;
  }

  Future<List<ProjectDraft>> listDrafts() => _enqueue(() async {
    await _loadLibrary();
    return List<ProjectDraft>.of(_drafts!)
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  });

  Future<void> _persist(EditorState state, {bool allowEmpty = false}) async {
    await _loadLibrary();
    if (_activeId == null && state.clips.isEmpty && !allowEmpty) return;
    final id = _activeId ?? _newId();
    final index = _drafts!.indexWhere((d) => d.id == id);
    final name = index >= 0 ? _drafts![index].name
        : state.clips.isEmpty ? 'Untitled video' : state.clips.first.name;
    final updated = ProjectDraft(id: id, name: name,
        updatedAt: DateTime.now(), json: await _json());
    final next = List<ProjectDraft>.of(_drafts!);
    if (index < 0) { next.add(updated); } else { next[index] = updated; }
    await _writeLibrary(next);
    _activeId = id;
  }

  Future<void> _preserveUnsaved() async {
    if (storageError == null) return;
    await _persist(await engine.getState(), allowEmpty: true);
    storageError = null;
  }

  Future<EditorState> openDraft(String id) => _enqueue(() async {
    await _preserveUnsaved();
    await _loadLibrary();
    final draft = _drafts!.firstWhere((d) => d.id == id,
        orElse: () => throw StateError('This draft no longer exists'));
    final state = await engine.openProjectJson(draft.json);
    if (state.lastError == null) {
      _activeId = id;
      storageError = null;
    }
    return state;
  });

  Future<void> deleteDraft(String id) => _enqueue(() async {
    await _loadLibrary();
    await _writeLibrary(_drafts!.where((d) => d.id != id).toList());
    if (_activeId == id) {
      _activeId = null;
      storageError = null;
    }
  });

  Future<void> duplicateDraft(String id) => _enqueue(() async {
    await _preserveUnsaved();
    await _loadLibrary();
    final draft = _drafts!.firstWhere((d) => d.id == id,
        orElse: () => throw StateError('This draft no longer exists'));
    var name = '${draft.name} copy';
    var suffix = 2;
    while (_drafts!.any((d) => d.name == name)) {
      name = '${draft.name} copy ${suffix++}';
    }
    // Library IDs identify independent saved documents. The engine snapshot is
    // copied intact and will be validated by Rust when the copy is opened.
    await _writeLibrary([..._drafts!, ProjectDraft(id: _newId(), name: name,
        updatedAt: DateTime.now(), json: draft.json)]);
  });

  Future<void> renameDraft(String id, String name) => _enqueue(() async {
    await _loadLibrary();
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError('Enter a project name');
    await _writeLibrary(_drafts!.map((d) => d.id == id
        ? ProjectDraft(id: d.id, name: trimmed, updatedAt: d.updatedAt, json: d.json)
        : d).toList());
  });
  Future<void> _tail = Future.value();

  Future<T> _enqueue<T>(Future<T> Function() call) {
    final result = _tail.then((_) => call());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<String> _json() async {
    final json = await engine.exportProjectJson();
    if (json.trim().isEmpty) {
      throw StateError('The engine could not save the project');
    }
    return json;
  }

  Future<EditorState> _change(
    Future<EditorState> Function() call,
  ) => _enqueue(() async {
    final state = await call();
    if (state.lastError == null) {
      try {
        await _persist(state);
        storageError = null;
      } catch (error) {
        storageError =
            'Autosave failed. Keep the editor open and retry Save project. $error';
      }
    }
    return state;
  });

  Future<String?> readSlot(ProjectSlot slot) =>
      _enqueue(() => store.read(slot));

  /// Explicit Save flushes this draft; it never replaces another project.
  Future<void> save() => _enqueue(() async {
    await _persist(await engine.getState(), allowEmpty: true);
    storageError = null;
  });

  @override
  Future<EditorState> newProject() => _enqueue(() async {
    await _preserveUnsaved();
    await _loadLibrary();
    final state = await engine.newProject();
    if (state.lastError == null) {
      _activeId = null;
      storageError = null;
    }
    return state;
  });
  @override
  Future<EditorState> getState() => _enqueue(engine.getState);
  @override
  Future<EditorState> seek(int timelineMs) =>
      _enqueue(() => engine.seek(timelineMs));
  @override
  Future<EditorState> setMuted(bool muted) =>
      _change(() => engine.setMuted(muted));
  @override
  Future<EditorState> moveSelected(int targetIndex) =>
      _change(() => engine.moveSelected(targetIndex));
  @override
  Future<EditorState> select(String? clipId) =>
      _enqueue(() => engine.select(clipId));
  @override
  Future<EditorState> addClip({
    required String path,
    required int durationMs,
  }) => _change(() => engine.addClip(path: path, durationMs: durationMs));
  @override
  Future<EditorState> splitSelectedAt(int timelineMs) =>
      _change(() => engine.splitSelectedAt(timelineMs));
  @override
  Future<EditorState> trimSelected({
    required int sourceInMs,
    required int durationMs,
  }) => _change(
    () => engine.trimSelected(sourceInMs: sourceInMs, durationMs: durationMs),
  );
  @override
  Future<EditorState> deleteSelected() => _change(engine.deleteSelected);
  @override
  Future<EditorState> undo() => _change(engine.undo);
  @override
  Future<EditorState> redo() => _change(engine.redo);
  @override
  Future<String> exportProjectJson() => _enqueue(_json);
  @override
  Future<EditorState> openProjectJson(String json) =>
      _change(() async {
        await _preserveUnsaved();
        final state = await engine.openProjectJson(json);
        if (state.lastError == null) _activeId = null;
        return state;
      });
}
