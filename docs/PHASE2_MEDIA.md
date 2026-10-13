# Phase 2 - Media import and project management

Status: implemented, awaiting manual owner verification. Phase 1 is now complete based on the owner's report that everything was tested and works. No app, build, analyzer, or tests were run for this update, as requested.

## What changed

- Home has a Media library entry. Import video, audio, or still images with Android's document picker; browse by type, search filenames, and open file details.
- Imports are durably copied into app-private media folders. Metadata is written with AtomicFile beside each source. Cancelled selection changes nothing; failed imports remove only their own new files. Original files and other drafts are untouched.
- Metadata includes duration, encoded dimensions, rotation/mirroring, display dimensions, MIME type, file size, video frame rate when reported, and audio stream codec/channel/sample-rate/bitrate/decode support. A frame-count/duration fallback is marked as average FPS. Unreported fields remain unknown rather than invented.
- Still-image thumbnails honor EXIF orientation. Video thumbnails and filmstrips use Android-decoded source frames. Filmstrip times include trim offsets; only visible tiles plus overscan request frames. Keyframe-based thumbnails are representative rather than exact-frame scrub previews.
- Derived thumbnails use an app-cache directory bounded to 48 MiB. Thumbnail failure shows a fallback without losing the media or project. Clearing Android's cache allows regeneration.
- Existing video imports are discovered and indexed when the library is opened; existing project paths remain valid.
- Editor + opens the video library. Pick an existing video or import a new one to append through the existing Rust engine API. Importing directly from this chooser immediately adds the imported video.
- The audio entry opens the audio-filtered library. Audio/images can be imported and inspected in Phase 2; their timeline placement, playback/mixing, and editing remain Phases 4/6. No synthetic audio/image clips are inserted into the video track.
- Draft menus now include Duplicate. A copy gets an independent library identity and name, while retaining an exact engine snapshot and shared immutable source files. Snapshot-internal IDs are scoped to each document and are preserved. Editing/deleting either draft does not alter the other.
- Drafts show the first source frame as a thumbnail. Create/rename/delete/recent-draft behavior is retained.
- Missing/unreadable private files are identified in the library and editor. Corrupt or unsupported media fails import/inspection with an actionable error; existing drafts can still be opened and broken clips deleted. Reimport-and-replace is supported; automatic relinking is future work.

## Boundaries and persistence

Media catalog metadata is Android-owned file information, not timeline state. Flutter displays it. Rust remains authoritative for timeline edits, clip ranges, undo/redo, validation, and saved project JSON. No Rust schema/API or generated bridge changes were needed for Phase 2.

Source files stay in `files/media/<id>/`; catalog sidecars are `metadata.json`. Existing source paths continue working. New imports prefix source filenames to avoid collisions with internal metadata/temp filenames. Thumbnails live in `cache/media-thumbnails/` and can be regenerated. Media remains available across multiple projects; reference-aware source cleanup is not included.

Decoder support depends on the device. Video import verifies frame decoding and audio-only import checks for a compatible platform decoder. Full-stream corruption and real playback synchronization still require playback validation. Frame rate can be absent or approximate, especially for variable-frame-rate media.

## Changed files

- Android `MediaLibrary.kt`: import, probe, catalog, file checks, thumbnails and cache.
- Android `MainActivity.kt`: delegates media channel/picker lifecycle.
- Android `app/build.gradle.kts`: AndroidX EXIF dependency.
- Dart `engine/media_library.dart`, `media_library_screen.dart`, `media_thumbnail.dart`: library boundary, browsing/details and thumbnail widgets.
- Dart `editor_screen.dart`, `home_screen.dart`: entry points, media reuse, source warnings and filmstrips.
- Dart `engine/project_session.dart`, `draft_list.dart`: duplicate drafts and project thumbnails.
- README, architecture and roadmap: updated phase status and behavior.

## Manual acceptance (owner runs these)

A full stop and `flutter run` is required for the new Android source and EXIF dependency. Hot reload is insufficient. No Rust rebuild is required for these Phase 2 changes.

1. Open an existing draft and confirm its videos still play and show filmstrips. Open Media library and confirm older imports appear.
2. Import landscape and rotated portrait videos, an audio file, and a rotated still image. Check names, duration, dimensions, rotation, available FPS and audio details. Cancel one picker and confirm nothing is added.
3. Filter/search the library; add an existing video into a new project, then import another from the editor + chooser. Confirm both appear in timeline order.
4. Trim and split a video with visibly changing frames. Confirm thumbnail sampling follows the source ranges. Scroll through a long clip.
5. Restart the app and confirm the library, metadata, imported paths, draft edits and thumbnails persist/regenerate. Move/delete an external original and confirm the imported copy remains usable.
6. Duplicate a draft. Edit the copy, reopen the original, then delete the copy. Confirm the original and shared source media remain available.
7. Try an empty/corrupt/unsupported file and confirm a readable error without an extra incomplete import. Check missing private-source behavior only in a disposable draft if desired.
8. Verify existing Phase 1 persistence and undo/redo remain correct. Prior widget tests that assumed a direct picker or two-slot persistence need updating before a future automated test run; none were run for this update.

Optional owner commands from `apps/mobile`: `flutter analyze`, `flutter test`, and `flutter run`. These are documentation only, not commands executed by the assistant.

## API references

- [Android MediaMetadataRetriever](https://developer.android.com/reference/android/media/MediaMetadataRetriever)
- [Android MediaExtractor](https://developer.android.com/reference/android/media/MediaExtractor)
- [Android MediaFormat](https://developer.android.com/reference/android/media/MediaFormat)
- [AndroidX ExifInterface releases](https://developer.android.com/jetpack/androidx/releases/exifinterface)
