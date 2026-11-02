# Cube Idle — Development Plan

How we get from today's prototype to a released PC game.
`docs/ROADMAP.md` is the task checklist. This file explains the *why* and the *how*.
If the two disagree, the owner decides and both files get fixed.

---

## 1. Where we are (measured 2026-11-02)

The owner's verdict: *"it looks bad and there is no progression."* A review backed that up with numbers:

| Problem | Evidence |
|---|---|
| Content runs out | A greedy bot tapping 3/s owns every helper and all 7 upgrades by **minute 53**. After that there are only more copies of the same 6 helpers at 1.15^n, and production levels off (~180K solves/s at 6 h). There's no prestige and no new goal. |
| Slow start | The first Friend costs 75 taps and pays back in 150 s. Minutes 0–6 are only Friends. A player who never taps gets nothing at all. |
| Nothing changes | The screen at minute 60 looks like the screen at minute 1. `solve_value_mult` exists but no upgrade uses it. |
| Looks like a prototype | Default Godot theme. Shop rows are text Buttons, and affordable vs. unaffordable rows look nearly the same. You press a separate button instead of the cube. The Upgrades tab has no badge when something is buyable. A solve gets 0.35 s of single-colour face as feedback. |

**So the order of work is:** first tools to *see* and *measure* the game, then fix the look, then fix
the progression, then build the long loop (prestige) and the polish on top.
The old plan put theme and balance last. That would mean building 30 tasks on a game that looks bad
and is tuned by guesswork.

---

## 2. Goal

| | Target |
|---|---|
| Platform | Windows PC first (Linux/Mac exports are nearly free later) |
| Engine | Godot 4.7, GDScript, GL Compatibility |
| Sessions | Fun in 5-minute check-ins *and* 1-hour active sessions |
| Total content | ~20–40 hours until the late game runs out |
| Release | itch.io first (free / pay-what-you-want demo), then Steam |

**What makes it ours:** real cubing culture. Puzzles go from 2×2 to Megaminx, methods go from Beginner
to God's Number, and helpers grow from a friend after school to a world-class speedcubing lab.
Every number should feel like something a cuber would recognize, and **progress should be visible on the
cube itself**: it grows, gains stickers, and turns faster as you advance.

### Pacing targets
Every balance change is checked against this table by the simulator (task 0.3). "Tapping" means 3 taps/s.

| Moment | Target |
|---|---|
| First helper | ≤ 20 s |
| First upgrade | < 1 min |
| Something new (helper, upgrade, puzzle, method) | every 1–3 min during the first hour, never > 10 min after that |
| 3×3 unlocked | ~5 min |
| Solving Robot | ~10 min |
| 4×4 unlocked | ~30 min |
| First World Championship (prestige) | ~90 min (owner can change; see D6) |
| Second run to the same point | ≤ 50 % of the first run's time |
| Never tapping | Still makes progress (e.g. the first Friend is free or there's a small tap-free trickle) |

---

## 3. How we work

### Roles
- **Owner:** decides direction, playtests after each phase, writes `docs/FEEDBACK.md`, answers the open decisions (section 7).
- **Claude sessions (any account):** do **one roadmap task per session**, keep tests green, leave notes.

### The session loop
1. The owner opens a Claude session on `numanberk/cube` and pastes the **session prompt** below.
2. Claude reads `CLAUDE.md`, this plan, `ROADMAP.md`, `CHANGELOG.md` and `FEEDBACK.md`.
   **Unhandled feedback comes before the next roadmap task.**
3. Claude does the **next unchecked task**. One task per session keeps changes small and easy to undo.
4. Claude runs `bash tools/run_tests.sh` (and `tools/screenshot.sh` for anything visual),
   updates ROADMAP and CHANGELOG, then commits and pushes.
5. The owner pulls (GitHub Desktop → **Pull**) and plays the change in Godot.

**Session prompt (copy this):**
> Read CLAUDE.md, docs/PLAN.md, docs/ROADMAP.md, docs/CHANGELOG.md and docs/FEEDBACK.md.
> Handle any open feedback first, otherwise do the next unchecked task in the roadmap — only that one task.
> Run the tests, update ROADMAP and CHANGELOG, then commit and push. If your session was given its own
> branch, push there and open a pull request; otherwise push to main.

For a specific task, replace the second sentence with e.g. "Do task 3.2."

### Rules that prevent a mess
- **One session at a time.** Two accounts editing at once will create conflicts.
- **Don't edit in Godot while a session is running.** Pull first, then edit, commit and push.
- **Every task has a "Done when"** in the roadmap. A task isn't ticked until that's true.
- **Tests stay green.** A red test is fixed before anything new is started.
- **Visual tasks leave a screenshot** in `docs/screenshots/` (PNG, keep each < 300 KB), linked from
  the CHANGELOG entry. The owner can see progress without opening Godot.
- **Balance tasks leave a sim run** in `docs/BALANCE.md`.
- **Don't guess open decisions.** If a task depends on an unanswered decision in section 7, stop and ask the owner.
- **Playtest after every phase**, not every task.

---

## 4. Phases

Each phase ends with something playable. Task details and "Done when" are in the roadmap.

| # | Phase | Why it's here | Tasks |
|---|---|---|---|
| 0 | **Tools and safety** | You can't fix what you can't see or measure. Save safety comes before 3 save-format changes. | screenshot script, simulator, pacing tests, safe saves |
| 1 | **Look** | The owner's #1 complaint, and every later task builds on the theme and shop cards. | theme + font, layout + click the cube, shop cards + teasers, juice |
| 2 | **Feel** | Makes the existing loop satisfying before adding more of it. | sound, Buy ×1/×10/Max, settings, keyboard, offline panel |
| 3 | **Puzzles** | The main progression axis. Starting on a 2×2 also fixes the slow start. | puzzle data, active puzzle + save v2, picker, N×N cube view, first rebalance |
| 4 | **Depth** | Fills the first hour so something new arrives every few minutes. | methods, generated helper milestones, synergies + solve value, tap scaling, 6 more helpers, rebalance |
| 5 | **Prestige: World Championship** | Gives the long loop and replaces "it ran out at minute 53". | formula + Compete screen, reset + save v3, trophy shop, tune second run |
| 6 | **Goals** | Gives long-term targets between prestiges. | achievements (save v4), stats tab |
| 7 | **Active play** | Rewards being present without making taps mandatory. | Golden Scramble, Scramble Challenge |
| 8 | **3D cube** *(if D3 = 3D)* | The centerpiece, built once the puzzle tiers it has to show exist. | 3D view with real face turns, resolution pass |
| 9 | **Release** | Ship it. | Windows export, itch.io, Steam (optional), launch checklist |
| 10 | **After launch** | Keep it alive. | bug fixes, Pyraminx/Skewb/Square-1, events, second prestige layer |

### Key design calls (with reasons)
- **Puzzles are tiers, and progress shows on the cube.** Unlocking 3×3 raises moves per solve *and* Solves per solve
  by more, so it's a net gain, and the cube view changes size. Starting curve for the sim to tune:
  2×2 = 8 moves / 1 Solve, 3×3 = 20 / 4, 4×4 = 60 / 18, 5×5 = 120 / 50, 7×7 = 300 / 200, Megaminx = 700 / 800.
- **Methods multiply moves per solve** (×0.7 each: Beginner → CFOP → Roux → ZZ → God's Number) with a floor per puzzle
  (e.g. 20 for 3×3, God's Number), so they never make a puzzle trivial.
- **Upgrades are generated from data where possible.** Helper milestones (×2 at 1/10/25/50/100/150/200 owned) come from
  one table in `content.gd`. Target is ~40 upgrades by the end of Phase 4, mostly generated.
- **Taps stay relevant:** later tap upgrades add a % of moves/s to each tap. Hold-to-repeat is **not** allowed.
- **Prestige:** `trophies = floor(sqrt(run_solves / 1e6))` as a starting formula, each unspent trophy +2 % all moves.
  The sim tunes the divisor to hit the first-prestige target.
- **Assets are CC0/OFL only** (e.g. Kenney audio, Inter font), each listed in `assets/CREDITS.md` with source and license.
- **Accessibility:** a "Reduce motion" setting turns off squash, particles and screen effects.

---

## 5. Architecture as it grows

- `game.gd` stays the single owner of state. When it passes ~600 lines, move logic into helper scripts under
  `scripts/systems/` (e.g. `prestige.gd`, `achievements.gd`) that `GameState` calls. UI still talks only to `Game`.
- **The simulator drives the real `GameState`**, never a copy of the formulas, so it can't drift from the game.
- Content stays as data. If `content.gd` gets huge, split it into `content_helpers.gd`, `content_upgrades.gd`, and so on.
- **Save versions:** v1 now → v2 puzzles → v3 prestige → v4 achievements. Every bump has a `_migrate()` step and a test
  that loads the older format. Saves are written to a temp file then renamed, with `save.bak` kept (task 0.4).
- Settings save to `user://settings.cfg`, separate from the game save, so a reset never wipes volume.
- New screens are new scenes (`scenes/tabs/settings_tab.tscn`, `scenes/shop_card.tscn`) instanced in `main.tscn`.
- One global theme at `ui/theme.tres`. No per-node colour or font overrides once it exists.
- Audio goes through an `Audio` autoload with Master/SFX/Music buses.
- Assets go in `assets/{audio,fonts,images}/`.

---

## 6. Timeline (rough)

| Weeks | Phases | You'll have |
|---|---|---|
| 1 | 0–1 | Tools, a game that looks finished on the surface |
| 2 | 2–3 | Sound and feel, puzzle tiers, a fixed early game |
| 3 | 4–5 | A full first hour and prestige: a complete loop |
| 4 | 6–7 | Achievements, stats, golden cubes |
| 5 | 8 | The 3D cube |
| 6 | 9 | Balanced, exported, on itch.io |

This assumes a few sessions per day. Going slower is fine; the order matters more than the speed.

---

## 7. Open decisions for the owner

Claude sessions must **not** guess these. Write the answer in place of the question so every session sees it.
Each question has a recommendation, and it says which task first needs the answer.

- **D1 Puzzles** (needed by 3.2): one active puzzle at a time, or all unlocked puzzles running in parallel?
  *Recommended: one active.* It's simpler, the cube always shows one puzzle, and tiers stay readable.
- **D2 Final name** (needed by 9.1): keep "Cube Idle" or pick another?
- **D3 Look** (needed by 8.1): clean flat 2D cube, or a 3D cube as the centerpiece?
  *Recommended: 3D.* The cube is the game's identity. Phases 1–7 work with either.
- **D4 Price** (needed by 9.2): free, pay-what-you-want on itch, or paid on Steam?
- **D5 Music** (needed by 2.1): none, one calm loop, or several tracks? *Recommended: one calm loop, off by default.*
- **D6 First prestige timing** (needed by 5.4): ~90 min (recommended, because the long loop starts sooner) or 2–3 h?
