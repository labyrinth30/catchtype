#!/bin/bash
# Catchtype macOS 빌드 스크립트 — swift build 래퍼 (Xcode 없음).
#
# usage:
#   ./build.sh            # 빌드 + 테스트 (Test target은 Linux에서 건너뜀)
#   ./build.sh --test     # 빌드 + 테스트 강제
#   ./build.sh --release  # release 빌드만
set -euo pipefail
cd "$(dirname "$0")/.."

SWIFT_BIN="$(command -v swift || true)"
if [ -z "$SWIFT_BIN" ]; then
  for c in /usr/bin/swift /opt/homebrew/bin/swift; do
    [ -x "$c" ] && SWIFT_BIN="$c" && break
  done
fi
[ -z "$SWIFT_BIN" ] && { echo "[catchtype] swift 없음 — xcode-select --install"; exit 1; }

CONF=debug
for a in "$@"; do
  case "$a" in
    --test) CONF=debug ;;
    --release) CONF=release ;;
  esac
done

echo "== swift build -c $CONF =="
"$SWIFT_BIN" build -c "$CONF"
echo "== bin path =="
"$SWIFT_BIN" build -c "$CONF" --show-bin-path

if [[ " $* " == *" --test "* ]]; then
  echo "== swift test =="
  "$SWIFT_BIN" test -c debug
fi

echo "[catchtype] 빌드 완료."
