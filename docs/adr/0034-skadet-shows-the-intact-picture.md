# ADR 0034: SKADET shows the intact picture (the buildings' middle damage picture is dropped)

**In short, for Michael:** a building under two thirds of its health no longer gets its own
"damaged" picture. It keeps looking whole, with the smoke and the fire of that stage on top, as
today. Under a third it still shows its broken KRITISK picture. Nothing else about damage changes.

Status: **accepted 2026-11-09** (Michael's answer "A", relayed by the lead on 2026-11-09).
Written by the architect in P200 (`docs/plans/2026-11-09-visual-polish.md`) on `main` at
b6bfe95; revised the same day after the docs lens (stage indexing kept, §3). Amends ADR 0029 §3,
§4, §5 and §10 and ADR 0028 §3 for the building patch `dmg1`; supersedes nothing else. The dated
notes that point here are drafted in the plan's section "ADR 0029 note (draft)" and are placed by
the lead's acceptance row P200b.

## Context
- ADR 0029 (accepted 2026-11-04) gives a building three stages, INTAKT, SKADET and KRITISK, at the
  strict lines 67 % and 34 % (`LifeSettings.building_stage_percent`), with a picture for each: the
  body, the patch `dmg1` over the trimmed body, the patch `dmg2` over the trimmed body. Smoke, fire,
  sparks and gas jets per stage are particles in `AirFx` (ADR 0029 §6), never in a sprite.
- Michael, 2026-11-09, on the phone: SKADET's picture (the same shape with a darker roof, "a bit of
  black") is not worth it, because the smoke and fire of that stage already say it. Answer "A": drop
  the picture, keep everything else.
- The cost of `dmg1`: 16 generated frames (8 buildings x 2 factions, one view each, no direction),
  149 KB of SVG, baked at `IsoAtlas.DAMAGE_SCALE` 0.75 into the sorted world's one page. Their area
  at that scale is about 381 000 px², 93 rows of the 4096 px page if packed without waste, so about
  100 or more rows with the shelves' waste. The cross-faction page is 3550 of its 3584 budget
  (`tests/view/test_iso_atlas_budget.gd`, `TODAY_CROSS`), so these rows are most of the room the
  page has.
- The view already copes with a sheet without `dmg1`: `BuildingDamage.picture(sheet, stage)` shows
  the highest stage at or under `stage` whose patch exists, so a sheet with `dmg2` alone shows the
  body at SKADET. The generator already allows `dmg2` alone (ADR 0029 §5, "Refusals kept").

## Decision
1. **SKADET draws the INTAKT picture.** At stage 1 a building shows its body untrimmed, exactly as
   at stage 0. KRITISK keeps `dmg2` over the trimmed body (ADR 0029 §3 and §12 unchanged).
2. **Unchanged:** the stage function `BuildingDamage.stage_of`, the thresholds 67/34 and their data,
   the stage a ghost remembers (`GhostMemoryLayer` shows the picture of the remembered stage, so
   SKADET's ghost is the intact one), SKADET's particles (ADR 0029 §6: the burning points by
   `LifeClock.pick`, `dmg_gas` jets, `dmg_spark`, thin grey smoke, the glow pass), KRITISK's
   picture, particles and `Anim` rule, the collapse (§8), the hit feedback (§7), the craters, the
   vehicles' stages (`vehicle_stage_percent` [50, 25], `scar1`, `scar2`, `loose`: this ADR is about
   buildings only) and reduced effects.
3. **Rule in the view, not only in the art; indexing stays by stage.**
   - `BuildingDamage.picture(sheet, stage)` returns 0 for stage 0 and stage 1 whatever the sheet
     holds, and 2 for stage 2 when the sheet has `dmg2` and two `cuts` (as today).
   - The three part lists, `BuildingDamage.PARTS`, `IsoAtlas.DAMAGE_PARTS` and the generator's
     `ArtModel.DAMAGE_PARTS`, **stay `[dmg1, dmg2]`**: they are stage-to-part tables, index stage
     - 1, and every reader indexes them by stage (`BuildingDamage` `PARTS[k - 1]`, `ArtModel`
     `DAMAGE_PARTS[stage - 1]`, `ArtGen` `DAMAGE_PARTS.find(part) + 1`, `ArtModel.damage_parts`'s
     `i + 1`). Dropping `dmg1` from them would turn KRITISK into stage 1 and break `dmg2`. `dmg1`
     stays the name of stage 1, a stage with no picture; `IsoSheetDef.origin`'s literal and
     `ArtMove`'s parse keep it too, and `tests/view/test_damage_parts_pin.gd` keeps its three
     equal lists of two.
   - A sheet's `cuts` keeps its two entries, index stage - 1 (the first is 0), so
     `picture(sheet, 2)` and the seam rule read them as today.
   - `BuildingDamage.cost(from, to, ...)` is called with picture stages (`BuildingLayer`'s
     `stage_want`), so an hp change from INTAKT to SKADET is no picture change and writes nothing;
     `cost` itself is unchanged.
4. **The art.** The generator writes no `dmg1` frame and no `dmg1` part in a sheet
   (`ArtModel.damage_parts()` lists only `dmg2`, the stage of a part still
   `DAMAGE_PARTS.find(part) + 1`), and refuses a model with a `dmg1` pose (it replaces the refusal
   "`dmg1` without `dmg2`"). Every committed
   `<id>_dmg2.svg` stays byte-identical: stage 2's picture is made from `dmg2`'s own moves and the
   primitives with `damage <= 2`, never from `dmg1`'s moves (`ArtModel.damage_prims`), so the art
   row removes the `dmg1` pose lines and keeps the `damage=1` primitives (they still appear at
   stage 2). The 16 `_dmg1.svg` files and their imports go.
5. **Damage points and ambient emitters.** The points stay one list per building, 2 to 4 of them
   (ADR 0029 §5). "Ink under every point at both stages" now means: inside a primitive of the
   intact picture (what SKADET shows) and inside one drawn at stage 2. An ambient emitter's
   `emitter_quiet` is the first stage whose SHOWN picture moves or hides its group, so a value of 1
   becomes 2 or 0 (the generator recomputes it; the four known cases are in ADR 0029 §5).
6. **What it saves:** the 16 frames, about 100 page rows on the cross-faction page and on each
   mirror page (a mirror bakes the patches once per player), about 16 KB of texture per row
   (4096 px x 4 B), so about 1.5 to 2 MB of GPU memory per match and the same in RAM while the
   page is baked, 16 fewer SVG rasterisations at match start (8 per player of a cross-faction
   match), and 149 KB of SVG in the pack. The art row measures the exact rows with
   `IsoAtlas.planned_page` and moves the `TODAY_*` pins.

## Consequences
- ADR 0029 §4's table keeps its SKADET column for the particles ("Light: one fire, a weak glow";
  "Smoke: grey and thin") only; its rows "Silhouette", "Surfaces" and "Team colour" for SKADET
  describe nothing that is drawn. §4's "Each stage changes the shape more than the one before" now
  holds between INTAKT and KRITISK. "Depth on the body" keeps only KRITISK's rule. The test of
  SKADET's team share (about 70 %) goes.
- The freed page rows are the room the polish rows P203 and P204 (contact shadows, team pads) need;
  the page budget (3584) and the one-page rule stand.
- The KRITISK picture now follows an intact one; the jump at 34 % is larger. Michael judged it on
  the phone; the particles at SKADET carry the warning.
- `HOW_TO_PLAY.md`'s row "A building is badly damaged" and the GDD's damage table (the "Damaged"
  row) change with the rows below.
- Writes: an hp change between INTAKT and SKADET is no picture change and writes nothing; INTAKT
  or SKADET to KRITISK is the picture change 0 -> 2 and costs what `BuildingDamage.cost(0, 2, ...)`
  costs today (§3: `cost` takes picture stages), so the largest stage cost and
  `damage_building_writes` (at least 6) are unchanged.

## Alternatives considered
- **Keep the frames and only stop showing them:** saves nothing on the phone; rejected (Michael's
  reason for the change is that it is not worth its cost).
- **A cheaper SKADET picture** (a smaller patch, roof only): still a frame per building on the page;
  rejected for the same reason.
- **Drop the stage itself:** the particles of SKADET would go too; not what Michael asked.
- **Drop `dmg1` from the part lists:** every reader indexes them by stage, so KRITISK would read
  as stage 1; rejected for stage-indexed lists that keep the name (§3, the docs lens).

## Rows
`docs/plans/2026-11-09-visual-polish.md`: P202 (art-director, the generator and the frames) at
once, then P201 (touch-ux-dev, the view rule; written beside P202, merged after it); P200b places
the dated notes.
