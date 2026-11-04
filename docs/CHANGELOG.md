# Changelog

Newest first. Every session adds an entry: what changed, what's unfinished, notes for the next session.

## 2026-11-04 — Task 5.8: first-hour rebalance
- **Done when met:** the pacing targets "something new every ≤ 3 min in the first hour" (longest wait 2:51), Solving Robot
  (8:34, window 8–12 min), 4×4 (27:53, 25–35) and 5×5 (52:28, 50–70) pass for real; their `expected_failure` marks are
  gone. Still passing: first helper, first upgrade (now Practice Partners I at 0:12), 3×3 (4:22), the 30-min split
  (20/45/35 %), the active profile (×2.38, D13) and never-tapping progress. Still expected failures: ≤ 10-min waits
  after the first hour (13:40 before Neural Upgrades II at ~1:36; the championship at ~90 min should end the run first),
  prestige and the multi-run targets (Phase 6). Margins are thin (the 3-min gap by 9 s, the Robot by 34 s): any content
  change can flip a target, which is what the test is for.
- **Bug fix (GameState):** the upgrade/Lab multiplier cache was keyed only by *how many* upgrades are owned, so swapping
  one for another of the same count reused stale numbers. The balance bot tries upgrades on one at a time, so **every
  trial after the first in a planning pass used the first one's effect**: the never-tapping bot valued every upgrade like
  Cube Lube (nothing, idle) and never bought one, and the tapping bot's choices were partly wrong (all earlier BALANCE.md
  runs). New `invalidate_upgrade_cache()`, called by buying, finishing research, reset, load and the Lab load; code that
  edits `upgrades`/`research_done` directly (the simulator, screenshot presets) calls it too. Test `test_upgrade_cache_swaps`.
  The never-tapping bot now buys upgrades (it picks Efficient Solving) and reaches the 4×4 at ~32 min, the 5×5 at ~57.
- **Why it was too fast:** measured with a throwaway per-30-s trace. Milestones cost a fraction of the copies they
  doubled (×2 at 50 owned for 7 copies' worth), the helper ladder got only ~1.6× worse per Solve per tier while Solves per
  move grew ~60× (puzzles, solve value, methods), and mastery levels grew with log(moves), so after ~20 min old puzzles
  out-earned a fresh 4×4/5×5 and the bot stopped valuing new puzzles. Income doubled every ~15 s at 6–12 min.
- **Numbers (all in `content.gd`):**
  - Helpers: costs Robot 12K, Competition 100K, Factory 1.7M, Lab 34M, Pro Team 450M, Federation 5B, Museum 240B,
    AI 6.7T, Orbital 100T, Quantum 2.1Qa; moves/s Club 3, Robot 33, Competition 180, Factory 1K, Lab 6K, Pro Team 38K,
    Federation 240K, Museum 1.6M, AI 11M, Orbital 75M, Quantum 550M (each tier ~2.5× worse per Solve; DESIGN.md table).
  - **Milestones:** a new row at 5 owned (×1.5), so 8 per helper (I–VIII; ids are by owned count, so saves are fine,
    only the roman numerals of the old II–VII moved up one). I costs 1× the helper's base cost (it follows the first copy),
    the rest ~2 × n × 1.15^n × base (about the price of the copies they double): 15, 80, 1650, 1.1e5, 2.3e8, 3.8e11, 5.5e14.
  - Puzzles: 3×3 300, 4×4 180M (22 Solves/solve), 5×5 250B (80/solve), 7×7 500B (300/solve, so it still pays more per
    move than the 5×5), Megaminx 100T; PLAN §4.1 table updated. Mastery `xp_growth` 1.15 → 1.25.
  - Upgrades: most mid-game costs ×3–30 (Magnetic Cube 36K, Sponsorship 500K, Prize Money 84M, Lab Prototypes 840M…);
    Club Coaching 1 % per Club (was 2 %); **Live Stream ×1.5** (was ×2, 2.5B: the bot hoarded for it, leaving 4-min holes);
    choices: Speed Practice / Efficient Solving 800, specialists 21M, Prize Hunting / Deliberate Practice 35B.
  - Lab/methods: Roux 140K, ZZ 98M (research 13:20, was 20 min), God's Number 200B; 2-look PLL 6 min, Lookahead 10 min
    (was 30: the one slot sat on it), Lookahead/Full PLL/Full OLL costs ×1.4.
  - **Two new synergies** (the chain Club→Friend … Lab→Factory continues): **Pro Scrims** (each Pro Team +1 % Labs, 2B,
    5 Pro Teams) and **Federation Rankings** (each Federation +1 % Pro Teams, 20B, 5 Federations); icons team-idea and podium
    (game-icons.net, Delapouite, CC BY 3.0, in CREDITS). Shot: `docs/screenshots/5.8-rebalance/`.
- **The other side of each choice** (the 5.8 note): the simulator takes a `forbid` list (`simulate.sh --forbid a,b`), and
  BALANCE.md now has a **"Main build vs the other side of each choice"** table: the tapping bot again for the first hour,
  once per pair, never buying the side it picked (lifetime Solves at 60 min, main build 9.8T):
  - **Big-Cube Specialist** was far stronger than Small-Cube (×3 on the puzzles that make most of the income: 35T even at
    ×2), so it's **×1.5** now: 10.5T, and that build passes every pacing target too. Both cost 21M, before the 4×4: Small
    pays at once, Big once the 4×4/5×5 run. (The bot still picks Small: it only values today's income.)
  - **Speed Practice** (taps ×3) instead of Efficient Solving: 2.3T. Taps stop mattering after ~10 min; **S.7** (taps add
    a % of moves/s) is what makes it a real choice. Not changed here.
  - **Deliberate Practice** (×3 mastery XP) instead of Prize Hunting: 3.9T. Mastery is kept through prestige, so it's the
    long-term pick; **Phase 6** should make that visible (e.g. 6.2/6.3). Not changed here.
- **For Phase 6:** lifetime Solves at 90 min are ~1e14, so 6.1's `sqrt(run_solves / 1e6)` would give ~10K trophies;
  pick the divisor from BALANCE.md (note added to 6.1). The 2-hour runs take ~90 s each now (simulate.sh ~4 min in all).
- **Review (diff-reviewer):** no correctness or save issues. Fixed: the comparison ran all three other sides in one run (so
  it couldn't back the content comment), stale cache comments, `--forbid` titles, a test label. Noted: `xp_growth` 1.25
  recomputes levels from saved XP, so **dev saves lose mastery levels** (a level-50 puzzle drops to ~39; the game isn't out,
  so no migration). The specialists are now picked ~8 min before the first big cube, on purpose (now-or-later choice; the
  5.7b review had put them after the 4×4). Only the simulator part of `test_upgrade_cache_swaps` guards the real bug (in
  the game the count always changed). `test_pacing_targets` takes ~2–3 min now (CLAUDE.md updated).
- **5.7 Helper Promotion → Phase 11** (its own rule: only if 5.8 showed the first hour needs more decisions; it doesn't).
- Tests (3752 checks, `All good.`): hard-coded numbers now read from `Content` (3×3 cost, Club Coaching's %, Big-Cube's
  ×1.5); the next-goal order (CFOP 200 now comes before the 3×3 300); `test_upgrade_cache_swaps`.
- **Next: Phase 6, task 6.1** (trophy formula and Compete screen).

## 2026-11-04 — Task 0.6: hooks that make sessions use the subagents (tooling only)
- **Owner: "make them trigger at appropriate times".** Agents described in CLAUDE.md are only used if the model
  remembers to, so `.claude/settings.json` now wires Claude Code hooks to `tools/hooks/workflow.py` (Python 3, stdlib):
  - **remind** (after Edit/Write): first edit of `content.gd`/`game.gd` -> "run `balance-analyst`"; first UI edit
    (`scenes/`, `ui/`, `scripts/ui/`, `assets/icons|fonts|images/`) -> "run `screenshot-checker`". Once per session each.
  - **gate** (before Bash): blocks `git commit` until, for the change set not yet on main (merge-base with
    `origin/main`, else local `main`, else HEAD): tests passed after the last code change, the balance bot ran after the
    last `content.gd`/`game.gd` change, screenshots were taken after the last UI change, and `diff-reviewer` reviewed
    every changed code file (it records the file list; fixing its findings needs no second review). Change sets with
    no code (`docs/`, `.claude/agents/`, `*.md`) pass. Deleted/moved files count as changed when their folder changed.
    Only a real `git [-C dir|-c k=v|--flag] commit` is gated, not one mentioned in quotes or a heredoc.
    Escape: `CUBE_SKIP_GATE=1 git commit ...`, with a CHANGELOG note.
  - **record** (after Bash, Agent, SubagentStop): notes passed checks (dated by when they *started*: the gate notes the
    start time per `tool_use_id`) and finished agents in `.git/cube-workflow.json`. Background Bash runs aren't seen.
    Agents usually run in the background, so a finished agent is recorded from **SubagentStop** (it has `agent_type`
    but not the agent's report; the Agent tool's own PostToolUse fires at launch and is ignored then). Hooks also fire
    for a subagent's own Bash calls, which is how `test-runner`'s and `balance-analyst`'s runs are recorded.
  - The first version was reviewed by `diff-reviewer` (10 findings: `grep -n` hid "All good.", no fallback without
    `origin/main`, deletions skipped the tests, a check counted edits made while it ran, a before-shot passed the
    screenshot check, the commit regex, a shared temp file, doc drift); all fixed and pipe-tested.
  - **aftercommit**: a commit that ticks the last task of a phase asks for a `fun-designer` pass for the owner.
- Verified: every case pipe-tested in a scratch clone; in this session the gate blocked a commit (tests + review
  missing), then allowed it after `test-runner` and `diff-reviewer` ran.
- Windows note: hooks call `python3`. In a local Claude Code on Windows without it they fail open (never block), but
  every Bash call then shows a hook error; install Python 3 or ignore the noise.
- No game code changed; the next roadmap task is whatever the 5.7b entry below says.

## 2026-11-04 — Task 5.7b: choices, pick one of two
- **Three pairs** (`choice_group` in `Content.UPGRADES`; buying one locks the other for this run, a championship (6.2)
  resets upgrades and so the choice): **Speed Practice** (taps ×3) *or* **Efficient Solving** (−20 % moves per solve),
  400 Solves; **Small-Cube Specialist** (×2 on 2×2/3×3) *or* **Big-Cube Specialist** (×3 on 4×4 and up), 300K;
  **Prize Hunting** (solves pay ×1.5) *or* **Deliberate Practice** (×3 mastery XP), 50M. Both sides cost the same.
- **New effect types** `puzzle_mult` (moves on the puzzles in `puzzles`; in `get_puzzle_moves_mult`) and
  `mastery_xp_mult` (in `get_mastery_xp_per_solve`). `_upgrade_mult(type, target)` matches `puzzles` lists too.
- **GameState:** `get_choice_partners(id)`, `get_choice_pick(group)`, `is_upgrade_locked_out(id)`; a locked-out upgrade
  isn't available, isn't a goal, and a damaged save with both sides keeps the first. **No save change** (the pick is
  just the owned upgrade).
- **UI:** choice tiles have a small **PICK 1** badge (new theme variation `ChoiceBadge`) and a tooltip line naming the
  other side; after picking, the pick says **PICKED** and the other stays next to it greyed out (**NOT PICKED**, "—").
  Screenshot option `PICK=<id>`; shots in `docs/screenshots/5.7b-choices/`.
- **Simulator:** picks greedily like any upgrade (it takes Speed Practice, Small-Cube Specialist and Prize Hunting);
  "everything bought" counts one side per pair.
- **Balance:** a bit faster overall (Robot 7:11, 4×4 8:15, 5×5 10:39, active ×2.67; the bot still takes Small-Cube Specialist, at 9:12). The longest first-hour wait reads
  19:41 now (it was 11:58 only because the old 36-min gap was cut off at 1:00:00): the late first hour is thin. **5.8**.
- Tests: pair data (two members, same cost, real puzzles), lock-out, effects, goals skip the locked side, save/load,
  damaged save, a new run reopens the choice; tiles (badge, tooltip, picked/not picked, order).
- **Review fixes (diff-reviewer via a general-purpose agent):** the specialists cost 1M (after the 4×4, so it can be
  compared); an open choice's goal names both sides ("Speed Practice or Efficient Solving") so the strip doesn't pick;
  `_effect_matches()` shared by upgrades and Lab projects; a content comment: never add a shipped upgrade to a group
  without a migration; ROADMAP notes for 6.2 (choices reopen, test), 6.3b (auto-buy skips choice pairs) and 5.8 (the
  greedy bot never values Deliberate Practice, check the other builds); more tests (Small-Cube ×2 incl. taps, tab
  count, locked-out tooltip, goal names). Seen, not changed: the never-tapping bot buys no upgrades at all (was so
  before) — look at it in 5.8.
- **Next: 5.8 rebalance** (5.7 Helper Promotion only if 5.8 shows the first hour needs more decisions), then Phase 6.

## 2026-11-04 — Task 5.6: the Algorithm Lab (save v9)
- **Real-time research, also while the game is closed** (capped at 8 h like offline progress). One project at a time
  (a second slot may come with the trophy tree, 6.3). Paid when started; the effect counts when it finishes.
- **Projects** (`Content.get_lab_projects()`): **every method after the Beginner Method** is now research ("learning a
  method = researching it": CFOP 45 s, Roux 4 min, ZZ 20 min, God's Number 1 h; `research_seconds` in METHODS), plus
  `Content.LAB["projects"]`: **Finger Tricks** (taps ×2, 2 min), **2-look OLL** / **2-look PLL** (−10 % moves per solve each,
  5 / 10 min), **Lookahead** (all moves ×1.25, 30 min, after Finger Tricks), **Full PLL** (−10 %, 1 h, after 2-look PLL),
  **Full OLL** (−15 %, 3 h, after 2-look OLL). Effects use the upgrade effect types (they count in `_upgrade_mult`).
- **Drill sets count as research (S.4 link):** learning 2-look OLL / 2-look PLL / Full PLL / Full OLL in the Solve Station
  drills finishes that project at once, free.
- **GameState:** `research` {id, left}, `research_done`, `start_research()`, `update_research()` (from `_process`, and for
  time away in `apply_save_data`; the welcome-back report says what finished), `finish_research()` (tests/debug),
  `is_research_done()`, `is_research_visible()`, `can_start_research()`, `get_research_progress()`, signals
  `research_started` / `research_finished`. **`buy_method()` now starts the method's research**; `purchased("method")`
  still fires when it's learned, so the showcase, news and tiers didn't change. **Save v9** (`"lab"`), v8 → v9 migration
  (methods already learned stay learned). Planned: **v10 prestige (6.2), v11 achievements (7.1)**.
- **UI:** a **Lab** tab (status line + bar, one card per visible project: time, cost, "Researching · 3m 42s left", ✓ when
  done; the tab title shows "Lab · 3:42" or "Lab (2)"). Method tiles in Upgrades show "Researching 0:32" and their research
  time in the tooltip. News line + sting when research finishes. Running research is its own goal in the goal strip
  ("Research CFOP · 0:32"); a method being researched is no longer a "buy" goal. The simulator researches too (it picks Lab projects like
  upgrades and ticks the Lab).
- **Balance:** the longest first-hour wait fell to 11:58 (was 25:40); active speedup ×2.61. Robot/4×4/5×5 are still early
  (7:07 / 8:11 / 11:08): **5.8**.
- Tests (3475 checks, `All good.`): a project online (paid at start, one slot, no effect until done, half way, done,
  effect, not twice, requirements), CFOP as research, drill sets finishing projects free; save/load mid-research (v9),
  finishing offline + the report, the 8 h cap, done projects saved, v8 → v9 keeps methods; the Lab tab (start, status,
  tab title, ✓). Screenshot tool `LAB=1`; shot in `docs/screenshots/5.6-lab/`.
- **Review fixes (diff-reviewer; the project agents in `.claude/agents/` weren't loaded in this session, so a
  general-purpose agent ran with diff-reviewer's instructions):** drill sets learned before v9 finish their project on
  load; the saved Lab is checked (unknown ids, unmet requirements, a method that isn't the next one, wrong types are
  dropped; time left clamped to the project's length); countdowns use the new `Num.clock()` ("0:32", "1:02:03") instead
  of a mangled cube time; one news line and one sound per method (research_finished skips methods; starting research
  plays the buy sound); names without "Learn " (`topic`) in status, goals, news and the welcome-back line, which no
  longer claims helpers kept solving when only the Lab did; the running Lab card is bright (ShopCard `active`); a busy
  Lab says so on method tiles and Lab cards; the simulator logs a method when its research finishes and counts Lab
  projects in "everything bought". New tests: Lab content data, goals, damaged saves, drilling the running project,
  `Num.clock`, the welcome line.
- **For 5.8:** with one Lab slot the methods hog it (Roux 4 min, ZZ 20 min, God's Number 1 h back to back), so the bot
  only gets to Finger Tricks (500 Solves!) at 1:31. Either give methods their own slot, make the bot weigh cheap
  projects, or shorten method research. Method times in BALANCE.md now show when a method is *learned*.
- **Next: 5.7b "pick one of two" choices** (5.7 Helper Promotion only if 5.8 needs it), then **5.8 rebalance**.

## 2026-11-04 — Task 0.5: project subagents (tooling only, no game changes)
- **Owner asked for subagents** to streamline sessions. Five in `.claude/agents/`, each with a model chosen for its job:
  **diff-reviewer** (Opus, high effort: reviews everything not on `main` against the rules of the code, save migration
  first), **screenshot-checker** (Sonnet: runs `tools/screenshot.sh`, reports clipped text, layout, colours),
  **balance-analyst** (Sonnet: runs `tools/simulate.sh`, explains which pacing targets moved and why),
  **test-runner** (Haiku, low effort: runs `tools/run_tests.sh`, returns only failures), **fun-designer** (Opus, high
  effort: ranked fun/engagement ideas grounded in PLAYER_RESEARCH; proposals only, no manipulative patterns).
- All report only and never commit. CLAUDE.md has a new "Subagents" section (when to use which) and the finish checklist
  now ends with a `diff-reviewer` pass. Ideas from `fun-designer` go to the owner before they become ROADMAP tasks.
- No addons or game code changed. Next roadmap task is unchanged (5.6 Algorithm Lab, after 5.5 landed).
- Next session: please actually use them and note in your CHANGELOG entry if one was unhelpful, so its prompt or model
  can be tuned (they're plain Markdown files; edit the prompt or the `model:` line).

## 2026-11-04 — Task 5.5: six more helpers (12 in all)
- **New helpers past the Speedcubing Lab** (`Content.BUILDINGS`, each ~16× the cost of the last and a bit less efficient
  per Solve): **Pro Team** 30M (180K moves/s), **Cubing Federation** 500M (1.8M), **Cube Museum** 8B (17M), **AI Solver**
  130B (170M), **Orbital Cube Station** 2T (1.6B), **Quantum Solver** 40T (20B). Copies pass 1e15. Each has a
  `milestone_name` (Team Bootcamp, Regional Branches, Exhibit Halls, Neural Upgrades, Launch Windows, Entanglement), so its 7
  milestones are generated by 5.2 (~100 upgrades in all now), and a news title (Pro / Delegate / Curator; AI, Station arm,
  Qubit array use machine codes). Big numbers in content.gd are written in e-notation.
- **6 new icons** (game-icons.net CC BY 3.0 via its GitHub mirror: team-upgrade, globe, greek-temple, circuitry, satellite,
  atom-core), credited in `assets/CREDITS.md`.
- **Screenshot preset `endgame`** (all 12 tiers owned, 30T Solves) and screenshot option `SCROLL=1` (helper list scrolled to
  the bottom). Shots: `docs/screenshots/5.5-helpers/`.
- **Balance:** the first-hour gap is 25:40 (was 34:01), but after it there's a 42-min gap before Team Bootcamp V: the
  pacing is now the job of **5.8**. Note for 5.8: the simulator is getting slow with ~100 upgrades (2-hour runs ~1–2 min;
  the never-tapping run is the slowest), so `test_pacing_targets` is ~1 min; consider caching `_candidates` / skipping
  unaffordable far-off upgrades in `_pick_target`.
- Tests (3444 checks, `All good.`): 12 helpers, each costing and making more than the last, the six new ones each less
  efficient per Solve, milestone names and news titles for all, the top one ≥ 10T (plus the existing icon and milestone tests).
- **Next: 5.6 Algorithm Lab** (real-time research, offline; learned drill sets count).

## 2026-11-04 — Task 5.3: synergies and solve-value upgrades
- **New effect type `synergy`** (`Content.EFFECT_TYPES`, applied in `GameState.get_building_mps` via `_synergy_mult`):
  each owned copy of the `source` helper makes the `target` helper `value` faster. Which synergies are owned is cached with
  the upgrade multipliers; the product uses the live helper counts.
- **8 new hand-written upgrades** (55 upgrades in all with the milestones): synergies **Club Coaching** (each Club +2 %
  Friends, 3K, 5 Clubs), **Robot Sparring** (each Robot +2 % Clubs, 40K), **Talent Scouts** (each Competition +1 % Robots,
  400K), **Factory Supply** (each Factory +1 % Competitions, 6M), **Lab Prototypes** (each Lab +1 % Factories, 90M); solve
  value (the old `solve_value_mult`, unused until now) **Sponsorship Deal** ×1.5 (25K), **Prize Money** ×2 (2.5M, 20
  Competitions), **Live Stream** ×2 (400M, 10 Labs).
- **8 new icons** from game-icons.net (CC BY 3.0: teacher, crossed-swords, magnifying-glass, cardboard-box, test-tubes,
  receive-money, trophy-cup, tv), fetched from the set's GitHub mirror (`raw.githubusercontent.com/game-icons/icons`;
  game-icons.net itself is blocked here), background square removed like the others; all in `assets/CREDITS.md`.
- **Balance (BALANCE.md):** more boosts made the run faster again, so content runs out sooner: the longest first-hour wait
  is 34:01 (from ~26 min), the 5×5 comes at 9:18. **5.5 (six more helpers) and 5.8 (rebalance) fix that.** Active speedup
  ×2.87 (near the 3× ceiling; recheck in 5.8).
- Tests (3093 checks, `All good.`): synergy math (scales with source copies, only its target), Robot Sparring, Sponsorship
  ×1.5 and Prize Money stacking to ×3, every synergy links real helpers. Screenshot: `docs/screenshots/5.3-synergies/`.
- **Next: 5.5 six more helpers** (then 5.6 Algorithm Lab, 5.7b choices, 5.8 rebalance; 5.7 only if 5.8 needs it).

## 2026-11-04 — Roadmap: Phase 5 → 6 next; Tasks 5.0 (free first Friend) and 5.2 (generated helper milestones)
- **Owner: "progress with Phase 5 and 6".** ROADMAP order: Phase 5, then Phase 6, before the rest of Phase S (S.7, R.5,
  R.6). New tasks from the fun review: **5.0** never tapping still progresses, **5.7b** "pick one of two" upgrade choices,
  **7.0** career moments (story beats at key unlocks).
- **5.0:** the first Cubing Friend is free (`"first_free": true` in BUILDINGS; `GameState._copy_cost()`), so a player who
  never taps still earns. The idle pacing target now passes for real (expected-failure mark removed).
- **5.2:** `Content.HELPER_MILESTONES` (one table: at 1/10/25/50/100/150/200 owned, ×2 for base_cost × 10/30/250/8K/8M/8B/8T)
  and `Content.milestones_for(helper)` generate 7 upgrades per helper ("Practice Partners I…VII", the helper's icon,
  `"milestone": true`). **`Content.get_upgrades()`** = UPGRADES + every helper's milestones (cached); `get_upgrade()` uses an
  index. Everything that listed upgrades (GameState, main.gd, the simulator, tests) now uses `get_upgrades()`.
  Each helper has a `milestone_name`. 47 upgrades in total now (the 5.8 target is ~40+).
- **Performance:** `GameState._upgrade_mult()` caches its products (dropped whenever the number of owned upgrades
  changes). With 47 upgrades the balance bot had become ~5× slower (160 s per 2-hour run); now ~29 s.
- **Balance (BALANCE.md):** the longest wait in the first hour fell from 30:01 to 22:21. The game got faster, so the 4×4
  (7:57) and 5×5 (11:11) are even earlier than before; that's for **5.8** (rebalance). **Flow raised** so D13 still holds:
  `flow_by_tier` [1.5, 1.8, 2.2, **2.6 Gold**, 3.0, 3.4, **3.8 Master**] (was …2.0…3.0); the active player is ×2.80 faster
  (with the old values it fell to ×1.72: milestones make a flat boost worth less). The speedup is sensitive to Flow
  (Gold ×2.0 → ×1.72, ×2.1 → ×2.05, ×2.2/2.6 → ×2.80); recheck it in 5.8.
- Tests (2995 checks, `All good.`): every helper has every milestone (target, ×2, requirement, rising cost, icon), a
  milestone appears at its count and doubles that helper, `milestones_for()` on a made-up helper; the free Friend (and
  bulk costs, shop card, goals, simulator idle run adjusted for it; the bulk test now uses the Club).
  Screenshot: `docs/screenshots/5.2-milestones/` (Upgrades tab).
- **Next: 5.3 synergies and solve-value upgrades.**

## 2026-11-04 — Task S.5: daily scramble and Fewest Moves (save v8)
- **"Daily" in the Solve Station:** today's scramble for the selected cube, the same for everyone that day: seeded from the
  **UTC date** + puzzle with FNV-1a (`GameState.daily_seed`, pinned by a test and checked against Python, so it never
  depends on the engine's hash). Enter or switching cube gives the day's scramble again.
  - **Timed:** a normal WCA attempt (inspection setting applies); it's also a hand-solve record (Flow, tiers…) and keeps
    today's best time.
  - **FMC** (toggle next to Daily): no clock, no inspection; the big number counts moves (rotations free, slices and wide
    turns count one). **Backspace starts over.** Keeps today's best and the **best FMC ever** per puzzle. Not a timed record.
  - Side panel: today's best time and FMC, best FMC ever, and whether the reward is waiting.
- **Daily reward:** the first daily finished each day (timed or FMC, not a DNF) pays 30 minutes of the current Solves/s
  (at least 50 solves' worth of the focused puzzle; `Content.DAILY`). News line. A new day (UTC) starts fresh results and a
  new reward; the best FMC ever stays.
- **GameState:** `daily` {date, rewarded, times, fmc, fmc_ever}, `get_daily_date()` (+ `daily_now` for tests),
  `get_daily()` (rolls the day over), `record_daily(puzzle, "time"|"fmc", value)`, `is_daily_reward_ready()`, signal
  `daily_rewarded`. **Save v8** (`"daily"`), v7 → v8 migration. Planned: **v9 prestige (6.2), v10 achievements (7.1)**.
  `SolveSession.restart()`. The footer's "Enter:" text follows the mode. Screenshot tool: `DAILY=fmc|timed` (fixed date).
- Tests (2729 checks, `All good.`): seed (same day/puzzle, different day, different puzzle, pinned value), same seed = same
  scramble, UTC date; DNF doesn't collect, first finish pays once, today's best FMC/time, a new day resets but keeps the best
  FMC ever, save/load v8 + migration; in the station: day label, Enter repeats, FMC counts moves, Backspace, FMC records +
  reward and isn't a timed record, timed daily is a record and today's time, Daily off.
- **Next: S.7 turns are taps + TPS streak** (then S.8 is already done; R.5/R.6; then Phase 5).

## 2026-11-04 — Task S.4: algorithm drills (save v7)
- **Full OLL (57) and PLL (21)** in `Content.ALGORITHMS` (new fields `full`, `case` = OLL number; the 2-look entries are
  part of the full sets too: Sune = OLL 27, Line = OLL 45, T/Y/A/U/H/Z perms…). Written as most cubers learn them; the V perm
  has a `y`, the rest are rotation-free or undo their `x`.
  **`test_full_oll_pll_data`** proves them: each keeps the first two layers (read relative to the centres), each PLL keeps
  the top oriented, and the cases are **57 different OLL cases** (up to a U turn) and **21 different PLL cases** (up to U
  turns before and after). **`test_drill_cases`**: every case set up by the drill is solved by its own algorithm + AUF.
- **Drills in the Solve Station** ("Drills" toggle): the picker shows the sets (`Content.DRILLS`: 2-look OLL 9, 2-look PLL 8,
  Full PLL 21, Full OLL 57, with "learned/total"). A drill is one case on a 3×3, **yellow on top** (z2, random AUF before and
  after), the clock running from the moment it appears (recognition + execution) until solved; the case's name stays hidden
  until then. After: "Ja perm · best 7.80 (PB!) · clean 1/5 · R' U L' U2 R U' R' U2 R L · Enter: next case". Under the
  set's target (10 s, keyboard) is **clean**; **5 clean solves learn a case**. The next case is one not learned yet, fewest
  clean first. The side panel lists every case with best time and clean count (✓ = learned; the algorithm in a tooltip).
  Drills aren't hand-solve records and give no Flow.
- **Learn all of Full PLL / Full OLL and the main cube's showcase uses one-look PLL / OLL** (`StagedSolver.solve(..., {full_oll,
  full_pll})`, `ShowcaseSolve.solver_options`): the last layer drops from ~33 to ~27 moves. News lines for a learned case and set.
- **GameState:** `drills` {id: {best, clean, count}}, `record_drill(set, case, seconds)`, `is_case_learned()`,
  `get_drill_record()`, `get_drill_set_progress()`, `is_drill_set_learned()`, signals `drill_case_learned`,
  `drill_set_learned`. **Save v7** (`"drills"`), v6 → v7 migration. Planned: **v8 prestige (6.2), v9 achievements (7.1)**.
  `SolveSession.start_drill(alg, now, rng)`. Screenshot tool: `DRILL=solving|done`; shots in `docs/screenshots/S.4-drills/`.
- Tests (2695 checks, `All good.`): the data proof above; clean / PB / learned (once) / set learned / 2-look cases counting for
  the full set / unknown ids; save v7 + migration; yellow on top and the clock from the case appearing; the station end to
  end (sets in the picker, hidden name, record, status with name + algorithm, 8 rows, Enter, Drills off); the showcase
  switching to one-look PLL.
- **Not done here:** 2×2 CLL drills (later, S.4b); the Algorithm Lab (5.6) should count learned sets as research.
- **Next: S.5 daily scramble + FMC.**

## 2026-11-04 — Task S.3: hand-solve rewards (D13 = 2–3×)
- **The player's level** (owner): best ~30 s on a real 3×3, consistently under 1:00. That corrects the earlier "almost
  professional" (PLAYER_RESEARCH, PLAN, ROADMAP updated). Targets are tuned for keyboard solving at that level.
- **Time targets** (`Content.SOLVE_REWARDS`, per puzzle, Bronze → Silver → Gold → Platinum → Diamond → Master):
  3×3 5:00 / 2:30 / 1:30 / 1:00 / 40 / 25 s; 2×2 90/45/25/15/10/6 s; 4×4 15:00 … 1:40; 5×5 25:00 … 3:30; 7×7 1:00:00 … 10:50;
  Megaminx (no station keys yet) 30:00 … 4:00. Retune freely; it's data.
- **Rewards** (all in GameState, from `record_hand_solve`; nothing for a DNF):
  - **Flow**: every finished hand solve sets all moves ×1.5 (under every target) / 1.6 / 1.8 / **2.0 Gold** / 2.3 / 2.6 /
    **3.0 Master** for max(2:00, 1.5 × the solve's time). A new solve replaces the old Flow. Not saved (ends on quit),
    never counts offline. "Flow ×2 · 1:45" in the top bar (tooltip explains it). `flow`, `get_flow_mult()`, `update_flow()`.
  - **Permanent tier bonus**: +5 % moves on a puzzle per tier its PB single has reached (Gold = +15 %, Master = +30 %),
    derived from the records (so it survives save/load, no save change). Signal `hand_tier_reached` → news line
    ("Your 3×3: Gold tier! +15 % moves on the 3×3 for good"). `get_hand_tier()`, `get_best_hand_tier()`, `get_hand_tier_mult()`.
  - **Mastery XP**: a hand solve gives 10 idle solves' XP on that puzzle, ×5 for a PB single.
- **Station:** the status line after a solve adds "· Platinum: Flow ×2.3 for 2:00 (· new tier: +20 % moves here for good)";
  the records panel lists the targets with the reached ones ticked.
- **Balance:** the simulator has an **active profile** (`run(taps, minutes, {"tier": 2})`: the tapping bot plus a hand solve
  just inside Gold on its biggest cube, back to back, + 30 s overhead) and samples lifetime Solves every 5 s. New pacing
  target **active_speedup** (type `speedup`): the active player reaches the tapping bot's 30-min lifetime Solves **2–3×
  sooner** — today **×2.31** (13:00 vs 30:00). The raw lifetime ratio at 30 min is ×6.3 because the early economy
  compounds (a 2× boost early pulls the whole timeline in), so progress speed is the D13 measure. BALANCE.md has the
  active profile. `test_pacing_targets` now also runs it (~10 s more).
- Screenshot tool: `FLOW=1`; the station's staged solves now use ~1:00 times (our player's pace). Shots:
  `docs/screenshots/S.3-rewards/` (a Platinum solve with Flow, the main screen with Flow running).
- Tests (2148 checks, `All good.`): tier boundaries and target data for every puzzle; Flow by tier, its length, ×2 on
  moves, expiry, replacement by a slower solve, none for a DNF, the under-every-target Flow; mastery XP (×5 PB); the tier
  bonus (+15 % Gold, +25 % Diamond, once each, only that puzzle); after a load no Flow but the bonus stays; never offline;
  the station's targets line and reward text, and the top-bar Flow label.
- **Next: S.4 algorithm drills** (PLL/OLL as data, shared with `Content.ALGORITHMS`; for this player start from 2-look).

## 2026-11-03 — Task S.6: Golden Scramble (save v6)
- **Every 2–5 min a golden sticker glows on the main cube for 12 s** (the middle of the top face, pulsing amber/cream;
  unshaded so it's always bright), with a gold **"Golden Scramble! 9s"** button under the cube for any puzzle (also the
  Megaminx, which has no golden sticker). Clicking the sticker (`PuzzleView3D.hits_golden` → `golden_clicked`, not a tap)
  or the button claims it: the Solve Station opens a **case 2–5 moves from solved** on the focused cube (or your biggest
  cube), no inspection, a gold 10 s countdown. Solve it in time for a random buff; Esc, closing or the clock running out
  is a miss. The station shows the result ~2 s and closes itself. Golden cases are **not** hand-solve records.
- **Buffs** (`Content.GOLDEN`, by weight 1:1): **Frenzy** = every move ×7 for 30 s (taps and helpers, in `add_moves_to`;
  "Frenzy ×7 · 24s" in the top bar), **Lucky solve** = 15 minutes of the current Solves/s at once (at least 10 solves'
  worth of the focused puzzle). A news line and a pop for each.
- **GameState** (all the timing): `update_golden(delta)` (from `_process`) runs the spawn wait, the 12 s glow, the 10 s
  attempt and the buff; `claim_golden()`, `finish_golden(success)`, `roll_golden_case_moves()`, `get_buff_mult()`; signals
  `golden_spawned`, `golden_expired`, `golden_finished(success, buff)`. `golden_rng` (tests seed it).
- **Save v6** (`"golden": {next, buff}`): the next spawn time and a running buff are saved; the buff **pauses while the game
  is closed** and never counts for offline progress (`_offline_catch_up`). v5 saves get the first golden in 5 min and no
  buff. Planned save numbers moved: **v7 prestige (6.2), v8 achievements (7.1)** (PLAN §6, ROADMAP updated; 6.2 should
  decide whether a running buff survives a prestige).
- `SolveSession.start(..., length)` scrambles a given number of moves; `SolveStation.open_golden(puzzle, moves)`.
  Theme: GoldenButton, BuffLabel, TimerGolden. Screenshot tool: `GOLDEN=glow|case|buff`; shots in
  `docs/screenshots/S.6-golden/`.
- Tests (2077 checks, `All good.`): spawn wait in range, glow and expiry, claim (once), the 10 s clock and the miss, a hit
  rolls a buff, case length; Frenzy ×7 on every move and its expiry, Lucky's two amounts; save/load keeps the buff and the
  timer, an hour away earns the same with or without a buff (and the buff waited), v5 → v6; on screen: sticker + button,
  clicking the sticker opens the case (not a tap), solving gives a buff and no record, the station closes itself, Esc = miss.
- Not in the simulator (it never claims goldens), so pacing is unchanged.
- **Next: S.3 rewards** (D13 = 2–3×). Ask the owner for the player's real csTimer averages first (S.2 handoff has the
  suggested design).

## 2026-11-03 — Task R.4: the news feed
- **A small "News" panel under the shop** (bottom of the right column, ~5 lines, scrolls back through the last 20; newest
  first and bright, older dim; tooltips hold the full line). The left column had no room left, so it lives on the right.
- **Lines** (`NewsFeed`, `scripts/ui/news_feed.gd`, pure data; main.gd connects the signals and draws `history`):
  - a helper kind's first copy: "Robot Nova-2 joins the team: 0.21 s a 3×3"; a helper kind at least 5 % faster on the
    focused puzzle (an upgrade, a method, mastery): "Club member Lucas: 0.87 s 3×3 single!"
  - mastery: every level up to 10, then every 5th, and milestones with what they give ("2×2 Mastery 5: +10 % moves…")
  - "Your team learned CFOP. Cross, F2L, OLL, PLL." · "New puzzle: 4×4. Your helpers start on it now."
  - time tiers ("3×3 team: Robot record pace! 0.21 s"), "1.00M lifetime Solves!", and the player's own Solve Station
    PBs ("Your new 3×3 PB: single 8.77, ao5").
- **Rate limit:** one line per 1.2 s (`Content.NEWS`), lines of the same kind waiting together are merged (newest kept),
  at most 6 wait (oldest dropped). Names are data (`Content.NEWS`: a title per helper and pools of people's names / machine
  codes), picked by a seeded hash so a member keeps its name.
- **New GameState signals** (derived, never saved, silent after a load or a focus change): `helper_best_time(building,
  puzzle, seconds, first)` via `check_helper_times()` (after purchases and mastery level-ups, before the tier check),
  `solves_milestone(amount)` (lifetime Solves passing 100, 1K, 10K…; one line for the highest passed),
  `hand_solve_pb(puzzle, single, averages, seconds)` from `record_hand_solve`. No save change.
- Screenshot tool: `NEWS=1` (a few typical lines through the real feed). Shots: `docs/screenshots/R.4-news/`.
- Tests (2040 checks, `All good.`): the rate limit, merging, queue cap, 20-line history, the mastery filter, the text of
  every kind of line (buying a helper or upgrade alone makes none), stable names, robots get codes; GameState events
  (first helper, no line for an equally fast copy, upgrade → faster, milestones once and highest only, nothing after a
  load, PBs only for faster solves); and the main screen (first Friend → "joins the team", then its tier).
- **The R.1–R.4 block ("readable main screen") is done.** Next in the roadmap order: **S.6 Golden Scramble**, then S.3
  rewards (D13 = 2–3× answered; ask the owner for the player's real csTimer times first, see the S.2 handoff), then S.4….

## 2026-11-03 — Task R.3: cube times and real goals
- **Solve times, a cuber's way to read speed.** `GameState.get_helper_solve_time(helper, puzzle)` = moves per solve ÷ one
  helper's moves/s on that puzzle (upgrades and the puzzle's mastery bonus count); `get_team_solve_time(puzzle)` = the
  fastest owned helper. Shown on every shop card first ("10.00 s a 3×3 · +2 moves/s each (+30/s)", for the focused
  puzzle), on every puzzle chip ("109 µs · 10%"; Solves/s moved to the chip's tooltip and the Puzzles tab, since it no
  longer fit), and under the big cube ("Team best 0.21 s (Robot record pace) · Click the cube…").
  `Num.cube_time()`: "1:23.45", "9.87 s", "4.08 ms", "38.0 µs", "12.0 ns", "—".
- **Time tiers** (`Content.TIME_TIERS`, per puzzle, slowest first): human tiers (3×3: Sub-1:00, Sub-30, Sub-20, Sub-10,
  Sub-5, WR pace ≈ 3.1 s), then machine tiers (Robot record pace ≈ 0.31 s, Faster than a blink, Sub-millisecond,
  Sub-microsecond). WR values are approximate (2025). `get_time_tier()`, `get_next_time_tier()`,
  `check_time_tiers()` + signal **`time_tier_reached(puzzle, tier, seconds)`**, checked after every purchase and mastery
  level-up; only the best newly reached tier pops ("3×3 team: Sub-10!  9.87 s" + unlock sting). Tiers are derived, not
  saved: loading a save or unlocking a puzzle notes its tier silently, so nothing pops twice.
- **Goals:** `get_goals(limit)` = the soonest goals, one per kind (helper, upgrade, method, puzzle, mastery = the
  focused puzzle's next milestone), each with `missing`, `unit` (Solves/XP), `seconds` (ETA, INF without helpers) and
  `progress` 0..1. `get_next_goal()` is unchanged (cheapest; kept for its tests). `get_puzzle_solve_rate()` = solves a
  second (a count).
  - **The goal strip** now shows the top 3 goals side by side, each with a thin bar: "Cubing Friend · 5 Solves" (no ETA
    yet: what's left), "Local Competition · 1m 45s", "ready!", "under 1s". The full text is in each goal's tooltip.
  - **Next-goal bar:** when the focused puzzle solves more than 10 times a second (`Content.GOAL_BAR_SOLVES_PER_SECOND`),
    the "moves to next solve" bar and its line track the top goal instead: "Next goal: 3×3 Mastery 5 · 127 more XP ·
    about 2s". Below that it stays the moves bar.
- Layout: the move ticker and hint line clip/ellipsize instead of widening the left column (a long Beginner stage or a
  late-game time used to push the shop over). Theme: GoalBar, GoalLabel, GoalLabelDim.
- Tests (2008 checks, `All good.`): `cube_time` formats; solve-time math, team best = fastest helper, tier pops (once, best
  only, not after load/unlock), tier data ordered for every puzzle; goals (fresh = Friend, ≤ 3, one per kind, soonest
  first, ETA = missing ÷ rate for Solves and XP, ready first); main screen: late game uses the goal bar + 3 goals + team
  time, a new game keeps the moves bar. Screenshots: `docs/screenshots/R.3-times-goals/` (fresh, mid, row5).
- **Next: R.4 news feed.** The tier pops and mastery pops are natural feed lines; `time_tier_reached` is ready for it.

## 2026-11-03 — S.1b + S.8: intuitive Solve Station controls (owner request)
- **Owner:** "fix cube control buttons to make it more intuitive"; asked which fixes: **drag to turn**, **key hints on the
  cube**, **a simpler key layout option**, in the Solve Station only (the main screen keeps click/Space = tap).
- **Drag to turn (S.8, done early):** press on the cube and drag along a row or column: that layer turns the way you
  dragged, like swiping a real cube (one turn per drag, after 12 px). Middle layers give M/E/S on the 3×3 and SiGN
  slices on big cubes (`2R`, `2L'`); a layer nearer the far side is named from there (`D'`, not `3U`). A drag that starts
  on the background still turns the view; a click is still not a turn. `PuzzleView3D.drag_turns`, `pick(at)`
  (ray vs the cube's box, model space), `move_for_drag(hit, drag)`, signal `drag_turned(move)`; the station's
  `play_move(move)` handles it like a key (timer, records, flash).
- **Key hints (toggle "Key hints", on by default, setting `key_hints`):** a small label per face, e.g. `R  I / K`, sitting
  on the middle of each face you can see and just outside the cube's outline for hidden faces (dimmer), following the
  cube as it sways or is dragged (`PuzzleView3D.face_label_position`). Under the timer: rotations and slices
  (`x T/Y/B/N · y ;/A · z P/Q · M 5/6/X/. · E 2/9 · S 0/1`). The old "Keys" chip is now "All keys" (the full list).
- **Simple keys (toggle "Simple keys", setting `solve_keys` = cstimer | simple):** `R U F L D B` turn that face,
  **Shift** = prime, `X Y Z` rotate, `M E S` are 3×3 slices, and a number first makes the next turn wider (`2` `R` = Rw,
  `3` `R` = 3Rw; capped at size − 1; "Next turn: 2 layers" shows meanwhile). Hints become `R / ⇧R`.
  `Content.SOLVE_KEYS_SIMPLE`, `SOLVE_WIDTH_KEYS`; `SolveSession.layout`, `next_width`, `move_for_simple_key()`;
  `press_key(key, now, shift)`. csTimer's layout stays the default.
- Theme: `KeyHint`. Screenshot tool: `KEYS=simple`. Shots: `docs/screenshots/S.8-controls/` (csTimer hints while
  solving, simple keys in inspection).
- Tests (1896 checks, `All good.`): simple layout (Shift, rotations, slices, widths on 3×3/5×5, caps, 2×2 has no M), drag
  mapping on 3×3 and 4×4 (R, R', L', D', F, U, M', 2R, 2L') through `pick` and through real mouse events (one turn, no
  tap, no view turn), and the station: hint texts for both layouts, six hints on screen, toggles saved, Shift+R,
  2 then R on a 4×4, a drag turn starting the timer.

## 2026-11-03 — Task R.2: the showcase solve on the main cube
- **The big cube now plays real solves.** For the 2×2 and 3×3 (what StagedSolver supports) the focused cube no longer
  shows random turns + rewind: it shows a real WCA scramble, ~1.6 s of inspection (the `z2 y` turns play in it), then the
  learned method's solve one move at a time, holds the solved cube ~1.4 s (flash + bounce), and starts the next one.
  - **Speed** (`Content.SHOWCASE`, owner OK'd): Beginner 3 TPS, CFOP 5, Roux 6, ZZ 7, God's Number 8, +0.9 TPS per 10×
    the focused puzzle's moves/s, max 12, and **never faster than the puzzle really gets moves**: with no helpers it only
    moves when you tap. Turn animation time follows the pace (0.7 / TPS, 0.05–0.12 s), so speed mode never kicks in.
  - **A tap plays the next move of the solve** (in inspection it does the inspection turns and the first move), and
    still counts as a normal tap for the economy.
  - **Stage chips** (`%StageChips`) under the cube: done = green text, playing = lit (F2L shows "F2L 2/4"), rest faint.
    Beginner: Cross · Layer 1 · Layer 2 · Yellow cross · Yellow edges · Corners · Twist; 2×2: Layer 1 · Orient · Permute.
  - **Ticker** (`%MoveTicker`, now a RichTextLabel): "F2L 3   F' U2 F U2 **R** U R'": stage name, moves played dim, the
    one just played in green, the rest faint; long stages show a window with "…". 3×3 wide moves are written `r` (cubers'
    style, `ShowcaseSolve.notation`). With ≥ 2 solves/s: "· 1 of 81 solves/s". When solved: "Solved in 64 moves · CFOP".
  - A method learned mid-solve is used from the next scramble. Economy solves no longer rewind the big cube (they still pop
    "+X Solves" and chime). 4×4+ and Megaminx keep the old scramble + rewind until R.6; the small row cubes are unchanged.
- **Code:** `ShowcaseSolve` (`scripts/cube/showcase_solve.gd`, pure data, signals started/stage_changed/finished);
  main.gd `_start_showcase()` (on ready, focus change, reset), `_play_showcase()`, `_showcase_ticker()`, chips,
  `pose_showcase(n)` for screenshots. main.gd warms StagedSolver up at start (~0.3 s, once). Theme: StageChip,
  StageChipActive, StageChipDone, StageChipRow, TickerText. The puzzle view's minimum height is 220 (was 300) so the new
  chip row fits at 1280×720.
- Screenshot tool: `SHOWCASE=<moves>` (hold the showcase N moves in) and `METHOD=<id>`. Shots in
  `docs/screenshots/R.2-showcase/`: CFOP in F2L (`mid_showcase22`), CFOP in PLL (`mid_showcase50`), Beginner second
  layer (`mid_showcase40_beginner`), fresh 2×2 first layer (`fresh_showcase3`).
- Tests (1829 checks, `All good.`): TPS rules (0 helpers = taps only, caps, CFOP > Beginner), a timed full solve ends
  solved and starts the next, taps (inspection, one move each, 0 TPS still), method change applies next solve, `r`
  notation, and a main-screen smoke check: full tapped showcase solves on the 3×3 with Beginner and CFOP (cube solved,
  chips all done, taps counted), 4×4 falls back. `test_juice_at_high_speed` now expects the showcase, not speed mode.
- **Next: R.3** (cube times + next-goal bar). Note: the "moves to next solve" bar still shows the economy's moves per
  solve, which differs from the showcase's move count; R.3 replaces it with a goal bar at high speed.

## 2026-11-03 — R.1 follow-up: solves look right to a pro (owner answers)
- **Owner answers:** showcase speed as recommended (~3 TPS Beginner → ~10–12 TPS CFOP; noted in ROADMAP R.2); the solve
  must **look right to a pro**; a 2×2 first layer in any colour is fine.
- **No more back-face inserts.** F2L and the beginner layers now work only at the front, like a real solver:
  - F2L inserts are `R U^k R'`, `L' U^k L`, `F' U^k F` (and the other directions, for taking pairs out), never `B`.
    To reach a back slot the cube turns with **`y` / `y'` / `y2`** (cost 2/2/3 moves, so it only rotates when that
    saves moves). About 1.4 `y` per CFOP solve.
  - Beginner: each corner is held at the front and inserted with repeated `R U R' U'` (or `L' U' L U`); each middle edge
    with the two classic front inserts; **a piece stuck in the wrong slot is held at the front and popped out with one
    insert first**, as beginners are taught. Corner positions: turn so the corner already in place is front-right, then
    `U R U' L' U R' U' L`. About 7 `y` per beginner solve.
  - The solver computes a `y` option's cost *without* turning the cube (`_rotated_option` / `_renamed`: where each piece
    lands and how it's renamed relative to the turned centres), so choosing stays cheap.
- **Inspection like a pro:** after `z2` (white cross on the bottom) the solver tries all four `y` holds and keeps the
  shortest cross (fewest `B` turns on a tie), e.g. `z2 y'`. `B` turns per CFOP solve dropped from 2.7 to 0.3 (only in
  crosses where every hold needs one, which is normal).
- **A-perms** are now the standard `x R' U R' D2 R U' R' D2 R2 x'` / `x R2 D2 R U R' D2 R U' R x'` (rotation-free versions
  used `B2`, which pros don't).
- Numbers after `warm_up()` (~0.25 s): 3×3 CFOP ~67 moves, ~11 ms (worst ~31 ms); Beginner ~134 moves, ~14 ms; 2×2 ~2 ms.
- Tests (1785 checks, `All good.`): new check that F2L/first layer/second layer/corner positions never turn `B` over 60
  solves and use `y` instead; inspection may be `z2` + a `y`.
- **For R.2:** display wide moves on the 3×3 as cubers write them (`r`, not `Rw`); TwistyModel.notation() gives the WCA
  form. Stage ids/names are unchanged.

## 2026-11-03 — Task R.1: the staged solver (real Beginner and CFOP solves)
- **`StagedSolver`** (`scripts/cube/staged_solver.gd`, pure data like TwistyModel): `StagedSolver.solve(model, method)`
  returns the solve as stages `[{id, name, moves}]` without touching the model; applying them in order solves it.
  `supports(puzzle_id)` (2×2, 3×3), `warm_up(puzzle_id)`, `is_stage_done(model, stage_id)`, `simplify(model, moves)`.
  - **CFOP (3×3):** `z2` in inspection (WCA scrambles are white top / green front; z2 gives a white cross and keeps green
    in front), an **optimal cross** (IDA*, avg 5.8 moves), **F2L pair by pair, easiest first**, with real inserts
    (`R U R'`, `F' U' F`, … plus U turns; ~6–8 moves a pair), then **2-look OLL and PLL** from the algorithm data
    (avg 14 + 18). About 64 moves in total, like a 2-look CFOP solver.
  - **Beginner (3×3):** cross, first-layer corners with repeated `R U R' U'`, second-layer edges with the two classic
    inserts, yellow cross (`F R U R' U' F'`), yellow edges (Sune), corner cycle (`U R U' L' U R' U' L`) and the
    `R' D' R D` corner twist. About 124 moves.
  - **2×2:** first layer (optimal, U/R/F only), then Orient (Sune/Antisune) + Permute (T/Y perm) for Beginner, or
    OLL + PLL with the 2-look OCLL algorithms for CFOP and later. The first layer is whatever colour the back-bottom-left
    corner has (the 2×2 has no centres and that corner never moves).
  - Roux, ZZ and God's Number fall back to CFOP until **R.5**; 4×4+ and Megaminx give `[]` until **R.6**.
- **Algorithms are data:** `Content.ALGORITHMS` (id, name, set OLL/PLL/Beginner, two_look, alg) + `Content.get_algorithm()`,
  meant to be shared with the S.4 drills (add the full OLL/PLL sets there; the solver will use them via the same ids).
- **How it works / speed:** pieces are tracked as slots (position × twist) with move tables built from the model's
  geometry. The cross uses one 3-edge distance table looked up four times (y-symmetry); every other stage uses cached
  cost-to-goal tables over a few pieces (F2L pair: 576 states), so a solve just walks downhill. After `warm_up()`
  (~0.3 s for the 3×3, ~50 ms for the 2×2 in the container) a 3×3 solve takes ~8–10 ms, worst ~20 ms; without warm-up the
  first solve builds what it needs (~0.5 s). **R.2: call `StagedSolver.warm_up()` at startup (or in a thread).**
- Tests (1783 checks, `All good.`): 200 random scrambles per method on 3×3 and 2×2, each stage's goal checked after it,
  the 50 ms budget, stage lists, realistic move counts, z2 + cross ≤ 8, cube held in another orientation, fallbacks,
  and every algorithm in the data keeps F2L/centres (PLLs also the top colour). The test suite now takes ~57 s (was ~51 s).
- **Not visual yet:** nothing on screen changes until R.2. Next: **R.2 showcase solve** (use PuzzleView3D's manual mode
  `show_state`/`turn` from S.1, `StagedSolver.solve(model, Game.method)`, and the stage ids/names for the chips).
- Known look details for later: F2L sometimes inserts at the back with `B U B'`-style moves instead of a `y` rotation
  (real solvers usually rotate); the 2×2 first layer isn't always white. Both are fine for a showcase; R.5 could add `y`.

## 2026-11-03 — Task S.2: solve records (save v5) + D13 answered + handoff notes
- **D13 answered by the owner: ~2–3×.** An active player who keeps solving earns about 2–3× an idle one (PLAN §7).
- **Records in GameState** (rule 1): `record_hand_solve(id, seconds, penalty, moves)` returns
  {final, pb_single, pb_averages}; `set_hand_solve_penalty()`, `delete_hand_solve()`, `get_solve_history()`,
  `get_hand_solve_count()`, `get_solve_bests()` ({single, 5, 12, 50, 100}, INF = none), `get_current_average()`,
  signal `solve_records_changed`. Averages: WCA trim 1 up to ao12, then 5 % each side (ao50 drops 3, ao100 drops 5);
  more DNFs than the trim = DNF; averages rounded, singles truncated (`SolveSession.trim_count/trimmed_average`).
  The last 1000 solves per puzzle are kept; bests are cached and only fully recomputed after an edit/delete/load (so a
  PB older than the last 1000 survives until you edit a time). Kept through prestige (6.2 must not reset `solve_records`).
- **Save v5** adds `solve_records` (puzzle id -> {history: [{t, p, m, d}], count}); damaged entries are cleaned on load.
  Planned: v6 prestige, v7 achievements.
- **Station:** the side panel is now "3×3 records · N solves": PB single/ao5/ao12/ao50/ao100, current averages, and the
  last 50 times with +2 / DNF toggles and × delete. The status line says "New PB single and ao5!".
- Tests (1640 checks, `All good.`): PB detection, penalties changing bests, delete, all-time count, ao50 DNF rule,
  trim sizes, history cap keeping an old PB, save/load, v4 → v5 migration with junk entries, station buttons.
  Screenshot: `docs/screenshots/S.2-records/mid_solvedone.png`.

### Handoff: where things stand and what to do next (written for the next chat)
- **Order from here** (a parallel session added R.1–R.6, see the entry below): **R.1 staged solver → R.2 showcase solve →
  R.3 cube times + goals → R.4 news feed → S.6 Golden Scramble → S.3 rewards → S.4 …**. The owner's two complaints were
  "nothing to do" (Phase S) and "the main cube is just random scrambles" (R.*); R.1–R.4 fix the second and are next.
  R.1 is the hard one: a real staged solver (Beginner + CFOP) as a pure class; use TwistyModel (exact, tested) and keep
  algorithms as data shared with S.4. R.2 should use PuzzleView3D's manual mode from S.1 (`show_state`, `turn`, `turn_time`).
- **S.3 Rewards (D13 = ~2–3×), when you get there.** Suggested design, all as data in `content.gd` and logic in `GameState`:
  - `SOLVE_TARGETS` per puzzle: tier times for *keyboard* solving (keyboard is slower than a real cube; elite csTimer
    keyboard 3×3 is ~8–10 s). Starting guess (s): 2×2 30/20/12/8/5/3, 3×3 90/60/40/25/15/10, 4×4 240/150/100/70/50/35,
    5×5 420/270/180/120/90/65, 7×7 1200/800/550/400/300/220, tiers Bronze/Silver/Gold/Platinum/Diamond/Master.
    Ask the owner what the player's real csTimer averages are and tune so Gold is "good for them", Master is a stretch.
  - **Flow buff:** every non-DNF hand solve sets all moves ×F for ~120 s (refreshes, doesn't stack); F from the solve's
    tier, about ×1.5 untiered up to ×3 at Master, so continuous solving lands at 2–3×. Don't save Flow (it ends on quit),
    and never apply it to offline progress.
  - **Permanent:** the best tier reached on a puzzle (derived from the PB single) gives +5 % moves on that puzzle per tier.
  - **Mastery XP:** a hand solve gives the XP of ~10 idle solves on that puzzle; a PB single ×5.
  - Add an "active" profile to `tools/simulator.gd` (e.g. a 3×3 Gold solve every 45 s) and a pacing target in
    `tools/pacing.gd` that active/idle income at 30 min is between 2× and 3×. Show the Flow timer on the main screen.
- **After S.3: S.4–S.8** in roadmap order (then R.5/R.6). S.4 (PLL/OLL drills) is the most "pro" feature: put algorithms in data and add a
  test that applies each algorithm to its generated case and checks the cube ends solved (TwistyModel can do this today).
  Then back to Phase 5 (5.2 milestones, 5.3, 5.5, 5.6 Algorithm Lab, 5.8 rebalance), which fixes the 30-min content gap.
- **Things to watch:** the economy runs out of new content at ~51 min (BALANCE.md); 5.8 is what fixes pacing, but the
  Robot/4×4/5×5 still come too early. `_recompute_solve_bests` is O(history × size) (~0.1 s for 1000 solves on ao100);
  fine now, optimise if edits feel slow. Station key handling is in `_input` and marks every key handled while open.
- **Ask the owner:** the player's real csTimer times (for S.3 targets); whether turn animation (0.055 s) feels right;
  whether any key differs from their csTimer setup (some players remap; a key-rebinding option could be added).
## 2026-11-03 — Roadmap: "Readable main screen" (R.1–R.6), docs only
- **Owner feedback:** the main cube is "just some random scrambles", hard to follow, and "nothing happens". Measured: helper
  moves are random face turns and a solve is the history rewound; past 12 moves/s it only wobbles; the moves-to-next-solve
  bar and the ticker mean nothing at speed. Phase S adds things to do, but no task changed what the main cube shows.
- **New ROADMAP block R.1–R.6** inside Phase S, right after S.2: R.1 staged solver (Beginner + CFOP on 3×3, 2×2) as a pure
  class; R.2 **showcase solve** on the big cube (one real solve at a watchable TPS, stage chips, real solution in the
  ticker, "1 of N solves/s"); R.3 **cube times** per helper + time-tier pops + a next-goal bar/strip; R.4 **news feed**;
  R.5 Roux/ZZ; R.6 big cubes by reduction (parity as a stage). Order: S.2 → R.1–R.4 → S.6 → S.3 (D13) → rest.
  PLAN §4.2 and §5 updated, feedback moved to Handled. No code changed.
- **Note for the session doing S.2 in parallel:** this commit only touches docs (ROADMAP Phase S, PLAN §4.2/§5, FEEDBACK,
  this entry). If you get a conflict here, keep both entries. R.2 should reuse S.1's PuzzleView3D manual mode
  (`show_state`/`turn`), and R.1 and S.4 should share one set of algorithm data.

## 2026-11-03 — Roadmap reorder (Phase S) + Task S.1: the Solve Station
- **Owner feedback** (FEEDBACK.md): idling was "just looking at the screen while it shuffles", and **the player is an
  almost professional speedcuber**. New **ROADMAP Phase S — Solve Station** (S.1–S.8), done before the rest of Phase 5:
  records (S.2), rewards (S.3, needs **new open decision D13**: how much hand solves pay), PLL/OLL drills (S.4), daily
  scramble + FMC (S.5), Golden Scramble as a quick solve (S.6, was 8.1), turns-as-taps + TPS streak (S.7, was 5.4),
  mouse turning (S.8). Planned save numbers moved again: v5 solve records, v6 prestige, v7 achievements.
- **S.1 done: "Solve it yourself"** (green button in the top bar) opens a full-screen station on the focused puzzle (any
  unlocked cube, 2×2–7×7; the Megaminx needs its own keys later):
  - **csTimer's virtual-cube keyboard layout** (`Content.SOLVE_KEYS`, checked against csTimer's source): I/K R, J/F U,
    H/G F, D/E L, S/L D, W/O B, ;/A y, T/Y/B/N x, P/Q z, U/M r, V/R l, 5/6 M, X/. M', 2/9 E, 0/1 S, ,/C u, Z// d, and
    3/4 + 8/7 move the left/right hand deeper on big cubes (Space resets). **Physical keys**, so a Turkish (or any)
    keyboard layout still works by position.
  - Random-move scrambles in WCA notation (`scramble_length` per puzzle: 11/25/40/60/100), **15 s WCA inspection**
    (+2 after 15 s, DNF after 17 s; toggle "WCA inspection", saved as the new setting `inspection`), rotations are free
    during inspection, the timer starts on the first real turn and stops when solved in any orientation.
  - Big tabular timer, then "Solved! 52 moves · 6.10 TPS"; session list with best, ao5 and ao12 (WCA trimmed mean,
    1 DNF dropped, 2 = DNF, averages rounded, singles truncated); csTimer-style "14.34+" / "DNF(12.34)".
  - "Keys" shows the layout, generated from the key map for the current puzzle. Enter = next scramble, Esc = close.
- **Code:** `SolveSession` (scripts/cube/solve_session.gd) holds the solving rules as pure data (tests drive it with fake
  clocks). TwistyModel now names and parses **x/y/z, M/E/S (3×3) and lowercase wide moves** (r = Rw), plus
  `is_rotation()`/`layer_count()`. PuzzleView3D got a manual mode: `show_state(moves)`, `turn(move)`, `flash()` and a
  `turn_time` (the station uses 0.055 s). `Num.solve_time()`. Theme: TimerLabel/TimerWaiting/TimerDone (Inter bold with
  tabular figures), ScrambleLabel, SidePanel.
- **No economy effect yet:** hand solves don't pay anything until S.3 (and D13). Session times aren't saved until S.2.
- Screenshot tool: `SOLVE=inspecting|solving|done`. Screenshots in `docs/screenshots/S.1-solve-station/`.
- Tests (1608 checks, `All good.`): every key's move on a 3×3 against csTimer's table, 2×2 edge cases, 5×5 hands
  (shift, clamp, reset); notation round trips and what x/M/E/S actually do to the stickers; scramble length; rotation
  during inspection; the timer from first turn to solve; solved upside down; +2/DNF; inspection off; averages with DNFs;
  time formatting; the station end to end (real key event, Space/Enter tap blocked, a full keyboard solve, Enter, Esc).
- **Next:** S.2 (records + save v5). Owner: please answer **D13** (PLAN §7) before S.3, and try the station. Tell us
  if any key feels different from your csTimer, or if turns should animate faster or slower.

## 2026-11-03 — Task 5.1: the method chain (save v4)
- **Methods are a chain of their own** (`Content.METHODS`): Beginner Method (free, everyone starts with it) → CFOP (200) →
  Roux (25K) → ZZ (50M) → God's Number (30B), each ×0.7 moves per solve on every puzzle. Only the next one can be learned;
  it shows up at half its cost in lifetime Solves, like upgrades. The hand-written `cfop` (×0.7) and `roux` (×0.8)
  upgrades are gone from `Content.UPGRADES`.
- **Per-puzzle floor:** `min_moves_per_solve` in `Content.PUZZLES` (2×2: 2, 3×3: 4, 4×4: 12, 5×5: 24, 7×7: 60,
  Megaminx: 140). `GameState.get_moves_per_solve()` = base × methods × upgrades × mastery, never below
  `get_moves_floor(id)`. Today only the 2×2 reaches it (all four methods: 8 → 1.92 → floored to 2); the Algorithm Lab
  (5.6) and trophies will push the others toward theirs.
- **GameState:** `method` (newest learned id), `get_method()`, `get_next_method()`, `is_method_learned()`,
  `is_method_available()`, `buy_method()` (emits `purchased("method", id)`), `get_method_mult()`. The next method is a
  "Next goal" candidate. `is_upgrade_available()` now returns false for unknown ids instead of erroring.
- **Save v4** adds `"method"`. `_migrate()` v3 → v4: the old `cfop`/`roux` upgrade ids leave the upgrade list and become the
  method (Roux if owned, with CFOP implied since the chain is in order; else CFOP; else Beginner). An unknown method id
  loads as Beginner. **The planned save numbers moved up one:** prestige is now v5 (6.2), achievements v6 (7.1)
  (PLAN §6 and ROADMAP updated).
- **UI:** the next method is an icon tile at the front of the Upgrades grid; learned methods stay as Owned tiles. Its
  tooltip says what it does to the focused puzzle ("2×2: 8 → 5.6 moves per solve (never below 2)").
  New icons: `beginner` (stairs), `zz` (lightning-helix), `gods_number` (crown), game-icons.net CC BY 3.0, credited.
  Screenshot: `docs/screenshots/5.1-methods/late_tab1.png`.
- **Simulator:** knows the "method" kind. Content now lasts to **51 min** (was 26): CFOP 5:05, Roux 9:05, ZZ 13:43,
  5×5 21:24, God's Number 51:25. The longest first-hour gap is 30 min (5×5 → God's Number), down from 34. Same passing
  targets as before; the stale expected-failure notes in `tools/pacing.gd` now describe today's numbers.
- Tests: method chain order, cost, signal, save/load and unknown ids; the floor (2×2 with every method and mastery Lv 10,
  solves taking exactly the floor's moves); v3 → v4 migration (CFOP only, Roux without CFOP, neither, and v1 all the way);
  method tiles in the grid; content validity for methods and floors. Screenshot presets still use `cfop`/`roux` in their
  old upgrade lists on purpose: they exercise the migration. 1514 checks, `All good.`
- **Next:** task 5.2 (generated helper milestones).

## 2026-11-03 — Task 4.7: early-game rebalance + the variety bonus (Phase 4 done)
- **The design risk was real:** with linear income, "everything on the top puzzle" always won. Fixed with a
  **variety bonus** (`Content.VARIETY`, exponent 0.5): a puzzle with share *s* gets *s*^0.5 of the helpers' moves. One puzzle is
  unchanged; smaller shares are boosted (10 % → ×3.2), so the best split is a mix ∝ (Solves per move)², at any scale.
  `GameState.add_helper_moves(seconds)` (used every frame and for offline progress) applies it; `add_moves(amount)` stays
  the raw split for tests. `get_puzzle_variety_bonus(id)`. Taps aren't affected.
  - First I tried an absolute "pace" per puzzle (moves beyond it counted for less). That failed: late-game helper output
    swamps any fixed pace, so income only grew with √helpers, which fights exponential costs. Variety is relative, so it scales.
- **The bot chooses its split:** `Simulator.choose_split()` sets each share ∝ value^(1/(1−e)), rounded to 5 %, every 30 sim
  seconds and after unlocks; the value of a puzzle unlock is estimated with that split (cached for 15 s, since it's slow).
  Checkpoints record the split; `BALANCE.md` shows it per checkpoint.
- **New pacing target `split_mix`:** at 30 min the bot's split uses 2+ puzzles and none above 70 %. Result:
  **3×3 25 % · 4×4 50 % · 5×5 25 %** ✓. Still passing: first helper 0:13 ✓, first upgrade 0:48 ✓, 3×3 4:18 ✓.
- **Tuning** (data only): Solving Robot base cost 700 → 1,500; 4×4 unlock 25K → 400K; 5×5 unlock 1.5M → 300M. Before tuning,
  variety + mastery finished all content at 12 min; now it's **26 min** (Robot 7:24, 4×4 11:19, 5×5 26:23). The Robot, 4×4
  and 5×5 windows (and "something new every 3 min") stay expected failures: **Phase 5 adds the content** that lets the
  first hour reach them (task 5.8). Income now explodes between minutes 5 and 15, then flattens when content runs out.
- **UI:** the Puzzles tab explains the bonus and shows "Lv 12 · ×2.2 variety" over "2.75K moves/s · +545 Solves/s" per
  puzzle. **Layout bug fixed:** long numbers widened the right column past the window; info lines and the progress line now
  shorten with an ellipsis instead (`text_overrun_behavior`), and a test checks the page's minimum width stays ≤ 1280 px.
  The progress line is shorter: "30 / 42 moves · 4×4 mastery Lv 2 → Lv 5: +10 % moves on this puzzle".
- Tests: a single puzzle gets no bonus; 10 % gets ×10^0.5; `add_helper_moves` adds share^e; the bot's mix earns more than
  focusing on the newest puzzle; the page-width guard. 1431 checks, `All good.` `docs/BALANCE.md` regenerated.
- **Phase 4 is complete.** Owner: a good point to play: unlock puzzles, try the split and the presets, and watch mastery levels.
- **Next:** Phase 5, task 5.1 (method chain).

## 2026-11-03 — Task 4.6: Puzzle Mastery (save v3)
- **`Content.MASTERY`** (data): levels 1–100; level L → L+1 needs `25 × 1.15^(L−1)` XP; a solve gives `moves_per_solve ÷ 8` XP
  (so XP per move is equal on every puzzle: a 2×2 solve = 1 XP, a 4×4 solve = 7.5); +1 % moves on that puzzle per level.
  **Milestones:** Lv 5 +10 % moves on the puzzle, Lv 10 −10 % moves per solve, Lv 25 +25 % Solves per solve, **Lv 50 +5 % moves
  on every puzzle**, Lv 100 ×2 Solves per solve. Effect types: moves / solve_moves / solve_value / all_moves.
- **`GameState`:** `mastery_xp` per puzzle (levels cached), XP added on every solve of that puzzle, so all running puzzles level in
  parallel (the Idle Skilling pattern). Moves arriving at a puzzle (taps and helpers) × `get_puzzle_moves_mult(id)`;
  `get_moves_per_solve(id)` and `get_solve_value(id)` include its milestones. Getters: level, XP, XP for a level, XP per
  solve, progress 0..1, next milestone. Signal `mastery_level_up(id, level)` (once per level, even when several at once).
  **Meant to be kept through prestige** (6.2 must keep `mastery_xp`).
- **Save v3:** a `mastery` block; **migration v2 → v3** starts everyone at level 1. The version schedule moves on:
  **v4 prestige (6.2), v5 achievements (7.1)**; ROADMAP and PLAN are updated.
- **UI:** every puzzle card shows "2×2 · Lv 12" and a thin mastery bar; the Puzzles tab rows start with "Lv N"; under the
  progress bar, "4×4 mastery Lv 2 (Lv 5: +10 % moves on this puzzle)". Reaching a milestone pops
  "2×2 Mastery 5: +10 % moves on this puzzle" over that puzzle, with the unlock sting.
- Screenshot: [mastery in the row](screenshots/puzzles/mastery.png) (the `row3` preset is now v3 with mastery XP).
- Tests: start at level 1; XP per solve (2×2 = 1, 4×4 = 7.5); 25 XP → level 2 (signalled); +1 %/level; level 10 has both
  milestones (moves × 1.09 × 1.10, moves per solve × 0.9) and every level on the way is signalled once; moves really
  multiplied; next milestone; independent per puzzle; a level-50 2×2 gives +5 % on the 3×3; level 25's Solves bonus; save round
  trip; **v2 → v3 migration**. 1421 checks, `All good.`
- **Balance:** not tuned yet; mastery makes the already-too-fast economy faster. Task 4.7 tunes everything together.
- **Next:** task 4.7 (rebalance the early game, and make the split a real choice).

## 2026-11-03 — Task 4.5: the rest of the placeholder tracks
- `tools/make_music.py` now makes all 7 tracks (`python3 tools/make_music.py [file.wav ...]`; ~25 s for all), adding
  plucked guitar (Karplus-Strong), kalimba, a soft synth lead and a `melody()` helper. Flavours from PLAN §4.3:
  **Parity** (4×4, 84 BPM, walking bass and plucked licks), **Big Cube Energy** (5×5, 92 BPM, brighter drums and synth lead),
  **Long Solve** (7×7, 66 BPM, ambient pads and rain), **Twelve Faces** (Megaminx, 78 BPM, kalimba melody) and **Finals**
  (World Championship, 88 BPM, lead + kalimba hook, fuller groove). All 21–29 s loops at −20 dBFS RMS; 7.5 MB total.
- **Seamless loops fixed for every track:** the final low-pass filter now pre-rolls with the loop's end, so it no longer
  starts from silence at sample 0. The seam jump is now ≤ the track's own largest step; for two tracks that's the kick on
  beat 1. All tracks were regenerated (Practice Room and First Sub-20 change slightly).
- `Content.TRACKS`: every entry now has a file (CC0, "Cube Idle (placeholder)"). `assets/CREDITS.md` lists them all, with an
  "Owner to supply" note: the final soundtrack is still decision D8.
- Tests: every track has a file, is credited, CC0/CC-BY and loops; the 4×4's track is Parity. **Jukebox locks:** a fresh game
  can play only Practice Room; First Sub-20 says "Unlock 3×3…", Twelve Faces "Unlock Megaminx…", Finals "Win a World
  Championship…"; after unlocking up to the 5×5 four are playable and Long Solve still needs the 7×7. 1400 checks, `All good.`
- **Owner:** none of these have been listened to (no speakers in the container). Please give them a listen in the Jukebox.
- **Next:** task 4.6 (Puzzle Mastery).

## 2026-11-03 — Test fix: sound checks no longer depend on timing
- The 4.4 commit was merged after a run that printed "1 failed" (my commit command checked that the run printed, not that
  it said `All good`). Six reruns were clean, and the likely culprit was one of the tests that count sounds (the 0.5 s
  unlock / 0.25 s chime rate limits overlapping). Those tests now clear `Audio._last_played` right before the sound they check,
  so they don't depend on timing. 1366 checks, `All good.` **Sessions: gate commits on `All good`, not on the run finishing.**

## 2026-11-03 — Task 4.4: Megaminx
- **`PuzzleShapes.megaminx()`:** a regular dodecahedron (face normals = the cyclic permutations of (0, ±φ, ±1)),
  turned so one face points up, scaled to inradius 1.6 (about a 3×3), with WCA face names U, F, R, BR, BL, L (upper ring by
  angle), DR, DBR, B, DBL, DL and D. **62 pieces** (12 centres, 30 edges, 20 corners) and 132 stickers in the 12 standard colours
  (`PuzzleShapes.MEGAMINX_COLORS`, `palette(model)`). Each face is cut the usual way into a centre pentagon, 5 edge quads and
  5 corner kites. **Three layers per axis** (cap, middle, opposite cap), with cuts computed from the geometry.
- **The same `TwistyModel`:** 72° steps give the 60-element icosahedral rotation group (same BFS as the cubes).
  New fields: `notation_style` ("wca" / "pochmann"), `palette`, `radius` (bounding, used by the view), `shape_key` and
  `piece_geometry`. **Rotation tables are now cached per `shape_key`** ("cube" for every n, "megaminx"), so building the
  60×60 table happens once, not once per view.
- **Pochmann notation:** two-layer moves `R++ R-- D++ D--` (everything but the opposite cap, 2/5 turn; also `R+`/`R-` for
  1/5), face turns `U U' F2 BL2'`; `parse()` reads them all. `random_move()` makes WCA-style Megaminx scramble moves:
  R±± and D±± alternating, with an occasional U/U'.
- **View:** shaped puzzles get one `MeshInstance3D` per piece (`PuzzleMeshes.shaped_piece`: dark body caps + sides down to
  an inner apex, and coloured sticker polygons, culling off, normals pointing outward). They're placed with the same
  transforms as cube pieces, so turns, the solve replay, speed mode, flash and drop-in all work unchanged. The camera,
  backdrop, shadow and drop-in now size from `model.radius` instead of `model.size` (0 for the Megaminx). A new puzzle starts
  with at least 16 scramble moves. The Megaminx clicks like a 6×6.
- Reachable in-game only after a World Championship (`requires_prestige`); `PUZZLE=megaminx` and the new `row6` preset
  show it now. Screenshots: [Megaminx](screenshots/puzzles/megaminx.png), [all 6 puzzles](screenshots/puzzles/row6.png)
  (this is also 4.3a's 6-puzzle shot).
- Tests: 62 pieces, 132 stickers, group of 60, solved at start; **every face turn ×5 = solved (and not before), R++ ×5 = solved,
  a 70-move scramble isn't solved and + inverse = solved**; notation round trips (R++, D--, U, U', BL2'); scrambles use R, D and U;
  face names; 12 colours. View: 62 nodes, and after animated turns every piece is where the model says; switching back to a cube
  uses the MultiMeshes. 1366 checks, `All good.`
- Limits: `drawn_stickers()` (the cube sticker check) doesn't cover the Megaminx; its test compares piece transforms instead.
- **Next:** task 4.5 (more placeholder tracks).

## 2026-11-03 — Task 4.3b: split controls
- **`GameState.set_share(id, share)`** sets one puzzle's share and rescales the others in proportion; if they were all 0, they
  get the rest equally. **`adjust_share(id, delta)`** steps it, snapped to whole percents. The total always stays 100 %
  (`set_split` normalises), and with a single puzzle it's always 100 %.
- **"Puzzles" shop tab** (`SplitPanel`, `scripts/ui/split_panel.gd`, tab index 2): a short explanation, **Quick split: Focus
  newest / Spread evenly**, and one row per unlocked puzzle with **− / +** (10 % steps), the share in big type, and
  "X moves/s · +Y Solves/s". It rebuilds when a puzzle unlocks or the save resets, and refreshes with the main UI and on
  `split_changed`. With one puzzle it says "Unlock the 3×3 to share your helpers between two puzzles" and disables the controls.
- Screenshot: [Puzzles tab](screenshots/puzzles/split_tab.png).
- Tests: set_share rescales in proportion; a share stops at 100 %; −10 % ×3 = 70 % with the rest going to the others;
  **200 random adjustments keep the total at 100 % with nothing negative**; presets; panel buttons (−, Spread evenly) and
  texts in the real main scene. 1331 checks, `All good.`
- Note: `test_puzzle_row`'s "unlock sting plays" check failed once during this work and passed on every run since. Watch it;
  the likely cause is the 0.5 s unlock-sound rate limit overlapping a helper reveal.
- **Next:** task 4.4 (Megaminx).

## 2026-11-03 — Task 4.3a: puzzle row + focus
- **Puzzle row** (`%PuzzleRow` under the big view): a `PuzzleChip` (`scenes/puzzle_chip.tscn`) for every unlocked puzzle
  except the focused one. Each has a small `PuzzleView3D` (always Graphics Low, never sways, ≤ 4 visible turns/s, speed
  mode above that, and its own solve replay when that puzzle solves), the name, and "+Solves/s · share %". The big view now
  turns at the focused puzzle's share only. Chips stay alive (one per puzzle) and the focused one is hidden.
- **Click-to-focus:** clicking a small puzzle calls `Game.set_focus`, so the big and small views swap. It doesn't tap.
  Drags on small views still rotate them.
- **Unlocking:** the next locked puzzle shows as a chip with a padlock, its cost (green when affordable) and an
  **Unlock** button. Unlocking focuses the new puzzle; the big view **drops it in** (`PuzzleView3D.drop_in()`, 0.55 s fall
  with a small bounce, skipped by Reduce motion), the unlock sting plays, and the music follows to its track (follow mode).
  7×7 and Megaminx don't show until prestige exists. The next puzzle was already in Next goal.
- Theme: `PuzzleChipPanel` card style.
- **Bench split:** `bench` (the 7×7 alone) and `bench_row` (all five cubes: the big 7×7 + 4 small views), both on the row5
  state with the economy running. In this container (software rendering), Low 34.5 → 46.4 ms (**1.35×**) and High
  86.7 → 94.4 ms (**1.09×**), within the 1.5× target.
- **Exit fix:** in the bench, solves kept starting new chimes *after* `stop_all()`, so a playback was alive at exit.
  `Audio.shut_down()` now stops everything and refuses new sounds; the screenshot tool also stops the economy before
  quitting, and the test runner uses `shut_down()`.
- New presets `row3` (2×2/3×3/4×4, focused on the 4×4) and `row5` (all cubes, focused on the 7×7), written as v2 saves.
  Screenshots: [1 puzzle](screenshots/puzzles/fresh.png), [3 puzzles](screenshots/puzzles/row3.png),
  [5 puzzles](screenshots/puzzles/row5.png). **The 6-puzzle shot comes with the Megaminx (4.4).**
- Tests: fresh shows the 2×2 and a locked 3×3 chip (Unlock disabled until 150 Solves); Unlock unlocks, swaps the big view, drops
  in and plays the sting; the 2×2 moves into the row and the 4×4 becomes the locked chip; clicking a small puzzle focuses it,
  swaps the views and doesn't tap; small views are Low and don't sway. 1312 checks, `All good.`
- **Next:** task 4.3b (split controls).

## 2026-11-03 — Task 4.2: parallel puzzles + save v2 (D9)
- **`GameState` runs every unlocked puzzle at once.** New state: `unlocked_puzzles` (ladder order), `puzzle_progress`
  (moves toward each puzzle's next solve), `focused_puzzle` and `split` (a weight per puzzle). `add_moves()` (helpers and
  offline) divides moves by the split; `tap()` goes to the focused puzzle; `add_moves_to(id, amount)` completes that puzzle's
  solves with its own `moves_per_solve` × method upgrades and `solve_value` × value upgrades. Income is summed over puzzles.
  The old global 15-move solve (`BASE_MOVES_PER_SOLVE`) and `move_progress` are gone: use `get_move_progress(id)`.
  `get_moves_per_solve(id)` / `get_solve_value(id)` default to the focused puzzle.
- **API:** `get_puzzle_share/get_split/set_split(weights)/set_split_preset("newest"|"even")`,
  `get_puzzle_moves_per_second/get_puzzle_solves_per_second(id)`, `get_next_locked_puzzle()`,
  `can_unlock_puzzle/unlock_puzzle(id)`, `set_focus(id)`, `is_puzzle_unlocked(id)`; `has_won_championship()` is `false` until
  Phase 6, so 7×7 and Megaminx stay out of reach. Unlocking spends the cost, **focuses the new puzzle and moves the whole split onto
  it**. Signals: `solved(count, puzzle_id)` (new argument), `puzzle_unlocked`, `focus_changed`, `split_changed`, and `purchased("puzzle", id)`.
  The next puzzle is now a Next goal candidate. The 4.0-era placeholders are replaced with real state.
- **Save v2:** a `puzzles` block {unlocked, progress, focus, split}. **Migration v1 → v2:** 2×2, plus the 3×3 if any upgrade was
  owned; the newest is focused and gets the whole split; v1 `move_progress` goes to the 2×2 (clamped under one solve).
  Screenshot presets are still v1 and migrate (mid/late start with 2×2 + 3×3, focused on the 3×3).
- **UI (minimal until 4.3a):** the big view shows the focused puzzle and follows `focus_changed`; the progress bar reads it;
  solves on other puzzles still chime and pop. **There's no unlock button yet; 4.3a adds the puzzle row.**
- **Simulator:** it learns kind `"puzzle"` (the next locked one; value measured by briefly unlocking it with the default
  split). **Pacing:** first helper 0:13 ✓, first upgrade 0:48 ✓, 3×3 at 4:38 ✓ now pass for real (their expected-failure marks
  were removed). **But the economy is now far too fast:** all content by 17:55 (4×4 at 12:01 vs 25–35, 5×5 at 17:55 vs 50–70)
  because higher puzzles pay so much more per move. **That's task 4.7's job.** `docs/BALANCE.md` regenerated.
- Tests: parallel puzzles (only 2×2 at start, ladder order, unlock cost/focus/split, weights → shares adding to 1, bad weights,
  presets, helper moves split exactly, per-puzzle solves and values, taps to the focused puzzle only, rates add up, 7×7 locked,
  v2 save round trip) and the **v1 → v2 migration** (with and without upgrades). Older tests updated from 15-move solves.
  1265 checks, `All good.`
- **Next:** task 4.3a (puzzle row + focus).

## 2026-11-03 — Task 4.1: puzzle data
- `Content.PUZZLES`: 2×2 → 3×3 → 4×4 → 5×5 → 7×7 → Megaminx with `moves_per_solve`, `solve_value`, `unlock_cost` and
  `requires_prestige`, using PLAN §4.1's starting curve (8/1/free, 20/4/150, 60/18/25K, 120/50/1.5M, and for after
  prestige 300/200/5e8 and 700/800/2e11, the last two placeholders until Phase 6). Solves per move rise every tier
  (0.125 → 0.2 → 0.3 → 0.42 → 0.67 → 1.14). `Content.get_puzzle(id)`. Puzzle ids are also the `PuzzleShapes` ids
  (`megaminx` arrives in 4.4).
- Tracks were already linked by their `unlock` field; a test now checks every track points at a real puzzle (or
  "championship") and every puzzle has a track.
- Not used by the game yet; 4.2 makes them run. 1227 checks, `All good.`
- **Next:** task 4.2 (parallel puzzles + save v2).

## 2026-11-02 — Task 3.6: Welcome back panel (Phase 3 done)
- **`scenes/welcome_panel.tscn` (`WelcomePanel`)** replaces the default AcceptDialog. It's a dimmed overlay with
  "Welcome back!", "You were away for 2h 15m.", a big green **"+220.6K Solves"** (new theme variation `BigAccentLabel`),
  "Your helpers kept solving while you were gone." and a **Collect** button (PrimaryButton; Space/Enter also collect).
  A damaged-save notice (`Game.load_notice`) shows in the same panel; alone, the button says OK.
- **Collect moment:** while the panel is open the Solves counter holds the pre-offline amount. Collect plays the solve chime,
  pops "+X Solves" under the counter and lets it count up. Space doesn't turn the cube while the panel is open.
- **No panel when nothing was earned** and there's no notice. `main.gd` clears `Game.offline_report` and `load_notice` once shown.
- New screenshot preset **`welcome`** (the mid state with `away_seconds: 8100`; the screenshot tool turns that into
  `saved_at`). Screenshot: [welcome](screenshots/welcome/welcome.png).
- Tests: no panel on a fresh start; after 2h 15m away it shows the right time and amount, holds the counter, ignores
  Space, chimes on Collect, then the counter reaches the total; a notice alone shows with OK and only once. 1159 checks, `All good.`
- **Phase 3 is complete** (3.5 was done in 2.2). Owner: a good time to play with sound on and write FEEDBACK.md. The
  sounds and music are synthesised placeholders, so please say what to change.
- **Next:** Phase 4, task 4.1 (puzzle data), then 4.2 parallel puzzles (D9).

## 2026-11-02 — Task 3.4: Settings autoload and panel
- **`Settings` autoload** (`scripts/autoload/settings.gd`, `GameSettings`; loads after Game and Audio). All settings are
  data in `SPEC` (section, default, choices or range): master/music/SFX volume (100/50/70 %), music mode
  (follow/shuffle/loop) + loop track, background audio (duck/mute/keep), graphics (high/low), reduce motion, notation
  (short/scientific). Stored in `user://settings.cfg`. `set_value()` validates (clamps volumes, rejects bad choices),
  saves, applies and emits `changed`. Audio and notation apply themselves; `main.gd` applies graphics and reduce motion.
  **Took over GraphicsConfig** (deleted): same file and `[graphics] quality` key, so a 1.5-era choice still loads (tested),
  and unknown sections in the file are kept.
- **Settings panel** (`scenes/settings_panel.tscn`, `SettingsPanel`), opened by the top-bar Settings button (now a plain
  Button) and closed by Close, Escape or a click outside. It has volume sliders with %, music mode, background audio,
  a **Jukebox** (play buttons for unlocked tracks, which switch to "Loop one track"; locked tracks say "Unlock 4×4 to hear
  this", "Win a World Championship…", or "Coming soon"), Graphics, a Reduce motion switch, Numbers (short/scientific),
  and **Reset save…** with a confirmation that names what's lost (Solves, lifetime, helper and upgrade counts, stats) and
  says settings are kept. Space doesn't tap while the panel is open. Sliders got accent styling in the theme.
- **Reduce motion** (`PuzzleView3D.set_reduce_motion`, `FxLayer.particles_enabled`): no idle sway, tap squash, solve
  bounce, speed-mode wobble or particle burst. Turns still animate and floating numbers stay (they're information).
- **Number notation:** `Num.notation` ("short" 1.50K / "scientific" 1.50e3).
- **Audio exit robustness:** `Audio.music_enabled` (the screenshot tool turns it off; a track still playing at exit was
  reported as a leak about a third of the time). The test runner waits 0.6 s after `stop_all()`. 5 + 3 screenshot runs clean.
- Screenshot tool: `SETTINGS=1` opens the panel; it also no longer writes settings. Screenshot: [panel](screenshots/settings/mid_settings.png).
- Tests: the store (defaults, validation, clamping, survives restart, survives a save wipe, legacy 1.5 file, unknown
  sections kept, bad stored values fall back) and the panel in the real main scene (opens, blocks Space, Graphics → view,
  Reduce motion → no sway/particles/squash/wobble, scientific notation in the UI, SFX slider → bus, Jukebox lists all and
  plays, reset dialog text, reset wipes the save but keeps settings, closes). 1127 checks, `All good.`
- **Next:** task 3.6 (offline panel), the last task of Phase 3.

## 2026-11-02 — Task 3.3: Buy ×1 / ×10 / Max
- **`GameState`:** `get_building_cost_for(id, count)` is the exact sum of each copy's `ceil(base × 1.15^n)`, so bulk costs
  match buying one at a time; a closed-form geometric sum would differ by the rounding. `get_max_affordable(id)`.
  `buy_buildings(id, count)`: ×10 is **all or nothing**, and `GameState.BUY_MAX` (−1) buys as many as affordable;
  it returns the number bought and emits `purchased` once. `buy_building(id)` is unchanged (the simulator uses it).
  Loops are capped at `BULK_LIMIT` (10,000).
- **Shop toggle:** "Buy ×1 / ×10 / Max" chips (`ToggleChip` theme variation, one `ButtonGroup`) at the top of the Helpers
  tab. Cards show the chosen amount's cost ("×10 · 1.23K Solves"; Max shows how many, "×22 · 3.02M Solves", or ×1
  greyed out if none), and they're affordable only if all of it is. `main.set_buy_amount(1 | 10 | BUY_MAX)`.
  The choice isn't saved (Settings could keep it later).
- `screenshot.sh` takes `BUY=10` / `BUY=-1`. Screenshots: [mid ×10](screenshots/buy/mid_buy10.png),
  [late ×10](screenshots/buy/late_buy10.png), [late Max](screenshots/buy/late_buy-1.png).
- Tests: ×10 = sum of singles; ×10 one Solve short buys nothing and spends nothing; exact ×10; Max with 0 Solves = 0;
  Max = the most affordable (one more is too many) and spends exactly that; the toggle changes the card texts; a Max press
  buys that many. 1090 checks, `All good.`
- **Next:** task 3.4 (Settings autoload and tab).

## 2026-11-02 — Task 3.2: music system (lo-fi)
- **`Content.TRACKS`**: all 7 tracks from PLAN §4.3 (id, title, artist, license, file, `unlock` puzzle id; "championship"
  for Finals). Two have files; the other five have `file = ""` and are skipped until task 4.5 or decision D8.
- **Two placeholder lo-fi loops, synthesised by `tools/make_music.py`** (CC0; music sites aren't reachable from the
  container): *Practice Room* (2×2, 70 BPM, Fmaj7–Em7–Dm7–Cmaj7, soft kick, rain) and *First Sub-20* (3×3, 80 BPM, swung,
  Dm9–G13–Cmaj9–A7b9). FM electric piano, a soft pad bed, saturated sine bass, synthesised drums and vinyl crackle;
  8 bars each (27 s / 24 s), the tail folded into the start for a seamless loop, about −20 dBFS RMS. 22.05 kHz mono WAV
  (~1.1 MB each), imported with forward looping (`edit/loop_mode=2`). **Not heard by me. Owner: please listen**; they're
  placeholders, but say if the style is off.
- **Music in `Audio`:** two `AudioStreamPlayer`s on the Music bus with a **2 s linear crossfade** (never two at full volume).
  Modes in `MUSIC_MODES`: *follow* (default: the focused puzzle's track; after 3 loops a 25 % chance of a 2-loop detour to
  another unlocked track), *shuffle* (a new track every 2 loops), *loop* (one track). **Ducks to 30 %** when the window loses
  focus (`focus_behaviour` duck/mute/keep, for 3.4's setting). Music starts **2 s after launch and fades in**. That lets the
  first clicks lead in, and it keeps the 120-frame headless smoke run from quitting with music playing, which Godot reports
  as a leaked resource. Loops are counted by playback-position wrap-around.
- **Rules in `GameState`:** `get_unlocked_track_ids()` and `get_track_for_puzzle()`, plus **placeholders**
  `get_unlocked_puzzle_ids()` (2×2 and 3×3) and `get_focused_puzzle_id()` ("3x3"); **task 4.2 replaces these two with real
  puzzle state.** `main.gd` passes the context to `Audio.set_music_context()` every UI refresh.
- Tests: track data (fields, unique ids, files exist, CC0/CC-BY, credited, looping, ≥ 2 with music); unlocked tracks;
  no music before the delay, then a fade-in from silence; the crossfade overlaps but never has two at full volume, and ends
  with one; ducking to 30 % and back; loop mode never changes; shuffle changes after 2 loops. 1068 checks, `All good.`
- **Next:** task 3.3 (Buy ×1 / ×10 / Max).

## 2026-11-02 — Task 3.1: Audio autoload + SFX
- **Sounds are synthesised by us** (`tools/make_sfx.py`, Python standard library only; CC0): kenney.nl isn't reachable
  from the container, and our own sounds avoid licence questions anyway. Lo-fi-friendly and soft (PLAN §4.3):
  `click.wav` (filtered-noise plastic clack + low knock, 0.09 s), `chime.wav` (FM "Rhodes" major third, 1.4 s),
  `buy.wav` (two Karplus-Strong plucks a fourth apart, 0.6 s), `unlock.wav` (rising C-E-G-C Rhodes arpeggio, 2.1 s).
  All about −20 dBFS RMS, no clipping, DC removed. **I can't listen in the container. Owner: please check they sound
  good**, and say what to change (brighter, softer, different notes…); it's a quick edit and re-run.
- **`Audio` autoload** (`scripts/autoload/audio.gd`, `AudioManager`) with buses from `default_bus_layout.tres`
  (Master > Music, SFX). Default volumes: SFX 70 %, Music 50 % (set by Settings in 3.4). One `AudioStreamPlayer` per sound,
  with polyphony. **Rate limits per sound:** click ≤ 20/s, chime ≤ 4/s, buy ≤ ~16/s, unlock ≤ 2/s.
  Click pitch: `(3 / size)^0.25` (7×7 about 20 % lower, 2×2 about 10 % higher) × random ±8 %.
- **Hooked up in `main.gd`:** tap → click, solve → chime, purchase → buy, a helper newly revealed in the shop → unlock
  sting (helpers already visible at start stay silent). Puzzle unlocks will use the same sting in 4.3a.
- `Audio.stop_all()`: the test runner and screenshot tool call it and wait 0.25 s before quitting. Otherwise a sound still
  playing at exit is reported as "resources still in use", which `run_tests.sh` treats as an error.
- Tests: buses exist with default volumes; 100 solves in one frame play **one** chime; each event plays; a second click in
  the same instant is skipped; the chime plays again after 0.25 s; volume 0 mutes. Game events → sounds in the real main scene.
  995 checks, `All good.`
- **Next:** task 3.2 (music system, lo-fi).

## 2026-11-02 — Task 2.4: juice (Phase 2 done)
- **Floating "+N" on every tap**, at the cursor (the view's `tapped` signal now carries the global click position) or at
  the puzzle's centre for Space/Enter. White bold text with a dark outline (theme variation `PopTap`), rising 70 px and
  fading over 0.9 s, with a little sideways jitter.
- **"+X Solves" + particle burst on solves:** green `PopSolve` text from the top of the puzzle and a one-shot
  `CPUParticles2D` of 28 squares in the six sticker colours. **Rate-limited:** solves are summed and popped at most every
  0.25 s, and the burst runs at most every 0.5 s, so a solve every frame stays readable.
- **Pooled:** `FxLayer` (`scripts/ui/fx_layer.gd`, `%FxLayer` drawn over the whole screen, ignores the mouse) keeps
  20 labels and reuses the oldest when all are busy, so it never allocates during play.
- **The Solves counter counts up:** it eases towards the real value (rate 12/s, snapping when within 0.2 %) and
  snaps down at once when you spend.
- **Squash on tap:** `PuzzleView3D.squash()`, 7 % down and 4 % out, easing back in about 0.1 s, on top of the per-move punch.
- **Reduce motion (3.4)** should set `FxLayer.enabled = false` and skip `squash()`; both are single switches.
- Test runner: tests may now `await` frames (the runner awaits each `test_*`).
- Tests: 1,000 taps in a frame keep ≤ 20 texts and they fade out; the counter eases up, reaches the value and snaps down;
  squash and spring-back; and **a real 120-frame run of the main scene at the late preset's ~369K moves/s** (speed mode,
  solves every frame): ≤ 20 texts, solve pops shown, no errors. 978 checks, `All good.`
- `screenshot.sh` takes `JUICE=1` (three taps and a solve, captured 8 frames later). Screenshot: [mid_juice](screenshots/juice/mid_juice.png).
- **Phase 2 is complete.** Owner: a good time to play and write FEEDBACK.md (look, shop cards, juice).
- **Next:** Phase 3. Task 3.1 (Audio autoload + SFX); 3.5 is already done.

## 2026-11-02 — Task 2.3: shop cards
- **Helper cards** (`scenes/shop_card.tscn`, `ShopCard`): a Button with an icon tile, name, description, rate line
  ("+2 moves/s each · +30/s total"), a big owned count and the cost. **Affordable:** bright, green cost, and it lifts 3 px
  on hover (a tween on the content; the hover border turns green). **Not affordable:** dimmed to 62 %, grey cost, disabled.
- **Next locked helper is always visible:** the first helper not unlocked yet shows as a "???" card with a padlock,
  "A new helper appears at X lifetime Solves" and "current / X". Helpers after it stay hidden.
  New `GameState.get_building_unlock_at(id)`.
- **Upgrades** are now a 5-column grid of icon tiles (`scenes/upgrade_tile.tscn`, `UpgradeTile`) with the cost underneath and
  a custom tooltip panel (name, description, "Costs X Solves"). Bought upgrades stay as dimmer **"Owned"** tiles after
  the buyable ones, so the grid shows progress. The tab title shows a badge, **"Upgrades (N)"**, when N are affordable.
- **Icons:** 14 SVGs from game-icons.net by Lorc and Delapouite (**CC BY 3.0**) in `assets/icons/`, with the black
  background removed so they tint; imported at 128 px (`svg/scale=0.25` in each `.import`). Every one is listed in
  `assets/CREDITS.md`. Content entries have a new `icon` field; `Content.icon(name)` loads it.
  **Credit requirement:** CC BY means the in-game Credits screen (9.3) must name game-icons.net, Lorc and Delapouite.
- `screenshot.sh` takes `TAB=1` to open the Upgrades tab.
- Tests: every content entry has an icon file and every icon is credited; card states (fresh: Friend unaffordable +
  Club as the only "???" card; after 40 Solves: affordable green cost, Club revealed, Robot the next "???"); the upgrade badge;
  clicking a card buys; owned tiles; buyable tiles first. 964 checks, `All good.`
- Screenshots: [fresh](screenshots/shop/fresh.png), [mid](screenshots/shop/mid.png), [late](screenshots/shop/late.png),
  [upgrades grid](screenshots/shop/mid_tab1.png).
- **Next:** task 2.4 (juice), the last task of Phase 2.

## 2026-11-02 — Task 2.2: layout (and 3.5 keyboard, done early)
- **New layout** (`main.tscn` rewritten; every unique name the code uses is kept):
  - **Top bar** (`TopBar` panel): Solves (TitleLabel, now 36 px), "+X solves/s · Y moves/s", and a **Settings** menu button on the right.
  - **Stage** (left, 1.25× the shop's width): the 3D puzzle now expands to fill the space (about 650×400 at 720p instead
    of 300×300), then the move ticker, a hint ("Click the cube or press Space: +N moves · drag to look around"), the solve
    progress bar, and a **Next goal** strip (`GoalStrip`: accent bar on the left).
  - **Shop** (right, min 460 px): unchanged tabs. The **Turn button is gone**; clicking the cube or pressing Space/Enter taps.
- **Next goal** = `GameState.get_next_goal()`: the cheapest helper not owned yet, or upgrade not bought yet whose
  requirements are met. When everything is owned, it's "another <cheapest helper>". It returns the missing Solves and the
  seconds at the current helper rate (INF without helpers → "tap to get there"); it shows "ready to buy!" when affordable.
  Puzzles join it in 4.3a.
- **Keyboard (task 3.5, done early):** a `tap` input action in `project.godot` (Space, Enter, keypad Enter, physical keys).
  `main.gd._unhandled_input` uses `is_action_pressed(..., allow_echo = false)`, so holding a key never repeats.
  This was needed now because Space used to work only through the Turn button's focus. New CLAUDE.md rule 9.
- **Settings menu:** the Graphics High/Low toggle moved from the button under the stats into a radio item in the
  Settings `MenuButton` popup. Task 3.4 replaces this popup with a real Settings panel.
- Theme additions: TopBar, GoalStrip, HintLabel, PopupMenu styles, HBox separation 12.
- Tests: next goal (first Friend, missing Solves, no-rate ETA, ready to buy, the next new thing, "another" at the end);
  layout (Turn button gone, strip and settings exist, Space taps, held Space doesn't repeat, Enter taps, strip text);
  the graphics test now goes through the Settings menu. 910 checks, `All good.`
- Screenshots: [fresh](screenshots/layout/fresh.png), [mid](screenshots/layout/mid.png), [late](screenshots/layout/late.png),
  [mid at 1920×1080](screenshots/layout/mid_1080p.png) (quantised to 256 colours to stay under 300 KB).
  1080p is the same layout scaled (canvas_items stretch, same 16:9 aspect).
- **Notes:** the shop column still has empty space early on. 2.3's "???" cards for locked helpers fill it.
  The stage is wide, not square; the camera frames by height, so the puzzle stays centred.
- **Next:** task 2.3 (shop cards).

## 2026-11-02 — Task 2.1: theme + font
- **Font:** Inter 4.1, variable (`assets/fonts/InterVariable.ttf`, 880 KB), downloaded from the official GitHub release, under
  SIL OFL 1.1 (full text in `assets/fonts/Inter-OFL.txt`). New `assets/CREDITS.md` lists it; every future asset goes there.
  The theme uses two weights through `FontVariation` (450 for text, 700 for titles, tabs and the main button).
- **`ui/theme.tres`** is the project theme (`gui/theme/custom`). Dark palette (bg `#16181d`, panels `#1d2027`, raised `#252932`,
  text `#eceef2` / dim `#aab0bd` / faint `#7c8392`) with **one accent, green `#3ccf8e`**. It styles buttons (normal, hover,
  pressed, disabled, focus), tabs (accent line on the selected tab), the progress bar, scrollbars, panels, dialogs and tooltips.
  Type variations: TitleLabel, SubtitleLabel, DimLabel, FaintLabel, TickerLabel, PrimaryButton (the Turn button: green
  border, bold 22 px, no extra focus ring because it always has focus), SubtleButton (the Graphics toggle), and layout
  variations PageMargin, ColumnsBox, StackBox. The default VBox separation is 8.
- **`main.tscn` has no overrides left:** all 23 `theme_override_*` lines and the 3 inline StyleBoxes are gone; nodes use
  `theme_type_variation` instead. New rule 8 in CLAUDE.md, enforced by `test_theme_is_used_everywhere` (no overrides in any
  scene, every variation used exists in the theme, the font loads and is credited). 895 checks, `All good.`
- Side effect: disabled (unaffordable) shop rows now look clearly different from affordable ones.
- Screenshots: before [mid](screenshots/theme/before_mid.png) / [late](screenshots/theme/before_late.png),
  after [mid](screenshots/theme/after_mid.png) / [late](screenshots/theme/after_late.png).
- The theme was generated once by a throwaway script; from now on **edit `ui/theme.tres` directly** (in the Godot editor or as
  text). The offline "Welcome back" dialog is themed but wasn't screenshotted (it only shows after time away); task 3.6 replaces it.
- **Next:** task 2.2 (layout: top bar, big stage, next-goal strip, remove the Turn button).

## 2026-11-02 — Decisions D9–D12 (docs only)
- **D9 (owner): all unlocked puzzles run at once**, replacing D1 (one active puzzle). Helpers are one shared team whose
  moves the player splits across puzzles. Taps go to the focused puzzle. The screen is one big focused puzzle plus a row of
  small ones (click to focus). A new unlock moves the whole split onto it, so a player who ignores the split still plays a ladder.
- PLAN §4.1 rewritten, with a **design risk**: if "everything on the top puzzle" is always best, the split is a fake
  choice. Task 4.7 now requires the bot's best split at 30 min to be a real mix (no puzzle above ~70 %).
  §4.2 notes the small views always use Graphics Low and the bench must cover a full row.
- Roadmap Phase 4: **4.2 Parallel puzzles + save v2**, **4.3a Puzzle row + focus**, **4.3b Split controls** replace
  "active puzzle" and "ladder UI + tier-up". 4.6 Mastery now levels every running puzzle in parallel.
- **D10** random drops with pity, **D11** toggles + Coach rules, **D12 Hall of Fame before 1.0**: new tasks
  **8.6 Hall of Fame reset**, **8.7 Legacy perk tree** (the first node automates Compete, and every branch adds new things to do),
  **8.8 Tune** (target time chosen with the owner after a playtest; ~8–12 h suggested).
- PLAN §7: D9–D12 moved to Answered; D1 struck through. FEEDBACK has a Handled entry. Nothing in Phases 0–1 changes.
- **Next:** task 2.1 (theme + font).

## 2026-11-02 — Player research and plan (docs only)
- The owner shared the Steam library of the player the game is made for. The idle games are Idle Skilling (804 h),
  The Perfect Tower II (159 h), Idle Pins (142 h), Revolution Idle (59 h) and Zero IDLE (49 h); tModLoader isn't idle,
  so it's left out. New **`docs/PLAYER_RESEARCH.md`**: what each game does, the 10 patterns this player keeps coming back to,
  what to avoid (opaque mechanics, RNG walls, slow first prestige, thin repeat prestiges, low FPS), and how each pattern
  becomes Cube Idle, with sources. Steam and the wikis are blocked by this container's network, so the research used web
  search summaries; exact numbers in those games may have changed since.
- **Roadmap:** new tasks marked **(PR)**, with no change to finished tasks:
  4.6 Puzzle Mastery [D9] (moved up from Phase 11; the rebalance is now 4.7), 5.6 Algorithm Lab (real-time research
  that runs offline), 5.7 Helper Promotion (optional; the rebalance is now 5.8), 6.3 Trophy shop → perk tree whose branches
  unlock systems, 6.3b auto-buyers + auto-Compete (6.4 keeps its number), 7.1 → ~100 tiered achievements,
  7.3 Cube Collection [D10], 7.4 Comp Kit loadout, 8.3 Competitions, 8.4 Challenge runs, 8.5 Coach rules [D11],
  Hall of Fame second layer [D12].
- **PLAN:** content target 40–100 h (was 20–40 h), new §4.6 summarising the research, an updated phase table, and new open
  decisions **D9–D12** in §7, each with a recommendation. CLAUDE.md lists PLAYER_RESEARCH.md as shared memory.
- No code changes. **Next:** task 2.1 (theme + font); D9–D12 aren't needed until 4.6 and later.

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
