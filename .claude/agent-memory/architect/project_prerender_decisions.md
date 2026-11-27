---
name: project-prerender-decisions
description: ADR 0053 PROPOSED 2026-11-27 (P654): pre-rendered 3D terrain + buildings at 1x, SVG units for now, bake-time GPU recolour; plan docs/plans/2026-11-27-prerender.md rows P656a-P659
metadata:
  type: project
---
# Pre-render (ADR 0053 PROPOSED, 2026-11-27, P654)

- Branch `claude/p654-prerender-adr`, base 7648d987. Michael: "Trinvis: terræn + én detaljeret tank (Recommended)" (11-26), "3D til terræn + bygninger, SVG-enheder" and "Vi kan starte der og så kan tanks laves til 3D senere når jeg har set det?" (11-27, lead yes), "Ironward (Recommended)" (Nordværn renamed; ids unchanged; P657 renames old text).
- New ADR, not an 0050 amendment: it reverses 0050 answer 1 for two art classes, adds a toolchain, a renderer outside Stack and CLAUDE.md lines. Notes placed in ADR 0050 (top + end of §2); ADR 0023 §5 note waits for acceptance (P654b).
- Decided in the proposal: 1x only (sprites' density; 2x = ~350 MB, 7 pages); recolour = P653 `recolour2` as a canvas shader run ONCE per player at match start via SubViewport + readback into IsoAtlas's per-player slots (sorted world keeps no material, "in white"); GDScript twin `TeamRecolour.gd` = reference, composer, cards, fallback; dummy renderer leaves sentinel; CI-only render test under xvfb (shader vs twin <= 1/255).
- Bake: Godot 4.7.2 Forward+/lavapipe under xvfb in a pinned image (mesa 25.2.8-0ubuntu0.24.04.5 x5 pkgs, libllvm20, xvfb 21.1.12, numpy 2.5.3, Pillow 12.3.0); committed PNGs + manifest (sha256); CI never re-renders; other Mesa = explicit re-bake row. No non-linear post grade (it breaks the recolour); exposure only.
- Art = data: building 3D detail in `assets/art/models/<f>/<id>_detail.tres` (reserved), builders in tools/prerender (MIT); artgen still writes every sheet, png paths for ids in `tools/prerender/owned.tres`.
- Ground: GroundLayer/GroundAtlas (the brief's "TerrainLayer"), base + edge layer at scale 0.5, pure piece choice with a fixed cell hash, lip <= 36 texels only over cells blocked for every move class, <= 9 writes per changed cell, SVG fallback; roads decoration only (Q4).
- Rows: P654b accept; P656a/b tool, P656c/c2 kit, P656e same-scene ground bands (new `same_scene_ground.tres`; `same_scene.tres` stays frozen), P656d wiring, P656f roads; P658-P658f SVG unit restyle (gate first: frozen bands), P643 after P658d/f; P644a recolour, P644a2 atlas PNG path, P644b/c Ironward 3x3; P659 Michael's look check (buildings kept? 3D units?); P645a-P647b after P659. ROADMAP Phase 5 row "Pre-rendered terrain kit". 7 questions.
- Pitfall: "1x" is ambiguous for the ground: today's diamonds import at svg/scale 0.5 (64x32 texels, 1 texel/world px), half the sprites' density; P653's "1x" kit is 128x64 per diamond (4x today's ground texels).
- Pitfall: CLAUDE.md Legal allows only SVG (hand/artgen), CC0/CC-BY, Figma vector exports and brand files; any PNG from our own renderer needs Michael's yes and a lead edit of CLAUDE.md before art merges.
- Pitfall: a CPU per-pixel recolour in GDScript of ~3 M keyed building texels per player is seconds on a phone; building texels measured from sheet canvases: 7.95 M (both factions, untrimmed, dmg2 at 0.75^2), 6.0 M keyed, SVG 1.38 MB.
