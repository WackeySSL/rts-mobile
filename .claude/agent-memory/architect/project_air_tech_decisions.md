---
name: project-air-tech-decisions
description: ADR 0036 (proposed 2026-11-09): air layer, anti-air, transports, drone squads, engineering centre upgrades, space centre reveal; plan rows P230-P268
metadata:
  type: project
---

- ADR 0036 PROPOSED 2026-11-09 (commit e01ee4c on `claude/design-air-and-tech`, base b6bfe95; plan `docs/plans/2026-11-09-air-and-tech.md`, rows P230-P256 = 1.1, P262-P268 = 1.2, P220-P229 buffer for polish, P257-P261/P269 reserved). Built after the Phase 4 gate; rec. update 1.1 then 1.2 (Q2 B).
- Key design: AIR = 4th move class with an open move_cost plane (kernels change only MOVE_CLASSES 3->4); `type_layer_bit` 1 ground / 2 air / 4 low air, `weapon_targets` mask (rockets 7, rifles+Redoubt 5, AA 6, fighters 2); SEPARATION same-layer; no 5th armour class; TABS 5 (FLIGHT 3, RESEARCH 4; label never "Air"); one layout row per release (STATE_FORMAT 6, then 7), exception 22.
- Reveal = strike kind 3; `FogGrid.reveal(p, ±1)` whole block in GDScript `Reveal.run` (REMOVE mark, after FogUpdate.begin so flips reach the dirty list); `reveal_until` hashed, `reveal_stamped` derived, prepare() re-stamps; all readers incl. TARGETING kernel get it free.
- Air.run (ECONOMY): pads cap at QUEUE, home re-home, ammo in Combat.fire, return/reload (ready_tick reused on mobile rows), repair on pad for credits. Upgrades = queue-only research types + derived mod tables; `Combat.damage(base, pct, dealt, taken)` identical to the old formula at 100/100. Upgrades only for stats read in GDScript-only phases.
- Carriers: boarded squads LEAVE the row table (passenger table, `World.insert_row` with the same id on unload) so no kernel edit; Commands LOAD 5 / UNLOAD 6 / REPAIR 7 shared with the ground design (lead reconciles numbers). Drone squads = AIR + low_flying, not hoppers.
- Questions: 1 names (A first options), 2 when (B: 1.1 + 1.2 after launch), 3 sweep A 45 s / 3 min, 4 AI gets it A Normal+Hard, 5 research A bombs +25 % + hull -25 %.
- Pitfall: the lead's brief named ADR 0034 and P210, but the polish lane had taken ADR 0034-0035 and P200-P219 on an unmerged branch; always grep `git log --all` and the worktrees' docs/plans before using any number.
- Pitfall: the art page is full (3550/3584); y-sorted items must stay on one page (two textures interleaved break batches at every switch), so a page 2 may hold only unsorted layers (AirLayer, shadows, DecalLayer, fx). New buildings need ~900-1300 rows: probe row (P237) before any art row.
- Pitfall (legal): ADR 0023 §13 already refuses an "Air" sidebar tab (RA2); game-title collisions are easy to miss for common words (Daylight, Clear Sky, Atelier): screen against game titles too, not only units.
