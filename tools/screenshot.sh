#!/usr/bin/env bash
# Renders the main scene in preset game states and saves PNGs.
#
#   bash tools/screenshot.sh <out_dir> [preset ...]      # default: every preset
#   SIZE=1920x1080 bash tools/screenshot.sh docs/screenshots/1080p
#   PUZZLE=5x5 bash tools/screenshot.sh /tmp/shots mid     # show another puzzle -> mid_5x5.png
#   POSE=turn bash tools/screenshot.sh /tmp/shots mid      # freeze a moment: turn | solved -> mid_turn.png
#   GRAPHICS=low bash tools/screenshot.sh /tmp/shots mid   # Graphics: Low -> mid_low.png
#   TAB=1 bash tools/screenshot.sh /tmp/shots mid          # open shop tab 1 (Upgrades) -> mid_tab1.png
#   JUICE=1 bash tools/screenshot.sh /tmp/shots mid        # taps + a solve pop mid-animation -> mid_juice.png
#   BANNER=puzzle bash tools/screenshot.sh /tmp/shots mid  # a big-moment banner: puzzle|helper|method|champion (V.7)
#   BUY=10 bash tools/screenshot.sh /tmp/shots mid         # shop on x10 (-1 = Max) -> mid_buy10.png
#   SETTINGS=1 bash tools/screenshot.sh /tmp/shots mid     # with the Settings panel open -> mid_settings.png
#   SOLVE=done bash tools/screenshot.sh /tmp/shots mid     # Solve Station: inspecting | solving | done -> mid_solvedone.png
#   SHOWCASE=20 bash tools/screenshot.sh /tmp/shots mid    # the main cube's showcase solve 20 moves in -> mid_showcase20.png
#   METHOD=beginner SHOWCASE=40 bash tools/screenshot.sh /tmp/shots mid  # ...with another method -> mid_showcase40_beginner.png
#   KEYS=simple SOLVE=solving bash tools/screenshot.sh /tmp/shots mid    # Solve Station, simple keys -> mid_solvesolving_keyssimple.png
#   NEWS=1 bash tools/screenshot.sh /tmp/shots mid         # a few news feed lines -> mid_news.png
#   GOLDEN=glow bash tools/screenshot.sh /tmp/shots mid     # Golden Scramble: glow | case | known (a learned PLL case, 7.13) | buff -> mid_goldenglow.png
#   FLOW=1 bash tools/screenshot.sh /tmp/shots mid          # Flow running after a Gold hand solve -> mid_flow.png
#   DRILL=done bash tools/screenshot.sh /tmp/shots mid      # a PLL drill: solving | done -> mid_drilldone.png
#   DAILY=fmc bash tools/screenshot.sh /tmp/shots mid       # the daily scramble: fmc | timed -> mid_dailyfmc.png
#   SCROLL=1 bash tools/screenshot.sh /tmp/shots endgame    # the helper list scrolled to the bottom -> endgame_scroll.png
#   LAB=1 bash tools/screenshot.sh /tmp/shots mid           # the Lab tab, one project done and one running -> mid_lab.png
#   PICK=speed_practice bash tools/screenshot.sh /tmp/shots mid  # a choice made (5.7b), Upgrades tab -> mid_pickspeed_practice.png
#   COMPETE=1 bash tools/screenshot.sh /tmp/shots endgame  # the Compete screen open (6.1) -> endgame_compete.png
#   COMPETE=won bash tools/screenshot.sh /tmp/shots endgame  # just after a championship (6.2) -> endgame_competewon.png
#   PERKS=1 bash tools/screenshot.sh /tmp/shots endgame    # the trophy perk tree open (6.3) -> endgame_perks.png
#   AUTO=1 bash tools/screenshot.sh /tmp/shots endgame     # the shop's Auto tab (6.3b) -> endgame_auto.png
#   GOALS=achievements bash tools/screenshot.sh /tmp/shots endgame  # the Goals screen: achievements|collection|stats|kit (7.1b-7.4b) -> endgame_goalsachievements.png
#   TOAST=career bash tools/screenshot.sh /tmp/shots mid   # a small pop: career|achievement|drop|set (7.0b/7.1b/7.3b) -> mid_toastcareer.png
#   TURNS=1 bash tools/screenshot.sh /tmp/shots mid         # your own key turns on the main cube + streak (S.7) -> mid_turns.png
#   GALLERY=all bash tools/screenshot.sh /tmp/shots       # the style gallery (V.0): kit | parts | all -> gallery_kit.png
#   GALLERY=kit FONT=/path/Rubik.ttf bash tools/screenshot.sh /tmp/shots  # ...with a candidate display font -> gallery_kit_Rubik.png
#   bash tools/screenshot.sh /tmp/shots bench              # 7×7 at max speed, 600 frames per quality, logs frame times
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
PUZZLE="${PUZZLE:-}"
POSE="${POSE:-}"
GRAPHICS="${GRAPHICS:-}"
TAB="${TAB:-}"
JUICE="${JUICE:-}"
BANNER="${BANNER:-}"
BUY="${BUY:-}"
SETTINGS="${SETTINGS:-}"
SOLVE="${SOLVE:-}"
SHOWCASE="${SHOWCASE:-}"
METHOD="${METHOD:-}"
KEYS="${KEYS:-}"
NEWS="${NEWS:-}"
GOLDEN="${GOLDEN:-}"
FLOW="${FLOW:-}"
DRILL="${DRILL:-}"
DAILY="${DAILY:-}"
SCROLL="${SCROLL:-}"
LAB="${LAB:-}"
PICK="${PICK:-}"
COMPETE="${COMPETE:-}"
PERKS="${PERKS:-}"
AUTO="${AUTO:-}"
TURNS="${TURNS:-}"
GOALS="${GOALS:-}"
TOAST="${TOAST:-}"
GALLERY="${GALLERY:-}"
FONT="${FONT:-}"

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
if [[ -n "$GALLERY" ]]; then
  # The style gallery (task V.0, scripts/dev/style_gallery.gd): no presets, no game state; one PNG per page.
  if [[ "$GALLERY" == "all" ]]; then PAGES=(kit parts); else PAGES=("$GALLERY"); fi
  font_tag=""
  if [[ -n "$FONT" ]]; then
    [[ -f "$FONT" ]] || { echo "FONT not found: $FONT" >&2; exit 2; }
    FONT="$(cd "$(dirname "$FONT")" && pwd)/$(basename "$FONT")"
    font_tag="_$(basename "${FONT%.*}" | tr -c 'A-Za-z0-9_\n-' '_')"
  fi
  for page in "${PAGES[@]}"; do
    out="$OUT_DIR/gallery_$page$font_tag.png"
    rm -f "$out"
    # timeout: a script that fails to parse leaves the scene running forever instead of quitting.
    timeout 300 "${RUN[@]}" "$GODOT" --path "$ROOT" --rendering-driver opengl3 --audio-driver Dummy --resolution "$SIZE" \
      --windowed --position 0,0 res://scenes/dev/style_gallery.tscn -- --page "$page" --out "$out" ${FONT:+--font "$FONT"} \
      >"$LOG" 2>&1 || true
    if [[ -f "$out" ]] && ! grep -qE "SCRIPT ERROR|Parse Error|ERROR:" "$LOG"; then
      grep "^Saved " "$LOG" || echo "Saved $out"
    else
      echo "FAILED: gallery page '$page'" >&2
      cat "$LOG" >&2
      failed=1
    fi
  done
  exit "$failed"
fi
for preset in "${PRESETS[@]}"; do
  out="$OUT_DIR/$preset${PUZZLE:+_$PUZZLE}${POSE:+_$POSE}${GRAPHICS:+_$GRAPHICS}${TAB:+_tab$TAB}${JUICE:+_juice}${BUY:+_buy$BUY}${SETTINGS:+_settings}${SOLVE:+_solve$SOLVE}${SHOWCASE:+_showcase$SHOWCASE}${METHOD:+_$METHOD}${KEYS:+_keys$KEYS}${NEWS:+_news}${GOLDEN:+_golden$GOLDEN}${FLOW:+_flow}${DRILL:+_drill$DRILL}${DAILY:+_daily$DAILY}${SCROLL:+_scroll}${LAB:+_lab}${PICK:+_pick$PICK}${COMPETE:+_compete${COMPETE#1}}${PERKS:+_perks}${AUTO:+_auto}${TURNS:+_turns}${BANNER:+_banner$BANNER}${GOALS:+_goals$GOALS}${TOAST:+_toast$TOAST}.png"
  rm -f "$out"
  "${RUN[@]}" "$GODOT" --path "$ROOT" --rendering-driver opengl3 --audio-driver Dummy --resolution "$SIZE" \
    --windowed --position 0,0 res://tools/screenshot.tscn -- --preset "$preset" --out "$out" ${PUZZLE:+--puzzle "$PUZZLE"} ${POSE:+--pose "$POSE"} ${GRAPHICS:+--graphics "$GRAPHICS"} ${TAB:+--tab "$TAB"} ${JUICE:+--juice 1} ${BUY:+--buy "$BUY"} ${SETTINGS:+--settings 1} ${SOLVE:+--solve "$SOLVE"} ${SHOWCASE:+--showcase "$SHOWCASE"} ${METHOD:+--method "$METHOD"} ${KEYS:+--keys "$KEYS"} ${NEWS:+--news 1} ${GOLDEN:+--golden "$GOLDEN"} ${FLOW:+--flow 1} ${DRILL:+--drill "$DRILL"} ${DAILY:+--daily "$DAILY"} ${SCROLL:+--scroll 1} ${LAB:+--lab 1} ${PICK:+--pick "$PICK"} ${COMPETE:+--compete "$COMPETE"} ${PERKS:+--perks 1} ${AUTO:+--auto 1} ${TURNS:+--turns 1} ${BANNER:+--banner "$BANNER"} ${GOALS:+--goals "$GOALS"} ${TOAST:+--toast "$TOAST"} \
    >"$LOG" 2>&1 || true
  if [[ -f "$out" ]] && ! grep -qE "SCRIPT ERROR|Parse Error|ERROR:" "$LOG"; then
    grep "^Bench " "$LOG" || true
    grep "^Saved " "$LOG" || echo "Saved $out"
  else
    echo "FAILED: preset '$preset'" >&2
    cat "$LOG" >&2
    failed=1
  fi
done
exit "$failed"
