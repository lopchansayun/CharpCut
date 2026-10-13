import 'package:charpcut/engine/video_importer.dart';
import 'package:flutter_test/flutter_test.dart';

void mockVideoPicker() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        VideoImporter.channel,
        (_) async => {'path': '/test-media/sample.mp4', 'duration_ms': 3000},
      );
}
