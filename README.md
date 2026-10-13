# CharpCut — Update 02: Rust Editor API + Bridge Setup

This update builds on the supplied project while preserving its latest home/editor UI and Rust timeline implementation.

## Added
- `charpcut-editor-api` Rust crate wrapping the timeline model in a bridge-facing API.
- Canonical in-process Rust editor state protected by a mutex.
- `flutter_rust_bridge` 2.13.0 dependency and code-generation config.
- Windows PowerShell setup script for generating the bridge.
- Updated architecture and roadmap.

## Setup

Requirements: current stable Flutter/Dart compatible with `flutter_rust_bridge` 2.13.0 (Dart SDK >= 3.9), Rust via rustup, and Android Studio/Android SDK.

From the repository root:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\setup-bridge.ps1
```

Then run Rust tests:

```powershell
cd rust
cargo test
```

Build the Android Rust library **before launching the app**. The native `.so` library is generated locally and is not included in source control.

```powershell
# From the repository root (CharpCut)
.\\scripts\\build-android-lib.ps1

cd apps\\mobile
flutter test
flutter clean
flutter pub get
flutter run
```

The build script detects the Android SDK/NDK from `ANDROID_HOME`, `ANDROID_SDK_ROOT`, `android/local.properties`, or the default Windows SDK folder. If it cannot find the NDK, install **NDK (Side by side)** in Android Studio > SDK Manager > SDK Tools. You can also set `ANDROID_NDK_HOME` to a specific NDK folder.

The script should create these files under `apps/mobile/android/app/src/main/jniLibs/`:
- `arm64-v8a/libcharpcut_editor_api.so`
- `armeabi-v7a/libcharpcut_editor_api.so`
- `x86_64/libcharpcut_editor_api.so`

If the app still reports the library missing, verify the `.so` exists for your device architecture, then rebuild and reinstall the app.

## UI refresh (CapCut-style mobile layout)
The Flutter UI in `apps/mobile/lib` was restyled to a CapCut-style mobile editor:
- `home_screen.dart` - light home with hero banner, New video / Edit photo cards, recent drafts, tool grid, bottom nav.
- `editor_screen.dart` - dark editor with preview, transport row, scrolling timeline with a fixed playhead, and a toolbar that switches to clip tools when a clip is selected.
- `export_panel.dart` - quality pill dropdown (resolution, frame rate, bitrate, estimated size).
- `export_done_screen.dart` - export-complete screen with share targets and quick actions.

Still placeholders: media import/preview, real export, and sharing. Unfinished controls show a short "coming soon" message. The export flow only plays the screens and does not write a file yet.

## Phase 0 status
The editor now runs on the Rust engine: Flutter asks Rust for every change and shows the state it returns.
Rust tests pass (`cargo test`: 13 timeline + 19 engine). The Flutter side has not been compiled or run by the
author of this change. Run `flutter test`; then `scripts\build-android-lib.ps1` (builds the Rust library for Android) and `flutter run`, and check that adding, splitting and
undoing clips works. See `docs/bridge-integration.md` and `docs/roadmap.md`.

## What's still not included
- Real media import, video decoding, thumbnails, playback, or export.
- Full Flutter editor-to-Rust command wiring.
- GPU renderer.
