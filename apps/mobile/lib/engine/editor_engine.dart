import 'package:flutter/widgets.dart';

import 'editor_state.dart';

/// The editing operations the UI can ask for. The app uses the Rust engine
/// ([RustEditorEngine]); tests can pass a small in-memory one.
///
/// Every call returns the new [EditorState]. A refused edit (nothing selected,
/// split outside the clip, ...) leaves the project unchanged and sets
/// [EditorState.lastError].
abstract class EditorEngine {
  Future<EditorState> newProject();
  Future<EditorState> getState();
  Future<EditorState> select(String? clipId);
  Future<EditorState> seek(int timelineMs);
  Future<EditorState> setMuted(bool muted);
  Future<EditorState> moveSelected(int targetIndex);

  /// Appends a clip covering a whole media file and selects it.
  Future<EditorState> addClip({required String path, required int durationMs});

  /// Splits the selected clip at a timeline position (the playhead).
  Future<EditorState> splitSelectedAt(int timelineMs);

  /// Sets which part of the source the selected clip plays.
  Future<EditorState> trimSelected({required int sourceInMs, required int durationMs});
  Future<EditorState> deleteSelected();
  Future<EditorState> undo();
  Future<EditorState> redo();

  /// The project as JSON for saving to a file.
  Future<String> exportProjectJson();

  /// Replaces the project with one read from saved JSON.
  Future<EditorState> openProjectJson(String json);
}

/// Makes the engine available to every screen below it.
class EngineScope extends InheritedWidget {
  const EngineScope({super.key, required this.engine, required super.child, this.previewEnabled = true});

  final EditorEngine engine;
  /// Widget tests can substitute the preview without starting a native decoder.
  final bool previewEnabled;

  static bool previewEnabledOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<EngineScope>()!.previewEnabled;

  static EditorEngine of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<EngineScope>();
    assert(scope != null, 'No EngineScope above this context');
    return scope!.engine;
  }

  @override
  bool updateShouldNotify(EngineScope old) => engine != old.engine || previewEnabled != old.previewEnabled;
}
