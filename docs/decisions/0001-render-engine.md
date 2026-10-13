# 0001 — Preview and export engine

**Decision:** Approved by the project owner on 2026-10-13. Android first; iOS later.

## Context

Rust owns the project, clip ranges, tracks, undo/redo, and saved JSON. A platform media stack decodes sources and renders a preview or output file. The app targets an Android release first and aims to use platform hardware codecs with a small native maintenance burden.

## Options considered

| Option | Benefit | Cost |
| --- | --- | --- |
| Android Media3 and later iOS AVFoundation | Platform codecs and device integration | Separate renderer per platform |
| Bundled FFmpeg | Flexible shared processing | Larger distribution, build and licensing work |
| FFmpeg inside Rust | Common core | Android/iOS cross-compilation and codec complexity |
| Custom GPU renderer | Full rendering control | Highest implementation cost; still needs platform decoders |

## Decision and current implementation

1. Rust remains authoritative for project edits and validated source ranges.
2. Android uses Media3 ExoPlayer for preview. The current player consumes a read-only projection of the validated Rust snapshot and plays clipped sources on one clock. It also handles silent black gaps, seek requests, audio focus, fullscreen and viewing zoom. The owner has tested the app's ordinary preview flows on Android.
3. A dedicated flat Rust renderer edit list and shared preview/export contract are planned for multi-track composition and export. They have **not** been implemented yet. The current snapshot projection does not write project data.
4. Android Media3 Transformer is the proposed export path, subject to evaluation of the effects and transitions needed in Phases 5 and 7. Real export is not implemented.
5. iOS AVFoundation remains a separate later implementation. Revisit a shared GPU or FFmpeg renderer only if requirements warrant its additional cost.

The owner has confirmed Android-only is acceptable for the first release. Authored fades/crossfades, audio/image tracks, and saved crop/scale require future project-model and renderer work; fullscreen zoom and fit currently affect viewing only. The [roadmap](../FEATURE_ROADMAP.md) tracks that scope.
