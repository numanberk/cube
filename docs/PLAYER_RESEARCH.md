# Player research: what our player loves in idle games

The game is made for one specific player first. Their Steam library (shared by the owner, 2026-11-02) shows these
idle games, by hours played:

| Game | Hours | Reviews (Steam) | One-line summary |
|---|---|---|---|
| **Idle Skilling** | **804** | Very Positive | Many parallel skills that feed each other, collections, 2 prestige layers, 5–10 min daily check-ins |
| **The Perfect Tower II** | 159 | Very Positive | A town of buildings, each a mini-game; modules (loadouts); military/town tier resets; scripts that automate everything |
| **Idle Pins** | 142 | Mixed (~62 %) | Collect 250+ pins, merge and tune them, slot them into formations; "Seasons" prestige |
| **Revolution Idle** | 59 | Very Positive | 10 coloured circles spinning faster and faster; per-circle ascension; 4+ stacked reset layers; 500+ achievements |
| **Zero IDLE** | 49 | Mixed (~69 %) | Clicker that grows into production and automated clicking; tiers, DNA upgrades, prestige |

(tModLoader is in the list too but isn't an idle game, so it's left out.)

**The player is also an almost professional speedcuber** (owner, 2026-11-03). They know csTimer, WCA rules, methods and
algorithm sets, so the game should respect real cubing: real notation, real scrambles, real inspection and averages,
and a way to use their actual skill (the Solve Station, ROADMAP Phase S). Never dumb the cubing down.

**What the numbers say:** this player isn't a casual idler. 804 hours in one game, and 140+ hours in a game with
*mixed* reviews (Idle Pins), means they stay for **systems depth, collecting and optimising**, more than for polish.
The top two games are the most *system-rich* ones on the list.

---

## 1. What each game does well

### Idle Skilling (804 h) — breadth that interlocks
- **Many parallel progress tracks.** Mining, fishing, pet breeding, crusading (combat), potions, lab research,
  construction, smithing, farming… each levels up on its own, and each feeds the others (ore → smithing → damage).
- **Collections with stars:** cards (with star levels and card perks), pets bred in a hatchery (more eggs = better odds
  of an upgraded pet), pets also drop rarely from raid bosses.
- **Mastery tasks:** collect a card set, beat a region… each task gives a permanent passive boost.
- **Two reset layers:** *Ascension* (points → permanent perks; first one around 100 AP) and a deeper *Rebirth*
  (unlocked by beating a dungeon boss). Perk trees where *the first node of each branch unlocks a new mechanic*.
- **Built for short daily sessions** (the store page says 5–10 minutes a day) with real offline progress.
- **Bosses, raids, dungeons, trekking with pet teams:** goals you can fail and come back to stronger.

### The Perfect Tower II (159 h) — a hub of mini-games and automation
- **Town of buildings, each its own mini-game** (Mine, Factory, Workshop, Laboratory, Museum, Arcade, Shipyard,
  Trading Post…), built and upgraded with a Construction Firm.
- **Modules = loadouts:** interchangeable parts that change how the tower plays.
- **Layered resets:** Military Tier, then Town Tiering, which resets almost everything else.
- **Automation as the endgame:** an in-game "AI" scripting system (impulses, conditions, actions) that can automate
  almost anything; players share scripts.
- **Weak spot (from reviews):** mechanics are opaque and the tutorial is thin. Players had to go to the wiki.

### Idle Pins (142 h, mixed reviews) — collecting and arranging
- **250+ pins to collect, merge (two Alphas make a Beta) and tune** (power, HP, multi-hit, crit chance).
- **Formations:** 25 layouts, each with its own bonus, slot count and slot types. Choosing *which pins go where* is the game.
- **Crafting blueprints (60+), dismantling, synthesising.**
- **Seasons (prestige):** pin levels reset, but unlocked stats and tunings stay; 200+ prestige upgrades.
- **Weak spots (from reviews):** thin idle side, and later prestiges add little new content.

### Revolution Idle (59 h) — the visual "number go up" engine
- **Hypnotic core visual:** ten coloured circles, each completing laps; reviewers call the spinning "smooth, almost
  hypnotic" and the appeal "numbers getting bigger while the circle spins faster".
- **Per-item ascension:** a circle levels to 100, then *ascends*: its level resets, but its multiplier and level cap rise.
- **Stacked reset layers:** Prestige → Promotion → Infinity (at 1.8e308) → Eternity. Each later layer automates the
  earlier one (auto-prestige, auto-ascension).
- **Challenges** (9, unlocked in Infinity) and **500+ achievements** that act as a guide through the game.
- **Slow start that pays off:** players say the slow parts make milestones feel earned.
- **Weak spots:** technical issues and low FPS.

### Zero IDLE (49 h, mixed reviews) — what *not* to do
- Loop: click → production → automate the clicking → prestige → tiers → DNA upgrades. The interface is praised.
- **Weak spots (from reviews):** the first prestige can take ~3 days, prestige upgrades are too expensive, there are RNG
  walls (DNA upgrades), and some tiers are much weaker than they should be.

---

## 2. The patterns this player keeps coming back to

1. **Many progress bars at once** that feed each other (Idle Skilling skills, Perfect Tower buildings).
2. **Collect, merge, star up** (cards, pets, pins).
3. **Loadouts with limited, typed slots**, an optimisation puzzle (formations, modules, pet teams).
4. **Layered resets**, each later layer automating the one before (Revolution Idle, Perfect Tower II, Idle Skilling).
5. **Small local resets** inside a run (Revolution Idle circle ascension).
6. **Automation earned as a reward**, up to "the game plays itself and I tune it" (Perfect Tower scripts).
7. **Achievements and mastery tasks as a map**, each with a permanent bonus.
8. **Things that finish while you're away** (hatchery, lab research), so a 5-minute check-in always has something to collect.
9. **Bosses and challenges you can fail**, then beat later with a better build.
10. **A satisfying, ever-faster core visual.**

**And what they put up with but we should avoid:** opaque mechanics (Perfect Tower), RNG walls and a very slow first
prestige (Zero IDLE), thin repeat prestiges (Idle Pins), and FPS problems (Revolution Idle).

---

## 3. How each pattern becomes Cube Idle

Owner decisions: D3 3D cube, D6 first prestige at ~90 min, and from this research **D9 all unlocked puzzles run at once**
(shared helper team split across them; one big focused puzzle plus a row of small ones), D10 random drops with pity,
D11 toggles + Coach rules, D12 Hall of Fame before 1.0.

| Pattern | Cube Idle version | Where in the roadmap |
|---|---|---|
| Many parallel bars (Idle Skilling) | **All unlocked puzzles run at once (D9)**, sharing one helper team that the player splits across them. **Puzzle Mastery:** every puzzle levels from its own solves, with milestone perks, kept through prestige. | 4.2, 4.3a/b, 4.6 |
| Things finish while away (hatchery, lab) | **Algorithm Lab:** real-time research (learn OLL, PLL, finger tricks, lookahead, methods) that keeps running offline. 1 slot, more from trophies. | 5.6 |
| Local resets (RI circles) | **Helper Promotion:** at 100 owned, promote a helper: its count goes back to 0, it gets a permanent ×3, and its milestones start again. Optional, never forced. | 5.7 |
| Perk trees that unlock systems (Idle Skilling) | **Trophy perk tree** with 4 branches (Practice, Team, Competition, Automation); the first node of each branch unlocks a system. | 6.3 (reworked) |
| Automation as reward (PT2, RI) | **Auto-buyers** (helpers, upgrades, puzzles) and **auto-Compete** with a threshold, bought in the Automation branch. | 6.3b |
| Achievements as a map (RI) | **~100 tiered achievements** (Solve 1/10/100/1K…) with a visible x/y bar; each +1 %. | 7.1 (expanded) |
| Collect, merge, star up (pins, cards, pets) | **Cube Collection:** ~40 real-world-style cubes (magnetic, stickerless, budget, flagship…), 1–5 stars, each with a small passive. Duplicates merge into a higher star. Drops have pity counters, so there are no RNG walls. | 7.3 |
| Loadouts with typed slots (formations, modules) | **Comp Kit:** 5 typed slots (Main cube, Backup cube, Timer, Mat, Lube); set bonuses for matching brands. | 7.4 |
| Bosses you can fail (raids, dungeons) | **Competitions:** timed events (Local → Regional → National → Continental → Worlds) where you must hit a solves/s target with your current kit; medals and collection drops. | 8.3 |
| Challenges (RI) | **Challenge runs:** a championship run with a rule (Beginner method only, No helpers, One-handed: taps ×0.5, Big cubes only…); finishing gives a permanent reward. | 8.4 |
| Scripting (PT2), but not opaque | **Coach:** a short list of if/then rules picked from menus (e.g. "If a helper costs < 5 % of my Solves → buy it"). No code. | 8.5 |
| Deeper reset layers (Rebirth, Infinity) | **Hall of Fame:** a second prestige layer that resets championships for *Legacy* points and automates Compete. | 8.6–8.8 (D12: before 1.0) |
| Hypnotic visual (RI) | Already there: real 3D turns, speed-mode wobble. Later: tiny helper cubes turning in the stage background at their own speed. | 2.4 / 9.1 |

### Rules that come from the "avoid" list
- **Every system explains itself in-game:** exact numbers in tooltips, a "?" panel per tab (Perfect Tower's biggest complaint).
- **No pure-RNG walls:** every random drop has pity (guaranteed after N tries), and merging always works.
- **The first prestige stays at ~90 min (D6); the second run is ≤ 50 % of that.** Pacing tests already enforce this.
- **Every prestige layer adds something new to do** (Idle Pins' repeat-prestige complaint): the first unlocks 7×7 and Megaminx,
  later ones unlock competitions, challenges, Coach rules and so on.
- **Performance is a feature:** the bench must stay green and Graphics: Low must hold 60 fps on a weak laptop.

---

## 4. Order of work (what changes in the roadmap)

Nothing already done changes, and phases keep their numbers. New or reworked tasks:

- **Phase 4:** 4.2/4.3 rewritten for parallel puzzles (D9: 4.2, 4.3a row + focus, 4.3b split controls), + **4.6 Puzzle Mastery** (moved from Phase 11; it's the "many bars" pattern and costs little). The rebalance becomes 4.7.
- **Phase 5:** + **5.6 Algorithm Lab**, + **5.7 Helper Promotion** (only if the sim shows the first hour still needs it). The rebalance becomes 5.8.
- **Phase 6:** **6.3 Trophy shop → perk tree**, + **6.3b Auto-buyers and auto-Compete** (6.4, tuning, stays last).
- **Phase 7:** **7.1 → ~100 tiered achievements**, + **7.3 Cube Collection [D10]**, + **7.4 Comp Kit**.
- **Phase 8:** + **8.3 Competitions**, + **8.4 Challenge runs**, + **8.5 Coach rules [D11]**.
- **Phase 8:** + **8.6–8.8 Hall of Fame** second layer (D12: before 1.0).

Content target moves from "20–40 hours" to **40–100 hours** before the late game runs out, because this player plays for hundreds.

## 5. Decisions (answered by the owner, 2026-11-02)
- **D9 Parallel play:** **all unlocked puzzles run at once.** Helpers are one shared team whose moves the player splits
  across puzzles; the screen is one big focused puzzle (taps go there) plus a row of small ones. (I had recommended
  keeping one active puzzle; the owner chose the fuller Idle Skilling feel.)
- **D10 Collection randomness:** random drops with pity counters.
- **D11 Automation depth:** toggles + menu-based Coach rules.
- **D12 Second prestige layer:** before 1.0 (tasks 8.6–8.8).

---

## Sources
Research was done with web search on 2026-11-02. The container's network blocks Steam and the wikis, so some details come
from search summaries of these pages, and exact numbers may have changed in later game updates.
- Idle Skilling: [Steam](https://store.steampowered.com/app/1048370/Idle_Skilling), [Mastery (wiki)](https://idle-skilling.fandom.com/wiki/Mastery),
  [Perks (wiki)](https://idle-skilling.fandom.com/wiki/Perks), [Raids (wiki)](https://idle-skilling.fandom.com/wiki/Raids),
  [Ultimate Guide (Steam)](https://steamcommunity.com/sharedfiles/filedetails/?id=2863651114),
  [Ascend & Rebirth timing](https://commonsensegamer.com/idle-skilling-best-time-to-ascend-rebirth/),
  [Ascension & Rebirth guide](https://tap-guides.com/2025/10/24/idle-skilling-ascension-rebirth-guide/)
- The Perfect Tower II: [Steam](https://store.steampowered.com/app/1197260/The_Perfect_Tower_II/), [official site](https://www.perfecttower2.com/),
  [Buildings (wiki)](https://wiki.perfecttower2.com/Buildings), [Headquarters (wiki)](https://wiki.perfecttower2.com/Headquarters),
  [Scripting (wiki)](https://wiki.perfecttower2.com/Scripting),
  [scripting discussion](https://steamcommunity.com/app/1197260/discussions/0/765184781366568008/)
- Idle Pins: [Steam](https://store.steampowered.com/app/1709920/Idle_Pins/), [IncrementalDB](https://www.incrementaldb.com/game/idle-pins),
  [Notes, Tips and Basic Info (Steam guide)](https://steamcommunity.com/sharedfiles/filedetails/?id=2633172919),
  [Beginner's guide](https://www.magicgameworld.com/idle-pins-beginners-guide-tips/), [Kongregate](https://www.kongregate.com/en/games/arkshija/idle-pins)
- Revolution Idle: [Steam](https://store.steampowered.com/app/2763740/Revolution_Idle/), [Revolution (wiki)](https://revolutionidle.wiki.gg/wiki/Revolution),
  [Beginner's guide](https://revolutionidle.com/guide/getting-started), [Tips & tricks](https://revolutionidle.com/guide/tips-tricks),
  [Ascend/Prestige/Promote (Game Rant)](https://gamerant.com/revolution-idle-ascension-prestige-promotion-guide/),
  [Joybit review](https://joybit.co.uk/revolution-idle/), [Vaporlens summary](https://vaporlens.app/app/2763740/revolution_idle)
- Zero IDLE: [Steam](https://store.steampowered.com/app/1236240/Zero_IDLE/), [Kongregate](https://www.kongregate.com/en/games/zeroworldwide/zero-idle),
  [Kongregate comments](https://www.kongregate.com/games/zeroworldwide/zero-idle/comments?pdis=qQQ-e&srid=11869733)
