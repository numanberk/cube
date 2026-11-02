#!/usr/bin/env bash
# Renders the main scene in preset game states and saves PNGs.
#
#   bash tools/screenshot.sh <out_dir> [preset ...]      # default: every preset
#   SIZE=1920x1080 bash tools/screenshot.sh docs/screenshots/1080p
#
# Presets live in tools/screenshot_presets.gd (fresh, mid, late, ...).
# Output: <out_dir>/<preset>.png at $SIZE (default 1280x720).
#
# Linux: runs under xvfb-run with the real OpenGL 3 renderer (software Mesa in the
# cloud container), so it works without a display. Elsewhere it opens a window briefly.
# Godot gets a throwaway user-data dir, so your real save is never read or touched.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/tools/find_godot.sh"

if [[ $# -lt 1 ]]; then
  echo "Usage: bash tools/screenshot.sh <out_dir> [preset ...]" >&2
  exit 2
fi
OUT_DIR="$1"
shift
mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"
SIZE="${SIZE:-1280x720}"

if [[ $# -gt 0 ]]; then
  PRESETS=("$@")
else
  # Every key of the PRESETS dictionary (lines like `	"name": {`).
  mapfile -t PRESETS < <(sed -nE 's/^\t"([a-z0-9_]+)": \{.*/\1/p' "$ROOT/tools/screenshot_presets.gd")
fi

SANDBOX="$(mktemp -d)"
LOG="$SANDBOX/godot.log"
trap 'rm -rf "$SANDBOX"' EXIT
# user:// resolves under XDG_DATA_HOME on Linux, so this keeps the real save safe.
export XDG_DATA_HOME="$SANDBOX/data" XDG_CONFIG_HOME="$SANDBOX/config" XDG_CACHE_HOME="$SANDBOX/cache"

if [[ ! -d "$ROOT/.godot" ]]; then
  echo "== Importing project"
  "$GODOT" --headless --path "$ROOT" --import >/dev/null 2>&1 || true
fi

RUN=()
if [[ "$(uname -s)" == "Linux" ]]; then
  if ! command -v xvfb-run >/dev/null 2>&1; then
    echo "xvfb-run not found (apt install xvfb)." >&2
    exit 1
  fi
  RUN=(xvfb-run -a -s "-screen 0 ${SIZE}x24")
fi

failed=0
for preset in "${PRESETS[@]}"; do
  out="$OUT_DIR/$preset.png"
  rm -f "$out"
  "${RUN[@]}" "$GODOT" --path "$ROOT" --rendering-driver opengl3 --audio-driver Dummy --resolution "$SIZE" \
    --windowed --position 0,0 res://tools/screenshot.tscn -- --preset "$preset" --out "$out" \
    >"$LOG" 2>&1 || true
  if [[ -f "$out" ]] && ! grep -qE "SCRIPT ERROR|Parse Error|ERROR:" "$LOG"; then
    grep "^Saved " "$LOG" || echo "Saved $out"
  else
    echo "FAILED: preset '$preset'" >&2
    cat "$LOG" >&2
    failed=1
  fi
done
exit "$failed"
