#!/bin/bash
# Catchtype macOS uninstaller
set -euo pipefail
launchctl bootout "gui/$(id -u)/app.catchtype.macos" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/app.catchtype.macos.plist"
sudo rm -f /usr/local/bin/catchtype 2>/dev/null || rm -f /usr/local/bin/catchtype 2>/dev/null || true
if [ -w /Applications ]; then rm -rf /Applications/CatchType.app; else sudo rm -rf /Applications/CatchType.app; fi
echo "[catchtype] 제거 완료 — 설정 파일은 남겨둠: ~/Library/Application Support/CatchType/"
