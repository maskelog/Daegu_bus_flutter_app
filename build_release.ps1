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

# PATH에 Flutter가 없으면 Android 로컬 설정의 SDK 경로를 사용한다.
$flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
if ($flutterCommand) {
    $flutter = $flutterCommand.Source
} else {
    $localProperties = Join-Path $PSScriptRoot "android/local.properties"
    if (-not (Test-Path -LiteralPath $localProperties)) {
        throw "flutter command not found and android/local.properties is missing."
    }
    $flutterSdkLine = Get-Content -LiteralPath $localProperties |
        Where-Object { $_ -match '^flutter\.sdk=' } |
        Select-Object -First 1
    if (-not $flutterSdkLine) {
        throw "flutter command not found and flutter.sdk is not set in android/local.properties."
    }
    $flutterSdk = ($flutterSdkLine -replace '^flutter\.sdk=', '') -replace '\\\\', '\'
    $flutter = Join-Path $flutterSdk "bin/flutter.bat"
    if (-not (Test-Path -LiteralPath $flutter)) {
        throw "Flutter executable not found: $flutter"
    }
}

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
    & $flutter build apk `
        --release `
        --build-name="$BuildName" `
        --build-number="$BuildNumber" `
        --dart-define-from-file=.env.json
    if ($LASTEXITCODE -ne 0) {
        throw "flutter build apk failed with exit code $LASTEXITCODE"
    }

    Write-Host "✅ APK 생성 완료: build/app/outputs/flutter-apk/app-release.apk"
} else {
    Write-Host "▶ AAB 빌드 (Play Store 업로드용)"
    & $flutter build appbundle `
        --release `
        --build-name="$BuildName" `
        --build-number="$BuildNumber" `
        --obfuscate `
        --split-debug-info=build/debug-info `
        --dart-define-from-file=.env.json
    if ($LASTEXITCODE -ne 0) {
        throw "flutter build appbundle failed with exit code $LASTEXITCODE"
    }

    Write-Host "✅ AAB 생성 완료: build/app/outputs/bundle/release/app-release.aab"
}
