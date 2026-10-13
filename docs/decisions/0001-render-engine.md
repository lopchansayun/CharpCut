# 0001 - Preview and export engine

Status: **approved** by the project owner on 2026-10-13 (Android first, iOS later). **Partial implementation:** an initial Android Media3 preview now consumes clip paths/ranges from Rust's existing validated snapshot. This code awaits the owner's manual build/test; a dedicated Rust edit-list output and shared preview/export `RenderEngine` interface remain planned. See [../VIDEO_PREVIEW_FIX.md](../VIDEO_PREVIEW_FIX.md) and [../FEATURE_ROADMAP.md](../FEATURE_ROADMAP.md).

## Context
Rust owns the project (clips, tracks, undo/redo, saved file). Something else has to decode video, play it
and render the final file. The choice affects every later phase, so it is made now even though no render
code is written yet.

Constraints we know about: the app is free (no licence fees), targets Android first and iOS later, and is
built by a small team, so we want hardware codecs and as little native code to maintain as possible.

## Options considered
| Option | For | Against |
| --- | --- | --- |
| **Platform media stacks**: Android Media3 (ExoPlayer for preview, Transformer for export); iOS AVFoundation later | Hardware encode/decode, maintained by the platform vendors, no codec licence to manage, small app size, effects and transitions supported | One implementation per platform; Android and iOS behave slightly differently |
| FFmpeg through a Flutter plugin | One code path for all platforms, very flexible | The popular `ffmpeg_kit` plugins were retired, so we would build and maintain FFmpeg ourselves; GPL/LGPL licence obligations; software encoding is slow and hot on phones; larger app |
| FFmpeg built into the Rust crate (`ffmpeg-next`) | Single engine in Rust | Cross-compiling FFmpeg for Android/iOS, same licence and speed concerns, no hardware path without extra work |
| Custom GPU renderer in Rust | Full control, identical output everywhere | Largest effort by far; still needs platform codecs for decode/encode |

## Decision (approved)
1. **Rust stays the source of truth.** It produces a flat, validated *edit list* from the project
   (which source range plays when, on which track, with which volume/speed/effects).
2. A small Dart interface, `RenderEngine`, takes that edit list for **preview** and **export**.
3. **Android first**: Media3 implements it (ExoPlayer composition for preview, Transformer for export),
   called over a platform channel.
4. **iOS later**: an AVFoundation implementation of the same interface and the same edit list.
5. Revisit a shared GPU renderer in Rust only when effects need identical output on both platforms.

## Consequences
- Phase 3 and Phase 7 each have an Android implementation first; iOS parity is a separate, later task.
- The edit list is a new, tested Rust output; the Dart/native renderers never read the project file directly.
- Export settings in the UI (resolution, frame rate, bitrate) map directly onto Transformer settings.

## Needs further evaluation
- Media3 Transformer's support for the effects and transitions planned in Phase 5 has not been checked against this project's needs.
- The edit-list format has not been designed.

## Resolved question
Is Android-only acceptable for the first release? **Yes.** The owner confirmed on 2026-10-13 that the first release targets Android only. iOS (AVFoundation behind the same `RenderEngine` interface and edit list) is a later task. Building it needs a Mac with Xcode and an Apple Developer account. Revisit the FFmpeg-in-Rust option only if iOS must ship at the same time as Android.
