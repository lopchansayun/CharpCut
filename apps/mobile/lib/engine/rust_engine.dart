import '../src/rust/api.dart' as rust;
import 'editor_engine.dart';
import 'editor_state.dart';

/// The real engine: every call goes through the generated bridge to Rust.
class RustEditorEngine implements EditorEngine {
  const RustEditorEngine();

  EditorState _read(String json) => EditorState.fromJson(json);

  @override
  Future<EditorState> seek(int timelineMs) async => _read(await rust.seekPlayhead(timelineMs: timelineMs));
  @override
  Future<EditorState> setMuted(bool muted) async => _read(await rust.setMainTrackMuted(muted: muted));
  @override
  Future<EditorState> moveSelected(int targetIndex) async => _read(await rust.moveSelectedClip(targetIndex: targetIndex));

  @override
  Future<EditorState> newProject() async => _read(await rust.newProject());

  @override
  Future<EditorState> getState() async => _read(await rust.getEditorState());

  @override
  Future<EditorState> select(String? clipId) async => _read(await rust.selectClip(clipId: clipId));

  @override
  Future<EditorState> addClip({required String path, required int durationMs}) async =>
      _read(await rust.addClip(path: path, durationMs: durationMs));

  @override
  Future<EditorState> splitSelectedAt(int timelineMs) async =>
      _read(await rust.splitSelectedClipAt(timelineMs: timelineMs));

  @override
  Future<EditorState> trimSelected({required int sourceInMs, required int durationMs}) async =>
      _read(await rust.trimSelectedClip(sourceInMs: sourceInMs, durationMs: durationMs));

  @override
  Future<EditorState> deleteSelected() async => _read(await rust.deleteSelectedClip());

  @override
  Future<EditorState> undo() async => _read(await rust.undo());

  @override
  Future<EditorState> redo() async => _read(await rust.redo());

  @override
  Future<String> exportProjectJson() => rust.exportProjectJson();

  @override
  Future<EditorState> openProjectJson(String json) async => _read(await rust.openProjectJson(json: json));
}
