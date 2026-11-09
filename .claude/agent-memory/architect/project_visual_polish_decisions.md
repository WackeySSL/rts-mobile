---
name: project-visual-polish-decisions
description: Visual polish plan (P200, 2026-11-09) for art-director's eight Figma proposals, ADR 0034 (SKADET shows the intact picture, accepted) and ADR 0035 (fog tint, map edge, world grade, team pad/ring; proposed); rows P200-P219
metadata:
  type: project
---

- P200 (2026-11-09, base b6bfe95, branch claude/plan-visual-polish): `docs/plans/2026-11-09-visual-polish.md`; rows P200-P219 (+P200b lead, P212b split); lanes A/A2/A3/A4 (art-director), V1-V4 + G (touch-ux-dev), H (qa); critical path P213 -> P214 -> P215 -> P216 -> P219. Phase 5 by kind, no ROADMAP box, nothing waits for Phase 4's gate.
- ADR 0034 ACCEPTED 2026-11-09 (Michael "A" via lead): buildings drop the `dmg1` (SKADET) picture; stage 1 shows the body; `picture(sheet,1)` = 0; DAMAGE_PARTS [dmg2] in view and generator; sheets keep two `cuts` (index stage-1, first 0) because `picture(sheet,2)` needs cuts.size() >= 2; dmg2 byte-identical (damage_prims(2) uses only dmg2's moves); emitter_quiet 1 -> 2/0; ~100 page rows freed (16 frames, 149 KB SVG).
- ADR 0035 PROPOSED: fog texel colour `fog_rgb` (lum <= 40), alphas and one-tile vision edge unchanged; `MapEdge` z 4 mask (+1 call); `WorldGrade` CanvasModulate (channels >= 0.90) + gradient CanvasLayer below Hud (+1 call); pad in key triad in unit shadow frames (baked per player); ring = team outer band + white inner band, baked once per match (own rings only -> one texture); no additive (ADR 0029 §6 kept); forecast 16 -> 18, worst ~26; `data/look_settings.tres` written whole once.
- Questions: Q1 locked card (A keep ADR 0032 sash, rec), Q2 fog blue-grey (B rec), Q3 page fallback SHADOW_SCALE 0.75 (A rec) vs separate pad sprite.
- Pitfall: any merge under `data/**` starts balance.yml (paths filter): view-only data files cost a balance run; write them in one row.
- Pitfall: a board proposal's file names can be wrong (cards are ItemTile.gd, not BuildButton.gd); its mechanism (additive, StyleBoxFlat gradient, modulate-tinted ring) can break an ADR or a renderer limit: keep the look, change the mechanism, say so.
- Pitfall: cross page was 3550/3584; any shadow-canvas growth needs a page measurement first; UnitLayer.gd is at 1000 lines (gdlint), HealthBarLayer draws rects only (ticks as one draw_multiline after rects).
