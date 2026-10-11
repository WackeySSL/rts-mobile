---
name: project-phase2-decisions
description: Phase 2 plan decisions (ADRs 0007-0011, 2026-10-11) - World v1 SoA with stable compaction, Command v1, xoshiro128**, SHA-256 hash, flow fields only on blocked lines, perf budget and gate
metadata:
  type: project
---

Plan `docs/plans/2026-10-11-phase-2.md`, PRs P26-P52, ADRs 0007-0011 proposed until Michael answers 3 questions (gate headroom, 3-unit roster, skill edits).
**Why:** each decision below is backed by a headless spike or a Phase 1 lesson. **How to apply:** review Phase 2 PRs against these; change them only with a new ADR.
- ADR 0007: World v1 declares ALL Phase 2 arrays up front (phase modules in own files, one call line in Sim.step) so two gameplay-dev lanes don't collide. Removal = stable compaction at end of tick (no swap-remove); projectiles = fixed slots + free stack. Buildings will be rows of the same table.
- ADR 0007: Command v1 adds MOVE 2, ATTACK 3, STOP 4, payload; 10-19 reserved for Phase 3 economy, 20-29 match. ATTACK target must be visible. CommandQueue API unchanged; DetRng stays a stateless factory.
- ADR 0007: DetRandom = xoshiro128** with mul32 by 16-bit halves (no int64 wrap), seed masked to 31 bits, lowbias32 seeding, STREAM_SIM 1, STREAM_AI_BASE 100. Hash = SHA-256 (HashingContext) first 8 bytes, coverage test via get_property_list; checkpoint every 15 ticks; replay = var_to_bytes dict with defs_hash.
- ADR 0008: line check (supercover) on order and on tile change; flow field only when blocked, so open maps keep Phase 1 exact paths. Dijkstra sliced 1024 cells/tick, cache 8 slots with refcount + LRU. Separation grid 1 tile, targeting grid 4 tiles, sqrt-free push.
- ADR 0009: roster light tank, rifle squad (hitscan), rocket squad; counter-triangle test is the balance judge; homing projectiles; units fire in the tick they die (death only in phase 11).
- ADR 0010: fog = refcount grid per player, stamp only on tile change, player p updates on tick % 3 == p-1; RGBA8 ImageTexture, linear filter, explored alpha 140.
- ADR 0011: absolute z_index (map 0, rigs 1-4, bars 5, projectiles 6, effects 7, fog 8, markers 9); perf budget mean 4 ms / p95 8 ms on CI; phone gate via dev Perf arena card (seed 42, hash must equal CI's PERF hash).
