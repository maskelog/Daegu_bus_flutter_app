#!/usr/bin/env bash
# 릴리즈 AAB 빌드 스크립트
# 사용: ./build_release.sh [build-name] [build-number]
# 예시: ./build_release.sh 1.0.2 15

set -e

BUILD_NAME=${1:-$(grep "^version:" pubspec.yaml | cut -d' ' -f2 | cut -d'+' -f1)}
BUILD_NUMBER=${2:-$(grep "^version:" pubspec.yaml | cut -d'+' -f2)}

echo "빌드 버전: $BUILD_NAME+$BUILD_NUMBER"

flutter build appbundle \
  --release \
  --build-name="$BUILD_NAME" \
  --build-number="$BUILD_NUMBER" \
  --obfuscate \
  --split-debug-info=build/debug-info \
  --dart-define-from-file=.env.json

echo "✅ AAB 생성 완료: build/app/outputs/bundle/release/app-release.aab"
