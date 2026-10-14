import 'package:charpcut/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fake_engine.dart';
import 'support/video_channel.dart';

class RecordingEngine extends FakeEngine {
  Map<String, dynamic>? edit;
  @override
  Future<EditorState> applyTimelineEdit(Map<String, dynamic> value) async {
    edit = value;
    return getState();
  }
}

void main() {
  setUp(mockVideoPicker);
  testWidgets('properties reject an empty crop then send normalized saved values', (tester) async {
    await phoneSurface(tester);
    final engine = RecordingEngine();
    await tester.pumpWidget(EngineScope(previewEnabled: false, engine: engine,
      child: const MaterialApp(home: EditorHome())));
    await tester.pumpAndSettle();
    await addVideo(tester);
    await tapTool(tester, 'Properties');
    Future<void> enter(String label, String value) async {
      final field = find.widgetWithText(TextField, label);
      await tester.ensureVisible(field);
      await tester.enterText(field, value);
      await tester.pumpAndSettle();
    }
    await enter('Crop left (%)', '60');
    await enter('Crop right (%)', '40');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(engine.edit, isNull);
    expect(find.textContaining('crop must leave visible content'), findsOneWidget);
    await enter('Crop left (%)', '10');
    await enter('Scale (%)', '150');
    await enter('Volume (%)', '35');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(engine.edit!['action'], 'properties');
    expect(engine.edit!['properties']['crop_left'], .1);
    expect(engine.edit!['properties']['crop_right'], .4);
    expect(engine.edit!['properties']['scale'], 1.5);
    expect(engine.edit!['properties']['volume'], .35);
    expect(find.text('Clip properties'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('multi-select sends one batch delete without ripple', (tester) async {
    await phoneSurface(tester);
    final engine = RecordingEngine();
    await tester.pumpWidget(EngineScope(previewEnabled: false, engine: engine,
      child: const MaterialApp(home: EditorHome())));
    await tester.pumpAndSettle();
    await addVideo(tester);
    await addVideo(tester);
    await tapTool(tester, 'Select');
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Select'));
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);
    await tapTool(tester, 'Delete only');
    expect(engine.edit!['action'], 'delete');
    expect(engine.edit!['ripple'], false);
    expect(engine.edit!['clip_ids'], (await engine.getState()).clips.map((c) => c.id).toList().reversed.toList());
    expect(tester.takeException(), isNull);
  });
}
