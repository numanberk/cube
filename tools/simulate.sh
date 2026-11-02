#!/usr/bin/env bash
# Runs the headless balance bot (tools/simulator.gd) and writes a Markdown report.
#
#   bash tools/simulate.sh                                  # 3 and 0 taps/s, 120 min -> docs/BALANCE.md
#   bash tools/simulate.sh --taps 5 --minutes 60 --out /tmp/balance.md
#
# --taps takes a comma list (one run per value). --out is a res:// path or an absolute path.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/tools/find_godot.sh"

if [[ ! -d "$ROOT/.godot" ]]; then
  "$GODOT" --headless --path "$ROOT" --import >/dev/null 2>&1 || true
fi

LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT
"$GODOT" --headless --path "$ROOT" -s res://tools/simulate.gd -- "$@" 2>&1 | tee "$LOG"
status=${PIPESTATUS[0]}
if grep -E "SCRIPT ERROR|Parse Error|ERROR:" "$LOG" >/dev/null; then
  exit 1
fi
exit "$status"
