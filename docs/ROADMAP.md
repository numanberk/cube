# Roadmap

Task checklist for `docs/PLAN.md`. Do the **next unchecked task**, one per session.
Tick it only when its **Done when** is true and `tools/run_tests.sh` prints `All good.`
Tasks marked **[D#]** need that owner decision (PLAN §7) first. If it's unanswered, ask, don't guess.
Tasks marked **(PR)** come from `docs/PLAYER_RESEARCH.md` (what our player loves in their favourite idle games); read
the matching row there before starting one.
If a task is too big for one session, split it here (e.g. 1.3a / 1.3b) and do the first part.

## Milestone 1 — Playable core ✅
- [x] Tap to make moves, moves complete solves
- [x] 6 helpers with scaling costs
- [x] 7 upgrades (tap, global, per-helper, moves-per-solve)
- [x] Autosave every 10 s and on quit, offline progress (8 h cap)
- [x] Headless tests + smoke run

## Phase 0 — Tools and safety
- [x] **0.1 Screenshot script** `tools/screenshot.sh`: runs the main scene under `xvfb-run` with
      `--rendering-driver opengl3` and a throwaway user-data dir. It has preset states (fresh, mid-game, late-game)
      and writes PNGs to a given folder.
      *Done when:* it produces 1280×720 PNGs of all presets in the cloud container, and CLAUDE.md explains how to use it.
- [x] **0.2 Simulator** `tools/simulate.sh` + `tools/simulate.gd`: a headless bot that drives the real `GameState`.
      It's greedy (buys the best-payback item), with configurable taps/s and duration. It logs when each
      helper, upgrade and puzzle is first bought, plus solves/s at 1/5/15/30/60/120 min.
      *Done when:* it writes a table to `docs/BALANCE.md`, and today's numbers roughly match PLAN §1 (everything bought by ~53 min).
- [x] **0.3 Pacing tests:** `test_runner.gd` checks PLAN §2's pacing table with the simulator.
      Targets the current content can't meet yet are *expected failures* that print but don't fail the run.
      *Done when:* tests pass, and the expected-failure list appears in `docs/BALANCE.md`.
- [x] **0.4 Safe saves:** write `save.json.tmp` then rename it; keep `save.bak`; if the save is corrupt, load the backup and warn.
      *Done when:* there are tests for a corrupt main save → loads the backup, and a missing save → starts fresh.

## Phase 1 — 3D cube (D3) ✅
- [x] **1.1 TwistyModel + cube shapes:** `scripts/cube/twisty_model.gd` (`TwistyModel`) and `scripts/cube/puzzle_shapes.gd`
      (`PuzzleShapes.cube(n)` for n = 2–7). Pure data: pieces, axes, layers, `apply`, `inverse`, `random_move`,
      `is_solved`, and WCA `notation` (`R`, `U'`, `F2`, `Rw`, `3Rw` on big cubes). No nodes.
      *Done when:* tests cover, for every n: a move applied 4× = solved; a random 50-move scramble + its inverse = solved;
      a scrambled cube is not solved; piece count = n³ − (n−2)³; and the notation strings.
- [x] **1.2 PuzzleView3D (static):** `scenes/puzzle_view_3d.tscn` + `scripts/ui/puzzle_view_3d.gd`. It renders a TwistyModel in a
      `SubViewport`: rounded cubies made with `SurfaceTool`, rounded-rect sticker shader, key + ambient light,
      3/4 camera framed to the puzzle size. It replaces `CubeView` in `main.tscn` with the same API
      (`scramble_step()`, `show_solved()`) plus `set_puzzle(id)`. **Clicking the puzzle taps.**
      *Done when:* screenshots of 2×2, 3×3, 5×5 and 7×7 are in `docs/screenshots/cube/`, the headless smoke run is clean,
      and clicking the puzzle calls `Game.tap()`.
- [x] **1.3 Animated turns:** each `scramble_step()` queues a real layer turn (rotate the layer's MultiMesh transforms, ~0.12 s, eased) and bakes it
      into the model. Turns get shorter as the queue grows. Above ~12 visual moves/s it switches to the speed-spin
      effect. On `show_solved()`, it plays the move history backwards at high speed (≤ 1 s), then flashes and bounces.
      *Done when:* the model and view agree after 1,000 random moves (a test compares sticker colours), there's no
      queue growth at 1,000 moves/s, and screenshots show a turn mid-animation and a solved flash.
- [x] **1.4 Stage and camera:** drag rotates the view and springs back (a drag doesn't tap), idle sway, vignette stage
      background, soft contact shadow, and a move ticker under the puzzle (last ~8 moves in notation).
      *Done when:* there's a screenshot, and a test or smoke check that a drag of > 6 px doesn't count as a tap.
- [x] **1.5 Graphics settings and cleanup:** `Graphics: High / Low` (MSAA, shadow, stage effects; stored for now in a small
      config the Phase 3 Settings autoload will take over). Delete the 2D `scripts/ui/cube_view.gd`.
      Add a `bench` preset to `tools/screenshot.sh` (7×7 at max speed, 600 frames, logs average frame time).
      *Done when:* bench runs without errors (and the frame time is noted in the CHANGELOG; xvfb is software-rendered,
      so the owner confirms real fps on their PC), and there are no references to `CubeView` left.

## Phase 2 — Look ✅
- [x] **2.1 Theme:** `ui/theme.tres` set as the project theme. One OFL font (e.g. Inter) in `assets/fonts/`, plus
      `assets/CREDITS.md`. Button states (normal/hover/pressed/disabled/focus), panels, tabs, progress bar, one accent colour.
      Remove per-node overrides from `main.tscn`.
      *Done when:* there are no `theme_override_*` lines left except deliberate ones, and before/after screenshots are in `docs/screenshots/`.
- [x] **2.2 Layout:** top bar (Solves, solves/s, settings button), the puzzle stage large on the left, the shop on the right,
      a "Next goal" strip under the stage (cheapest locked thing and how far away it is), and a "Click the cube (Space)"
      hint. The old Turn button is removed.
      *Done when:* it works at 1280×720 and 1920×1080, and there are screenshots.
- [x] **2.3 Shop cards:** `scenes/shop_card.tscn` replaces the text Buttons. Each card has an icon, name, short description,
      a big owned count, the cost (accent when affordable, grey when not), and "+X/s" total. Affordable cards lift on hover.
      Locked helpers show as "???" cards with their requirement. Upgrades become a grid of icon tiles with a tooltip panel,
      and the Upgrades tab shows a badge "(N)" when any are buyable.
      *Done when:* you can tell affordable from not at a glance in screenshots, and the next locked item is always visible.
- [x] **2.4 Juice:** floating "+N" at the cursor on tap, a rising "+X Solves" plus a particle burst on each solve
      (pooled, ≤ 20 on screen), the Solves counter tweens up, the puzzle squashes slightly on tap.
      *Done when:* the smoke run at 1,000 moves/s is clean, and there's a screenshot.

## Phase 3 — Sound and feel ✅
- [x] **3.1 Audio autoload + SFX** (soft, warm sounds that fit lo-fi): `scripts/autoload/audio.gd` with Master/Music/SFX buses. Turn click (random pitch ±8 %,
      lower on bigger puzzles), solve chime (rate-limited to ~4/s), buy sound, unlock sting. CC0 sounds, credited.
      *Done when:* each event plays a sound, 100 solves in one frame don't play 100 chimes, and tests pass.
- [x] **3.2 Music system (lo-fi, D7):** `Content.TRACKS` (id, title, artist, license, file, `unlock_puzzle`). The Audio autoload has two
      players crossfading over 2 s, the modes *Follow progress* / *Shuffle unlocked* / *Loop one*, and ducks to 30 % when
      the window is unfocused. Add at least **2 lo-fi placeholder tracks** (CC0/CC-BY, style in PLAN §4.3; if they can't be downloaded,
      list candidates with links in the CHANGELOG for the owner).
      *Done when:* tracks loop and crossfade with no two at full volume (tested via the player volumes), and licenses
      are recorded in `assets/CREDITS.md`.
- [x] **3.3 Buy ×1 / ×10 / Max:** the cost of n helpers is a geometric series sum in `GameState`; there's a toggle on the shop.
      *Done when:* tests cover ×10 cost, Max with too few Solves, and Max = 0, and cards show the cost for the chosen amount.
- [x] **3.4 Settings autoload and tab:** `scripts/autoload/settings.gd` → `user://settings.cfg`. A settings panel has
      Master/Music/SFX volume, music mode, **Jukebox** (unlocked tracks to play; locked ones show "Unlock 4×4 to hear this"),
      unfocused-window audio (duck/mute/keep), Graphics High/Low (taking over from 1.5), Reduce motion, number notation,
      and "Reset save" behind a dialog that names what will be lost.
      *Done when:* settings survive a restart and a save reset, and Reduce motion turns off sway, squash, particles and speed-spin.
- [x] **3.5 Keyboard:** *(done early in 2.2: removing the Turn button needed it)* Space/Enter tap from anywhere through an input action (not button focus); holding the key does **not** repeat.
      *Done when:* there's a test or smoke check that echo events are ignored.
- [x] **3.6 Offline panel:** a styled "Welcome back" panel (time away, Solves earned, a Collect button) replaces the default AcceptDialog.
      *Done when:* there's a screenshot, and there's no panel when nothing was earned.

## Phase 4 — Puzzles (D9: all unlocked puzzles run at once)
- [x] **4.1 Puzzle data:** `Content.PUZZLES` (id, name, shape, `moves_per_solve`, `solve_value`, `unlock_cost`, `requires_prestige`)
      using the starting curve in PLAN §4.1, and each track linked to its puzzle.
      *Done when:* a test checks each puzzle earns more Solves per move than the one before it.
- [x] **4.2 Parallel puzzles + save v2 [D9]:** `GameState` stores the unlocked puzzles, each with its own move progress,
      the focused puzzle, and the helper split (a weight per puzzle). Helper moves are divided by the split; taps go to the
      focused puzzle; each puzzle completes its own solves with its own `moves_per_solve` and `solve_value`. Income is the
      sum. Unlocking a puzzle moves the whole split onto it (so not touching the split plays like a ladder). Presets:
      *Focus newest*, *Spread evenly*. Signals `puzzle_unlocked`, `focus_changed`, `split_changed`; unlocked tracks follow
      unlocked puzzles. Migration: v1 progress goes to the starting puzzle; old saves get 3×3 unlocked too if they own any upgrade.
      The simulator must learn to buy puzzles and (for now) keep the default split.
      *Done when:* there's a v1 → v2 migration test, a new game has only 2×2, and tests cover the split (puzzle moves add up to
      helper moves), taps going to the focused puzzle, per-puzzle solves, and the unlock moving the split.
- [x] **4.3a Puzzle row + focus [D9]:** one big `PuzzleView3D` (the focused puzzle) and a row of small ones under it for every
      other unlocked puzzle, each always on Graphics Low, turning at the speed of its own share and showing its solves/s.
      Clicking a small one focuses it (the big and small views swap). The next locked puzzle shows as a "???" card with its
      cost (also in "Next goal"). Unlocking drops the new puzzle in with a short animation and fades to its track.
      *Done when:* there are screenshots with 1, 3 and 6 puzzles; a test or smoke check covers click-to-focus; and the
      bench (extended to show all 6) stays within 1.5× of the single-puzzle frame time.
- [ ] **4.3b Split controls [D9]:** a small panel to set each puzzle's share (+/− or sliders that always add up to 100 %),
      the two presets, and each puzzle's moves/s and solves/s next to its share. All changes go through `GameState`.
      *Done when:* tests cover that shares always add up to 100 % and presets give the right split, and there's a screenshot.
- [ ] **4.4 Megaminx:** `PuzzleShapes.megaminx()` (12 faces, 72° turns, Pochmann notation `R++ D-- U`), with the view rendering
      pentagonal pieces.
      *Done when:* model tests cover a move applied 5× = solved and scramble + inverse = solved, and there's a screenshot.
- [ ] **4.5 More placeholder tracks:** one per remaining puzzle tier plus "Finals" (or candidates listed for the owner).
      *Done when:* every `Content.TRACKS` entry has a file or an explicit "owner to supply" note in CREDITS, and the
      Jukebox shows them correctly locked/unlocked.
- [ ] **4.6 Puzzle Mastery (PR):** each puzzle gains mastery XP from its own solves, so every running puzzle levels in parallel
      (levels 1–100, XP curve as data),
      with milestone perks at 5/10/25/50/100 (e.g. +10 % moves on that puzzle, −1 move per solve, +1 % all moves).
      Kept through prestige. A mastery bar on every puzzle in the row. Save change → bump the save version with a migration.
      *Done when:* tests cover XP gain, level-ups, perk effects and the migration, and mastery shows in a screenshot.
- [ ] **4.7 Rebalance (early game):** tune puzzles, helpers and mastery with the simulator. The bot learns to choose a split.
      *Done when:* the first helper, first upgrade and 3×3 targets pass as real (not expected-failure) pacing tests, **and the
      bot's best split at 30 min is a real mix** (no puzzle above ~70 %), so splitting is a real choice (PLAN §4.1 design risk).

## Phase 5 — Depth
- [ ] **5.1 Method chain:** Beginner → CFOP → Roux → ZZ → God's Number, each ×0.7 moves per solve, with a per-puzzle floor.
      Replaces the hand-written `cfop`/`roux` upgrades (migrate their ids).
      *Done when:* tests cover the floor and the old-id migration.
- [ ] **5.2 Generated helper milestones:** ×2 at 1/10/25/50/100/150/200 owned, generated from one table in `content.gd`.
      *Done when:* adding a helper automatically gets its milestones, and a test checks this.
- [ ] **5.3 Synergies and solve value:** e.g. "Club Coaching" (each Club gives Friends +1 %), and upgrades that use
      `solve_value_mult` ("Sponsorship deal", "Prize money"). New effect types go in `Content.EFFECT_TYPES` and `GameState`.
      *Done when:* each new effect type has a test.
- [ ] **5.4 Tap scaling:** tap upgrades that add a % of moves/s to each tap.
      *Done when:* the sim shows taps still give ≥ 10 % of income at 30 min when tapping 3/s.
- [ ] **5.5 Six more helpers** past the Lab (e.g. Pro Team, Cubing Federation, Cube Museum, AI Solver, Orbital Cube Station,
      Quantum Solver), so costs reach ~1e15, each with an icon.
      *Done when:* they're in the data, their milestones are generated, and there's a screenshot of the shop.
- [ ] **5.6 Algorithm Lab (PR):** real-time research that keeps running offline (Idle Skilling's hatchery / Perfect Tower's lab).
      One research slot to start (more from the trophy tree). Projects are data: learn OLL, learn PLL, finger tricks,
      lookahead, and the method chain from 5.1 (buying a method becomes researching it). Each takes minutes to hours.
      The game logic (timers, completion while offline) lives in `GameState`; there's a Lab tab with progress bars.
      *Done when:* tests cover a project finishing online, finishing while offline (capped like offline progress), and
      save/load mid-research, and there's a screenshot of the tab.
- [ ] **5.7 Helper Promotion (PR, optional):** at 100 owned, a helper can be promoted: its count resets to 0, it gets a
      permanent ×3 (stacking per promotion), and its milestones start again. Never required. Only do this task if the
      5.8 sim run shows the first hour still needs more decisions; otherwise move it to Phase 11.
      *Done when:* tests cover the reset, the multiplier and the cost curve after promotion.
- [ ] **5.8 Rebalance (first hour):** ~40 upgrades in total.
      *Done when:* the "something new every 1–3 min", Robot, 4×4 and 5×5 pacing tests pass for real.

## Phase 6 — Prestige: World Championship
- [ ] **6.1 Trophy formula and Compete screen:** `floor(sqrt(run_solves / 1e6))` to start, each unspent trophy +2 % all moves.
      The Compete screen shows the trophies you'll get, the new bonus, and exactly what you keep and lose. It plays "Finals".
      *Done when:* there's a screenshot and tests cover the formula.
- [ ] **6.2 Reset logic + save v3:** keeps trophies, achievements, unlocked tracks and settings; resets Solves, helpers,
      upgrades, puzzles and methods. 7×7 and Megaminx become unlockable after the first championship.
      *Done when:* tests check what resets and what stays, and there's a v2 → v3 migration test.
- [ ] **6.3 Trophy perk tree (PR):** permanent perks as data, arranged in 4 branches: Practice (start with 3×3, +offline cap),
      Team (start with 10 Friends, helper boosts), Competition (unlocks Competitions 8.3, medal bonuses) and Automation
      (unlocks 6.3b). As in Idle Skilling, **the first node of each branch unlocks a system**. Nodes need their parent.
      *Done when:* each perk has a test, and there's a screenshot of the tree.
- [ ] **6.3b Auto-buyers and auto-Compete (PR):** toggles bought in the Automation branch: auto-buy the cheapest helper,
      auto-buy upgrades, auto-unlock the next puzzle, and auto-Compete when the trophy gain reaches a set amount.
      The logic is in `GameState` (checked once a second); the toggles live in a small Automation panel.
      *Done when:* tests cover each auto-buyer, auto-Compete's threshold, and that nothing runs before it's bought.
- [ ] **6.4 Tune prestige (D6: ~90 min):**
      *Done when:* the sim's first prestige lands at 80–100 min, and the second run reaches the same point in ≤ 45 min, as real pacing tests.

## Phase 7 — Goals
- [ ] **7.1 Achievements:** data (`id`, `name`, `description`, condition type + value), checked once a second, each giving +1 %
      all moves, with a toast when earned. Save v4. **~100 achievements (PR)**, mostly tiered (Solve 1/10/100/1K/…,
      own 1/10/100 of each helper, every puzzle, every track heard, mastery levels, …), shown with an x/y progress bar
      so they work as a map of the game, like Revolution Idle's.
      *Done when:* there are tests for the conditions and the v3 → v4 migration, and a screenshot of the tab and toast.
- [ ] **7.2 Stats tab:** time played, total taps, best solves/s, solves per puzzle, achievements x/y, trophies earned.
      *Done when:* stats survive save/load and prestige where intended, and tests cover this.

- [ ] **7.3 Cube Collection (PR) [D10]:** ~40 cubes as data (budget, magnetic, stickerless, flagship, world-record cubes…),
      each with 1–5 stars and a small passive (e.g. +2 % moves on 3×3). Sources: Golden Scramble, Competitions,
      achievements. Duplicates merge into the next star. Every random drop has a pity counter (guaranteed after N tries).
      A Collection tab shows owned and "???" cards.
      *Done when:* tests cover drops with pity, merging, passives and save/load, and there's a screenshot.
- [ ] **7.4 Comp Kit loadout (PR):** 5 typed slots (Main cube, Backup cube, Timer, Mat, Lube) filled from the collection,
      with set bonuses for matching brands (Idle Pins formations / Perfect Tower modules). Only the kit's items give
      their full bonus; the rest of the collection gives a small "owned" bonus.
      *Done when:* tests cover slot types, set bonuses and swapping, and there's a screenshot.

## Phase 8 — Active play and Hall of Fame (D12: before 1.0)
- [ ] **8.1 Golden Scramble:** a small golden 3D cube flies across the stage every 2–5 min for 12 s. Clicking it gives a random buff
      (×7 moves for 30 s, or 15 minutes' worth of Solves instantly). The timing and buff logic live in `GameState`.
      *Done when:* tests cover the buff math and expiry, a buff survives save/load, and there's a screenshot.
- [ ] **8.2 Scramble Challenge:** an optional 10-second burst where taps count ×10, with a result card. Never required.
      *Done when:* there are tests and a screenshot.

- [ ] **8.3 Competitions (PR):** timed events like Idle Skilling's raids: Local → Regional → National → Continental → Worlds.
      Each asks for a solves/s target held for 60 s with your current kit and puzzle. Medals (bronze/silver/gold) give
      permanent bonuses and collection drops. You can fail and come back later. Unlocked by the Competition branch (6.3).
      *Done when:* tests cover pass/fail, medal rewards and the unlock, and there's a screenshot.
- [ ] **8.4 Challenge runs (PR):** a championship run with a rule: Beginner method only, No helpers, One-handed
      (taps ×0.5), Big cubes only, No upgrades… Finishing one gives a permanent reward. 6–9 challenges as data.
      *Done when:* tests cover each rule's restriction and its reward, and there's a screenshot.
- [ ] **8.5 Coach rules (PR) [D11]:** Perfect Tower-style automation without code: a list of if/then rules picked from
      menus (If <helper costs < X % of Solves / trophy gain ≥ N / a research slot is free> → <buy / Compete / start
      research>). Unlocked late in the Automation branch. Every rule shows exactly what it will do.
      *Done when:* tests cover each condition and action type, and there's a screenshot.

- [ ] **8.6 Hall of Fame reset + save version bump (PR) [D12]:** a second prestige layer. Entering the Hall of Fame resets
      championships (trophies, the trophy tree except what Legacy perks keep) and everything a championship resets, for
      **Legacy points** (starting formula from total trophies ever earned, for the sim to tune). Keeps achievements,
      collection, mastery and settings. A screen shows exactly what you keep and lose, like Compete.
      *Done when:* tests check what resets and what stays, there's a migration test, and there's a screenshot.
- [ ] **8.7 Legacy perk tree (PR):** perks as data. The first node automates Compete completely (Revolution Idle's
      "later layers automate earlier ones"), and every branch adds something new to do (new competition tier, new
      challenges, more lab slots), so the second layer isn't just a bigger number (Idle Pins' weak spot).
      *Done when:* each perk has a test, and there's a screenshot of the tree.
- [ ] **8.8 Tune the Hall of Fame:** pick the target time for the first Hall of Fame with the owner after a playtest
      (suggested ~8–12 h of play), add it to `tools/pacing.gd`, and tune until it passes. The sim learns multiple runs.
      *Done when:* the new pacing target and the multi-run targets (7×7/Megaminx timing, second run ≤ 50 %) pass for real.

## Phase 9 — Polish
- [ ] **9.1 Resolution pass:** 1280×720, 1920×1080 and 2560×1440; final background and layout tweaks.
      *Done when:* there are screenshots at all three sizes.
- [ ] **9.2 First-time hints:** short, skippable hints ("Click the cube", "Buy your first Friend", "Upgrades are here").
      *Done when:* a fresh save shows them once, and they never show again after being dismissed or done.
- [ ] **9.3 Credits screen:** in-game list of every asset and track with its license (required for CC-BY).
      *Done when:* it matches `assets/CREDITS.md` (a test compares them).
- [ ] **9.4 Final music and mix [D8]:** final tracks in, loudness matched (~−16 LUFS music, SFX balanced against it).
      *Done when:* the owner signs off in `docs/FEEDBACK.md`.

## Phase 10 — Release
- [ ] **10.1 Windows export [D2]:** export preset, `.ico` icon, version in the corner, 64-bit build.
- [ ] **10.2 itch.io [D4]:** page text, screenshots, `butler` upload, a feedback link.
- [ ] **10.3 Steam (optional) [D4]:** Steamworks ($100 per game), store page, capsule art, GodotSteam for achievements and
      cloud saves. GodotSteam is an addon, so log it in the CHANGELOG.
- [ ] **10.4 Launch checklist:** fresh-install test, offline progress across a reboot, a 1-hour soak test with no errors,
      fps check on a low-end PC with Graphics Low.

## Phase 11 — After launch
- [ ] Bug fixes from player reports
- [ ] New puzzles: Pyraminx, Skewb, Square-1 (each a new `PuzzleShapes` entry and a new track)
- [ ] Seasonal events
- [ ] A third prestige layer, if players ask for more
