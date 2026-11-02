# Cube Idle — Development Plan

How we get from today's prototype to a released PC game.
`docs/ROADMAP.md` is the task checklist. This file explains the *why* and the *how*.
If the two disagree, the owner decides and both files get fixed.

**Owner decisions so far:** one active puzzle (D1), a **3D cube** as the centerpiece (D3),
**several music tracks** (D5), **first prestige at ~90 min** (D6), **lo-fi music** (D7). See §7.

---

## 1. Where we are (measured 2026-11-02)

The owner's verdict: *"it looks bad and there is no progression."* A review backed that up with numbers:

| Problem | Evidence |
|---|---|
| Content runs out | A greedy bot tapping 3/s owns every helper and all 7 upgrades by **minute 53**. After that there are only more copies of the same 6 helpers at 1.15^n, and production levels off (~180K solves/s at 6 h). There's no prestige and no new goal. |
| Slow start | The first Friend costs 75 taps and pays back in 150 s. Minutes 0–6 are only Friends. A player who never taps gets nothing at all. |
| Nothing changes | The screen at minute 60 looks like the screen at minute 1. `solve_value_mult` exists but no upgrade uses it. |
| Looks like a prototype | Default Godot theme. A flat 3×3 square of random colours, not a cube. Shop rows are text Buttons; affordable vs. unaffordable look the same. You press a separate button instead of the cube. A solve gets 0.35 s of single-colour face as feedback. |

**Order of work:** tools to *see* and *measure* the game → the **3D cube** (the centerpiece everything
else is built around) → the UI look → sound and music → puzzle progression → depth → prestige → goals →
active play → polish → release.

---

## 2. Goal

| | Target |
|---|---|
| Platform | Windows PC first (Linux/Mac exports are nearly free later) |
| Engine | Godot 4.7, GDScript, **GL Compatibility** (the 3D cube must run on old integrated GPUs) |
| Sessions | Fun in 5-minute check-ins *and* 1-hour active sessions |
| Total content | ~20–40 hours until the late game runs out |
| Release | itch.io first (free / pay-what-you-want demo), then Steam |

**What makes it ours:** real cubing culture, shown on a real 3D puzzle. Puzzles go from 2×2 to Megaminx,
methods go from Beginner to God's Number, and helpers grow from a friend after school to a world-class
speedcubing lab. The cube on screen really turns: each move is a real face turn written in WCA notation
(`R U R' U'`), and each solve really un-scrambles. **Progress is visible on the puzzle itself:** it grows from 2×2 to 7×7,
becomes a Megaminx, and turns faster as helpers pile up. Every puzzle tier also unlocks its own music track.

### Pacing targets
Every balance change is checked against this table by the simulator (task 0.3). "Tapping" means 3 taps/s.

| Moment | Target |
|---|---|
| First helper | ≤ 20 s |
| First upgrade | < 1 min |
| Something new (helper, upgrade, puzzle, method, track) | every 1–3 min during the first hour, never > 10 min after that |
| 3×3 unlocked | ~5 min |
| Solving Robot | ~10 min |
| 4×4 unlocked | ~30 min |
| 5×5 unlocked | ~60 min |
| First World Championship (prestige) | **~90 min** (D6) |
| 7×7 / Megaminx | 2nd–3rd run / 4th–5th run |
| Second run to the same point | ≤ 50 % of the first run's time |
| Never tapping | Still makes progress (e.g. the first Friend is free or there's a small tap-free trickle) |

---

## 3. How we work

### Roles
- **Owner:** decides direction, playtests after each phase, writes `docs/FEEDBACK.md`, answers open decisions (§7),
  and supplies anything a Claude session can't make (final music, store art, store accounts).
- **Claude sessions (any account):** do **one roadmap task per session**, keep tests green, leave notes.

### The session loop
1. The owner opens a Claude session on `numanberk/cube` and pastes the **session prompt** below.
2. Claude reads `CLAUDE.md`, this plan, `ROADMAP.md`, `CHANGELOG.md` and `FEEDBACK.md`.
   **Open feedback comes before the next roadmap task.**
3. Claude does the **next unchecked task**. One task per session keeps changes small and easy to undo.
4. Claude runs `bash tools/run_tests.sh` (and `tools/screenshot.sh` for anything visual),
   updates ROADMAP and CHANGELOG, then commits and pushes.
5. The owner merges the branch if needed, pulls (GitHub Desktop → **Pull**) and plays the change in Godot.

**Session prompt (copy this):**
> Read CLAUDE.md, docs/PLAN.md, docs/ROADMAP.md, docs/CHANGELOG.md and docs/FEEDBACK.md.
> Handle any open feedback first, otherwise do the next unchecked task in the roadmap — only that one task.
> Run the tests, update ROADMAP and CHANGELOG, then commit and push. If your session was given its own
> branch, push there and open a pull request; otherwise push to main.

For a specific task, replace the second sentence with e.g. "Do task 4.2."

### Rules that prevent a mess
- **One session at a time.** Two accounts editing at once will create conflicts.
  **Merge each session's pull request before starting the next session**, or the next one starts from old files.
- **Don't edit in Godot while a session is running.** Pull first, then edit, commit and push.
- **Every task has a "Done when"** in the roadmap. A task isn't ticked until that's true.
- **Tests stay green.** A red test is fixed before anything new is started.
- **Visual tasks leave a screenshot** in `docs/screenshots/` (PNG, each < 300 KB), linked from the CHANGELOG.
- **Balance tasks leave a sim run** in `docs/BALANCE.md`.
- **Don't guess open decisions.** If a task depends on an unanswered decision in §7, stop and ask the owner.
- **Playtest after every phase**, not every task.
- **Too big for one session?** Split the task in the roadmap (e.g. 1.3a / 1.3b), do the first part, and say so in the CHANGELOG.

---

## 4. Design

### 4.1 Puzzles — one active puzzle (D1)
- Puzzles are a **ladder**: 2×2 → 3×3 → 4×4 → 5×5 → 7×7 → Megaminx. Each is a one-time unlock bought with Solves.
- **One puzzle is active.** All taps and helper moves go into it. Buying the next tier switches to it automatically
  with a tier-up animation (the old puzzle spins away, the new one drops in, and its music track fades in).
- Each tier raises moves per solve *and* Solves per solve by more, so moving up is always a net gain.
  Starting curve for the simulator to tune:

  | Puzzle | Moves/solve | Solves/solve | Unlock cost |
  |---|---|---|---|
  | 2×2 | 8 | 1 | start |
  | 3×3 | 20 | 4 | ~150 |
  | 4×4 | 60 | 18 | ~25K |
  | 5×5 | 120 | 50 | ~1.5M |
  | 7×7 | 300 | 200 | after prestige |
  | Megaminx | 700 | 800 | after prestige |
- You can switch back to an unlocked lower puzzle. It's never better for income, but some achievements
  and Scramble Challenges use it.
- Methods (Beginner → CFOP → Roux → ZZ → God's Number) multiply moves per solve by ×0.7 each,
  with a **floor per puzzle** (e.g. 20 on 3×3, "God's Number"), so a puzzle never becomes trivial.
- *Later idea (Phase 11):* puzzle mastery, where solves on each puzzle give a small permanent bonus.

### 4.2 The 3D cube (D3)
**Look:** a black plastic body made of rounded cubies, with standard-colour rounded stickers (white/yellow,
red/orange, blue/green; Megaminx uses 12 colours). There's soft key light plus ambient light, and a 3/4 camera
angle showing three faces. The puzzle sways gently when idle. It sits on a "stage" (vignette background,
soft contact shadow) to the left of the shop.

**Interaction:**
- **Click the puzzle = tap.** Each tap plays one real face turn.
- **Drag** rotates the view (it springs back slowly). A drag is not counted as a tap.
- On each solve, the move history since the last solve **plays backwards at high speed** (≤ 1 s),
  the puzzle flashes and bounces, and a "+X Solves" pops out. Then helper moves scramble it again.
- A small ticker under the puzzle shows the last ~8 moves in WCA notation
  (`R U R' U' F2 Rw`; Megaminx uses `R++ D-- U`).

**Speed:** moves join a queue. Each turn takes ~0.12 s, shortened as the queue grows. Above ~12 visual
moves/s the puzzle stops animating every turn: it plays a "speed-spin" effect (fast whole-puzzle wobble,
streaks) and snaps occasional turns. The game's numbers never wait for the animation.

**Architecture** (built so cubes and the Megaminx share one turning system):
- `TwistyModel` (`scripts/cube/twisty_model.gd`): pure data with no nodes, so it's fully unit-tested. A puzzle is a
  list of pieces (position, orientation, sticker colours) and turn axes. A move = rotate every piece whose position
  lies in a layer along an axis by 90° (cubes) or 72° (Megaminx), then snap it to the nearest valid slot.
  It provides `apply(move)`, `inverse(move)`, `random_move()`, `is_solved()` and `notation(move)`.
- `PuzzleShapes` (`scripts/cube/puzzle_shapes.gd`): builds the pieces for `cube(n)` (n = 2–7) and `megaminx()`.
- `PuzzleView3D` (`scenes/puzzle_view_3d.tscn` + `scripts/ui/puzzle_view_3d.gd`): a `SubViewportContainer` →
  `SubViewport` → camera, lights and piece meshes. It animates a turn by parenting the layer's pieces to a pivot,
  tweening the pivot, and baking the result back. It keeps the old API (`scramble_step()`, `show_solved()`) and adds
  `set_puzzle(id)`.
- Meshes are made in code: a rounded box via `SurfaceTool`, and stickers as quads with a small rounded-rectangle shader.
  No imported models, so there's no external tool or addon.
- **This is visual state, not game state.** Sticker positions never affect any number, so this code lives under
  `scripts/cube/` and `scripts/ui/`, not in `game.gd`. It's not saved; a fresh scramble on load is fine.
- **Performance budget:** 7×7×7 = 218 visible cubies + 294 stickers. Must hold 60 fps at 1080p on an integrated GPU.
  A **Graphics: High / Low** setting toggles MSAA, shadows and the stage effects. The headless smoke run must still pass
  (it uses the dummy renderer).
- The old 2D `CubeView` is deleted once the 3D view lands. There's no 2D fallback to maintain.

### 4.3 Music — several tracks (D5)
- **One track per puzzle tier, plus one for the World Championship.** Unlocking a puzzle unlocks its track, so music
  is part of the progression. Working titles:

  **Style: lo-fi (D7).** Mellow lo-fi hip-hop / chillhop at ~70–90 BPM: soft drums, warm keys, vinyl crackle,
  no vocals (or only short wordless chops). Calm enough to idle to for hours, and every track should sit in the same
  family so crossfades sound natural. Each tier adds a bit more energy or texture, so moving up the ladder
  *sounds* like progress:

  | Unlocks with | Track (working title) | Lo-fi flavour |
  |---|---|---|
  | 2×2 (start) | Practice Room | sparse: soft kick, Rhodes chords, rain/room noise, ~70 BPM |
  | 3×3 | First Sub-20 | classic chillhop: swung drums, jazzy piano, ~80 BPM |
  | 4×4 | Parity | warmer: bass line, guitar licks, tape wobble |
  | 5×5 | Big Cube Energy | the most upbeat: ~90 BPM, brighter drums, a little sax or synth lead |
  | 7×7 | Long Solve | spacious, ambient lo-fi with long pads and a slow beat |
  | Megaminx | Twelve Faces | lo-fi with a twist: koto/kalimba or vibraphone melody |
  | First World Championship | Finals | celebratory lo-fi with a fuller arrangement and a bigger drop; plays on the Compete screen, then joins the Jukebox |
- **SFX match the music:** soft, warm clicks and a mellow chime (e.g. a muted Rhodes or kalimba note), not bright arcade sounds.
- **Playback modes** (in Settings): *Follow progress* (the default: plays the active puzzle's track, and sometimes
  a random unlocked one), *Shuffle unlocked*, or *Loop one track*.
- **Jukebox** in Settings lists unlocked tracks with title and artist. Locked ones show "Unlock 5×5 to hear this".
- **`Audio` autoload** with Master / Music / SFX buses. Two music players crossfade over 2 s, and there are never two
  songs at full volume. Music ducks to 30 % while the window is unfocused (setting: duck / mute / keep).
  Defaults: Music 50 %, SFX 70 %.
- SFX follow the puzzle: bigger puzzles click lower, and the Megaminx clicks softer. Solve chimes are rate-limited
  (at most ~4/s however many solves happen).
- **Files:** OGG Vorbis, looping, 96–128 kbps, ≤ 4 MB each, ~40 MB total. They go in `assets/audio/music/`.
- **Licensing (important for a paid release, D4):** only **CC0** or **CC-BY** (credit in `assets/CREDITS.md` *and* an
  in-game Credits screen). Never NC (non-commercial), ND or "free for personal use", because those would block selling the game.
- **Where the music comes from:** Claude sessions can't compose audio. Sessions add CC0/CC-BY **lo-fi** placeholder tracks
  if the container can download them; otherwise they list candidate tracks (with links and licenses) in the
  CHANGELOG for the owner to add. The **final** source is still open (**D8**, needed by 9.4).

### 4.4 Economy
- **Upgrades are generated from data where possible.** Helper milestones (×2 at 1/10/25/50/100/150/200 owned) come
  from one table in `content.gd`. Target is ~40 upgrades by the end of Phase 5, most of them generated.
- **Synergies** (e.g. "Club Coaching": each Club gives Friends +1 %) and **solve value** upgrades ("Sponsorship deal")
  use the existing `solve_value_mult`.
- **Taps stay relevant:** later tap upgrades add a % of moves/s to each tap. Hold-to-repeat is **not** allowed.
- **12 helpers** in total by the end of Phase 5, with costs reaching ~1e15.
- **Prestige — World Championship:** `trophies = floor(sqrt(run_solves / 1e6))` as the starting formula. Each unspent trophy
  gives +2 % all moves. The Trophy shop has permanent perks. 7×7 and Megaminx are only reachable after prestige.

### 4.5 Look and feel
- One global theme (`ui/theme.tres`) with one OFL font (e.g. Inter). Dark UI with a single accent colour, so the
  colourful puzzle is the brightest thing on screen.
- Shop cards (icon, name, owned count, cost green/grey). Locked items appear as "???" cards with their requirement,
  so there's always a visible next goal. The Upgrades tab has a badge when something is buyable.
- Juice: floating "+N" numbers, solve bursts, the counter ticks up, cards lift on hover. A **Reduce motion** setting
  turns off squash, particles, camera sway and the speed-spin effect.
- Assets are CC0/OFL/CC-BY only, each in `assets/CREDITS.md`.

---

## 5. Phases

Each phase ends with something playable. Task details and "Done when" are in the roadmap.

| # | Phase | Why it's here | ~Tasks |
|---|---|---|---|
| 0 | **Tools and safety** | You can't fix what you can't see or measure. Save safety comes before 3 save-format changes. | 4 |
| 1 | **3D cube** | The centerpiece (D3). The layout, puzzles, juice and golden cubes all build on it. | 5 |
| 2 | **Look** | The UI around the cube: theme, layout, shop cards, juice. | 4 |
| 3 | **Sound and feel** | SFX, the music system (D5), Buy ×N, settings, keyboard, offline panel. | 6 |
| 4 | **Puzzles** | The main progression axis (D1). Starting on 2×2 fixes the slow start. | 6 |
| 5 | **Depth** | Fills the first hour so something new arrives every few minutes. | 6 |
| 6 | **Prestige: World Championship** | Gives the long loop. 7×7, Megaminx and the "Finals" track sit behind it. | 4 |
| 7 | **Goals** | Gives long-term targets between prestiges: achievements and stats. | 2 |
| 8 | **Active play** | Rewards being present without making taps mandatory. | 2 |
| 9 | **Polish** | Resolution pass, first-time hints, credits screen, final music. | 4 |
| 10 | **Release** | Windows export, itch.io, Steam (optional), launch checklist. | 4 |
| 11 | **After launch** | Bug fixes, Pyraminx/Skewb/Square-1, events, puzzle mastery, second prestige layer. | — |

---

## 6. Architecture as it grows

```
scripts/autoload/game.gd       GameState: ALL rules and numbers (unchanged role)
scripts/autoload/audio.gd      Audio: buses, SFX, music playlist/crossfade/Jukebox (Phase 3)
scripts/autoload/settings.gd   Settings: user://settings.cfg (volumes, graphics, motion, notation) (Phase 3)
scripts/cube/twisty_model.gd   TwistyModel: pure puzzle state + moves + notation (Phase 1)
scripts/cube/puzzle_shapes.gd  PuzzleShapes: cube(n), megaminx() (Phase 1)
scripts/ui/puzzle_view_3d.gd   PuzzleView3D: renders + animates a TwistyModel (Phase 1)
scripts/systems/*.gd           Split-outs from game.gd once it passes ~600 lines (prestige, achievements)
scenes/shop_card.tscn, scenes/tabs/*.tscn, scenes/puzzle_view_3d.tscn
ui/theme.tres
assets/{audio/sfx,audio/music,fonts,images}/ + assets/CREDITS.md
tools/screenshot.sh, tools/simulate.sh (+ .gd)
docs/BALANCE.md, docs/screenshots/
```
- `game.gd` stays the single owner of *game* state. The UI and audio talk to `Game` through its methods and signals
  (`solved`, `purchased`, and new ones like `puzzle_changed` and `tier_unlocked`).
- **The simulator drives the real `GameState`**, never a copy of the formulas, so it can't drift from the game.
- Content stays as data (`Content.PUZZLES`, `Content.TRACKS`, `Content.ACHIEVEMENTS`, …). If `content.gd` gets huge,
  split it into `content_helpers.gd`, `content_upgrades.gd`, and so on.
- **Save versions:** v1 now → **v2 puzzles** (incl. unlocked tracks) → **v3 prestige** → **v4 achievements**.
  Every bump has a `_migrate()` step and a test that loads the older format. Saves are written to a temp file then
  renamed, with `save.bak` kept (task 0.4).
- Settings live in `user://settings.cfg`, separate from the save, so a reset never wipes volume or graphics choices.
- **GL Compatibility limits:** no SDFGI/SSR/volumetrics. Use one directional light (+ optional cheap shadow), ambient,
  and simple shaders. Test the 3D view headless (dummy renderer) and under xvfb (screenshots).
  Real frame rate is checked by the owner on a real PC.

---

## 7. Decisions

Claude sessions must **not** guess open decisions. Write the answer in place of the question so every session sees it.

### Answered
- **D1 Puzzles:** **one active puzzle at a time**, as a ladder you can switch back down (see §4.1).
- **D3 Look:** **3D cube as the centerpiece** (see §4.2). It's built in Phase 1, and the 2D view is removed.
- **D5 Music:** **several tracks**: one per puzzle tier plus "Finals", with Jukebox and crossfade (see §4.3).
- **D6 First prestige timing:** **~90 minutes** into the first run. The simulator's pacing test checks this (task 6.4),
  and the second run must reach the same point in ≤ 45 min.
- **D7 Music style:** **lo-fi** (mellow lo-fi hip-hop / chillhop, no vocals; per-track flavours in §4.3).

### Open
- **D2 Final name** (needed by 10.1): keep "Cube Idle" or pick another?
- **D4 Price** (needed by 10.2): free, pay-what-you-want on itch, or paid on Steam?
  *Either way, only CC0/CC-BY assets, so a paid release stays possible.*
- **D8 Final music source** (needed by 9.4; placeholders are fine until then): (a) the owner picks final CC0/CC-BY lo-fi
  tracks, (b) buys a royalty-free lo-fi pack with a license that allows commercial games, or (c) commissions a lo-fi
  producer for the 7 tracks. *Recommended: (b) or (c)*, so the soundtrack is consistent and can be sold on Steam later.

---

## 8. Timeline (rough)

| Weeks | Phases | You'll have |
|---|---|---|
| 1 | 0–1 | Tools, safe saves, a real 3D cube that turns and un-scrambles |
| 2 | 2–3 | A finished-looking UI, sound effects, music with crossfade |
| 3 | 4 | Puzzle tiers 2×2 → 5×5, a fixed early game, a track per tier |
| 4 | 5–6 | A full first hour, prestige, 7×7 and Megaminx |
| 5 | 7–8 | Achievements, stats, Golden Scramble |
| 6 | 9 | Polish, first-time hints, credits, final music |
| 7 | 10 | Balanced, exported, on itch.io |

This assumes a few sessions per day. Going slower is fine; the order matters more than the speed.
