---
name: project-treadline-restyle-decisions
description: ADR 0049 (proposed 2026-11-24, P600): Treadline restyle toward Michael's Figma, factions Nordværn/Helix, rows P601-P621; Figma art = style reference only
metadata:
  type: project
---
# Treadline restyle (ADR 0049, PROPOSED 2026-11-24)

- P600 on `claude/p600-treadline-plan` (base 52b2649e): ADR 0049 + `docs/plans/2026-11-24-treadline-restyle.md`, rows P601 (prototype, other lane) to P621 (pipeline ADR 0050 after P601). Acceptance row P603; Figma read-out P602 (art-director, can run now).
- Decided in the proposal: corner HUD geometry kept, file's look via theme (Q1 A rec); no Move/Attack/Guard/Patrol/Train/radio line/objectives panel in skirmish; loading stays a still card; internal ids fossil/renew stay; restyle changes no HudCorners geometry before guide v2's P595; guide card look = theme values only after P592 (never a CoachMark edit).
- Figma raster fills (units, buildings, terrain, backdrops) are a style reference only: never imported, traced, measured to copy; screenshots in scratchpad only; get_design_context code and asset URLs never used.
- 8 questions: 1 layout A, 2 rename Helix (B: Facet/Lattice), 3 keep unit names A, 4 keep energy lore A, 5 Helix blue accent + triad 3 A, 6 mono face only if file uses one, 7 clock+count in pill A, 8 free TM searches now.
- Pitfall: the title has been Treadline since ADR 0006; a "rename" brief may only be the factions. Check ADR 0006 / MainMenuText before planning a title row.
- Pitfall: `UnitDef.display_name` -> `World.type_names` is in TYPE_ARRAYS and so in `defs_hash`: renaming a unit moves the defs hash (goldens, resume files). Faction display names are not hashed. Row P606 (conditional) drops names from the hash.
- Pitfall: "Helix" is a C&C Generals: Zero Hour unit (China transport helicopter); screen every faction/unit name a brief or a design file brings against C&C/RA/Generals/TS/StarCraft names.
- Pitfall: this architect session had no ToolSearch/Figma MCP tools; the brief's read-out was used and a read-out row (P602) added. Say so in the ADR, never invent file values.
- Pitfall: a producer tap selects the building and does NOT open the drawer (HOW_TO_PLAY build-menu-select-producer); battle-screen HOW_TO_PLAY ids start `the-screen-in-battle-`.
