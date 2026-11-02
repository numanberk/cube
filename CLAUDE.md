# Cube Idle — guide for Claude sessions

This project is worked on by **several different Claude sessions/accounts**, one after another.
You have no memory of earlier sessions: this file, `docs/PLAN.md`, `docs/ROADMAP.md`,
`docs/CHANGELOG.md` and `docs/FEEDBACK.md` are the shared memory. Read all of them before changing
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
scripts/autoload/game.gd   class GameState: ALL rules, numbers, save/load, offline progress
scripts/data/content.gd    class Content: helpers + upgrades as plain data (balance here)
scripts/ui/main.gd         Main screen: reads Game, calls Game; no rules here
scripts/ui/cube_view.gd    class CubeView: draws the cube face
scripts/util/num.gd        class Num: number/time formatting (1.50K, 2h 1m)
tests/test_runner.gd       Headless tests (any func test_* runs automatically)
tools/run_tests.sh         Runs tests + a 120-frame smoke run of the main scene
docs/                      PLAN (why/how), ROADMAP (tasks), CHANGELOG, FEEDBACK, DESIGN
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
2. Tick off the task in `docs/ROADMAP.md`, but only if its "Done when" is true.
   Visual changes: add a screenshot to `docs/screenshots/` (see task 0.1).
3. Add a dated entry at the top of `docs/CHANGELOG.md`: what changed, what's half-done,
   anything the next session should know.
4. Commit with a clear message. Pull before you start and push when you're done,
   so the next session (possibly another account) starts from your work.

## Debug keys (debug builds only)
- **F9**: +1000 Solves
- **F10**: wipe the save and restart from zero

The save file is `user://save.json`. On Windows that's
`%APPDATA%\Godot\app_userdata\Cube Idle\save.json`.
