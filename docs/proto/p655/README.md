# P655: detailed Ironward heavy_tank, a quality probe (prototype only, never merged)

Question (Michael, 2026-11-26, "step by step: terrain plus one detailed tank"): does one tank, modelled
with real detail and pre-rendered at today's density, reach the look of the Figma card "K-7 Bastion"? If yes, the
full roster may go 3D; if not, we stay SVG.

Everything here is ours. The mesh is built from code only (`tools/prerender/DetailTank.gd`, about 1,200 lines
after gdformat, a plane-clipped solid builder with bevels, cylinders, domes and tori). The material is one
procedural shader (`tools/prerender/detail.gdshader`). No sculpt import, no asset pack, no web texture, no AI
generator. The Figma card was looked at for material, proportion and colour only, nothing traced, and no Figma
pixels are committed (the three-way PNGs with the card are in the scratchpad only).

## What the mesh has

Same footprint, silhouette proportions and turret pivot as `heavy_tank` (hull canvas 166x104, turret 214x118,
turret mount 25.1 art px up). 42,032 triangles (hull 35,772, turret 6,260). Rivet domes, hatches with hinges and
handles, a commander cupola with 8 vision blocks and a machine gun, driver and radio hatches, 74 track links per
side with cleats and a guide tooth, 6 dual road wheels with hubs and bolts, sprockets with 11 teeth, idlers,
return rollers, front mudguards, 4 hinged and bolted skirt plates per side, tow eyes, tow cable loops, spare
track links, a shovel, jerry cans, louvred engine deck with a fan hatch, exhausts with heat shields, a rear stowage
cage with a tarp roll, smoke dischargers, lamp posts (the tank's horns), a gun with mantlet, sleeve, bore
evacuator, clamps and a slotted muzzle brake, panel seams, bevelled edges everywhere.

Weathering is in the shader, from model-space position, normal and a bevel flag in the vertex colour: edge wear
(bare metal at bevels, chipped paint on team panels), dust on up-facing faces and a dust gradient towards the
ground, mud on the running gear, vertical rain streaks, soot at the exhausts, per-plate tint.

Team colour (ADR 0050 amendment): the turret shell and the 8 skirt plates are the magenta sentinel; the body is
neutral gunmetal and steel. P653's `recolour2` shows them as Signal `#E8681F` and Kobolt `#3F6FE0`.

## Files

- `compare3_z1_no_figma.png`, `compare3_z2_no_figma.png`: today's SVG L2 | P653 | P655, 960x720 (the real
  three-way with the Figma card as 4th column is in the scratchpad, `threeway_z1.png`, `threeway_z2.png`).
- `scene_z1.png`, `scene_z2.png`: P653's terrain patch and factory with a Signal and a Kobolt tank facing each
  other, and a second pair side by side, 1280x720 at zoom 1 and 2.
- `mirror_pair_z2.png`: Signal and Kobolt tank side by side, grass and sand, zoom 2.
- `contact_sheet_16dir.png`: 16 directions, Signal rows 1-2, Kobolt rows 3-4, zoom 2.
- `readability_32px_grey.png`: 32 px on the long side (scaled with today's heavy_tank as the 32 px reference),
  greyscale, x6. Top row direction 2, bottom row direction 9. Columns: today's heavy_tank, P655 heavy_tank,
  light_tank, artillery, harvester, bunk wagon, shot truck.
- `ref_2x_not_shippable.png`, `scene_z2_2xdata_not_shippable.png`, `detail_2xdata_x4.png`: 2x-density renders,
  reference only, NOT SHIPPABLE (about 4x the texels, see numbers).
- `tools/`: `build655.py` (compose), `recolour_test655.py`, `numbers655.py`, `numbers.json`,
  `recolour_numbers.json`. The Godot side is `tools/prerender/DetailTank.gd`, `detail.gdshader`, `bake_detail.gd`.
  Shadows are P653's (the footprint and silhouette are the same). The post-process is P653's `pipeline.py`.

## Numbers (this container, 4-core llvmpipe, one-off, not a game timing run)

| | |
|---|---|
| Triangles | 42,032 (hull 35,772, turret 6,260); P653 mesh was a few thousand |
| Mesh build | 0.32 s for both parts |
| Render | 32 frames (hull and turret, 16 directions) at 8 texels per art px in 20.7 s, 0.65 s a frame |
| Post-process | 4.5 s (1x), 6.3 s (2x) |
| Atlas at 1x (tight boxes, hull+turret+shadow) | 3.41 MB (today 3.41, P653 3.36) |
| Atlas at 2x (not shippable) | 13.5 MB per tank, about 350 MB for the roster, 7 pages |
| PNG at 1x | 432 KB for 32 hull and turret frames (mean 13.5 KB, max 19.5 KB), plus shadow frames of a few KB each (P653's whole 48-frame set was 444 KB) |
| PNG at 2x | 1,392 KB (mean 43.5 KB, max 64 KB) |

Recolour (P653's `recolour2` against a full re-render with the team material set to the target; directions 3
and 9, Signal and Kobolt, hull and turret):

| Density | Team px | Mean error | Worst p99 | Max | px over 12/255 | px over 24/255 | Magenta fringe px | Clipped sentinel px |
|---|---|---|---|---|---|---|---|---|
| 1x | 8,622 | 2.5 | 9 | 32 | 6 | 2 | 0 | 0 |
| 2x | 31,957 | 2.5 | 9 | 33 | 24 | 7 | 1 | 0 |

That is better than P653's 3.1 mean at 1x. The weathering on the paint only darkens and thins it, so the hue key
holds. The remaining errors are specular highlights.

## Verdict (honest)

**It gets close at zoom 2 and does not get there at zoom 1. It does not reach the Figma card.**

At zoom 2 (the tank is 166 px wide) the P655 tank is clearly the same family as the card: dark gunmetal body, big
team-coloured turret, a team band on the skirts, a visible row of road wheels under it, a gun with a muzzle brake,
hatches, vision blocks and stowage on the roof. It is a big step from today's flat SVG and from P653's
re-skinned blockout, mostly because of the new palette contrast (neutral body, team panels) and the real shape of
the turret and gun, not because of the fine detail.

At zoom 1 (83 px) it is a dark grey tank with an orange or blue turret. The card is shown at about 330 px; we
draw the tank at a quarter of that. Rivets are 0.7 texel across, a track link is 3 px, the bevel is 1.4 texel, the
vision blocks and hinges are one or two pixels. They survive only as a faint noise and a slightly busier
silhouette. The card gets its look from fine facets and sculpted cast surfaces at 4x our pixel count; a
1x pre-render cannot carry that. Mud, dust and streaks read as a slightly warmer, patchier body, not as dirt.

**What is lost at 1x:** everything below about 2 art px: rivets, seams, hinges, the link pattern, edge wear, streaks.
What is kept: value structure, the team panels, the wheel row, the gun, the turret form, the shadow.

**Readability at 32 px greyscale:** still a tracked tank with a turret and a gun (`readability_32px_grey.png`),
distinct from the light tank, artillery, harvester and the two trucks. The body is darker than today's, so the hull
has less top-to-side contrast; the turret and the gun carry the identification.

**Density is still the blocker for the card's look.** 2x would show the detail (`ref_2x_not_shippable.png`) but costs
about 350 MB for the roster.

### Estimated effort per unit for the full roster

This tank took one long session (mesh builder and shader about 1,200 lines, 10 renders to tune). The helpers and
the shader now exist, so a new vehicle (light tank, artillery, harvester, trucks) is about the size of one P638-P647
row each, i.e. a half to one working day of agent time for model plus tuning plus the sheet and gallery checks.
Buildings are of the same size per building with damage stages (2 to 3 poses) as extra. Infantry (8 directions,
walk and idle poses) are harder: about two rows each. A full roster of 22 units and 26 buildings is therefore
roughly 35 to 50 rows; the bake itself is not the cost.

### Recommendation

Unless Michael accepts that the visible gain is mainly the neutral-body-plus-team-panel palette and a better
turret and gun (both of which a hand-drawn SVG model change could also deliver cheaply), stay SVG for units. If he
wants the 3D look, take it only for terrain and buildings first, where P653 already showed the larger gain, and
keep units on the new palette as SVG.

## Notes

- Lint: `gdlint` reports class-definition order and a max-file-lines error for `DetailTank.gd`; it is prototype
  tooling on a branch that is never merged, so it was not cleaned up. No `verify.sh`, no balance or perf runs.
- Apt: nothing installed in this session (Mesa lavapipe `mesa-vulkan-drivers 25.2.8` was already there from P653).
- The detail shader, mesh and bake are deterministic in this container only (see P653's determinism note).
