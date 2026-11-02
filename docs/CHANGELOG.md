# Changelog

Newest first. Every session adds an entry: what changed, what's unfinished, notes for the next session.

## 2026-11-02 — Task 1.5: graphics settings and cleanup (Phase 1 done)
- **Graphics: High / Low.** `PuzzleView3D.set_graphics("high"|"low")`. High = MSAA 4×, rounded piece bodies (432 triangles
  each), stage glow and contact shadow. Low = no MSAA, bevelled bodies (48 triangles each, 9× fewer), no glow or shadow.
  Switching keeps the puzzle's state and works mid-turn.
- **Where it's stored:** `GraphicsConfig` (`scripts/util/graphics_config.gd`) reads and writes `user://settings.cfg`, section
  `[graphics]`, key `quality`. It's separate from the save, so F10/reset doesn't touch it, and saving keeps other sections.
  **Task 3.4's Settings autoload should take over this exact file/section/key** and then delete `GraphicsConfig`.
- **Temporary UI:** a small flat "Graphics: High" button under the lifetime stats toggles it (and saves). It moves into
  the Settings panel in 3.4. `focus_mode` is none, so Space/Enter still go to the Turn button.
- **Deleted** `scripts/ui/cube_view.gd` (the 2D face); no code references `CubeView` any more.
- **Bench:** `bash tools/screenshot.sh <dir> bench` = the late preset on a 7×7 with the economy running (speed mode,
  369K moves/s, solves every frame), 60 warm-up frames + 600 measured frames at Low, then at High, then `bench.png`.
  Results in this container (xvfb + **software** Mesa llvmpipe, 1280×720, so it's not representative of a GPU):
  - Low: **30.6 ms/frame** (33 fps), worst 57 ms
  - High: **76.8 ms/frame** (13 fps), worst 121 ms
  - The view's own script work is only **0.47 ms/frame** (speed mode, 7×7) and 0.24 ms for animated turns (timed
    headless), so nearly all of that is the software rasteriser. **Owner: please check real fps on your PC**, especially an
    integrated-GPU laptop on High; if High struggles there, the next lever is fewer sticker segments or a lower MSAA.
  - The bench needs a renderer: run headless, it waits forever for a frame to be drawn. Always run it through `screenshot.sh`.
- `screenshot.sh` takes `GRAPHICS=low` (adds `_low` to the file name). Screenshots: [High](screenshots/graphics/mid_7x7.png) vs
  [Low](screenshots/graphics/mid_7x7_low.png).
- Tests: config defaults/round-trip/unknown value/keeps other sections; Low switches MSAA, stage and mesh and keeps the state;
  High restores them; the main-scene button toggles and saves (to a test path). 879 checks, `All good.`
- **Phase 1 is complete.** Owner: a good time to pull `main`, play, and write FEEDBACK.md (the plan says playtest after each phase).
- **Next:** task 2.1 (theme + font).

## 2026-11-02 — Task 1.4: stage and camera
- **Drag to rotate:** pressing the puzzle and moving more than 6 px becomes a drag. It turns the view (0.01 rad/px; yaw wraps,
  pitch is clamped to ±0.7) and never taps, even if the mouse returns to the start. On release it springs back
  (exponential, rate 2.5/s). A press-and-release within 6 px still taps. `drag_offset()` exposes the current turn.
- **Idle sway:** a slow yaw (±0.06 rad) and tilt (±0.025 rad) on top of drag and speed-mode wobble. `sway_enabled` is
  there for the Reduce motion setting (3.4).
- **Stage:** `Backdrop` (a quad under the camera that exactly fills the view) draws a soft radial glow that fades to
  *transparent* at the edges, so the real UI background shows there and the 3D view has no border. A first try faded to the
  background colour instead and came out 3 RGB steps darker after the 3D colour pipeline; transparency avoids that.
  `Shadow` is a flat dark ellipse just under the puzzle's lowest corner. Both shaders are in `scripts/ui/shaders/`.
  The camera sits a little lower (`CAMERA_DROP`) and further back (`FRAME_DISTANCE` 1.0), so there's room for the shadow.
- **Move ticker:** `%MoveTicker` (a Label under the puzzle in `main.tscn`) shows the last 8 moves in WCA notation
  (`view.ticker_text()`), including the backwards replay. It clears on a solve.
- Tests: a drag rotates and doesn't tap, out-and-back is still a drag, a 4 px wiggle still taps, a released drag springs
  back, and the ticker is ≤ 8 valid moves and clears on solve. 865 checks, `All good.` The headless smoke run is clean.
- Screenshots: [3×3](screenshots/stage/mid.png), [7×7](screenshots/stage/mid_7x7.png),
  [late game, speed mode](screenshots/stage/late.png).
- **For later:** the stage effects (glow, shadow) are what 1.5's Graphics: Low should turn off, along with MSAA.
  In screenshots the sway depends on frame timing, so two shots of the same preset can differ by a degree or two.
- **Next:** task 1.5 (graphics settings, delete `cube_view.gd`, bench preset).

## 2026-11-02 — Task 1.3: animated turns
- `PuzzleView3D` now animates real layer turns. `scramble_step()` queues a move. The front of the queue rotates its layer's
  MultiMesh transforms around the face axis (0.12 s per quarter turn, ease-out cubic, half turns ×1.4) and is applied to
  the model only when it finishes. Turns get faster as the queue grows (time ÷ (1 + 0.6 × queued)); past
  `MAX_QUEUE` (6) the backlog is applied instantly, so the queue can't grow.
- **Speed mode:** `main.gd` now passes the real moves/s each frame (`set_speed`). Above 12 moves/s (off again below 9),
  moves snap without animation and the puzzle wobbles (turntable yaw ±0.07 rad, tilt ±0.04 rad). A solve there snaps to
  solved with a small pulse at most every 0.6 s, with no hold. **This fixes the late-game "stuck on solved" cube** noted in 0.1.
- **Solves:** `show_solved()` replays the last ≤ 30 moves backwards (all within 0.9 s), then snaps to solved, flashes
  (sticker emission 0.45, fading) and bounces (+8 % swell). The flash is rate-limited to once per 0.6 s; quicker solves just pulse.
  New moves are ignored during the replay and the 0.35 s hold.
- New view API: `set_speed()`, `queued_moves()`, `is_idle()`, `finish_animations()`, `pose("turn"|"solved")` (freezes a
  moment for screenshots), `drawn_stickers(unturn)`, `record_moves`/`recorded_moves` (tests).
  `screenshot.sh` takes `POSE=turn|solved`.
- **Headless gotcha:** the dummy renderer doesn't keep MultiMesh data (reads back identity/black), so the view keeps a
  CPU-side copy of every sticker transform and colour it sends; `drawn_stickers()` reads that copy.
- Tests (3×3, 4×4, 7×7): after 1,000 moves with partial frames, every drawn sticker matches the model. Mid-turn, the drawing
  equals the model plus the half-done rotation. Replaying the recorded moves on a separate model gives the same state, and
  all 1,000 moves were applied. Also: 1,000 moves in one frame never queue more than 6, speed mode doesn't queue, the
  thresholds have hysteresis, a solve replay ends solved within 0.9 s, and speed-mode solves don't hold or repeat every frame.
  I checked the tests can fail by removing the transform refresh at the start of a turn: the mid-turn check caught it.
  855 checks, `All good.`
- Screenshots: [3×3 mid-turn](screenshots/cube/mid_turn.png), [5×5 mid-turn](screenshots/cube/mid_5x5_turn.png),
  [solved flash](screenshots/cube/mid_solved.png).
- **Not done here:** the moves are random, not a real solve, so the replay is the scramble undone. That's intended
  (PLAN §4.2). "Reduce motion" (3.4) should turn off wobble, bounce and flash. The constants are at the top of `puzzle_view_3d.gd`.
- **Next:** task 1.4 (stage and camera: drag to rotate, idle sway, vignette, shadow, move ticker).

## 2026-11-02 — Task 1.2: PuzzleView3D (static)
- New `scenes/puzzle_view_3d.tscn` + `scripts/ui/puzzle_view_3d.gd` (`PuzzleView3D`) replace the 2D `CubeView` in
  `main.tscn` (node `%PuzzleView`, 300×300). Same API, `scramble_step()` and `show_solved()`, plus `set_puzzle(id)` for
  "2x2" ... "7x7" (`PuzzleShapes.from_id()`). A new puzzle starts part-scrambled (size × 4 moves).
- **Clicking the puzzle taps:** the view emits `tapped` when the mouse is released within 6 px of where it was pressed
  (a drag doesn't tap, ready for 1.4); `main.gd` connects it to the same handler as the Turn button.
- **Rendering:** SubViewport (transparent, own world, MSAA 4×) > `Puzzle` node (tilted 28° towards the camera, scaled for
  the tap punch) > `Turntable` (turned −38° so F and R show) > `Bodies` + `Stickers` MultiMeshes. That's two draw calls for
  any size. Key light from the upper left, a weak fill from the right, ambient colour, no shadows yet.
  The camera backs off to fit the puzzle's bounding sphere, so every size fills the view the same.
- `scripts/cube/puzzle_meshes.gd` (`PuzzleMeshes`): a rounded box (rounded edges and corners, smooth normals) and a
  rounded-rectangle sticker, both from `SurfaceTool`. **Two deviations from the plan:** stickers are geometry, not a
  shader (MSAA then smooths the corners), and pieces are MultiMesh instances, not nodes, so 1.3 rotates the turning
  layer's transforms instead of parenting to a pivot. PLAN §4.2 and ROADMAP 1.3 are updated.
- Screenshots: [2×2](screenshots/cube/mid_2x2.png), [3×3](screenshots/cube/mid_3x3.png),
  [5×5](screenshots/cube/mid_5x5.png), [7×7](screenshots/cube/mid_7x7.png). `screenshot.sh` takes `PUZZLE=5x5` for this.
- Tests: puzzle ids, click vs drag on the view, `set_puzzle` instance counts, `show_solved`, and a click on the real
  main scene raising `Game.total_moves` by one tap. The test runner now waits one frame first, so added nodes get `_ready()`.
  822 checks, `All good.` The headless smoke run is clean.
- **Still the same / for later:** the game always shows a 3×3 until puzzles exist (4.2 calls `set_puzzle`). Moves
  are instant, not animated, and at high speed the puzzle sits solved like the 2D cube did (1.3).
  The Turn button stays until 2.2. `cube_view.gd` is unused and is deleted in 1.5.
  Under `canvas_items` stretch, the SubViewport renders at the 1280×720 layout size and is scaled up on bigger windows,
  so it may look soft at 1440p. Check it in 9.1, or render at the real window scale.
- **Owner:** this is the first change you can see. Please play it and note anything in FEEDBACK.md
  (angle, colours, size, the black plastic).
- **Next:** task 1.3 (animated turns).

## 2026-11-02 — Task 1.1: TwistyModel + cube shapes
- New `scripts/cube/twisty_model.gd` (`TwistyModel`, pure data, no nodes) and `scripts/cube/puzzle_shapes.gd`
  (`PuzzleShapes.cube(n)`, n = 2–7, standard colours: white U, yellow D, green F, blue B, red R, orange L).
- **How it works:** each piece has a home position + stickers, and its state is one int, an index into the
  puzzle's rotation group (24 for cubes, built by BFS from the face turns; the Megaminx will get 60).
  A move multiplies the orientation of the pieces in its layers via a precomputed table, so it's exact and never drifts.
  `piece_basis(i)` / `piece_position(i)` give the transform the 3D view needs, and `color_at(position, face)` reads a sticker.
- Moves are `{face, turns, width, depth}`. `notation()` gives WCA (`R`, `U'`, `F2`, `Rw`, `3Rw`, `3Uw2`; inner slices
  in SiGN, e.g. `2R`), and `parse()` / `parse_sequence()` read them back. `random_move()` makes scramble-style moves
  (outer blocks of width 1..⌊n/2⌋, never the same face twice in a row). There are also `scramble()`, `inverse()` and `inverse_sequence()`.
- `is_solved()` = every face shows one colour, so identical big-cube centres count as solved.
- Coordinates: +x = R, +y = U, +z = F (towards the camera), one unit per cubie, centred on the origin.
- Tests for every n: piece count n³ − (n−2)³, 6n² stickers, every face/width ×4 = solved (and not before),
  (R U R' U')×6 = solved, 50-move scramble not solved + inverse = solved, turn direction checked on real stickers
  (U brings red onto F, R brings green onto U, Rw on 5×5), notation strings and parse round-trips. 805 checks, `All good.`
- Speed: 1,000 moves take ~22 ms on 3×3 and ~143 ms on 7×7 (headless, this container), so ~0.15 ms per visual turn.
- Not used by the game yet; 1.2 builds the 3D view on it. `CubeView` (2D) stays until 1.5.
- **Next:** task 1.2 (PuzzleView3D, static).

## 2026-11-02 — Task 0.4: safe saves
- `GameState.save_game()` now writes `save.json.tmp`, checks it reads back as a save, moves the old `save.json` to
  `save.bak`, then renames the temp file into place. It returns `true`/`false`. A crash at any step leaves a readable save or backup.
- `load_game()`: if `save.json` is damaged (or missing while `save.bak` exists), it loads `save.bak` and sets
  `Game.load_notice`. A damaged save is copied to `save.corrupt.json` first, so nothing is lost. If both are unreadable,
  it starts fresh and says so. "Damaged" = not JSON, not a dictionary, or no `version` key.
- JSON is parsed with `JSON.new().parse()` (quiet) instead of `JSON.parse_string()` (logs an engine ERROR that
  `run_tests.sh` would flag).
- `main.gd` shows `load_notice` once in the existing "Welcome back" dialog, above the offline report if there is one.
- `wipe_save()` (F10) also removes `save.bak` and any `.tmp`. `save_path` is now a variable so tests use `user://test_saves/`.
- Tests: atomic write + backup contents, corrupt save → backup, missing save → fresh, missing save + backup → backup,
  both corrupt → fresh + kept copy, wipe removes both. 224 checks, `All good.` The WARNING lines in the test output are
  these tests damaging saves on purpose.
- No save-format change, so SAVE_VERSION stays at 1.
- **Phase 0 is done.** Next: task 1.1 (TwistyModel + cube shapes). Owner: good moment to pull and check that the game
  still loads your existing save.

## 2026-11-02 — Task 0.3: pacing tests
- New `tools/pacing.gd`: the 12 pacing targets from PLAN §2 as data (first helper ≤ 20 s, first upgrade < 1 min,
  something new every ≤ 3 min in hour 1 and ≤ 10 min after, 3×3/Robot/4×4/5×5/first prestige windows, multi-run targets,
  idle progress). Each has an `expected_failure` reason while today's content can't meet it.
  "~X min" became explicit windows: 3×3 4–6 min, Robot 8–12, 4×4 25–35, 5×5 50–70, prestige 80–100 (from 6.4).
- `test_pacing_targets` runs the bot (3 taps/s for 120 min, plus 0 taps/s for 10 min) and checks every target. A missed
  real target fails, an expected failure prints, and an expected failure that **now passes fails on purpose**, so
  the session that fixed it removes the mark (checked by hand: loosening one target made the test fail as intended).
  `test_pacing_checks` covers the rules on made-up data.
- `docs/BALANCE.md` now starts with a pacing table (target, actual, status) and the expected-failure list.
  Today: **all 12 are expected failures**. That's the baseline Phase 4 starts from.
- The simulator report reuses `Pacing.clock()` / `Pacing.longest_gap()`, so there's no duplicate gap logic.
- The test suite now takes ~10 s longer (the 120-min sim). 204 checks, `All good.`
- **For Phase 4+:** when puzzles/prestige land, the bot must buy them as events with kind `"puzzle"` (ids `3x3`, `4x4`, `5x5`)
  and `"prestige"` (id `compete`); those targets already look for exactly that. `unsupported` targets need multi-run sim (6.4).
- **Next:** task 0.4 (safe saves).

## 2026-11-02 — Task 0.2: balance simulator
- New `tools/simulator.gd`: a greedy bot that drives a real `GameState` in 0.1 s steps. Every second, and after each
  purchase, it targets the visible item with the lowest *time to afford + cost ÷ Solves/s gained*, measured by
  briefly owning the item in the real state and then undoing it. It records the first purchase of each item,
  checkpoints at 1/5/15/30/60/120 min, when everything is owned, and the longest wait for something new.
- `tools/simulate.sh [--taps 3,0] [--minutes 120] [--out res://docs/BALANCE.md]` (via `tools/simulate.gd`) writes the report.
  The default runs two profiles, tapping 3/s and never tapping, in ~20 s.
- `docs/BALANCE.md` (today's content): **everything owned at 51:32** (PLAN §1 measured ~53 min ✓), first Friend 0:25,
  Speedcubing Lab is a 16-minute wall, and with no taps nothing at all happens in 2 hours. That's what Phase 4 fixes.
- Tests: a short sim run (first buy is a Friend; idle buys nothing) and a check that measuring an item leaves the
  state unchanged. 168 checks, `All good.`
- **Workflow change (owner):** every commit is merged into `main` and pushed. CLAUDE.md step 4 and the PLAN session loop say so now.
- **Notes for 0.3:** reuse `Simulator.run()` from the tests. A 120-min run takes ~8 s headless; keep test runs short
  or run them once and check several targets from one result. Puzzles (Phase 4) need new candidate kinds in
  `_candidates/_income_gain/_cost/_buy`; each is a single `match` branch.
- **Next:** task 0.3 (pacing tests).

## 2026-11-02 — Task 0.1: screenshot script
- Merged `claude/relaxed-edison-220seq` (the plan rebuilt around D1/D3/D5/D6/D7) into this branch; the owner
  confirmed that plan is the one to follow. This branch now carries both that plan and the 0.1 work.
- New `tools/screenshot.sh <out_dir> [preset ...]`: runs `tools/screenshot.tscn` under `xvfb-run` with
  `--rendering-driver opengl3`, dummy audio and a throwaway `XDG_DATA_HOME`, so a real save is never read or written.
  It loads a preset, freezes `Game`, seeds the RNG, waits 30 frames and saves `<out_dir>/<preset>.png`.
  `SIZE=1920x1080` changes the resolution. Usage is in CLAUDE.md under "Screenshots".
- Presets `fresh` / `mid` / `late` live in `tools/screenshot_presets.gd` as v1 save data loaded through
  `apply_save_data()`, so `_migrate()` keeps them valid. A new test (`test_screenshot_presets_still_load`) checks this.
- The Godot download logic moved from `run_tests.sh` into `tools/find_godot.sh`; both scripts source it. Same behaviour.
- Baseline screenshots (before any visual work): [fresh](screenshots/baseline/fresh.png),
  [mid](screenshots/baseline/mid.png), [late](screenshots/baseline/late.png). 40–100 KB each.
- Added `docs/.gdignore` so Godot doesn't import the screenshots as game textures.
- Tests: 154 checks, `All good.`
- **Notes for the next session:**
  - The shots are taken with the game *paused*. When the game is running, the late preset (~44K solves/s) completes a solve every frame,
    so the 2D cube stays stuck on one colour. Task 1.3's speed-spin effect should fix this; check it with a running game.
  - `tools/` (screenshot scene, presets) must be excluded from the Windows export in 10.1.
  - The ALSA "cannot find card" error in the container is avoided with `--audio-driver Dummy`; `run_tests.sh` is unaffected.
- **Next:** task 0.2 (simulator).

## 2026-11-02 — Decisions D6 and D7 (docs only)
- Owner answered: **D6** first prestige at ~90 min, **D7** lo-fi music.
- PLAN: the pacing table now says 90 min; §4.3 has a lo-fi style guide (70–90 BPM, no vocals, a flavour per tier)
  and SFX that fit it; §7 moves D6/D7 to answered. The final music *source* is now open decision **D8** (needed by 9.4).
- ROADMAP: 3.1/3.2 reference the lo-fi style; 6.4 has concrete targets (first prestige 80–100 min, second run ≤ 45 min);
  9.4 is now tagged [D8].
- **Open decisions left:** D2 (name), D4 (price), D8 (final music source). None block Phases 0–8.
- **Next:** task 0.1 (screenshot script).

## 2026-11-02 — Plan rebuilt around the owner's decisions (docs only)
- Owner answered: **D1** one active puzzle (Claude's recommendation), **D3** 3D cube, **D5** several music tracks.
- Merged `main` (which had the owner-supplied plan) into this branch; that plan is superseded by `docs/PLAN.md`.
- Rewrote `docs/PLAN.md` and `docs/ROADMAP.md`:
  - The 3D cube is now Phase 1, right after the tools, because it's the centrepiece and the
    layout, puzzles and juice all build on it. It's built on a generic `TwistyModel`
    (cubes 2–7 and Megaminx share one turning system), and there's no N×N 2D view any more.
  - Music: an `Audio` autoload with a playlist, crossfades and a Jukebox. There's one track per puzzle
    tier, and unlocking a puzzle unlocks its track. Licensing rules: CC0/CC-BY only, never NC.
  - New open decision **D7** (music style and source). D2, D4 and D6 are still open.
- **Next:** task 0.1 (screenshot script).

## 2026-11-02 — Merged development plan (docs only)
- Added `docs/PLAN.md`, which merges the owner-supplied phase plan with the review earlier today.
  - Kept from the owner's plan: session loop + prompt, one task per session, "Done when" per task,
    FEEDBACK.md, open decisions D1–D5, save-version schedule, architecture rules, release steps.
  - Kept from the review: measured problems, pacing targets, and putting tools/simulator and the visual
    overhaul *first* (Phase 0–1) instead of last; puzzles start on a 2×2, which fixes the slow start.
  - New: decision D6 (first-prestige timing), safe saves moved early (0.4), screenshots in `docs/screenshots/`.
- Rewrote `docs/ROADMAP.md` as numbered tasks (0.1 … 9.4), each with a "Done when". Added `docs/FEEDBACK.md`.
  Updated CLAUDE.md to read PLAN and FEEDBACK and do one task per session.
- **Next:** task 0.1 (screenshot script). Owner: please answer D1, D3 and D5 in PLAN §7 before Phase 2–3.

## 2026-11-02 — Review and new plan (no code changes)
- Owner said the game looks bad and has no progression. Took screenshots (xvfb + opengl3
  works in the cloud container) and simulated the economy with a greedy bot.
- Findings: all content is gone by ~53 min, the start is slow (first Friend = 75 taps), nothing
  visual changes as you progress, and the UI is the default Godot theme with text-only buttons.
- Rewrote `docs/ROADMAP.md`: added pacing targets and new Milestones 2–8 (tools → visual overhaul →
  economy rework with puzzle tiers → 3D cube → prestige → active play → release).
  The old Milestone 2–5 items are folded into the new ones.
- **Next:** Milestone 2 (screenshot script + sim bot driving the real `GameState`), then Milestone 3.

## 2026-11-02 — Development plan (on main; superseded by the merged plan above)
- Added `docs/PLAN.md`: phases 1–10 to release, workflow and session prompt, architecture notes,
  balance targets, open owner decisions D1–D5.
- Rewrote `docs/ROADMAP.md` as numbered tasks with "Done when" criteria. Added `docs/FEEDBACK.md`.
- CLAUDE.md now points to PLAN and FEEDBACK and says one task per session.
- **Next:** task 1.1 (floating "+N Solves" text). Phase 2.2 waits on owner decision D1.

## 2026-11-02 — Project setup
- Created the Godot 4.7 project: one main screen, `Game` autoload with all rules,
  content as data, autosave + offline progress, number formatting.
- Added headless tests (`tools/run_tests.sh`): 124 checks passing on Godot 4.7.2.
- Added CLAUDE.md, DESIGN, ROADMAP, CI workflow.
- **Next:** start Milestone 2 in `docs/ROADMAP.md`. Balance is a first guess; expect tuning.
