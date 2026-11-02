# Roadmap

The checklist version of `docs/PLAN.md` (read that for details).
Do tasks in order, **one per session**, unless the owner says otherwise.
Only tick a task when its "Done when" is true and `tools/run_tests.sh` prints `All good.`

## Phase 0 — Setup ✅
- [x] 0.1 Tap → moves → solves; 6 helpers; 7 upgrades
- [x] 0.2 Autosave, offline progress (8 h cap), headless tests, CI

## Phase 1 — Game feel
- [ ] 1.1 Floating "+N Solves" text — *Done when:* each solve shows rising, fading text; no more than ~20 on screen.
- [ ] 1.2 Sound (CC0 assets, `Audio` autoload, `assets/CREDITS.md`) — *Done when:* tap, solve and buy make sounds.
- [ ] 1.3 Buy ×1 / ×10 / Max — *Done when:* the toggle works and bulk cost math is tested.
- [ ] 1.4 Settings tab (volume, reset with confirmation) — *Done when:* settings persist across restarts.
- [ ] 1.5 Space/Enter taps from anywhere — *Done when:* an input action works regardless of focus, with no hold-repeat.

## Phase 2 — Puzzles
- [ ] 2.1 Puzzle data (2×2 → Megaminx) — *Done when:* content tests cover puzzles.
- [ ] 2.2 Active puzzle + save v2 migration — *Done when:* a v1 save loads into v2 in a test. *(Needs owner decision D1 in PLAN §6.)*
- [ ] 2.3 Puzzle picker UI — *Done when:* the player can unlock and switch puzzles.
- [ ] 2.4 CubeView draws N×N and Megaminx — *Done when:* each puzzle looks distinct.

## Phase 3 — Depth
- [ ] 3.1 Method chain upgrades
- [ ] 3.2 Helper tier upgrades at 10/25/50/100 (generated from data)
- [ ] 3.3 Synergy upgrades
- [ ] 3.4 Two late-game helpers (~40 upgrades total)

## Phase 4 — Achievements & stats
- [ ] 4.1 Achievements as data, +1% each, toast pop-up, save v3
- [ ] 4.2 Stats tab

## Phase 5 — Prestige
- [ ] 5.1 Trophy formula + Compete confirmation
- [ ] 5.2 Reset logic, save v4
- [ ] 5.3 Trophy shop

## Phase 6 — Active play
- [ ] 6.1 Golden Scramble
- [ ] 6.2 Scramble Challenge mini-game

## Phase 7 — Look & polish
- [ ] 7.1 3D cube with animated face turns
- [ ] 7.2 Theme resource + font
- [ ] 7.3 Juice (+ "Reduce motion" setting)
- [ ] 7.4 Layout pass at 720p / 1080p / 1440p

## Phase 8 — Balance
- [ ] 8.1 Headless simulator → `docs/BALANCE.md`
- [ ] 8.2 Tune to the targets in PLAN Phase 8

## Phase 9 — Release
- [ ] 9.1 Save safety (temp + rename, backup, corrupt-save recovery)
- [ ] 9.2 Windows export preset + icon + version label
- [ ] 9.3 itch.io page and upload
- [ ] 9.4 Steam (optional)
- [ ] 9.5 Launch checklist
