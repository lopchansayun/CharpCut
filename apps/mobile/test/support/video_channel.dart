import 'package:charpcut/engine/media_library.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void mockVideoPicker() {
  mockMediaImport(() async => {'path': '/test-media/sample.mp4', 'duration_ms': 3000});
}

void mockMediaImport(Future<Map<String, Object>?> Function() pick) {
  final items = <Map<String, Object>>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(MediaLibrary.channel, (call) async {
    switch (call.method) {
      case 'listMedia': return items;
      case 'checkPaths': return [];
      case 'thumbnail': return null;
      case 'pickVideo': return pick();
      case 'importMedia':
        final value = await pick();
        if (value == null) return null;
        final item = <String, Object>{...value, 'kind': 'video',
          'name': (value['path'] as String).split('/').last};
        items.add(item);
        return item;
      case 'inspectMedia':
        return items.firstWhere((item) => item['path'] == call.arguments['path']);
      default: throw StateError('Unexpected media method: ${call.method}');
    }
  });
}

Future<void> addVideo(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Add clip'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Import video'));
  await tester.pumpAndSettle();
}

Future<void> tapTool(WidgetTester tester, String label) async {
  await tester.scrollUntilVisible(find.text(label), 80,
      scrollable: find.descendant(of: find.byType(ListView).last, matching: find.byType(Scrollable)));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text(label));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

Future<void> phoneSurface(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(430, 900);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
