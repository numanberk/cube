# Changelog

Newest first. Every session adds an entry: what changed, what's unfinished, notes for the next session.

## 2026-11-02 — Development plan
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
