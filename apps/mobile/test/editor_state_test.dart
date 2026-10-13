import 'dart:io';

import 'package:charpcut/engine/editor_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // test/fixtures/editor_state.json is a real snapshot produced by the Rust engine
  // (add two clips, select the first, split it at 1.5 s).
  final fixture = File('test/fixtures/editor_state.json').readAsStringSync();

  test('parses a real Rust snapshot', () {
    final s = EditorState.fromJson(fixture);

    expect(s.clips.map((c) => c.name), ['IMG_0042', 'IMG_0042', 'BEACH']);
    expect(s.clips.map((c) => c.startMs), [0, 1500, 4000]);
    expect(s.clips.map((c) => c.durationMs), [1500, 2500, 6000]);
    expect(s.clips[1].sourceInMs, 1500);
    expect(s.totalDurationMs, 10000);
    expect(s.totalSeconds, 10.0);
    expect(s.canUndo, isTrue);
    expect(s.canRedo, isFalse);
    expect(s.status, 'Clip split');
    expect(s.lastError, isNull);
    expect(s.playheadMs, 0);
    expect(s.mainTrackMuted, false);
    // The second half of the split is selected.
    expect(s.selectedClip?.startMs, 1500);
  });

  test('clips from the same file share a tint', () {
    final s = EditorState.fromJson(fixture);
    expect(s.clips[0].color, s.clips[1].color);
    expect(s.clips[0].assetId, s.clips[1].assetId);
  });

  test('clipAt picks the clip under a position and the last clip past the end', () {
    final s = EditorState.fromJson(fixture);
    expect(s.clipAt(0)?.startMs, 0);
    expect(s.clipAt(1499)?.startMs, 0);
    expect(s.clipAt(1500)?.startMs, 1500);
    expect(s.clipAt(99999)?.startMs, 4000);
    expect(EditorState.empty.clipAt(0), isNull);
  });

  test('an engine message without a project becomes an error state', () {
    final s = EditorState.fromJson('{"last_error":"boom"}');
    expect(s.lastError, 'boom');
    expect(s.clips, isEmpty);
  });

  test('rejects JSON that is not an object', () {
    expect(() => EditorState.fromJson('[1,2]'), throwsFormatException);
  });

  test('displayName strips folders and extension', () {
    expect(displayName('content://media/IMG_0042.mp4'), 'IMG_0042');
    expect(displayName(r'C:\clips\beach.day.mov'), 'BEACH.DAY');
    expect(displayName('placeholder'), 'PLACEHOLDER');
  });
}
