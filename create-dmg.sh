#!/bin/bash
# Abysso 배포용 DMG 패키징 스크립트
#
# 빌드된 Abysso.app을 표준 "드래그 설치" 레이아웃의 .dmg로 만든다:
#   왼쪽에 Abysso.app 아이콘 · 오른쪽에 /Applications 폴더 바로가기(Symlink).
#
# Homebrew의 create-dmg가 설치돼 있으면 그것을 사용하고,
# 없으면 macOS 내장 hdiutil + Finder AppleScript로 동일한 레이아웃을 구성한다.
#
#   설치(선택, 더 깔끔한 결과): brew install create-dmg
#   사용:                       ./create-dmg.sh
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Abysso"
APP="build/${APP_NAME}.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist 2>/dev/null || echo "1.0")
DMG="build/${APP_NAME}-${VERSION}.dmg"
VOL_NAME="${APP_NAME} ${VERSION}"

# DMG 창/아이콘 레이아웃 (창 약 500x300)
WIN_W=500
WIN_H=300
ICON_SIZE=100
APP_X=120;  APP_Y=150      # 왼쪽: 앱 아이콘
LINK_X=380; LINK_Y=150     # 오른쪽: Applications 바로가기

# 드래그 앤 드롭 안내 화살표가 그려진 커스텀 배경 (없으면 자동 생성)
BG="packaging/dmg-background.png"

# ---- 1. 앱 빌드 (항상 최신 상태로) ----
echo "▸ Abysso.app 빌드 중…"
./build-app.sh

# ---- 1-b. DMG 배경 이미지 준비 ----
if [ ! -f "$BG" ]; then
  echo "▸ DMG 배경 이미지 생성 중… (Tools/make-dmg-background.swift)"
  swift Tools/make-dmg-background.swift
fi

# ---- 2. 기존 DMG 및 잔여 마운트/스테이징 정리 ----
echo "▸ 이전 DMG·잔여물 정리 중…"
rm -f "$DMG"
MOUNT_DIR="/Volumes/${VOL_NAME}"
if [ -d "$MOUNT_DIR" ]; then
  hdiutil detach "$MOUNT_DIR" -force >/dev/null 2>&1 || true
fi

# ---- 3-A. Homebrew create-dmg 경로 ----
if command -v create-dmg >/dev/null 2>&1; then
  echo "▸ create-dmg(Homebrew)로 패키징…"
  STAGING="$(mktemp -d)"
  cp -R "$APP" "$STAGING/"
  # create-dmg가 --app-drop-link로 Applications 심볼릭 링크를 자동 생성한다.
  create-dmg \
    --volname "$VOL_NAME" \
    --background "$BG" \
    --window-pos 200 120 \
    --window-size "$WIN_W" "$WIN_H" \
    --icon-size "$ICON_SIZE" \
    --icon "${APP_NAME}.app" "$APP_X" "$APP_Y" \
    --app-drop-link "$LINK_X" "$LINK_Y" \
    --no-internet-enable \
    "$DMG" "$STAGING"
  rm -rf "$STAGING"
  echo "✅ 완료: $PWD/$DMG"
  exit 0
fi

# ---- 3-B. hdiutil 폴백 경로 ----
echo "▸ create-dmg 미설치 → 내장 hdiutil로 패키징 (설치 유도 레이아웃 포함)…"

STAGING="$(mktemp -d)"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"   # 오른쪽 드롭 대상
mkdir -p "$STAGING/.background"               # 안내 화살표 배경 (숨김 폴더)
cp "$BG" "$STAGING/.background/background.png"

TMP_DMG="build/${APP_NAME}-tmp.dmg"
rm -f "$TMP_DMG"

# 쓰기 가능(UDRW) 이미지로 먼저 생성 → 마운트 후 레이아웃 지정
hdiutil create \
  -srcfolder "$STAGING" \
  -volname "$VOL_NAME" \
  -fs HFS+ \
  -format UDRW \
  -ov "$TMP_DMG" >/dev/null

hdiutil attach "$TMP_DMG" -mountpoint "$MOUNT_DIR" -nobrowse -noautoopen >/dev/null

# Finder로 아이콘 위치·창 크기 지정 (자동화 권한이 없으면 이 단계만 건너뛰고 계속 진행)
osascript <<EOF 2>/dev/null || echo "  (Finder 자동화 권한이 없어 아이콘 배치는 건너뜀 — DMG 자체는 정상 생성됩니다)"
tell application "Finder"
  tell disk "${VOL_NAME}"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    -- {left, top, right, bottom} → 폭 ${WIN_W} x 높이 ${WIN_H}
    set the bounds of container window to {200, 120, $((200 + WIN_W)), $((120 + WIN_H))}
    set theViewOptions to the icon view options of container window
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to ${ICON_SIZE}
    set background picture of theViewOptions to file ".background:background.png"
    set position of item "${APP_NAME}.app" of container window to {${APP_X}, ${APP_Y}}
    set position of item "Applications" of container window to {${LINK_X}, ${LINK_Y}}
    close
    open
    update without registering applications
    delay 1
  end tell
end tell
EOF

sync
hdiutil detach "$MOUNT_DIR" -force >/dev/null 2>&1 || \
  hdiutil detach "$MOUNT_DIR" >/dev/null

# 압축 읽기 전용(UDZO)으로 변환 → 최종 배포 DMG
rm -f "$DMG"
hdiutil convert "$TMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
rm -f "$TMP_DMG"
rm -rf "$STAGING"

echo "✅ 완료: $PWD/$DMG"
