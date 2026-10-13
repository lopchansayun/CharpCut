# Builds the Rust editing engine for Android and puts the .so files where Gradle packages them.
# Run this after any change under rust/, then `flutter run`.
# Needs: rustup, the Android NDK (set ANDROID_NDK_HOME), and cargo-ndk (installed below).
$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot

if (-not $env:ANDROID_NDK_HOME) {
  throw "ANDROID_NDK_HOME is not set. Install the NDK from Android Studio (SDK Manager > SDK Tools > NDK) and point ANDROID_NDK_HOME at it."
}

Write-Host "Adding Android Rust targets..."
rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android

Write-Host "Installing cargo-ndk..."
cargo install cargo-ndk --locked

$out = Join-Path $repoRoot "apps/mobile/android/app/src/main/jniLibs"
Write-Host "Building libcharpcut_editor_api.so into $out ..."
Push-Location (Join-Path $repoRoot "rust")
cargo ndk -t arm64-v8a -t armeabi-v7a -t x86_64 -o $out build --release -p charpcut-editor-api
if ($LASTEXITCODE -ne 0) { Pop-Location; throw "Android build of the Rust library failed. Review the error output above." }
Pop-Location

Write-Host "Done. Run 'flutter run' from apps/mobile."
