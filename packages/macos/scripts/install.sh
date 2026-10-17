#!/bin/bash
# Catchtype macOS CLI installer — packages/macos/scripts/install.sh
#
# 소유자의 Mac에서 1회 실행: 빌드 + /usr/local/bin 심볼릭 + LaunchAgent 등록.
# 앱은 swift build만으로 구동(NSSupports 變조 entry) — Xcode 프로젝트 불필요.
#
# usage:
#   chmod +x install.sh && ./install.sh          # 빌드 + CLI + LaunchAgent
#   UNINSTALL=1 ./install.sh                     # LaunchAgent 제거
#
set -euo pipefail

cd "$(dirname "$0")/.."   # packages/macos root

SWIFT_BIN="${SWIFT_BIN:-$(command -v swift || true)}"
if [ -z "$SWIFT_BIN" ]; then
  if [ -x "/usr/bin/swift" ]; then SWIFT_BIN="/usr/bin/swift";
  elif [ -x "/opt/homebrew/bin/swift" ]; then SWIFT_BIN="/opt/homebrew/bin/swift";
  else
    echo "[catchtype] swift 툴체인 없음 — Xcode Command Line Tools를 설치하세요:"
    echo "  xcode-select --install"
    exit 1
  fi
fi

echo "== [1/4] swift build (release) =="
"$SWIFT_BIN" build -c release
BIN_DIR="$(dirname "$SWIFT_BIN" | xargs dirname)/bin"   # toolchain-root/bin? 실제 경로는 swift build -v 로 확인
BUILD_BIN="$( "$SWIFT_BIN" build -c release --show-bin-path )"

echo "== [2/4] CLI 심볼릭 링크 =="
CLI_SRC="$BUILD_BIN/catchtype"
if [ ! -f "$CLI_SRC" ]; then echo "[catchtype] 빌드 산출에 catchtype CLI가 없습니다: $BUILD_BIN"; exit 1; fi
if [ -w /usr/local/bin ] 2>/dev/null; then
  ln -sf "$CLI_SRC" /usr/local/bin/catchtype
else
  echo "  /usr/local/bin 권한 없음 — sudo 필요:"
  sudo ln -sf "$CLI_SRC" /usr/local/bin/catchtype
fi
echo "  installed: $(readlink /usr/local/bin/catchtype || echo /usr/local/bin/catchtype)"

echo "== [3/4] 앱 번들 생성 (.app) =="
APP_DIR="$BUILD_BIN/CatchType.app/Contents/MacOS"
mkdir -p "$APP_DIR"
cp "$BUILD_BIN/CatchType" "$APP_DIR/CatchType"
cat > "$BUILD_BIN/CatchType.app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>CatchType</string>
    <key>CFBundleIdentifier</key><string>app.catchtype.macos</string>
    <key>CFBundleName</key><string>CatchType</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSAccessibilityUsageDescription</key>
    <string>키 입력의 한/영 상태를 판정해 교정하기 위해 손쉬운 사용 권한이 필요합니다.</string>
</dict>
</plist>
PLIST
APP_BUNDLE="$BUILD_BIN/CatchType.app"
# /Applications 복사 (기존 것 대체)
if [ -w /Applications ]; then
  rm -rf /Applications/CatchType.app
  cp -R "$APP_BUNDLE" /Applications/CatchType.app
  APP_BUNDLE_INSTALLED=/Applications/CatchType.app
else
  echo "  /Applications 권한 없음 — sudo 필요:"
  sudo rm -rf /Applications/CatchType.app
  sudo cp -R "$APP_BUNDLE" /Applications/CatchType.app
  APP_BUNDLE_INSTALLED=/Applications/CatchType.app
fi
echo "  installed: $APP_BUNDLE_INSTALLED"

echo "== [4/4] LaunchAgent 등록 (로그인 시 자동 시작) =="
LAUNCH_PLIST="$HOME/Library/LaunchAgents/app.catchtype.macos.plist"
cat > "$LAUNCH_PLIST" <<LAUNCH
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>app.catchtype.macos</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Applications/CatchType.app/Contents/MacOS/CatchType</string>
    </array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>ProcessType</key><string>Background</string>
    <key>StandardOutPath</key><string>/tmp/catchtype.log</string>
    <key>StandardErrorPath</key><string>/tmp/catchtype.err.log</string>
</dict>
</plist>
LAUNCH
launchctl bootout "gui/$(id -u)/app.catchtype.macos" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$LAUNCH_PLIST"
launchctl enable "gui/$(id -u)/app.catchtype.macos"
echo "  LaunchAgent: $LAUNCH_PLIST"

echo ""
echo "[catchtype] 설치 완료 — 첫 실행 시 손쉬운 사용 권한 얼럿이 뜬다."
echo "  - 권한 부여 후 앱 아이콘(⌨)를 클릭해 상태 확인"
echo "  - CLI 테스트:  echo 'dkssudgktpdy' | catchtype"
echo "  - First-run checklist: docs/FIRST-RUN-MACOS.md"
