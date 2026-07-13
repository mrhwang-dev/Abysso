#!/bin/bash
# Cleanova.app 빌드 스크립트 — Xcode 없이 SPM + CLT만으로 빌드
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="build/Cleanova.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp .build/release/Cleanova "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"
[ -f AppIcon.icns ] || swift Tools/make-icon.swift
cp AppIcon.icns "$APP/Contents/Resources/"

# ---- Sparkle.framework 임베드 (동적 프레임워크) ----
SPARKLE_FW=$(find .build/artifacts -type d -name "Sparkle.framework" -path "*macos*" 2>/dev/null | head -1)
if [ -n "$SPARKLE_FW" ]; then
  # 심볼릭 링크/버전 구조를 보존하며 복사
  ditto "$SPARKLE_FW" "$APP/Contents/Frameworks/Sparkle.framework"
  # 실행 파일이 Contents/Frameworks에서 프레임워크를 찾도록 rpath 추가
  if ! otool -l "$APP/Contents/MacOS/Cleanova" | grep -q "@executable_path/../Frameworks"; then
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/Cleanova"
  fi
  # Sparkle 내부 번들(XPC 서비스, Autoupdate, Updater.app)까지 ad-hoc 서명
  codesign --force --deep --sign - "$APP/Contents/Frameworks/Sparkle.framework"
  echo "Sparkle.framework 임베드 완료"
else
  echo "경고: Sparkle.framework를 찾지 못했습니다 (swift package resolve 필요)"
fi

# ad-hoc 서명 (개인 사용용) — 프레임워크 서명 후 앱 본체 서명
codesign --force -s - "$APP"

echo "빌드 완료: $PWD/$APP"
echo "실행: open $PWD/$APP"
