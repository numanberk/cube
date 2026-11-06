# Cube Idle — design

## Core loop
1. **Tap** "Turn the cube" → moves (1 per tap, boosted by upgrades).
2. Every **15 moves** (reduced by method upgrades) completes a **solve** → +1 Solve.
3. Spend Solves on **helpers** that make moves automatically.
4. Spend Solves on **upgrades** that multiply taps, helpers, or cut moves per solve.
5. Close the game; helpers keep working (offline progress, max 8 h).

## Numbers
| Thing | Rule |
|---|---|
| Moves per solve | `15 × product(solve_moves_mult)`, min 1 |
| Helper cost | `ceil(base_cost × 1.15^owned)` |
| Helper unlock | Visible once lifetime Solves ≥ 50% of base cost (or `unlock_at`) |
| Upgrade unlock | Visible once lifetime Solves ≥ 50% of cost, and its `requires` are met |
| Offline | Seconds away × moves/sec, capped at 8 h (12–16 h with Practice perks) |

## Helpers (current, task 5.8)
| Helper | Base cost | Moves/s |
|---|---|---|
| Cubing Friend | 5 | 0.5 |
| Cubing Club | 60 | 3 |
| Solving Robot | 12K | 33 |
| Local Competition | 100K | 180 |
| Cube Factory | 1.7M | 1K |
| Speedcubing Lab | 34M | 6K |
| Pro Team | 450M | 38K |
| Cubing Federation | 5B | 240K |
| Cube Museum | 240B | 1.6M |
| AI Solver | 6.7T | 11M |
| Orbital Cube Station | 100T | 75M |
| Quantum Solver | 2.1Qa | 550M |

## Planned systems
The build order and pacing targets are in `docs/PLAN.md`. Numbers above are the current (v1) game.

- **Puzzles:** 2×2 → 3×3 → 4×4 → 5×5 → 7×7 → Megaminx. Each pays more Solves per solve and needs more moves.
- **Methods:** Beginner → CFOP → Roux → ZZ → "God's Number" (20 moves).
- **Prestige — World Championship:** reset Solves/helpers for **Trophies** (permanent multiplier).
- **Active play:** occasional "Scramble Challenge" event for a timed boost.
- **Achievements:** first solve, sub-10 personal best, 1M moves, etc.
- **3D cube:** replace `CubeView` with a real 3D cube that animates face turns.
