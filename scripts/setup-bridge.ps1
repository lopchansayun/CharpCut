$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot

Write-Host "Installing flutter_rust_bridge code generator 2.13.0..."
cargo install flutter_rust_bridge_codegen --version 2.13.0 --locked

Write-Host "Fetching Flutter dependencies..."
Push-Location (Join-Path $repoRoot "apps/mobile")
flutter pub get
Pop-Location

Write-Host "Generating Dart/Rust bridge bindings..."
Push-Location $repoRoot
flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml
if ($LASTEXITCODE -ne 0) {
  throw "Bridge code generation failed. Review the error output above."
}
Pop-Location

Write-Host "Bridge generation finished. Next run Rust tests and Flutter tests."
