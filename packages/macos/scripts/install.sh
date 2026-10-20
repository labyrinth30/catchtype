#!/bin/bash
# Build, sign, and install the app, its bundled CLI, and a login LaunchAgent.
set -euo pipefail
source "$(dirname "$0")/install-common.sh"
cd "$PACKAGE_ROOT"

[ "$(uname -s)" = Darwin ] || { echo "[catchtype] macOS에서 실행하세요."; exit 1; }
SWIFT_BIN="${SWIFT_BIN:-$(command -v swift || true)}"
[ -n "$SWIFT_BIN" ] || { echo "[catchtype] swift 없음 — xcode-select --install"; exit 1; }

echo "== [1/4] swift build (release) =="
"$SWIFT_BIN" build -c release
BUILD_BIN="$("$SWIFT_BIN" build -c release --show-bin-path)"
for binary in catchtype CatchTypeApp; do
  [ -x "$BUILD_BIN/$binary" ] || { echo "[catchtype] 실행 파일 없음: $BUILD_BIN/$binary"; exit 1; }
done

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
APP_BUNDLE="$STAGING/CatchType.app"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Helpers"
cp "$BUILD_BIN/CatchTypeApp" "$APP_BUNDLE/Contents/MacOS/CatchType"
# Keep the CLI outside MacOS/: CatchType and catchtype collide on default macOS filesystems.
cp "$BUILD_BIN/catchtype" "$APP_BUNDLE/Contents/Helpers/catchtype"
cat > "$APP_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleExecutable</key><string>CatchType</string>
    <key>CFBundleIdentifier</key><string>app.catchtype.macos</string>
    <key>CFBundleName</key><string>CatchType</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.1.1</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSAccessibilityUsageDescription</key>
    <string>키 입력의 한/영 상태를 판정해 교정하기 위해 손쉬운 사용 권한이 필요합니다.</string>
</dict></plist>
PLIST
plutil -lint "$APP_BUNDLE/Contents/Info.plist"
codesign --force --sign - "$APP_BUNDLE/Contents/Helpers/catchtype"
codesign --force --sign - "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"

# Request elevation only for destinations this user cannot write.
app_cmd() { if [ -w /Applications ]; then "$@"; else sudo "$@"; fi; }
cli_cmd() { if [ -w /usr/local/bin ]; then "$@"; else sudo "$@"; fi; }
CLI_LINK=/usr/local/bin/catchtype
if [ -e "$CLI_LINK" ] && [ ! -L "$CLI_LINK" ]; then
  echo "[catchtype] 기존 일반 파일을 덮어쓰지 않습니다: $CLI_LINK"
  exit 1
fi

CLI_PREVIOUS="$(readlink "$CLI_LINK" || true)"
if [ -L "$CLI_LINK" ] && ! owns_cli_link "$CLI_PREVIOUS"; then
  echo "[catchtype] 다른 설치가 소유한 링크를 덮어쓰지 않습니다: $CLI_LINK → $CLI_PREVIOUS"
  exit 1
fi
LAUNCH_PLIST="$HOME/Library/LaunchAgents/app.catchtype.macos.plist"
if [ -f "$LAUNCH_PLIST" ]; then cp "$LAUNCH_PLIST" "$STAGING/previous.plist"; fi
APP_REPLACED=0
CLI_REPLACED=0
PLIST_REPLACED=0

echo "== [2/4] 앱 번들 설치 =="
# Stage on the destination filesystem before touching the working installation.
DEST_STAGE="$(app_cmd mktemp -d /Applications/.catchtype.XXXXXX)"
rollback() {
  if [ "$APP_REPLACED" = 1 ]; then app_cmd rm -rf /Applications/CatchType.app; fi
  if [ -d "$DEST_STAGE/previous.app" ]; then
    app_cmd mv "$DEST_STAGE/previous.app" /Applications/CatchType.app
  fi
  if [ "$CLI_REPLACED" = 1 ]; then
    if [ -n "$CLI_PREVIOUS" ]; then cli_cmd ln -sfn "$CLI_PREVIOUS" "$CLI_LINK";
    else cli_cmd rm -f "$CLI_LINK"; fi
  fi
  if [ "$PLIST_REPLACED" = 1 ]; then
    launchctl bootout "gui/$(id -u)/app.catchtype.macos" 2>/dev/null || true
    if [ -f "$STAGING/previous.plist" ]; then cp "$STAGING/previous.plist" "$LAUNCH_PLIST";
    else rm -f "$LAUNCH_PLIST"; fi
  fi
  if [ -f "$LAUNCH_PLIST" ]; then
    launchctl bootstrap "gui/$(id -u)" "$LAUNCH_PLIST" 2>/dev/null || true
  fi
  app_cmd rm -rf "$DEST_STAGE"
  rm -rf "$STAGING"
}
trap rollback EXIT
app_cmd ditto "$APP_BUNDLE" "$DEST_STAGE/CatchType.app"
launchctl bootout "gui/$(id -u)/app.catchtype.macos" 2>/dev/null || true
stop_installed_app
if [ -e /Applications/CatchType.app ]; then
  app_cmd mv /Applications/CatchType.app "$DEST_STAGE/previous.app"
fi
app_cmd mv "$DEST_STAGE/CatchType.app" /Applications/CatchType.app
APP_REPLACED=1

echo "== [3/4] CLI 링크 설치 =="
cli_cmd mkdir -p /usr/local/bin
cli_cmd ln -sfn /Applications/CatchType.app/Contents/Helpers/catchtype "$CLI_LINK"
CLI_REPLACED=1

echo "== [4/4] LaunchAgent 등록 =="
mkdir -p "$(dirname "$LAUNCH_PLIST")"
cat > "$STAGING/launch.plist" <<'LAUNCH'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>Label</key><string>app.catchtype.macos</string>
    <key>ProgramArguments</key><array><string>/Applications/CatchType.app/Contents/MacOS/CatchType</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
    <key>ProcessType</key><string>Background</string>
    <key>StandardOutPath</key><string>/tmp/catchtype.log</string>
    <key>StandardErrorPath</key><string>/tmp/catchtype.err.log</string>
</dict></plist>
LAUNCH
plutil -lint "$STAGING/launch.plist"
cp "$STAGING/launch.plist" "$LAUNCH_PLIST"
PLIST_REPLACED=1
launchctl enable "gui/$(id -u)/app.catchtype.macos"
launchctl bootstrap "gui/$(id -u)" "$LAUNCH_PLIST"
# Installation is complete; remove the previous version only after registration succeeds.
app_cmd rm -rf "$DEST_STAGE"
trap 'rm -rf "$STAGING"' EXIT

echo "[catchtype] 설치 완료: /Applications/CatchType.app"
echo "  첫 실행: 시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용 → CatchType 허용"
echo "  CLI: echo 'dkssudgktpdy' | /usr/local/bin/catchtype"
echo "  체크리스트: docs/FIRST-RUN-MACOS.md"
