---
name: project-phase0-decisions
description: Phase 0 decisions from ADR 0002 (2026-10-10) - DetRng/CommandQueue autoload naming, DetRandom, game/core, dev button size, docs-alignment issue blocking Phase 2
metadata:
  type: project
---

- Autoloads `DetRng`/`CommandQueue` live in `game/core/` with no class_name; sim RNG class is `DetRandom`. **Why:** autoload name hides any same class_name (silent parse error). **How to apply:** never propose `class_name DetRng`; game/sim never references autoloads.
- CLAUDE.md, rts-sim-conventions, ai-dev.md and ROADMAP Phase 2 still say `DetRng`/lack game/core; an issue for Michael's approval blocks the Phase 2 plan. Check it is closed before planning Phase 2.
- Dev UI buttons >= 120x120 base px until Phase 1 UiScale (worst case 0.42 dp per base px on a landscape phone browser). See [[pitfalls-godot-472]].
- WP1-style config/view/UI work goes to the lead or touch-ux-dev, never gameplay-dev (its agent file limits it to game/sim, data, tests/sim).
