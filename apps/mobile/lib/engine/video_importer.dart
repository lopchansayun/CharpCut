import 'package:flutter/services.dart';

class ImportedVideo {
  const ImportedVideo({required this.path, required this.durationMs});
  final String path;
  final int durationMs;
}

/// Minimal Android import; metadata validation and durable copying happen natively.
class VideoImporter {
  static const channel = MethodChannel('charpcut/media');
  Future<ImportedVideo?> pickVideo() async {
    final result = await channel.invokeMapMethod<String, dynamic>('pickVideo');
    if (result == null) return null;
    final path = result['path'];
    final duration = result['duration_ms'];
    if (path is! String ||
        path.trim().isEmpty ||
        duration is! int ||
        duration < 100) {
      throw const FormatException('The selected video has invalid metadata');
    }
    return ImportedVideo(path: path, durationMs: duration);
  }
}
