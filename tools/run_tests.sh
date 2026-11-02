#!/usr/bin/env bash
# Runs the headless test suite and a short smoke run of the main scene.
#
#   bash tools/run_tests.sh
#
# Uses $GODOT if set, else `godot` on PATH, else (Linux only) downloads Godot
# into ~/.cache/godot. On Windows, point GODOT at the *console* executable, e.g.
#   GODOT="/c/Godot/Godot_v4.7.2-stable_win64_console.exe" bash tools/run_tests.sh
set -euo pipefail

GODOT_VERSION="${GODOT_VERSION:-4.7.2}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ -z "${GODOT:-}" ]]; then
  if command -v godot >/dev/null 2>&1; then
    GODOT="godot"
  elif [[ "$(uname -s)" == "Linux" ]]; then
    CACHE="$HOME/.cache/godot"
    GODOT="$CACHE/Godot_v${GODOT_VERSION}-stable_linux.x86_64"
    if [[ ! -x "$GODOT" ]]; then
      echo "Downloading Godot ${GODOT_VERSION}..."
      mkdir -p "$CACHE"
      curl -sSL -o "$CACHE/godot.zip" \
        "https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip"
      unzip -q -o "$CACHE/godot.zip" -d "$CACHE"
      rm "$CACHE/godot.zip"
      chmod +x "$GODOT"
    fi
  else
    echo "Godot not found. Set GODOT to your Godot console executable." >&2
    exit 1
  fi
fi

LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT

echo "== Importing project"
"$GODOT" --headless --path "$ROOT" --import >"$LOG" 2>&1 || true

echo "== Unit tests"
"$GODOT" --headless --path "$ROOT" -s res://tests/test_runner.gd 2>&1 | tee -a "$LOG"
status=${PIPESTATUS[0]}

echo "== Smoke run of main scene (120 frames)"
"$GODOT" --headless --path "$ROOT" --quit-after 120 >>"$LOG" 2>&1 || true

if grep -E "SCRIPT ERROR|Parse Error|ERROR:" "$LOG" >/dev/null; then
  echo "Errors found:" >&2
  grep -E -A3 "SCRIPT ERROR|Parse Error|ERROR:" "$LOG" >&2
  exit 1
fi
if [[ $status -ne 0 ]]; then
  exit "$status"
fi
echo "All good."
