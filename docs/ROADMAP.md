# Roadmap

Work top to bottom unless the owner says otherwise. Tick items as you finish them.
Each milestone is sized for roughly one session. Don't start the next one with the
previous one half-done; if you must stop, say exactly where in the CHANGELOG.

## Why this roadmap was rewritten (2026-11-02)
Owner feedback: "it looks bad and there is no progression". Measured problems:
- **Content runs out at ~53 min.** A greedy bot tapping 3/s owns every helper and all
  7 upgrades by minute 53. After that it's only more copies of the same 6 helpers at
  1.15^n, and production levels off (~180K solves/s at 6 h). There's no prestige and no new goal.
- **Slow start.** First Friend = 75 taps, pays back in 150 s. Minutes 0–6 are only Friends.
- **Nothing changes as you progress.** Same flat 3×3 square, same button and list at min 1 and min 60.
  `solve_value_mult` exists, but no upgrade uses it.
- **Looks like a prototype.** Default Godot theme. Shop rows are text-only Buttons, and affordable
  vs. unaffordable rows look nearly the same. You press a separate button instead of the cube.
  The Upgrades tab hides buyable items with no badge. A solve gets 0.35 s of single-colour face as feedback.

### Pacing targets (all balance work is checked against these)
| Moment | Target |
|---|---|
| First purchase (tapping ~3/s) | ≤ 20 s |
| Something new (helper, upgrade, puzzle) | every 1–3 min during the first hour |
| First puzzle tier up (2×2 → 3×3) | ~5 min |
| First World Championship (prestige) available | 45–60 min |
| Second run reaches the same point | ≤ 50 % of the first run's time |
| Idle-only play (no taps) | can still get started (first helper free or tap-free trickle) |

## Milestone 1 — Playable core ✅
- [x] Tap to make moves, moves complete solves
- [x] 6 helpers with scaling costs
- [x] 7 upgrades (tap, global, per-helper, moves-per-solve)
- [x] Autosave every 10 s and on quit, offline progress (8 h cap)
- [x] Headless tests + smoke run

## Milestone 2 — Tools to see and measure the game (do first, small)
So that later sessions aren't working blind.
- [ ] `tools/screenshot.sh`: runs the main scene under `xvfb-run` with
      `--rendering-driver opengl3`, optionally with a cheat state, and saves PNGs to a
      folder outside the repo. (Proven to work in the cloud container; ALSA errors are harmless.)
- [ ] `tests/sim.gd`: headless bot that drives the **real** `GameState` (not a copy of
      the formulas). Greedy buy-best-payback, configurable taps/s. Prints a timeline
      (first purchase, each unlock, solves/s at 1/5/15/30/60 min).
- [ ] Pacing tests in `test_runner.gd` that use the sim to check the pacing targets above,
      so balance can't drift back.

## Milestone 3 — Visual overhaul ("make it look like a game")
- [ ] One global `theme.tres` set in Project Settings: bundled OFL font (put the font in
      `assets/fonts/` and note the license), button states (normal/hover/pressed/disabled),
      panel and tab styles, one accent colour. No per-node colour overrides after this.
- [ ] Shop card scene (`scenes/shop_card.tscn` + script) instead of text Buttons:
      icon, name, short description, big owned count, cost shown green when affordable
      and grey when not, plus a "+X/s" contribution line. Affordable cards glow or lift.
- [ ] Locked helpers show as a dark "???" card with the unlock requirement, so there's always a visible next goal.
- [ ] Badge on the Upgrades tab when something is buyable. Upgrades become a grid of
      icon tiles with a tooltip panel (Cookie Clicker style), not long text rows.
- [ ] Click the **cube itself** to tap. Keep the button only as a Space/Enter hint.
- [ ] Juice: cube squash on tap, floating "+N" numbers at the cursor, a particle burst and a
      floating "+X Solves" on every solve, the Solves counter tweens instead of jumping.
- [ ] Layout: top bar (Solves, solves/s), cube large in the centre-left, shop on the right,
      a "next goal" strip under the cube. Subtle background gradient or pattern.
- [ ] Sound: turn click (pitch varies), solve chime, buy sound, volume in Settings.

## Milestone 4 — Economy rework (the progression fix)
Use the sim from Milestone 2 for every change here.
- [ ] **Puzzle tiers** as the main chapters: 2×2 → 3×3 → 4×4 → 5×5 → 7×7 → Megaminx.
      Each tier is a one-time purchase that raises moves per solve *and* Solves per solve by more,
      so it's a clear net gain. Start the game on 2×2 (≈8 moves per solve), which also fixes the slow start.
      Data in `Content.PUZZLES`, new effect wiring in `GameState`. The cube view must
      show the current puzzle (more stickers per face), so progress is visible.
- [ ] **Milestone upgrades generated from data**: every helper gets ×2 at 1/5/25/50/100/150/200 owned.
      Generate them in `content.gd` from a table, not by hand.
- [ ] Use `solve_value_mult` (e.g. "Sponsorship deals", "Prize money").
- [ ] 6 more helpers past the Lab (e.g. Pro Team, Cube Museum, AI Solver, Orbital Cube
      Station, Quantum Scrambler, Multiverse League) so the cost curve reaches ~1e15.
- [ ] Tap upgrades that scale with production (tap gains +1 % of moves/s per level), so tapping
      stays relevant past minute 10.
- [ ] Buy ×1 / ×10 / Max toggle.
- [ ] Rebalance until the sim meets the pacing table. Record the final numbers in DESIGN.md.
- [ ] Save migration: `SAVE_VERSION` 2, existing saves start on the 3×3 tier if they own any upgrade.

## Milestone 5 — 3D cube
The cube is the game's identity, so it should look like a real one.
- [ ] Replace `CubeView` with a `SubViewport` 3D cube (works in GL Compatibility):
      N×N×N cubies made from rounded `BoxMesh`/stickers, slight idle rotation.
- [ ] Real cube state: each move tweens a real face turn (~0.12 s, queued and sped up when
      helpers are fast). On solve, play a quick un-scramble and a "solved" flash, then re-scramble.
- [ ] Keep the same `scramble_step()` / `show_solved()` API so `main.gd` barely changes.
- [ ] Size follows the current puzzle tier from Milestone 4.

## Milestone 6 — Prestige: World Championship
- [ ] Available once lifetime Solves hit the target (tune to ~45–60 min, first run).
- [ ] Trophies = f(lifetime Solves this run) (e.g. cube root). Each Trophy gives +2 % production.
- [ ] Confirmation screen showing "you will get X Trophies (+Y %)" and what resets.
- [ ] Trophy shop with permanent upgrades: start with N Friends, keep a puzzle tier,
      better offline cap, auto-buy helpers, faster early game.
- [ ] Save migration + tests for reset (what resets, what stays).

## Milestone 7 — Active play and long-term goals
- [ ] "Lucky Scramble": a shiny cube floats across now and then; clicking it gives a random buff
      (×7 production for 30 s, a lump of Solves, or ×5 taps).
- [ ] Speedsolve combo: tapping fast fills a combo meter that multiplies tap moves; it decays when you stop.
- [ ] Achievements tab (each gives +1 % production so they matter), stats tab
      (time played, best solves/s, total taps, Trophies earned).
- [ ] Offline report as a styled panel, not the default AcceptDialog.
- [ ] Settings tab: volume, number notation, reset save (typed confirmation).
- [ ] Keyboard: Space to tap even when the mouse is elsewhere.

## Milestone 8 — Release on PC
- [ ] Windows export preset + app icon
- [ ] Steam/itch.io page prep
