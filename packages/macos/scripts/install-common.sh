#!/bin/bash
# Shared ownership and process checks for install/uninstall.
PACKAGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
INSTALLED_EXECUTABLE=/Applications/CatchType.app/Contents/MacOS/CatchType

owns_cli_link() {
  case "$1" in
    /Applications/CatchType.app/Contents/Helpers/catchtype|"$PACKAGE_ROOT"/.build/*/catchtype) return 0 ;;
    *) return 1 ;;
  esac
}

stop_installed_app() {
  local pid owner executable attempt processes
  processes="$(ps -ww -axo pid=,uid=,comm=)" || return 1
  # comm is the executable path (without arguments), so debug builds and other users are excluded.
  while read -r pid owner executable; do
    [ "$owner" = "$(id -u)" ] && [ "$executable" = "$INSTALLED_EXECUTABLE" ] || continue
    executable="$(ps -ww -p "$pid" -o comm= 2>/dev/null || true)"
    [ "$executable" = "$INSTALLED_EXECUTABLE" ] || continue
    /bin/kill -TERM "$pid" 2>/dev/null || true
    for ((attempt=0; attempt<50; attempt++)); do
      executable="$(ps -ww -p "$pid" -o comm= 2>/dev/null || true)"
      [ "$executable" = "$INSTALLED_EXECUTABLE" ] || break
      sleep 0.1
    done
    if [ "$executable" = "$INSTALLED_EXECUTABLE" ]; then
      echo "[catchtype] 설치된 앱이 종료되지 않았습니다 (pid=$pid). 설치/제거를 중단합니다."
      return 1
    fi
  done <<< "$processes"
}
