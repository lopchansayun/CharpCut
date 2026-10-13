# Build the Rust editing engine for Android and place the shared libraries where Gradle packages them.
# Run from any directory: .\scripts\build-android-lib.ps1
# Requirements: Rust (rustup), Android SDK/NDK, and PowerShell.
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$mobileRoot = Join-Path $repoRoot "apps/mobile"
$androidRoot = Join-Path $mobileRoot "android"
$jniLibs = Join-Path $androidRoot "app/src/main/jniLibs"

function Resolve-AndroidSdk {
  if ($env:ANDROID_HOME -and (Test-Path $env:ANDROID_HOME)) { return $env:ANDROID_HOME }
  if ($env:ANDROID_SDK_ROOT -and (Test-Path $env:ANDROID_SDK_ROOT)) { return $env:ANDROID_SDK_ROOT }

  $localProperties = Join-Path $androidRoot "local.properties"
  if (Test-Path $localProperties) {
    $line = Get-Content $localProperties | Where-Object { $_ -match '^\s*sdk\.dir\s*=' } | Select-Object -First 1
    if ($line) {
      $sdk = ($line -split '=', 2)[1].Trim() -replace '\\:', ':' -replace '\\\\', '\'
      if (Test-Path $sdk) { return $sdk }
    }
  }

  if ($env:LOCALAPPDATA) {
    $defaultSdk = Join-Path $env:LOCALAPPDATA "Android/Sdk"
    if (Test-Path $defaultSdk) { return $defaultSdk }
  }
  return $null
}

if (-not (Get-Command rustup -ErrorAction SilentlyContinue)) {
  throw "Rust is not installed or rustup is not on PATH. Install Rust from https://rustup.rs and reopen PowerShell."
}
if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
  throw "Cargo is not on PATH. Install Rust and reopen PowerShell."
}

$sdk = Resolve-AndroidSdk
if (-not $sdk) {
  throw "Android SDK not found. Install Android SDK/NDK in Android Studio, or set ANDROID_HOME to your SDK folder."
}

# Prefer an explicitly configured NDK, otherwise choose the newest installed side-by-side NDK.
$ndk = $env:ANDROID_NDK_HOME
if (-not $ndk -or -not (Test-Path $ndk)) {
  $ndkRoot = Join-Path $sdk "ndk"
  if (Test-Path $ndkRoot) {
    $candidate = Get-ChildItem $ndkRoot -Directory | Sort-Object { try { [version]$_.Name } catch { [version]"0.0" } } -Descending | Select-Object -First 1
    if ($candidate) { $ndk = $candidate.FullName }
  }
}
if (-not $ndk -or -not (Test-Path (Join-Path $ndk "toolchains/llvm"))) {
  throw "Android NDK not found under '$sdk'. In Android Studio > SDK Manager > SDK Tools, install NDK (Side by side), then rerun this script."
}
$env:ANDROID_NDK_HOME = $ndk
$env:ANDROID_NDK_ROOT = $ndk
Write-Host "Using Android SDK: $sdk"
Write-Host "Using Android NDK: $ndk"

Write-Host "Adding Android Rust targets..."
rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android
if ($LASTEXITCODE -ne 0) { throw "Could not install Rust Android targets." }

# Install cargo-ndk only if it is not already available.
$cargoNdkAvailable = $false
try {
  cargo ndk --version *> $null
  $cargoNdkAvailable = ($LASTEXITCODE -eq 0)
} catch {
  $cargoNdkAvailable = $false
}
if (-not $cargoNdkAvailable) {
  Write-Host "Installing cargo-ndk..."
  cargo install cargo-ndk --locked
  if ($LASTEXITCODE -ne 0) { throw "cargo-ndk installation failed." }
}

New-Item -ItemType Directory -Force -Path $jniLibs | Out-Null
Write-Host "Building Rust editor library for Android (arm64, armv7, x86_64)..."
Push-Location (Join-Path $repoRoot "rust")
try {
  cargo ndk -t arm64-v8a -t armeabi-v7a -t x86_64 -o $jniLibs build --release -p charpcut-editor-api
  if ($LASTEXITCODE -ne 0) { throw "Rust Android build failed. Check the compiler output above." }
} finally {
  Pop-Location
}

$expected = @(
  (Join-Path $jniLibs "arm64-v8a/libcharpcut_editor_api.so"),
  (Join-Path $jniLibs "armeabi-v7a/libcharpcut_editor_api.so"),
  (Join-Path $jniLibs "x86_64/libcharpcut_editor_api.so")
)
$missing = $expected | Where-Object { -not (Test-Path $_) }
if ($missing) {
  throw "Build finished but expected native library file(s) are missing:`n$($missing -join "`n")"
}

Write-Host ""
Write-Host "Native engine built successfully:"
$expected | ForEach-Object { Write-Host "  $_" }
Write-Host ""
Write-Host "Now run these commands:"
Write-Host "  cd `"$mobileRoot`""
Write-Host "  flutter clean"
Write-Host "  flutter pub get"
Write-Host "  flutter run"
