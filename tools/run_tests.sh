#!/usr/bin/env bash
# Runs the headless test suite and a short smoke run of the main scene.
#
#   bash tools/run_tests.sh
#
# Finds Godot via tools/find_godot.sh (set $GODOT to override).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/tools/find_godot.sh"

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
