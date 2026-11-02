# Roadmap

Task checklist for `docs/PLAN.md`. Do the **next unchecked task**, one per session.
Tick it only when its **Done when** is true. Tasks marked **[D#]** need that owner decision
(PLAN section 7) first. If it's unanswered, ask, don't guess.

## Milestone 1 — Playable core ✅
- [x] Tap to make moves, moves complete solves
- [x] 6 helpers with scaling costs
- [x] 7 upgrades (tap, global, per-helper, moves-per-solve)
- [x] Autosave every 10 s and on quit, offline progress (8 h cap)
- [x] Headless tests + smoke run

## Phase 0 — Tools and safety
- [ ] **0.1 Screenshot script** `tools/screenshot.sh`: runs the main scene under `xvfb-run` with
      `--rendering-driver opengl3` and a throwaway user-data dir. Supports a few preset states (fresh,
      mid-game, late-game) and writes PNGs to a given folder.
      *Done when:* it produces 1280×720 PNGs of all presets in the cloud container, and CLAUDE.md explains how to use it.
- [ ] **0.2 Simulator** `tools/simulate.gd`: a headless bot that drives the real `GameState`. It's greedy (buys
      the best-payback item), with configurable taps/s and duration. It logs when each helper, upgrade and puzzle is
      first bought, plus solves/s at 1/5/15/30/60/120 min.
      *Done when:* `tools/simulate.sh` writes a table to `docs/BALANCE.md`, and today's numbers roughly match PLAN §1
      (everything bought by ~53 min).
- [ ] **0.3 Pacing tests:** `test_runner.gd` checks PLAN §2's pacing table with the simulator.
      Targets the current content can't meet yet are listed as *expected failures* that print but don't fail the run.
      *Done when:* tests pass, and the expected-failure list appears in `docs/BALANCE.md`.
- [ ] **0.4 Safe saves:** write `save.json.tmp` then rename it; keep `save.bak`; if the save is corrupt, load the
      backup and warn.
      *Done when:* there are tests for a corrupt main save → loads the backup, and a missing save → starts fresh.

## Phase 1 — Look
- [ ] **1.1 Theme:** `ui/theme.tres` set as the project theme. One OFL font (e.g. Inter) in `assets/fonts/`,
      plus `assets/CREDITS.md`. Button states (normal/hover/pressed/disabled/focus), panels, tabs, progress bar,
      one accent colour. Remove per-node overrides from `main.tscn`.
      *Done when:* there are no `theme_override_*` lines left except deliberate ones, and before/after screenshots are in `docs/screenshots/`.
- [ ] **1.2 Layout and click the cube:** top bar (Solves, solves/s), a large cube centre-left that you **click to tap**,
      the shop on the right, and a "Next goal" strip under the cube (cheapest locked thing and how far away it is).
      The old Turn button goes away; a "Click the cube (Space)" hint replaces it.
      *Done when:* clicking the cube taps, it works at 1280×720 and 1920×1080, there's a screenshot, and tests pass.
- [ ] **1.3 Shop cards:** `scenes/shop_card.tscn` replaces the text Buttons. Each card has an icon, name, short
      description, a big owned count, the cost (accent colour when affordable, grey when not), and "+X/s" total.
      Affordable cards lift or glow. Locked helpers show as "???" cards with their unlock requirement.
      Upgrades become a grid of icon tiles with a tooltip panel, and the Upgrades tab shows a badge "(N)" when any are buyable.
      *Done when:* you can tell affordable from not at a glance in screenshots, and the next locked item is always visible.
- [ ] **1.4 Juice:** cube squash on tap, floating "+N" at the cursor, a rising "+X Solves" plus a particle burst on each
      solve (pooled, ≤ 20 on screen), and the Solves counter tweens up instead of jumping.
      *Done when:* this runs at a steady 60 fps with 1,000 moves/s in the smoke run, and there's a screenshot.

## Phase 2 — Feel
- [ ] **2.1 Sound [D5]:** `Audio` autoload with Master/SFX/Music buses. Turn click (random pitch ±8 %), solve chime,
      buy sound, plus music if D5 says so. CC0 assets credited in `assets/CREDITS.md`.
      *Done when:* each event plays a sound, a burst of 100 solves doesn't stack 100 chimes (rate-limited), and tests pass.
- [ ] **2.2 Buy ×1 / ×10 / Max:** the cost of n helpers is a geometric series sum in `GameState`; there's a toggle on the shop.
      *Done when:* tests cover ×10 cost, Max with too few Solves, and Max = 0, and cards show the cost for the chosen amount.
- [ ] **2.3 Settings tab:** Master/SFX/Music volume, Reduce motion, number notation (1.5K vs 1.5e3), and
      "Reset save" behind a dialog that names what will be lost. Settings are stored in `user://settings.cfg`.
      *Done when:* settings survive a restart and a save reset, and Reduce motion turns off 1.4's effects.
- [ ] **2.4 Keyboard:** Space/Enter tap from anywhere through an input action (not button focus); holding the key does **not** repeat.
      *Done when:* there's a test or smoke check that echo events are ignored.
- [ ] **2.5 Offline panel:** a styled "Welcome back" panel (time away, Solves earned, a Collect button) replaces the default AcceptDialog.
      *Done when:* there's a screenshot, and there's no panel when nothing was earned.

## Phase 3 — Puzzles
- [ ] **3.1 Puzzle data:** `Content.PUZZLES` with 2×2, 3×3, 4×4, 5×5, 7×7, Megaminx (`moves_per_solve`,
      `solve_value`, `unlock_cost`, `grid`). Use the starting curve in PLAN §4.
      *Done when:* the data is in place and a test checks every puzzle is a net gain in Solves per move over the one before it.
- [ ] **3.2 Active puzzle [D1]:** puzzle state in `GameState`, with moves per solve and solve value read from it. Save v2:
      old saves start on 3×3 if they own any upgrade, otherwise 2×2.
      *Done when:* there's a migration test that loads a v1 save, and the game starts on 2×2.
- [ ] **3.3 Puzzle picker:** a row of puzzle buttons above the cube. Locked ones show their unlock cost; the next one teases in "Next goal".
      *Done when:* there's a screenshot, and buying a puzzle switches to it.
- [ ] **3.4 N×N cube view:** `CubeView` draws 2–7 grids and a pentagon-ish Megaminx face, keeping the same
      `scramble_step()` / `show_solved()` API.
      *Done when:* there's a screenshot per puzzle in `docs/screenshots/puzzles/`.
- [ ] **3.5 Rebalance (early game):** tune puzzles and helpers with the simulator.
      *Done when:* the first helper, first upgrade and 3×3 targets pass as real (not expected-failure) pacing tests.

## Phase 4 — Depth
- [ ] **4.1 Method chain:** Beginner → CFOP → Roux → ZZ → God's Number, each ×0.7 moves per solve, with a per-puzzle floor.
      Replaces the hand-written `cfop`/`roux` upgrades (migrate their ids).
      *Done when:* tests cover the floor and the old-id migration.
- [ ] **4.2 Generated helper milestones:** ×2 at 1/10/25/50/100/150/200 owned, generated from one table in `content.gd`.
      *Done when:* adding a helper automatically gets its milestones, and a test checks this.
- [ ] **4.3 Synergies and solve value:** e.g. "Club Coaching" (each Club gives Friends +1 %), and upgrades that use
      `solve_value_mult` ("Sponsorship deal", "Prize money"). New effect types go in `Content.EFFECT_TYPES` and `GameState`.
      *Done when:* each new effect type has a test.
- [ ] **4.4 Tap scaling:** tap upgrades that add a % of moves/s to each tap.
      *Done when:* the sim shows taps still give ≥ 10 % of income at 30 min when tapping 3/s.
- [ ] **4.5 Six more helpers** past the Lab (e.g. Pro Team, Cubing Federation, Cube Museum, AI Solver,
      Orbital Cube Station, Quantum Solver), so costs reach ~1e15.
      *Done when:* they're in the data with icons and descriptions, and their milestones are generated.
- [ ] **4.6 Rebalance (first hour):** ~40 upgrades in total.
      *Done when:* the "something new every 1–3 min", Robot and 4×4 pacing tests pass for real.

## Phase 5 — Prestige: World Championship
- [ ] **5.1 Trophy formula and Compete screen:** `floor(sqrt(run_solves / 1e6))` to start, each unspent trophy +2 % all moves.
      The Compete screen shows the trophies you'll get, the new bonus, and exactly what you keep and lose.
      *Done when:* there's a screenshot and tests cover the formula.
- [ ] **5.2 Reset logic + save v3:** keeps trophies, achievements and settings; resets Solves, helpers, upgrades, puzzles and methods.
      *Done when:* tests check what resets and what stays, and there's a v2 → v3 migration test.
- [ ] **5.3 Trophy shop:** permanent perks (start with 3×3, +2 h offline cap, auto-buy Friends, start with 10 Friends, …) as data.
      *Done when:* each perk has a test.
- [ ] **5.4 Tune prestige [D6]:**
      *Done when:* the sim's first prestige and second-run (≤ 50 % time) pacing tests pass.

## Phase 6 — Goals
- [ ] **6.1 Achievements:** data (`id`, `name`, `description`, condition type + value), checked once a second, each giving
      +1 % all moves, with a toast when earned. Save v4. ~40 achievements (first solve, every puzzle, 1M moves, sub-X, …).
      *Done when:* there are tests for the conditions and the v3 → v4 migration, and a screenshot of the tab and toast.
- [ ] **6.2 Stats tab:** time played, total taps, best solves/s, solves per puzzle, achievements x/y, trophies earned.
      *Done when:* stats survive save/load and prestige where intended, and tests cover this.

## Phase 7 — Active play
- [ ] **7.1 Golden Scramble:** a glowing cube appears every 2–5 min for 12 s. Clicking it gives a random buff
      (×7 moves for 30 s, or 15 minutes' worth of Solves instantly). The timing logic lives in `GameState`.
      *Done when:* tests cover the buff math and expiry, and a buff survives save/load.
- [ ] **7.2 Scramble Challenge:** an optional 10-second burst where taps count ×10. Never required.
      *Done when:* there are tests, and a screenshot.

## Phase 8 — 3D cube [D3]
- [ ] **8.1 3D cube:** a `SubViewport` with N×N×N cubies (current puzzle); each move tweens a real 90° face turn (~0.12 s),
      queued and sped up. Above 12 moves/s it shows a fast-spin effect instead of every turn. Same API as `CubeView`.
      *Done when:* it works in GL Compatibility, the smoke run is clean, and there's a screenshot per puzzle size.
- [ ] **8.2 Resolution pass:** check 1280×720, 1920×1080 and 2560×1440; add a background and final layout tweaks.
      *Done when:* there are screenshots at all three sizes.

## Phase 9 — Release
- [ ] **9.1 Windows export [D2]:** export preset, `.ico` icon, version in the corner, 64-bit build.
- [ ] **9.2 itch.io [D4]:** page text, screenshots, `butler` upload, a feedback link.
- [ ] **9.3 Steam (optional) [D4]:** Steamworks ($100 per game), store page, capsule art, GodotSteam for achievements
      and cloud saves. GodotSteam is an addon, so log it in the CHANGELOG.
- [ ] **9.4 Launch checklist:** fresh-install test, offline progress across a reboot, a 1-hour soak test with no errors.

## Phase 10 — After launch
- [ ] Bug fixes from player reports
- [ ] New puzzles: Pyraminx, Skewb, Square-1
- [ ] Seasonal events
- [ ] Second prestige layer
