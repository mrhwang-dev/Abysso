#!/bin/bash
# MacCleaner.app 빌드 스크립트 — Xcode 없이 SPM + CLT만으로 빌드
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="build/MacCleaner.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/MacCleaner "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"
[ -f AppIcon.icns ] || swift Tools/make-icon.swift
cp AppIcon.icns "$APP/Contents/Resources/"

# ad-hoc 서명 (개인 사용용)
codesign --force -s - "$APP"

echo "빌드 완료: $PWD/$APP"
echo "실행: open $PWD/$APP"
