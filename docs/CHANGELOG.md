# Changelog

Newest first. Every session adds an entry: what changed, what's unfinished, notes for the next session.

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
