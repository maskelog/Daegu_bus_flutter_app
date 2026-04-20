# 릴리즈 빌드 스크립트 (PowerShell)
# 사용:
#   .\build_release.ps1          → AAB (Play Store 업로드)
#   .\build_release.ps1 -Apk     → APK (기기 테스트)
#   .\build_release.ps1 1.0.2 16
#   .\build_release.ps1 1.0.2 16 -Apk

param(
    [string]$BuildName = "",
    [string]$BuildNumber = "",
    [switch]$Apk
)

$ErrorActionPreference = "Stop"

# pubspec.yaml에서 버전 자동 추출
if (-not $BuildName -or -not $BuildNumber) {
    $versionLine = (Get-Content pubspec.yaml | Select-String "^version:").ToString()
    $version = $versionLine -replace "version:\s*", ""
    $parts = $version.Split("+")
    if (-not $BuildName)   { $BuildName   = $parts[0].Trim() }
    if (-not $BuildNumber) { $BuildNumber = $parts[1].Trim() }
}

Write-Host "빌드 버전: $BuildName+$BuildNumber"

if ($Apk) {
    Write-Host "▶ APK 빌드 (기기 테스트용)"
    flutter build apk `
        --release `
        --build-name="$BuildName" `
        --build-number="$BuildNumber" `
        --dart-define-from-file=.env.json

    Write-Host "✅ APK 생성 완료: build/app/outputs/flutter-apk/app-release.apk"
} else {
    Write-Host "▶ AAB 빌드 (Play Store 업로드용)"
    flutter build appbundle `
        --release `
        --build-name="$BuildName" `
        --build-number="$BuildNumber" `
        --obfuscate `
        --split-debug-info=build/debug-info `
        --dart-define-from-file=.env.json

    Write-Host "✅ AAB 생성 완료: build/app/outputs/bundle/release/app-release.aab"
}
