# Imported-video preview fix — 2026-10-13

The user imported a real video, but the editor showed only its filename. Import was copying the actual file and passing its measured duration to Rust; the preview itself still drew a gradient, a movie icon and text. This fix replaces that placeholder with a native Android video surface.

## Changes

- `apps/mobile/lib/engine/editor_state.dart`: `EditorClip.path` carries the source path already present in the Rust snapshot.
- `apps/mobile/lib/video_preview.dart`: embeds the native video view and sends timeline ranges, play/pause, mute and explicit seek requests. Old callbacks are rejected by command revision. Player progress updates the engine without creating a seek-feedback loop.
- `apps/mobile/lib/editor_screen.dart`: uses real video preview; replaces the simulated ticker with native playback positions; keeps timeline scrolling synchronized with Rust; pauses on app backgrounding and before edits.
- `apps/mobile/android/app/src/main/kotlin/com/example/charpcut/VideoPreview.kt`: Media3 ExoPlayer renders a playlist clipped to each Rust clip's source range. Reorder/split/trim rebuild that playlist; mute controls volume. Missing or unsupported sources produce a visible error. Disposal releases the decoder.
- `apps/mobile/android/app/src/main/res/layout/charpcut_preview.xml`: TextureView-backed PlayerView with aspect-fit rendering and buffering indication.
- `apps/mobile/android/app/src/main/kotlin/com/example/charpcut/MainActivity.kt`: registers the platform view and pauses/releases players with activity lifecycle.
- `apps/mobile/android/app/build.gradle.kts`: adds matching Media3 ExoPlayer/UI dependencies (1.11.1).
- `apps/mobile/lib/engine/editor_engine.dart` and existing widget-test wrappers: allow fake-engine UI tests to disable the native preview. These tests were edited for isolation, not executed.
- README, architecture and roadmap: distinguish new, unverified preview code from previously verified Phase 1 work.

The implementation follows the official [Media3 player setup](https://developer.android.com/media/media3/exoplayer/hello-world), [clipped media items](https://developer.android.com/media/media3/exoplayer/media-items) and [Flutter Android platform-view](https://docs.flutter.dev/platform-integration/android/platform-views) APIs. Rust remains the source of clip identity, order, start time, source range and mute; no saved-file schema or Rust API changed.

## Verification status

**No app launch, build, analyzer, or test command was executed for this fix**, following the user's explicit request to perform manual verification themselves. Earlier Phase 1 test results do not verify this preview code.

For manual verification, stop the current `flutter run` session and run `flutter run` again from `apps/mobile`. A full rebuild/relaunch is needed for the new Android platform view and Gradle dependencies; Dart hot reload alone cannot load the native change. No additional Rust-library rebuild or bridge regeneration is needed for this fix.

Import or reopen a real video project, confirm a video frame appears, then check Play/Pause, scrub, split/trim/reorder and Mute. Old `placeholder://` sample clips have no source file and must be removed and replaced with a real import.

## Limits

- Android main video track only; iOS, effects, transitions, additional tracks and real export remain planned.
- Timeline tiles still show names and tint colors; thumbnail/filmstrip generation is a separate Phase 2 feature. The preview above the timeline now has actual video-rendering code.
- The initial renderer consumes ranges projected from the existing validated Rust snapshot; a dedicated Rust renderer edit-list API has not been introduced.
- File/codec compatibility, seek precision, background behavior and resource cleanup remain unverified until the user runs this change.
