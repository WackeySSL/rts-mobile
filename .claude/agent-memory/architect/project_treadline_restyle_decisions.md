---
name: project-treadline-restyle-decisions
description: ADR 0049 ACCEPTED 2026-11-24 (Nordværn/Facet, corner HUD, names+lore kept) and ADR 0050 PROPOSED (SVG L2 units, Figma PNG 3x3 buildings, fixed colours + marker, zoom 2.0); rows P600-P649
metadata:
  type: project
---
# Treadline restyle (ADR 0049 ACCEPTED, ADR 0050 PROPOSED, 2026-11-24)

- P600 on `claude/p600-treadline-plan` (base 52b2649e): ADR 0049 + `docs/plans/2026-11-24-treadline-restyle.md`, rows P601 (prototype, other lane) to P621 (pipeline ADR 0050 after P601). Acceptance row P603; Figma read-out P602 (art-director, can run now).
- Decided in the proposal: corner HUD geometry kept, file's look via theme (Q1 A rec); no Move/Attack/Guard/Patrol/Train/radio line/objectives panel in skirmish; loading stays a still card; internal ids fossil/renew stay; restyle changes no HudCorners geometry before guide v2's P595; guide card look = theme values only after P592 (never a CoachMark edit).
- Figma raster fills (units, buildings, terrain, backdrops) are a style reference only: never imported, traced, measured to copy; screenshots in scratchpad only; get_design_context code and asset URLs never used.
- 8 questions: 1 layout A, 2 rename Helix (B: Facet/Lattice), 3 keep unit names A, 4 keep energy lore A, 5 Helix blue accent + triad 3 A, 6 mono face only if file uses one, 7 clock+count in pill A, 8 free TM searches now.
- Pitfall: the title has been Treadline since ADR 0006; a "rename" brief may only be the factions. Check ADR 0006 / MainMenuText before planning a title row.
- Pitfall: `UnitDef.display_name` -> `World.type_names` is in TYPE_ARRAYS and so in `defs_hash`: renaming a unit moves the defs hash (goldens, resume files). Faction display names are not hashed. Row P606 (conditional) drops names from the hash.
- Pitfall: "Helix" is a C&C Generals: Zero Hour unit (China transport helicopter); screen every faction/unit name a brief or a design file brings against C&C/RA/Generals/TS/StarCraft names.
- Pitfall: this architect session had no ToolSearch/Figma MCP tools; the brief's read-out was used and a read-out row (P602) added. Say so in the ADR, never invent file values.
- Pitfall: a producer tap selects the building and does NOT open the drawer (HOW_TO_PLAY build-menu-select-producer); battle-screen HOW_TO_PLAY ids start `the-screen-in-battle-`.
- ACCEPTED 2026-11-24 (P603 on the same branch, PR #642): Q1 A, Q2 Facet (Helix dropped: C&C Generals ZH unit), Q3 A names kept (P606 not run, moves to Phase 7), Q4 A lore kept, Q5 superseded by fixed faction colours + team marker, Q6 no mono unless file uses one, Q7 A clock/count in pill, Q8 Michael runs free TM searches. Notes in ADR 0006, 0023 (top), 0025 §13/§15.
- ADR 0050 PROPOSED (P621): units SVG via artgen detail L2 (+L3 bevels/contact), gradient metal sheen (ThorVG 4.7.2 probe: linear+radial render, stop-color hex swap works), PNG only for the 12 3x3 buildings made in Figma (drawn or Figma AI per ADR 0051, model kept as shadow/lift volume), one sentinel magenta key triad replaces the per-faction keys (Signal/Arktisk hexes collide with fixed orange), marker 2-6 % (TEAM_SHARE 2-12 % in transition), zoom 4th level 2.0 appended (softness accepted; sharp bake = ~193 MB, rejected). 5 questions. Art rows P630-P649 (P622/P623 belong to ADR 0051's lane).
- Pitfall: Basics `zoom` beat is ZOOM_LEVEL value 2 with equality (assumes index 2 = closest); a 4th level needs Kind 19 ZOOM_AT_LEAST first (P633 before P634). `data/input_settings.tres` is not negated in balance.yml.
- Pitfall: another lane took row numbers P622/P623 (ADR 0051, #643) while this plan used them; grep open PR branches for row numbers before numbering new rows.
- ADR 0050 answers 2026-11-24 ("ja til alle 4, men ... helhed i grafikken ... ikke tilfældigt"): Q2 zoom 2.0, Q3 own white / computer red with dark rim, Q4 sheen, Q5 style text = yes; Q1 (building route) OPEN until P637 compares artgen SVG / Figma vector / Figma AI Facet HQ in the same scene (round 2: Michael preferred artgen SVG). Default if Figma AI does not clearly win: all artgen SVG, PNG rows P635/P636 struck, P644/P645 become SVG batches. New §8: one coherent look; same-scene check (P629 headless composer + tests/art/test_same_scene.gd, bands in tools/artgen) gates every art route and batch. Status stays proposed; P621b accepts after the pick.
- Pitfall: "never rewrite an accepted ADR" also applies to one accepted minutes earlier on the same unmerged branch; add a dated note (done in ADR 0049 §7 for the art-row start rule).
