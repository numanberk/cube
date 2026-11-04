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
project.godot              Engine config; autoloads "Game", "Audio", "Settings" (in that order); input action "tap"
default_bus_layout.tres    Audio buses: Master > Music, SFX
scenes/main.tscn           The one screen (UI layout)
ui/theme.tres              Project theme: Inter font, colours, button/tab/bar styles, type variations (see rule 8)
assets/                    fonts/ (Inter, OFL) and later audio/, images/; every file listed in assets/CREDITS.md
scenes/puzzle_view_3d.tscn The 3D puzzle (SubViewport > Puzzle tilt > Turntable > Bodies/Stickers MultiMeshes)
scripts/autoload/game.gd   class GameState: ALL rules, numbers, save/load, offline progress
scripts/autoload/audio.gd  class AudioManager ("Audio"): play_click/solve/buy/unlock (rate-limited), bus volumes,
                           music (Content.TRACKS; 2 players crossfading 2 s; follow/shuffle/loop; ducks when unfocused)
scripts/autoload/settings.gd  class GameSettings ("Settings"): every setting in user://settings.cfg (SPEC), get/set_value,
                           `changed` signal; applies audio + notation itself, main.gd applies graphics + reduce motion
scenes/welcome_panel.tscn  class WelcomePanel: "Welcome back" (time away, +Solves, Collect) and damaged-save notices
scenes/compete_panel.tscn  class CompetePanel: the Compete screen (6.1): trophies you'd win, bonus before/after, next
                           trophy, keep/reset lists (Content.CHAMPIONSHIP); display only, main.gd plays "Finals" meanwhile
scenes/settings_panel.tscn class SettingsPanel: sound, music mode, Jukebox, graphics, reduce motion, notation, reset save
scenes/solve_station.tscn  class SolveStation (scripts/ui/solve_station.gd): the "Solve it yourself" overlay: keyboard
                           solving (csTimer or simple keys), drag-to-turn, key hints on the cube, scramble, inspection,
                           timer, records panel (Phase S; records
                           themselves live in GameState: record_hand_solve, get_solve_bests, ...)
scripts/data/content.gd    class Content: helpers + upgrades as plain data (balance here)
scripts/ui/main.gd         Main screen: reads Game, calls Game; no rules here
scenes/shop_card.tscn      class ShopCard (scripts/ui/shop_card.gd): one helper row; set_view({...}), display only
scenes/upgrade_tile.tscn   class UpgradeTile (scripts/ui/upgrade_tile.gd): one upgrade icon tile + tooltip panel
scenes/puzzle_chip.tscn    class PuzzleChip: one card in the puzzle row (small Low-quality PuzzleView3D, name, Solves/s,
                           share) or the next locked puzzle (padlock, cost, Unlock button)
scripts/ui/news_feed.gd    class NewsFeed (main.news): the news feed under the shop (R.4): GameState events -> lines,
                           one per ~1.2 s, repeats merged, last 20 kept (%NewsList). Pure data, tested with fake time
scripts/ui/split_panel.gd  class SplitPanel (%SplitPanel, the shop's "Puzzles" tab): per-puzzle share −/+ and presets
scripts/ui/fx_layer.gd     class FxLayer (%FxLayer in main.tscn): pooled floating "+N" texts (max 20) + solve particle burst
scripts/ui/puzzle_view_3d.gd  class PuzzleView3D: draws a TwistyModel; scramble_step/show_solved/set_puzzle/set_speed,
                           `tapped`; animated turn queue, solve replay, speed mode (see its header comment)
scripts/cube/twisty_model.gd   class TwistyModel: pure-data puzzle (pieces, layers, moves, WCA notation)
scripts/cube/puzzle_shapes.gd  class PuzzleShapes: builds models (from_id("3x3"), cube(2..7), megaminx()), palette(model)
scripts/cube/puzzle_meshes.gd  class PuzzleMeshes: rounded box + rounded sticker (cubes), shaped_piece() (Megaminx)
scripts/cube/solve_session.gd  class SolveSession: Solve Station rules (scramble, WCA inspection, timer, keys -> moves,
                           big-cube hands, session averages). Pure data; keys are Content.SOLVE_KEYS
scripts/cube/staged_solver.gd  class StagedSolver: solves a 2×2/3×3 like a person, in named stages (Beginner, CFOP:
                           cross, F2L 1-4, OLL, PLL) for the showcase solve (R.2). Pure data; algorithms are
                           Content.ALGORITHMS (shared with S.4). Call StagedSolver.warm_up() before the first solve
scripts/cube/showcase_solve.gd class ShowcaseSolve: the main cube's showcase solve (R.2): scramble, inspection, then a
                           StagedSolver solve one move at a time (advance(delta, tps) / tap()); main.gd feeds the moves to
                           PuzzleView3D's manual mode and draws the stage chips (%StageChips) + ticker (%MoveTicker)
scripts/ui/shaders/        stage_backdrop (radial glow) + contact_shadow .gdshader, used by PuzzleView3D
scripts/util/num.gd        class Num: number/time formatting (1.50K, 2h 1m)
tests/test_runner.gd       Headless tests (any func test_* runs automatically)
tools/run_tests.sh         Runs tests + a 120-frame smoke run of the main scene
tools/screenshot.sh        PNGs of the main scene in preset states (see "Screenshots" below)
tools/find_godot.sh        Shared by the tools/*.sh scripts: finds or downloads Godot
tools/make_sfx.py          Synthesises assets/audio/sfx/*.wav (CC0, ours); edit and re-run to change a sound
tools/make_music.py        Synthesises the placeholder lo-fi loops in assets/audio/music/ (CC0, until decision D8)
tools/simulate.sh          Balance bot (tools/simulator.gd) -> docs/BALANCE.md; run after any balance change
tools/pacing.gd            PLAN §2 pacing targets as data; tests fail if one is missed (or newly met, see below)
docs/                      PLAN (why/how), ROADMAP (tasks), CHANGELOG, FEEDBACK, DESIGN,
                           PLAYER_RESEARCH (what our player loves; tasks marked (PR) come from it)
.claude/agents/            Project subagents (see "Subagents" below): diff-reviewer, screenshot-checker,
                           balance-analyst, test-runner, fun-designer
.claude/settings.json      Hooks that run tools/hooks/workflow.py (the commit gate and reminders, see "Subagents")
```

## Rules of the code
1. **Game logic lives only in `game.gd`.** UI scripts read state and call public methods.
2. **Content is data.** A new helper/upgrade = a new entry in `content.gd`, not new code. Every entry has an `icon`
   (an SVG in `assets/icons/`, credited in `assets/CREDITS.md`; game-icons.net CC BY 3.0 works well; a test checks both).
   New effect types go in `Content.EFFECT_TYPES` *and* are applied in `GameState`.
3. **Static typing everywhere** (`var x := 1.0`, `-> void`). Tabs for indentation.
4. Big numbers are `float`. Format all player-facing numbers with `Num.format()`.
5. **Save compatibility matters.** If you change the shape of `get_save_data()`, bump
   `SAVE_VERSION` and add a step in `_migrate()` so old saves still load.
6. Cost formula: `ceil(base_cost * 1.15 ^ owned)`. Offline progress is capped at 8 hours.
7. Keep scenes editable in the Godot editor: use `%UniqueName` nodes, no deep `get_node` paths.
8. **Style lives in `ui/theme.tres`.** No `theme_override_*` in scenes (a test enforces it); give a node a
   `theme_type_variation` instead (TitleLabel, SubtitleLabel, DimLabel, FaintLabel, TickerLabel, HintLabel,
   PrimaryButton, SubtleButton, PageMargin, ColumnsBox, StackBox, TopBar, GoalStrip, ShopCard, IconTile, CardMargin,
   TightBox, CardTitle, CardLine, CardOwned, CostAffordable, CostUnaffordable, UpgradeGrid, ToggleChip, PopTap,
   PopSolve, TimerLabel, TimerWaiting, TimerDone, ScrambleLabel, SidePanel, StageChip, StageChipActive, StageChipDone,
   StageChipRow, TickerText, KeyHint, GoalBar, GoalLabel, GoalLabelDim, NewsPanel, NewsNew, NewsOld, GoldenButton,
   BuffLabel, TimerGolden, FlowLabel, ChoiceBadge), or add a new variation.
9. **Taps:** clicking the puzzle or the `tap` input action (Space / Enter, no repeat when held). Shop and other
   buttons use `focus_mode = none`, so Space never presses a focused button by accident.
   One accent colour: green `#3ccf8e` (dim `#2a9d6c`). Every new asset gets a line in `assets/CREDITS.md`.

## Subagents
`.claude/agents/` holds helpers for side jobs. The main session writes the code; don't split a task's code between
agents (they'd collide on `game.gd`, `content.gd` and the save version). Use them like this:

| Agent | Model | When |
|---|---|---|
| `test-runner` | Haiku | Whenever you run the tests: it runs `tools/run_tests.sh` and returns only the failures |
| `balance-analyst` | Sonnet | After any content/balance change: runs `tools/simulate.sh`, explains what moved in BALANCE.md |
| `screenshot-checker` | Sonnet | After visual changes: tell it what changed and which presets; it shoots and reports problems |
| `diff-reviewer` | Opus | Every session, once tests pass and before committing: reviews everything not yet on `main` |
| `fun-designer` | Opus | At the end of a phase, or when the owner asks for a "fun pass": ranked ideas, proposals only |

All of them report and never commit. Fix what they find yourself (or say why not in the CHANGELOG). Ideas from
`fun-designer` go to the owner first; only the ones they pick become ROADMAP tasks, marked "(fun pass, date)".
Background agents are fine while you keep working (e.g. `balance-analyst` while you write tests).

**Hooks enforce this** (`.claude/settings.json` -> `tools/hooks/workflow.py`; its header explains each part):
- Editing `content.gd`/`game.gd` or UI files (`scenes/`, `ui/`, `scripts/ui/`, `assets/icons|fonts|images/`) gives
  you a one-time reminder to run `balance-analyst` / `screenshot-checker`.
- **`git commit` is blocked** while the change set (everything not yet on `main`, committed or not) has code in it
  (anything outside `docs/`, `.claude/agents/` and `*.md` files) and: tests haven't passed since the last code
  change; or `content.gd`/`game.gd` changed since the balance bot last ran; or UI files changed since the last
  screenshots; or `diff-reviewer` hasn't reviewed every changed code file (fixing its findings needs no second
  review). A check counts from when it *started*, so edits made while it runs still need a new run.
- The hook reads the checks' own output: run them in the foreground or via their agents (a background Bash run isn't
  seen), and keep `All good.` / `Wrote …docs/BALANCE.md` / `Saved …` in that same command's output (`… > log; grep
  "All good" log` in one command is fine; a log read by a later, separate command isn't seen).
- A commit that ticks the last task of a roadmap phase asks for a `fun-designer` pass.
- What ran is kept in `.git/cube-workflow.json` (per clone, never committed). If the gate is wrong, or the owner asks
  to skip it, prefix the command with `CUBE_SKIP_GATE=1` and say why in the CHANGELOG.

## Before you finish (every session)
1. Run `bash tools/run_tests.sh` (or the `test-runner` agent) and make sure it prints `All good.`
   (On Linux it downloads Godot automatically. Elsewhere set `GODOT=/path/to/godot`.)
   Add or adjust tests in `tests/test_runner.gd` for any rule you changed.
   `test_pacing_targets` runs the balance bot (~2–3 min since 5.8: three runs, the 2-hour one ~90 s). Targets with an `expected_failure` in
   `tools/pacing.gd` may miss; if your change makes one pass, the test tells you to remove its mark.
   After any content/balance change, also run `bash tools/simulate.sh` (or `balance-analyst`) and commit `docs/BALANCE.md`.
   Then have `diff-reviewer` review the change and fix what it finds.
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
TAB=1 bash tools/screenshot.sh /tmp/shots mid                     # shop tab 1 Upgrades / 2 Puzzles -> mid_tab1.png
JUICE=1 bash tools/screenshot.sh /tmp/shots mid                   # taps + solve pop mid-animation -> mid_juice.png
BUY=10 bash tools/screenshot.sh /tmp/shots mid                    # shop on ×10 (BUY=-1: Max) -> mid_buy10.png
SETTINGS=1 bash tools/screenshot.sh /tmp/shots mid                # Settings panel open -> mid_settings.png
SOLVE=done bash tools/screenshot.sh /tmp/shots mid                # Solve Station: inspecting|solving|done -> mid_solvedone.png
SHOWCASE=20 bash tools/screenshot.sh /tmp/shots mid               # main cube's showcase solve 20 moves in -> mid_showcase20.png
METHOD=beginner SHOWCASE=40 bash tools/screenshot.sh /tmp/shots mid  # ...with another method -> mid_showcase40_beginner.png
KEYS=simple SOLVE=solving bash tools/screenshot.sh /tmp/shots mid    # Solve Station with simple keys -> mid_solvesolving_keyssimple.png
NEWS=1 bash tools/screenshot.sh /tmp/shots mid                    # a few news feed lines -> mid_news.png
GOLDEN=glow bash tools/screenshot.sh /tmp/shots mid               # Golden Scramble: glow | case | buff -> mid_goldenglow.png
FLOW=1 bash tools/screenshot.sh /tmp/shots mid                    # Flow running after a Gold hand solve -> mid_flow.png
DRILL=done bash tools/screenshot.sh /tmp/shots mid                # a PLL drill: solving | done -> mid_drilldone.png
DAILY=fmc bash tools/screenshot.sh /tmp/shots mid                 # the daily scramble: fmc | timed -> mid_dailyfmc.png
SCROLL=1 bash tools/screenshot.sh /tmp/shots endgame              # helper list scrolled to the bottom -> endgame_scroll.png
LAB=1 bash tools/screenshot.sh /tmp/shots mid                     # the Lab tab: one project done, one running -> mid_lab.png
PICK=speed_practice bash tools/screenshot.sh /tmp/shots mid       # a choice made (Upgrades tab) -> mid_pickspeed_practice.png
COMPETE=1 bash tools/screenshot.sh /tmp/shots endgame            # the Compete screen open -> endgame_compete.png
bash tools/screenshot.sh /tmp/shots bench bench_row               # 7×7 alone vs all 5 cubes at max speed: ms/frame
```
- Writes `<dir>/<preset>.png` (default 1280×720), then open the PNGs with the Read tool to check them.
- It runs under `xvfb-run` with the real OpenGL 3 renderer (software Mesa, so it's slow but correct) and
  a throwaway user-data dir, so it never touches a real save.
- Presets (`fresh`, `mid`, `late`, `welcome`; v2 puzzle states `row3`, `row5`, `row6`; `endgame` = all 12 helper tiers) are save data in `tools/screenshot_presets.gd`. They go through
  `_migrate()`, so they keep working after save-format changes. A test checks that they still load.
  Add a preset there when a new feature needs its own state (e.g. a puzzle tier or prestige).
- The economy is frozen during the shot, so numbers match the preset exactly. The cube is seeded, so
  before/after shots compare. `docs/screenshots/baseline/` is the look before Phase 1.
- New `class_name` scripts aren't known to Godot until an import runs (`run_tests.sh` does one). If a
  `-s` script can't find a class you just added, run `godot --headless --path . --import` first.
- `docs/` has a `.gdignore`, so Godot never imports these PNGs into the game. Keep committed PNGs small (< 300 KB each). Don't commit throwaway shots; put them in `/tmp` or a scratchpad.

**Testing gotcha:** the test runner compiles any script whose `class_name` it names as a type *before* the autoloads
exist. A class that uses `Game`/`Audio`/`Settings` by name (like SettingsPanel) must be used untyped in tests.
Tests that touch the real `Settings`/`Game` autoloads set `persistence_enabled = false` (and Game's `save_path` to
`user://test_saves/`) so they never write the player's files.

## Debug keys (debug builds only)
- **F9**: +1000 Solves
- **F10**: wipe the save and restart from zero

The save file is `user://save.json`. On Windows that's
`%APPDATA%\Godot\app_userdata\Cube Idle\save.json`. Next to it: `save.bak` (the previous save),
and `save.corrupt.json` if a damaged save was ever found. Saves go through `save.json.tmp` + rename (task 0.4),
so never write the save file directly; call `Game.save_game()`.
