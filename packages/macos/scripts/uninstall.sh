#!/bin/bash
# Remove only the installed app, its CLI link, and its login LaunchAgent.
set -euo pipefail
source "$(dirname "$0")/install-common.sh"
[ "$(uname -s)" = Darwin ] || { echo "[catchtype] macOS에서 실행하세요."; exit 1; }
launchctl bootout "gui/$(id -u)/app.catchtype.macos" 2>/dev/null || true
stop_installed_app
rm -f "$HOME/Library/LaunchAgents/app.catchtype.macos.plist"
CLI_LINK=/usr/local/bin/catchtype
if [ -L "$CLI_LINK" ]; then
  CLI_TARGET="$(readlink "$CLI_LINK")"
  if owns_cli_link "$CLI_TARGET"; then
    if [ -w /usr/local/bin ]; then rm -f "$CLI_LINK"; else sudo rm -f "$CLI_LINK"; fi
  else
    echo "[catchtype] 다른 설치가 소유한 링크 유지: $CLI_LINK"
  fi
fi
if [ -w /Applications ]; then rm -rf /Applications/CatchType.app; else sudo rm -rf /Applications/CatchType.app; fi
echo "[catchtype] 제거 완료 — 설정 파일 유지: ~/Library/Application Support/CatchType/"
