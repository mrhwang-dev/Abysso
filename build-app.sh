#!/bin/bash
# Abysso.app 빌드 스크립트 — Xcode 없이 SPM + CLT만으로 빌드
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="build/Abysso.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp .build/release/Abysso "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"
[ -f AppIcon.icns ] || swift Tools/make-icon.swift
cp AppIcon.icns "$APP/Contents/Resources/"

# ---- 다국어 리소스(.lproj) 임베드 (ko / en / ja) ----
# Bundle.main이 사용자 Mac 언어에 맞는 Localizable.strings를 자동 선택한다.
for lproj in Resources/*.lproj; do
  [ -d "$lproj" ] && cp -R "$lproj" "$APP/Contents/Resources/"
done
echo "다국어 리소스 임베드 완료: $(ls -d Resources/*.lproj 2>/dev/null | xargs -n1 basename | tr '\n' ' ')"

# ---- Sparkle.framework 임베드 (동적 프레임워크) ----
SPARKLE_FW=$(find .build/artifacts -type d -name "Sparkle.framework" -path "*macos*" 2>/dev/null | head -1)
if [ -n "$SPARKLE_FW" ]; then
  # 심볼릭 링크/버전 구조를 보존하며 복사
  ditto "$SPARKLE_FW" "$APP/Contents/Frameworks/Sparkle.framework"
  # 실행 파일이 Contents/Frameworks에서 프레임워크를 찾도록 rpath 추가
  if ! otool -l "$APP/Contents/MacOS/Abysso" | grep -q "@executable_path/../Frameworks"; then
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/Abysso"
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

# ---- /Applications 자동 동기화 ----
# 빌드가 여기까지 왔다면(set -e) 성공한 것 — 설치본을 항상 최신으로 유지한다.
# 건너뛰려면: ABYSSO_SKIP_INSTALL=1 ./build-app.sh
if [ "${ABYSSO_SKIP_INSTALL:-0}" != "1" ]; then
  INSTALLED="/Applications/Abysso.app"
  # 실행 중이면 파일이 잠기지 않도록 먼저 정상 종료 요청
  osascript -e 'quit app "Abysso"' >/dev/null 2>&1 || true
  sleep 1
  rm -rf "$INSTALLED"
  cp -R "$APP" "$INSTALLED"
  echo "동기화 완료: $INSTALLED (최신 빌드로 교체됨)"
fi
echo "실행: open /Applications/Abysso.app"
