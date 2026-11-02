# Cube Idle — Development Plan

From today's playable prototype to a released PC game.
`docs/ROADMAP.md` is the checklist version of this plan; this file explains the *why* and the *how*.

---

## 1. Goal

| | Target |
|---|---|
| Platform | Windows PC first (Linux/Mac exports are nearly free later) |
| Engine | Godot 4.7, GDScript |
| Session length | Fun in 5-minute check-ins *and* 1-hour active sessions |
| First prestige | ~2–3 hours of play |
| Total content | ~20–40 hours until the late game runs out |
| Release | itch.io first (free/pay-what-you-want demo), then Steam |

**What makes it ours:** real cubing culture. Puzzles go from 2×2 to Megaminx, methods go from Beginner
to God's Number, and helpers grow from a friend after school to a world-class speedcubing lab.
Every number should feel like something a cuber would recognize.

---

## 2. How we work

### Roles
- **Owner (you):** decides direction, playtests after each phase, writes feedback, answers open questions (section 6).
- **Claude sessions (any account):** do one roadmap task per session, keep tests green, leave notes.

### The session loop
1. Owner opens a Claude session on the `numanberk/cube` repo and pastes the **session prompt** below.
2. Claude reads `CLAUDE.md`, this plan, `ROADMAP.md`, `CHANGELOG.md` and `FEEDBACK.md`.
3. Claude does the **next unchecked task** in the roadmap. One task per session keeps changes small and easy to undo.
4. Claude runs `bash tools/run_tests.sh`, updates ROADMAP and CHANGELOG, commits and pushes.
5. Owner clicks **Pull** in GitHub Desktop and plays the change in Godot.

**Session prompt (copy this):**
> Read CLAUDE.md, docs/PLAN.md, docs/ROADMAP.md, docs/CHANGELOG.md and docs/FEEDBACK.md.
> Do the next unchecked task in the roadmap — only that one task. Run the tests,
> update ROADMAP and CHANGELOG, then commit and push to main.

For a specific task, replace the second sentence with e.g. "Do task 2.3."

### Rules that prevent a mess
- **One session at a time.** Two accounts editing at once will create conflicts.
- **Don't edit in Godot while a session is running.** Pull first, then edit, then commit and push.
- **Every task has a "Done when"** in the roadmap. Claude doesn't tick it until that's true.
- **Tests stay green.** A red test is fixed before anything new is started.
- **Playtest after every phase**, not every task. Write what felt good or bad in `docs/FEEDBACK.md`.

---

## 3. Phases

Each phase ends with something playable. Estimates assume ~1 Claude session per task.

### Phase 1 — Game feel (≈5 tasks)
Make the existing loop satisfying before adding more of it.
- **1.1 Floating "+N Solves" text** that rises and fades on each solve (pooled labels, capped at ~20 on screen).
- **1.2 Sound:** cube-turn click (slight random pitch), solve chime, buy sound. Use CC0 assets
  (e.g. Kenney audio packs) and record their source + license in `assets/CREDITS.md`.
  Add an `Audio` autoload with SFX/Music buses.
- **1.3 Buy ×1 / ×10 / Max** toggle for helpers. Cost math goes in `GameState` (geometric series sum), with tests.
- **1.4 Settings tab:** master/SFX volume sliders, "Reset save" behind a confirm dialog naming what is lost.
  Settings save to `user://settings.cfg` (separate from the game save).
- **1.5 Keyboard:** Space/Enter taps from anywhere (an input action, not button focus); hold-to-repeat is *not* allowed.

### Phase 2 — Puzzles (≈4 tasks)
The main progression axis.
- **2.1 Puzzle data** in `content.gd`: 2×2, 3×3, 4×4, 5×5, 7×7, Megaminx. Each has `moves_per_solve`,
  `solve_value`, `unlock_cost`. Example curve: 2×2 = 15 moves / 1 Solve, 3×3 = 50 / 5, 4×4 = 120 / 20, and so on.
- **2.2 Active puzzle** in `GameState` (one active at a time, *pending owner decision D1*). Save v2 + migration test.
- **2.3 Puzzle picker UI** (row of puzzle buttons above the cube; locked ones show their unlock cost).
- **2.4 CubeView supports N×N** grids (2–7) and a pentagon-ish Megaminx face.

### Phase 3 — Depth (≈4 tasks)
- **3.1 Method chain** as upgrades: Beginner → CFOP → Roux → ZZ → God's Number (moves per solve × 0.7 each, floor of 20 for 3×3).
- **3.2 Helper tier upgrades:** ×2 when owning 10, 25, 50 and 100 of a helper (generated from data, not hand-written).
- **3.3 Synergy upgrades:** e.g. "Club Coaching": each Club gives Friends +1%.
- **3.4 Two more helpers** at the late end (e.g. "Cubing Federation", "Quantum Solver") to fill the curve.

Target: ~40 upgrades in total by the end of Phase 3.

### Phase 4 — Achievements and stats (≈2 tasks)
- **4.1 Achievements** as data (`id`, `name`, `description`, condition type + value), checked once per second.
  Each one gives +1% to all moves, which rewards collecting them. Toast pop-up when earned. Save v3.
- **4.2 Stats tab:** time played, total taps, best solves/sec, solves per puzzle, achievements x/y.

### Phase 5 — Prestige: World Championship (≈3 tasks)
- **5.1 Trophies formula:** `trophies = floor(sqrt(run_solves / 1e6))`. Each unspent trophy = +2% all moves.
  "Compete" button shows exactly what you keep and lose, then confirms.
- **5.2 Reset logic:** keeps trophies, achievements and settings; resets Solves, helpers, upgrades and puzzles. Save v4.
- **5.3 Trophy shop:** permanent perks (start with 3×3 unlocked, +10% offline cap, auto-buy Friends, …).

### Phase 6 — Active play (≈2 tasks)
- **6.1 Golden Scramble:** a glowing cube appears every 2–5 minutes for 12 seconds. Click it for a random buff
  (×7 moves for 30 s, or instant 15 minutes' worth of Solves).
- **6.2 Scramble Challenge** mini-game: a 10-second burst where taps count ×10. Optional, never required.

### Phase 7 — Look and polish (≈4 tasks)
- **7.1 3D cube:** a `SubViewport` with 26 cubies; each move tweens a real face turn (90°, ~0.12 s);
  falls back to the 2D view at more than 12 moves/s. Keeps the same `scramble_step()` / `show_solved()` API.
- **7.2 Theme resource** (`ui/theme.tres`): one font (OFL-licensed, e.g. Inter), button styles, colors. Remove per-node overrides.
- **7.3 Juice:** button press scale, number tick-up animation, solve particle burst. Respect a "Reduce motion" setting.
- **7.4 Background and layout pass** at 1280×720, 1920×1080 and 2560×1440.

### Phase 8 — Balance (≈2 tasks, repeat as needed)
- **8.1 Simulator** `tools/simulate.gd`: a headless bot that buys the cheapest best-value item and logs when each
  helper/upgrade/puzzle unlocks. Outputs a table to `docs/BALANCE.md`.
- **8.2 Tune** content numbers to hit these targets: first helper < 30 s, first upgrade < 1 min, Robot ~10 min,
  4×4 ~30 min, first prestige 2–3 h. Re-run after every content change.

### Phase 9 — Release (≈5 tasks)
- **9.1 Save safety:** write to a temp file then rename; keep `save.bak`; recover from a corrupt save.
- **9.2 Windows export:** export preset, `.ico` icon, version number shown in the corner, a 64-bit build.
- **9.3 itch.io:** page text, screenshots, upload with `butler`. Gather feedback from players.
- **9.4 Steam (optional):** Steamworks account ($100 fee per game), store page, capsule art,
  GodotSteam integration for achievements and cloud saves. *Note: GodotSteam is an addon; log it in the CHANGELOG.*
- **9.5 Launch checklist:** fresh-install test, offline progress test across a reboot, a 1-hour soak test with no errors.

### Phase 10 — After launch
Bug fixes from player reports, new puzzle tiers (Pyraminx, Skewb, Square-1), seasonal events, a second prestige layer.

---

## 4. Architecture as it grows

- `game.gd` stays the single owner of state. When it passes ~600 lines, split logic into helper scripts under
  `scripts/systems/` (e.g. `prestige.gd`, `achievements.gd`) that `GameState` calls. The UI still talks only to `Game`.
- Content stays as data. If `content.gd` gets huge, split it into `content_helpers.gd`, `content_upgrades.gd` and so on.
- **Save versions:** v1 now, v2 puzzles, v3 achievements, v4 prestige. Every bump has a migration and a test that loads the older format.
- New screens are new scenes under `scenes/` (e.g. `scenes/tabs/settings_tab.tscn`), added to `main.tscn` as instances.
- Assets go in `assets/{audio,fonts,images}/`, each listed in `assets/CREDITS.md` with its license.

---

## 5. Timeline (rough)

| Weeks | Phases | You'll have |
|---|---|---|
| 1 | 1 | A satisfying core loop with sound |
| 2–3 | 2–3 | Puzzles and real progression depth |
| 4 | 4–5 | Achievements and prestige: a complete loop |
| 5 | 6–7 | Golden cubes, 3D cube, polished look |
| 6 | 8–9 | Balanced, exported, on itch.io |

This assumes a few sessions per day. It's fine to go slower; the order matters more than the speed.

---

## 6. Open decisions for the owner

Claude sessions should **not** guess these. If a task depends on one that's unanswered, ask the owner.

- **D1 Puzzles:** one active puzzle at a time (simpler, the plan's default) or all unlocked puzzles running in parallel?
- **D2 Final name:** keep "Cube Idle" or choose another?
- **D3 Look:** clean flat 2D or the 3D cube as the centerpiece?
- **D4 Price:** free, pay-what-you-want on itch, or paid on Steam?
- **D5 Music:** none, a single calm loop, or several tracks?

Write answers here (replace the question) so every session sees them.
