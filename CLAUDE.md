# Cube Idle — guide for Claude sessions

This project is worked on by **several different Claude sessions/accounts**, one after another.
You have no memory of earlier sessions: this file, `docs/PLAN.md`, `docs/ROADMAP.md`,
`docs/CHANGELOG.md`, `docs/FEEDBACK.md` and `docs/PLAYER_RESEARCH.md` are the shared memory. Read all of them before changing
anything, and update ROADMAP and CHANGELOG before you finish.

**Do one roadmap task per session** (the next unchecked one, unless the owner names one).
Handle open items in `docs/FEEDBACK.md` first. Never guess an open owner decision (PLAN §7): ask.

## What the game is
An idle/incremental game about Rubik's cubes, for PC (Windows first).
The player taps to turn a cube; every N moves completes a **solve**, and **Solves** are the currency.
Solves buy **helpers** (passive moves/sec) and **upgrades** (multipliers).
Full design: `docs/DESIGN.md`.

## Tech
- **Godot 4.7.x**, GDScript only (no C#). Renderer: GL Compatibility (runs on older PCs).
- Window 1280×720, `canvas_items` stretch.
- No plugins or addons yet. Don't add any without noting it in the CHANGELOG.

## Layout
```
project.godot              Engine config; autoload "Game" -> scripts/autoload/game.gd
scenes/main.tscn           The one screen (UI layout)
scenes/puzzle_view_3d.tscn The 3D puzzle (SubViewport > Puzzle tilt > Turntable > Bodies/Stickers MultiMeshes)
scripts/autoload/game.gd   class GameState: ALL rules, numbers, save/load, offline progress
scripts/data/content.gd    class Content: helpers + upgrades as plain data (balance here)
scripts/ui/main.gd         Main screen: reads Game, calls Game; no rules here
scripts/ui/puzzle_view_3d.gd  class PuzzleView3D: draws a TwistyModel; scramble_step/show_solved/set_puzzle/set_speed,
                           `tapped`; animated turn queue, solve replay, speed mode (see its header comment)
scripts/cube/twisty_model.gd   class TwistyModel: pure-data puzzle (pieces, layers, moves, WCA notation)
scripts/cube/puzzle_shapes.gd  class PuzzleShapes: builds models (from_id("3x3"), cube(2..7); megaminx() in 4.4), colours
scripts/cube/puzzle_meshes.gd  class PuzzleMeshes: rounded box + rounded sticker meshes (SurfaceTool)
scripts/ui/shaders/        stage_backdrop (radial glow) + contact_shadow .gdshader, used by PuzzleView3D
scripts/util/num.gd        class Num: number/time formatting (1.50K, 2h 1m)
scripts/util/graphics_config.gd  class GraphicsConfig: Graphics High/Low in user://settings.cfg (3.4 takes over)
tests/test_runner.gd       Headless tests (any func test_* runs automatically)
tools/run_tests.sh         Runs tests + a 120-frame smoke run of the main scene
tools/screenshot.sh        PNGs of the main scene in preset states (see "Screenshots" below)
tools/find_godot.sh        Shared by the tools/*.sh scripts: finds or downloads Godot
tools/simulate.sh          Balance bot (tools/simulator.gd) -> docs/BALANCE.md; run after any balance change
tools/pacing.gd            PLAN §2 pacing targets as data; tests fail if one is missed (or newly met, see below)
docs/                      PLAN (why/how), ROADMAP (tasks), CHANGELOG, FEEDBACK, DESIGN,
                           PLAYER_RESEARCH (what our player loves; tasks marked (PR) come from it)
```

## Rules of the code
1. **Game logic lives only in `game.gd`.** UI scripts read state and call public methods.
2. **Content is data.** A new helper/upgrade = a new entry in `content.gd`, not new code.
   New effect types go in `Content.EFFECT_TYPES` *and* are applied in `GameState`.
3. **Static typing everywhere** (`var x := 1.0`, `-> void`). Tabs for indentation.
4. Big numbers are `float`. Format all player-facing numbers with `Num.format()`.
5. **Save compatibility matters.** If you change the shape of `get_save_data()`, bump
   `SAVE_VERSION` and add a step in `_migrate()` so old saves still load.
6. Cost formula: `ceil(base_cost * 1.15 ^ owned)`. Offline progress is capped at 8 hours.
7. Keep scenes editable in the Godot editor: use `%UniqueName` nodes, no deep `get_node` paths.

## Before you finish (every session)
1. Run `bash tools/run_tests.sh` and make sure it prints `All good.`
   (On Linux it downloads Godot automatically. Elsewhere set `GODOT=/path/to/godot`.)
   Add or adjust tests in `tests/test_runner.gd` for any rule you changed.
   `test_pacing_targets` runs the balance bot (~10 s). Targets with an `expected_failure` in
   `tools/pacing.gd` may miss; if your change makes one pass, the test tells you to remove its mark.
   After any content/balance change, also run `bash tools/simulate.sh` and commit `docs/BALANCE.md`.
2. Tick off the task in `docs/ROADMAP.md`, but only if its "Done when" is true.
   Visual changes: add a screenshot to `docs/screenshots/` (see "Screenshots" below).
3. Add a dated entry at the top of `docs/CHANGELOG.md`: what changed, what's half-done,
   anything the next session should know.
4. Commit with a clear message. Pull `main` before you start. **Owner's rule: every commit is merged into
   `main` and pushed** (if your session has its own branch, push it, then fast-forward/merge it into `main`
   and push `main` too). No pull request needed. The next session (possibly another account) starts from `main`.

## Screenshots
You can't see the game window, so look at it this way (works in the cloud container):
```
bash tools/screenshot.sh docs/screenshots/<task-name>             # every preset
bash tools/screenshot.sh /tmp/shots mid late                      # only some presets
SIZE=1920x1080 bash tools/screenshot.sh docs/screenshots/1080p    # another resolution
PUZZLE=7x7 bash tools/screenshot.sh /tmp/shots mid                # another puzzle -> mid_7x7.png
POSE=turn bash tools/screenshot.sh /tmp/shots mid                 # frozen moment: turn | solved -> mid_turn.png
GRAPHICS=low bash tools/screenshot.sh /tmp/shots mid              # Graphics: Low -> mid_low.png
bash tools/screenshot.sh /tmp/shots bench                         # 7×7 at max speed: logs ms/frame for Low and High
```
- Writes `<dir>/<preset>.png` (default 1280×720), then open the PNGs with the Read tool to check them.
- It runs under `xvfb-run` with the real OpenGL 3 renderer (software Mesa, so it's slow but correct) and
  a throwaway user-data dir, so it never touches a real save.
- Presets (`fresh`, `mid`, `late`) are version-1 save data in `tools/screenshot_presets.gd`. They go through
  `_migrate()`, so they keep working after save-format changes. A test checks that they still load.
  Add a preset there when a new feature needs its own state (e.g. a puzzle tier or prestige).
- The economy is frozen during the shot, so numbers match the preset exactly. The cube is seeded, so
  before/after shots compare. `docs/screenshots/baseline/` is the look before Phase 1.
- New `class_name` scripts aren't known to Godot until an import runs (`run_tests.sh` does one). If a
  `-s` script can't find a class you just added, run `godot --headless --path . --import` first.
- `docs/` has a `.gdignore`, so Godot never imports these PNGs into the game. Keep committed PNGs small (< 300 KB each). Don't commit throwaway shots; put them in `/tmp` or a scratchpad.

## Debug keys (debug builds only)
- **F9**: +1000 Solves
- **F10**: wipe the save and restart from zero

The save file is `user://save.json`. On Windows that's
`%APPDATA%\Godot\app_userdata\Cube Idle\save.json`. Next to it: `save.bak` (the previous save),
and `save.corrupt.json` if a damaged save was ever found. Saves go through `save.json.tmp` + rename (task 0.4),
so never write the save file directly; call `Game.save_game()`.
