# Changelog

Newest first. Every session adds an entry: what changed, what's unfinished, notes for the next session.

## 2026-11-02 — Review and new plan (no code changes)
- Owner said the game looks bad and has no progression. Took screenshots (xvfb + opengl3
  works in the cloud container) and simulated the economy with a greedy bot.
- Findings: all content is gone by ~53 min, the start is slow (first Friend = 75 taps), nothing
  visual changes as you progress, and the UI is the default Godot theme with text-only buttons.
- Rewrote `docs/ROADMAP.md`: added pacing targets and new Milestones 2–8 (tools → visual overhaul →
  economy rework with puzzle tiers → 3D cube → prestige → active play → release).
  The old Milestone 2–5 items are folded into the new ones.
- **Next:** Milestone 2 (screenshot script + sim bot driving the real `GameState`), then Milestone 3.

## 2026-11-02 — Project setup
- Created the Godot 4.7 project: one main screen, `Game` autoload with all rules,
  content as data, autosave + offline progress, number formatting.
- Added headless tests (`tools/run_tests.sh`): 124 checks passing on Godot 4.7.2.
- Added CLAUDE.md, DESIGN, ROADMAP, CI workflow.
- **Next:** start Milestone 2 in `docs/ROADMAP.md`. Balance is a first guess; expect tuning.
