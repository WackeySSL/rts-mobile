---
name: project-visual-polish-decisions
description: Visual polish plan (P200, 2026-11-09) for art-director's eight Figma proposals, ADR 0034 (SKADET shows the intact picture, accepted) and ADR 0035 (fog tint, map edge, world grade, team pad/ring; proposed); rows P200-P219
metadata:
  type: project
---

- P200 (2026-11-09, base b6bfe95, branch claude/plan-visual-polish): `docs/plans/2026-11-09-visual-polish.md`; rows P200-P219 (+P200b lead, P212b split); lanes A/A2/A3/A4 (art-director), V1-V4 + G (touch-ux-dev), H (qa); critical path P213 -> P214 -> P215 -> P216 -> P219. Phase 5 by kind, no ROADMAP box, nothing waits for Phase 4's gate.
- ADR 0034 ACCEPTED 2026-11-09 (Michael "A" via lead): buildings drop the `dmg1` (SKADET) picture; stage 1 shows the body; `picture(sheet,1)` = 0; sheets keep two `cuts` (index stage-1, first 0); dmg2 byte-identical (damage_prims(2) uses only dmg2's moves); emitter_quiet 1 -> 2/0; ~100 page rows freed (16 frames, 149 KB SVG).
- Docs-lens fix 1 (2026-11-09): the part lists (BuildingDamage.PARTS, IsoAtlas.DAMAGE_PARTS, ArtModel.DAMAGE_PARTS) STAY [dmg1, dmg2] as stage-to-part tables (every reader indexes by stage: PARTS[k-1], DAMAGE_PARTS[stage-1], find(part)+1, damage_parts' i+1); generator's damage_parts() lists only dmg2; P201 merges after P202; P216 owns PerfBases CALLS_FORECAST/STRIKE/WORST 16/17/22 -> 18/19/25 + test_perf_bases card line; Hud CanvasLayer 1 -> 2, WorldGrade layer 1 (pinned on both scenes); CanvasModulate tints FogLayer/MapEdge but not the clear colour.
- Pitfall: never shrink a list that code indexes by stage/position (`[dmg2]` would make KRITISK stage 1); keep the slot and drop the content. Pitfall: draw-call forecasts are also pinned in code (game/ui/PerfBases.gd + tests/ui/test_perf_bases.gd): a forecast change needs an owning row. Pitfall: "a layer below the Hud" is layer 0 (root canvas) when Hud is at the default 1; name explicit layer numbers.
- ADR 0035 PROPOSED: fog texel colour `fog_rgb` (lum <= 40), alphas and one-tile vision edge unchanged; `MapEdge` z 4 mask (+1 call); `WorldGrade` CanvasModulate (channels >= 0.90) + gradient CanvasLayer below Hud (+1 call); pad in key triad in unit shadow frames (baked per player); ring = team outer band + white inner band, baked once per match (own rings only -> one texture); no additive (ADR 0029 §6 kept); forecast 16 -> 18, worst ~26; `data/look_settings.tres` written whole once.
- Questions: Q1 locked card (A keep ADR 0032 sash, rec), Q2 fog blue-grey (B rec), Q3 page fallback SHADOW_SCALE 0.75 (A rec) vs separate pad sprite.
- Pitfall: any merge under `data/**` starts balance.yml (paths filter): view-only data files cost a balance run; write them in one row.
- Pitfall: a board proposal's file names can be wrong (cards are ItemTile.gd, not BuildButton.gd); its mechanism (additive, StyleBoxFlat gradient, modulate-tinted ring) can break an ADR or a renderer limit: keep the look, change the mechanism, say so.
- Pitfall: cross page was 3550/3584; any shadow-canvas growth needs a page measurement first; UnitLayer.gd is at 1000 lines (gdlint), HealthBarLayer draws rects only (ticks as one draw_multiline after rects).
