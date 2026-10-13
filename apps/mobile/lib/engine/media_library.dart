import 'package:flutter/services.dart';

class LibraryMedia {
  const LibraryMedia(this.data);
  final Map<String, dynamic> data;
  factory LibraryMedia.fromMap(Map value) => LibraryMedia(Map<String, dynamic>.from(value));
  String get path => data['path'] as String? ?? '';
  String get name => data['name'] as String? ?? 'Imported media';
  String get kind => data['kind'] as String? ?? 'unknown';
  int get durationMs => (data['duration_ms'] as num?)?.toInt() ?? 0;
  bool get available => data['available'] != false;
  String? get error => data['error'] as String?;
  List<Map<String, dynamic>> get audioStreams =>
      (data['audio_streams'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  String get summary {
    final parts = <String>[kind.toUpperCase()];
    if (durationMs > 0) parts.add('${(durationMs / 1000).toStringAsFixed(1)} s');
    if (data['width'] != null && data['height'] != null) {
      final rotated = data['rotation'] == 90 || data['rotation'] == 270;
      parts.add(rotated ? '${data['height']} × ${data['width']}' : '${data['width']} × ${data['height']}');
    }
    return parts.join(' • ');
  }
}

class MediaLibrary {
  static const channel = MethodChannel('charpcut/media');

  Future<List<LibraryMedia>> list() async {
    final values = await channel.invokeListMethod<dynamic>('listMedia') ?? [];
    return values.map((e) => LibraryMedia.fromMap(e as Map)).toList();
  }

  Future<LibraryMedia?> importMedia(String kind) async {
    final value = await channel.invokeMapMethod<String, dynamic>('importMedia', {'kind': kind});
    return value == null ? null : LibraryMedia(value);
  }

  Future<LibraryMedia> inspect(String path) async {
    final value = await channel.invokeMapMethod<String, dynamic>('inspectMedia', {'path': path});
    if (value == null) throw const FormatException('Media details are unavailable');
    return LibraryMedia(value);
  }

  Future<List<String>> unavailablePaths(Iterable<String> paths) async {
    final values = await channel.invokeListMethod<dynamic>('checkPaths', {'paths': paths.toSet().toList()}) ?? [];
    return values.map((e) {
      final item = Map<String, dynamic>.from(e as Map);
      final name = (item['path'] as String).split(RegExp(r'[/\\]')).last;
      return '$name: ${item['error']}';
    }).toList();
  }

  Future<String?> thumbnail(String path, int positionMs) => channel.invokeMethod<String>(
    'thumbnail', {'path': path, 'position_ms': positionMs},
  );
}
