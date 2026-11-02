# Changelog

Newest first. Every session adds an entry: what changed, what's unfinished, notes for the next session.

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
