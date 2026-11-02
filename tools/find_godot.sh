#!/usr/bin/env bash
# Sourced by the other tools/*.sh scripts. Sets $GODOT to a Godot executable.
#
# Uses $GODOT if set, else `godot` on PATH, else (Linux only) downloads Godot
# into ~/.cache/godot. On Windows, point GODOT at the *console* executable, e.g.
#   GODOT="/c/Godot/Godot_v4.7.2-stable_win64_console.exe" bash tools/run_tests.sh

GODOT_VERSION="${GODOT_VERSION:-4.7.2}"

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
export GODOT
