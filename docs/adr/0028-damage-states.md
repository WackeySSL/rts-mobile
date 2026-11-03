# ADR 0028: Damage states of buildings and vehicles (view and art only)

Status: accepted 2026-11-03 (Michael's answers: 1 A, 2 A; see "Questions for Michael"). Written on
`main` at 64f0402 (P141 merged; P145 `AirFx` in review on `claude/p145-air-fx` at a803e2f).
Revised the same day before merge, after the review lens: the neutral sheet moved out of the
generated tree (§4), one write budget for both layers (§8), the review's smaller points (§2, §3,
§4, §6); no answer of Michael's changes. Plan: `docs/plans/2026-11-03-damage-states.md`
(rows P155-P162 and the reworked P148; P155 is this ADR and plan). On acceptance the lead's P26ar
writes the dated notes in ADR 0027 §3, §4 and §8, ADR 0023 §2 and §5 and the unit-life plan's P148
row (not done here: another lane edits those files today). It amends ADR 0027 §3 (the damage quota
of `AirFx`), §8 (what `reduced` keeps) and the unit-life plan's P148; ADR 0023 §2 ("a damaged
building looks intact") and §5 (two new part names). No rule, state column, Command, event or
golden hash changes.

Status note (2026-11-03, P26ar docs; accepted on #291; P156 #294 as merged): the dated notes
in ADR 0027 §3, §4 and §8, ADR 0023 §2 and §5 and the unit-life plan's P148 row are written. §3
and §8 carry dated notes from P156's review: the stage's draw order and its cut row, the overlap's
double fringe, the rules on damage parts and points, and the `hang` point's side per hull frame (a
lead decision). No accepted text changed.

## Context
- **Michael, 2026-11-03** (his own answers): buildings and vehicles under 50 % hp must look as if
  they are falling apart; infantry not. Two stages: under 50 % cracks, soot and smoke; under 25 %
  visibly falling apart, with fire and sparks. Buildings get damaged body variants (stage 1 and
  stage 2) from the art generator (ADR 0023, ADR 0027 §4); a building does not turn, so a variant
  is one picture per stage per building (broken roof edges, missing panels, tilted or fallen parts,
  scorch). Vehicles get overlays, not new per-direction frames, because the page has about 318 px
  left (budget 3584, the cross-faction page 3266 after P143): a darker or burnt look, soot, sparks,
  a loose or hanging part, smoke and fire. Smoke and fire by hp is P148 of the unit-life plan,
  folded in here; it builds on `AirFx` (P145).
- **Can hp go up again?** Only on a site. `Production`'s construction walk raises a site's hp by
  the step of `_site_hp` from `construct_start_hp_percent` (10, `data/rules.tres`) to the type's max
  as its work goes on. A complete building and every unit only lose hp (`Combat`, `Strike`); there is
  no repair, healing or regeneration in `game/sim`, `data/`, the GDD or the ROADMAP.
- **What the view can read** (ADR 0012 §3). `MatchSnapshot` copies `hp` and `type_max_hp` for every
  row, own and enemy, and `type_armour` (`INFANTRY` marks the squads, as `UnitLayer` already uses
  it). The view decides what is shown: own rows always, an enemy rig on a tile the local player
  sees, an enemy building while any cell of its footprint is seen (`BuildingLayer.is_shown`). A
  shown enemy's hp is already public through its bar (ADR 0027 §6). **One gap:** a last-seen record
  (`ghost_id`, `ghost_type`, `ghost_owner`, `ghost_cell`, `LastSeen`) carries no hp, so the snapshot
  cannot say what the player saw of a building that is out of sight now.
- **Batching** (ADR 0023 §2): every sorted sprite is a region of one per-match atlas page with white
  modulate, so `WorldSort` is one draw call. A per-sprite tint, a material or a sprite from another
  texture in the sort splits the batch wherever it interleaves (ADR 0012's probe: 150 calls for
  alternating tints). Sprites may change region, offset, position, scale and flip freely.
- **The page.** `tests/view/test_iso_atlas_budget.gd` pins the cross-faction two-player page at bake
  scale 1.0 at 3266 of the 3584 budget (mirror Derrick 2702, mirror Lumen 2894). The 16 building
  bodies (8 per faction; 128 x 104 up to 384 x 388 in 2x art px) are about 1.47 M texels per stage,
  358 page rows even if packed without loss.
- **The life layers** (ADR 0027): `BuildingLayer` (one `Body`, an `Anim` child after it on eight
  buildings, a `Head` on defences), `UnitLayer` (rig: `Shadow`, `Hull`, `Turret`; recoil, rock and
  rumble are offsets on `Hull` and `Turret`), `GhostMemoryLayer` (z 5, one dim, the body and the
  rest frame of the `Anim`), `LifeFx` → `AirFx` (z 25, one `_draw` from `fx/life_atlas.svg`, which
  already has `soot`, `exhaust`, `fire` and `spark` sprites). `UnitLayer.gd` is 916 lines (gdlint's
  limit is 1000), `BuildingLayer.gd` 673.

## Decisions in short
1. **View and art only.** The sim is untouched; the one gap (hp at last sight) is closed in the view.
2. **Stage** = a pure function of `hp` and `type_max_hp`: stage 1 when `hp x 100 < max x 50`,
   stage 2 when `hp x 100 < max x 25`, the percents in `data/life_settings.tres`. No hysteresis, no
   latch. A site shows no stage. Infantry has none.
3. **Buildings:** each stage is a generated **top patch** (part `dmg1` or `dmg2`): the damaged
   model's picture above a cut line, laid over the intact `Body`, which shows only the rows below
   the line (a sub-rectangle of its own region, no new texels). Patches of about a third of the body
   height fit the page (estimate 3534 of 3584). The `anim` keeps running; the shadow, the card, the
   head, the pick shape and the bar stay intact.
4. **Vehicles:** at most two overlay sprites per vehicle, **on the sorted world's page** (a neutral
   sheet, one shared slot each): a scar (soot at stage 1, char at stage 2) and, at stage 2, a loose
   part (a skirt plate or a fender). Children of `Hull`, so they follow its rock and kick with no
   write; placed per hull frame from points the generator writes. No tint.
5. **Fog and ghosts:** a stage shows only on a shown row. `BuildingLayer` remembers the stage it last
   showed for each enemy building; the ghost shows that stage, dimmed, with no smoke.
6. **Effects (P148, reworked):** soot, fire and sparks in `AirFx` from the sheets' `damage` points,
   in a damage ring of 64 slots of its own.
7. **Reduced effects** keep every stage picture, the overlays, the damage smoke and the fire; they
   drop the sparks.
8. **Budget:** no new draw call; stage writes share one budget of 60 a frame (20 buildings, 40
   vehicles); the page stays at most 3584.

## Decision

### 1. View and art only
- Stages read the published snapshot only, in the layers' `ticked` and frame paths. No file in
  `game/sim` or `native/` changes; no state, hash, `STATE_FORMAT`, event or Command.
- **The gap is closed in the view (§5)**, not by a `ghost_hp` column in `LastSeen`. **Rejected:** that
  column is hashed state (a re-pin of the golden hashes, a `STATE_FORMAT` bump, a write in
  `LastSeen` every tick a building is seen) for a look, and the view already sees every tick the
  player sees.

### 2. Stages and thresholds
- `stage(hp, max) = (1 if hp x 100 < max x P1) + (1 if hp x 100 < max x P2)`, integers, with
  `LifeSettings.damage_stage_percent = [50, 25]` (`[P1, P2]`, a data test holds 100 > P1 > P2 > 0).
  "Under" is strict: exactly 50 % is intact. One static function (`BuildingDamage.stage_of`) serves
  buildings, vehicles and `AirFx`.
- **Who has stages:** every building row that is complete (`build_left == 0`) and every unit row
  whose type's armour is not `INFANTRY`. **A site shows stage 0** whatever its hp: its hp is low
  because it is unfinished (it starts at 10 %), so a stage would say "falling apart" about a new
  building. A site that took hits shows its stage the moment it is complete (its hp is then below
  the max). A cancelled site (`build_left` below 0) is a site.
- **Hysteresis: none; the stage is stateless.** Today hp never rises on a row that has a stage, so
  stage-follows-hp and a latch give the same picture. The pure function wins because a building
  first seen, a replay, a second viewer and a ghost all agree on the stage without history, and a
  repair (if a later ADR adds one) shows as a repaired building. **Rejected:** a latch (wrong after a
  repair); a band (`stage up at 50, back at 55`: per-row view state for a case the sim cannot make;
  a repair ADR adds it then, as another number in `damage_stage_percent`'s neighbourhood).
- **When it is read.** Vehicles: in `UnitLayer._note_hits`, which already compares every row's hp
  once per new snapshot tick; the stage check rides on that compare (a row whose hp did not change
  keeps its stage; hp only falls, so the newest snapshot's stage is the one to show). Buildings: in
  `BuildingLayer`'s `ticked` handler (every publish emits `ticked`, also each tick of a frame that
  plays several), over its entries (at most about 60), so the remembered stage of §5 is the one of
  the last tick the building was shown. That walk calls `_sync()` first: after a death the rows
  compact and an entry's `row` is stale until the merge has run. A changed stage is queued and
  applied in the frame (§8).
- **Applied stage.** Each building entry and each rig keeps the stage its sprites show. A stage is
  applied only to a shown building or a visible rig; a building that is shown again, a rig that
  turns visible and a rig dressed for a new row (out of the pool or new) compare their applied stage
  with the row's and queue the difference, so nothing keeps a stale stage.

### 3. Building stages: generated top patches
- **How the generator makes them** (art-director, `tools/artgen/`). A model gains damage poses
  `dmg1` and `dmg2` beside its `anim` poses, each a list of moves of named groups: `shift` and `turn`
  (today's `ArtMove`), `hide` (the group is not drawn: a missing panel, a fallen chimney) and `char
  <percent>` (the group's face colours are mixed toward the palette's char colour: scorch). A
  primitive tagged `damage=<k>` is drawn only from stage k on (an exposed dark interior behind a
  missing panel, a broken beam, debris on the roof). The generator draws the stage with today's
  projection, light, outline and team-key rules. **Generated, never hand-edited.**
- **The cut line.** A changed primitive (moved, turned, hidden, charred or added) can only change
  pixels inside its own projected outline, before and after the move. So the generator computes
  the stage's cut row geometrically: the lowest screen row of the union of those outlines (no
  raster compare). Below it the damaged picture equals the intact one. The patch is the damaged
  picture from its top down to the cut row plus an overlap of 4 art px (at least one texel at any
  bake scale, so a rounding or a filter seam at the cut is covered), cropped left and right to its
  ink. The sheet gets the parts `dmg1` and `dmg2` (`<type_id>_dmg1.svg`, `<type_id>_dmg2.svg`, size
  and anchor like any part) and `cuts` (the cut row of each stage in the body's canvas).
- **Why parts, not the frame axis.** The frames of a part share one canvas size (`IsoSheetDef.sizes`
  is per part); the two patches have different cuts and sizes. Two one-frame parts with no
  direction need no change in the bake: `IsoAtlas._collect_sheet` bakes every part a sheet lists.
- **How the view shows it** (`BuildingDamage.gd`, a static helper, so `BuildingLayer` grows by calls).
  Stage 0: today's `Body`. Stage k: `Body`'s region becomes the rows of its own region from the cut
  down (same base, a smaller rect, the offset moved down by the cut: no texel on the page), and a
  `Damage` child (made with the building, hidden while intact) shows `dmg<k>`. Child order: `Body`,
  `Damage`, `Anim`, `Head`, so the patch is drawn over the body's cut and under the moving element.
  A building's node, sort key, `rise`, `frame_box`, pick shape and `bar_lift_px` keep their intact
  values, so a tap, a bar and the sort do not move with the stage.
- **Why patches, not whole variants** (estimates, a replica of `IsoAtlas.planned_page`, tallest-first
  shelves with the 2 px gutter, over the committed sheets; it gives today's pinned 3266 and 2894
  exactly, and for the Derrick mirror 2698, the value the test names when no player wears the key
  triad, against the pinned 2702 with it; the reviewer's own replica gives 3528 to 3531 for the
  30 % row; P158's page test measures the real page):

  | Building pictures added (both factions) | Cross-faction page | Fits 3584? |
  | --- | --- | --- |
  | none (today) | 3266 | yes |
  | whole variants, both stages | 4040 | no |
  | whole variant, stage 2 only | 3646 | no |
  | top patches of 50 % of the body height, both stages | 3652 | no |
  | top patches of 40 %, both stages | 3616 | no |
  | top patches of 35 %, both stages | 3583 | 1 px left |
  | **top patches of 30 %, both stages** | **3534** | **yes, 50 px left** |
  | top patch of 50 %, stage 2 only | 3418 | yes, 166 px left |

  Mirror matches with 30 % patches: Derrick about 2967, Lumen about 3082. The estimate takes every
  patch at the body's full width; cropping to ink gives more room. The page's GPU memory goes from
  about 53.5 MB to about 57.9 MB (58.7 MB at the full 3584 rows), inside ADR 0023 §2's 64 MB; the bake
  gains 40 slots with §4's (about 5 % more time).
- **The art rule that follows:** damage sits in the top third of a building (the roof edges, panels,
  chimneys, stacks, masts, flare towers, antennas), which is where Michael's examples are and where
  a ruin reads at phone zoom. Below the cut the walls stay as they are; soot and fire there come from
  `AirFx`. A small defence's body may use more of its height (its whole body is 104 to 130 px). The
  page test (≤ 3584) is the arbiter, not a per-building percentage.
- **Fallback, in order, if the measured page passes 3584:** (a) tighter patches (lower damage moved
  up, crops to ink); (b) stage 1 by the neutral scar overlays of §4 placed at the building's `damage`
  points (so P159 then also waits for P160's sheet), and only stage 2 as a patch of up to half the
  body (3418 estimated). Never a lower bake
  scale, a second page or the 512 rows above 3584 that ADR 0027 §4 keeps for later types.
- **The `anim` part keeps running at both stages, at its rate.** A held loop already means "site or
  blackout" (ADR 0027 §6, P144); a radar that stops at stage 2 would read as switched off. A slower
  loop would need a clock per building or a jump in the frame when the stage changes, for little
  gain. The generator keeps the element seated: a damage move may not shift, turn, hide or char a
  primitive of an `anim` group or one tagged `mount` (the generator fails such a model), so the
  antenna, rotors and beacons still stand on what holds them.
- **Intact by rule:** the cast shadow (`DecalLayer`; a fallen chimney's shadow error is accepted),
  the build card (`assets/art/iso/icons/item_*.svg`), a defence's `Head` (16 directions per stage
  would cost page rows), the crater and the site look.

Status note (2026-11-03, P26ar docs; P156 #294, 732cb6c, as merged in `tools/artgen/`; the text
above stays as accepted):
- **The stage and its cut.**
  - A stage is drawn in its own greedy painter's order (`ArtGen.stage_polys`), not in the intact
    body's.
  - `cuts` holds the **first intact row**, not the last changed one:
    `ceili(low + 1) + origin.y` (`ArtGen.damage_cut`), where `low` is the lowest outline row and
    1 is half of the 2 px edge (`ArtSvg.EDGE_PX / 2`).
  - The cut also covers the screen overlap (the intersection, not the union) of every pair of
    untouched primitives that the stage draws in the other order than the intact body
    (`ArtModel.damage_swaps`): such a swap shows only where the two overlap.
  - The 4 overlap rows (`CUT_OVERLAP_PX`) draw an edge's anti-aliased fringe twice, the patch's
    over the body's (edge pixels only). P159 trims the body at `ceil(cut x bake_scale)`
    texels and draws the patch over it (a lead decision, 2026-11-03: at `MIN_SCALE` 0.25 the 4 px
    overlap is still at least 1 texel).
- **Damage parts and points** (`ArtModel._pose_problems` for the part, count and `scar_milli`
  rules; `ArtModel._damage_problems` for the moves; `ArtGen.damage_problems` for the stages):
  - A building with stage 1 only (`dmg1` without `dmg2`) is refused; stage 2 only is allowed
    (fallback (b)).
  - The seated group is the hull group named `mount` (`ArtModel.SEATED_GROUP`); a damage move may
    not touch it or an `anim` group. P158 puts a defence's `Head` seat in it.
  - Count rules: a building has at most two `damage` points and no `hang`; a vehicle at most one
    of each; infantry none.
  - `scar_milli` is for vehicles only (0 on every other model).
  - A stage is refused when it changes nothing, when a change lies wholly above the body's canvas,
    or when a change reaches the body's foot (the overlap would not fit the canvas).

### 4. Vehicle overlays
- **Where the sprites live: on the sorted world's page, not in `fx/life_atlas.svg`.** An overlay
  sorts with its vehicle, so it is a sprite in `WorldSort`; a sprite of another texture there splits
  the one batch at every damaged vehicle. Drawing it in `AirFx` (z 25) instead would put a tank's
  scorch over a building in front of it. So the overlays are a **neutral sheet**: hand-written SVG
  (CLAUDE.md Legal: authored in this repo, no outside art) baked onto the page in every match.
- **Where the files are: outside the generated tree.** Everything under `assets/art/iso/` is
  generator output with its marker (`tests/art/test_artgen.gd` checks every `.svg` and `.tres`
  there), and `IsoAtlas.load_sheets()` reads only the generated `index.tres` (28 sheets, pinned by
  `test_artgen_sheets.gd`). So the overlays live with the other hand-written art, in
  `assets/art/svg/damage/` (`test_art_assets.gd`'s hand-drawn rules apply to them), each SVG with a
  "Keep File" import (`importer="keep"`, as STYLE.md's "Files" asks of every frame the bake reads,
  so the export carries the SVG text), beside a hand-written sheet
  `assets/art/svg/damage/damage_sheet.tres` (`IsoSheetDef`, `faction` `neutral`, category `dmg`).
  `IsoSheetDef` gains `root` (P156): empty is today's `assets/art/iso/<faction>/<category>/`; set,
  it is the folder the sheet's frames are in, so `path()` finds the neutral frames with no second
  path scheme. The bake (P157) loads the sheet from one fixed path (`IsoAtlas.NEUTRAL_SHEET`), not
  through the index; `WorldSort.bake` adds it after its art-id filter, for every scenario, and after
  `_player_arts` (whose faction lookup reads the sheets: `neutral` is no player's faction);
  `IsoAtlas._collect` collects a `neutral` sheet for every player. It has no key colour, so each
  frame is one slot shared by all players (`_collect_sheet`'s rule). Estimated page cost: 0 px (its
  eight slots of up to 64 x 48 px fit the shelves' free ends). **Rejected:** keeping it under
  `assets/art/iso/neutral/` with an exemption in the generated-file test (a hand-written island in a
  tree whose rule is "generated, never edited").
- **The sprites** (two looks each, a frame of the part, picked by `LifeClock.mix(id, salt)`):
  - `scar1`: a cluster of soot smudges and scratches on a top face, near-black at partial alpha;
  - `scar2`: a larger char patch with a torn edge, bare-metal scratches and a thin ember seam
    (yellow-white, hue at least 46°, ADR 0027 §4);
  - `loose`: a part hanging off a broken bracket, four frames: a track-guard skirt plate in two
    looks for a vehicle whose sheet says `marks` `tracks`, a bent wheel fender in two looks for
    `wheels`.
- **Per vehicle:** a `Scar` sprite (stage 1 `scar1`, stage 2 `scar2`) and a `Loose` sprite (stage 2
  only). They are made with the rig (hidden while intact) for every non-infantry kind; a rig kind gets
  a bit for them, so a squad never takes a vehicle's rig from the pool, and `_new_rig` hides them
  when a rig is reused.
- **Following the hull.** Both are children of `Hull`, after it in the tree, so they draw over the
  hull and under the `Turret`, inherit the hull's offset (recoil rock, drive rumble) with no write,
  and hide with the rig. Their positions per hull frame come from the vehicle's sheet: two emitter
  kinds the generator writes per hull frame, `damage` (a point on the hull's top face, where the scar
  sits and where `AirFx`'s smoke starts) and `hang` (the bracket on the side that faces the camera).
  `Loose` is mirrored (`flip_h`) when the hang point is left of the hull's centre. A sheet number
  `scar_milli` scales the scar to the hull's top (1000 = the battle tank). The positions are written
  only when the hull frame changes (§8).
- **No tint.** A darker hull by `modulate` splits the batch at every damaged vehicle (up to `2k + 1`
  calls, ADR 0023 §2); a darkened copy of each hull and turret frame, even at half resolution,
  costs about 268 page rows (3534 alone; 3656 to 3768 beside any of §3's building pictures), and of
  the hull frames alone about 173 (3439 alone; 3596 to 3660 beside them), so neither fits with the
  buildings' pictures; a shader is a material per sprite. The burnt look is the scar, the char and the
  smoke.
- **Originality** (CLAUDE.md Legal, ADR 0023 §13): every picture is drawn here from our own models
  and our own fx sheets; nothing copies another game's damaged frames, burning-wreck sprites, its
  flame colours or its smoke columns. Flames stay yellow-white and smoke grey, outside both
  factions' key bands, so a fire never reads as team colour.

### 5. Fog and ghosts
- **Live rows:** the stage is drawn only where the row is: an enemy building while
  `BuildingLayer.is_shown`, an enemy vehicle while its rig is visible (its children hide with it). A
  hidden enemy's stage change writes nothing; when it is seen again it shows its stage of now, as
  its bar would.
- **The remembered stage:** `BuildingLayer` keeps `last_seen_stage` (unit id → stage) for enemy
  buildings, written in `ticked` while the building is shown. It is cleared with a new match and when
  the local player changes. An id it has no entry for is stage 0.
- **Ghosts:** `GhostMemoryLayer` (a new `building_layer` export, one line in `main.tscn`) draws a
  record at the remembered stage: the trimmed body and a `Damage` child per ghost sprite (pooled with
  the sprite, as `BuildingAnims.dress_ghost` does the `Anim`), dim like the rest. The `Damage`
  child comes before the `Anim` (it is drawn under the moving element), and `dress_ghost` today
  takes `get_child(0)` as the `Anim`, so P159 makes it find its child by name. It redraws on the
  fog version, as today: a building leaves sight in the tick the fog moves, and its stage of that
  tick is already noted. A ghost has no smoke, fire or sparks (ADR 0027 §6: no life on a ghost).
- **Why it is honest:** a stage changes only from what the player saw; the ghost of a building that
  was hit after it left sight keeps the stage of the last look, exactly like its hp would.

### 6. Smoke, fire and sparks (P148, reworked)
- **Sources.** A building's sheet gets two `damage` emitter points (on the broken parts of its
  `dmg2` model). A vehicle's sheet has its per-hull-frame `damage` point (§4).
- **Looks by stage** (sprites already in `fx/life_atlas.svg`):

  | Source | Stage 1 (under 50 %) | Stage 2 (under 25 %) |
  | --- | --- | --- |
  | building, each `damage` point | `soot` | `soot`, `fire`, `spark` |
  | vehicle, its `damage` point | thin trail (`exhaust`) | `soot`, a small `fire`, `spark` |

  Each kind emits every `damage_emit_ms` of its kind from a phase of `LifeClock.pick(id, salt + point)`,
  as `AirFx`'s emitters do; a vehicle's puff is born at the rig's drawn point and stays in the world,
  so a moving vehicle trails smoke. Damage smoke goes on in a blackout (power does not put a fire
  out); a site never smokes.
- **Accepted draw order:** `AirFx` is at z 25, so a vehicle's flame, smoke and sparks draw over a
  building that stands in front of the vehicle. §4 rejects `AirFx` for the scar, and the difference
  is time: a scar is a mark on the hull that stays as long as the damage, so over a building in
  front it would float there for minutes; a flame is a puff of at most 0.7 s that rises off the hull
  into the air, like the stack smoke ADR 0027 §3 accepts over units in front of a building, and a
  fire seen over a roof reads as a fire behind it. The vehicle is shown, so it reveals nothing.
  Putting the flame on the hull instead would need a sprite in `WorldSort` with frame writes for its
  flicker; rejected for the writes.
- **Who sees it:** a source that is shown in that tick (`BuildingLayer.is_shown`; `UnitLayer.is_shown`
  through a new `unit_layer` export on `LifeFx`) and inside the view rect grown by a tile. A puff lives
  out its time.
- **The quota (amends ADR 0027 §3):** a **damage ring of 64 slots** in `AirFx`, its own, drawn in the
  same `_draw` from the same texture (no new call). ADR 0027 §3 gave damage smoke and flame 24 slots,
  for buildings only; vehicles and stage 2 need more (four burning buildings and ten smoking vehicles
  are about 70 live puffs). When the ring is full the oldest puff, the most faded one, goes. `AirFx`
  then holds three rings: emitters 80 (P145), damage 64 (P148), muzzle and exhaust 24 (P149).

### 7. Reduced effects (amends ADR 0027 §8)
- The stages tell the player something, so `reduced` keeps: the building patches, the vehicle
  overlays, the ghost's stage, the damage smoke and the fire (ADR 0027 §8 already keeps "damage smoke
  and flame").
- It drops the **sparks** (detail on top of the fire). On the switch the ambient ring empties as
  today; the damage ring keeps its puffs (they are not ambient).

### 8. Budget
- **Draw calls: none new.** Patches, trimmed bodies and overlays are regions of the sorted world's
  page (one batch); the ghosts' patches are in the ghost layer (one texture, one dim); damage puffs
  are in `AirFx`'s one `_draw`. ADR 0027's forecast stays 16 (about 22 in the worst moment).
- **What a change costs** (sprite writes, counted in `life_writes`):

  | Change | Writes |
  | --- | --- |
  | building 0 → 1, 0 → 2 | 5: the body's region and offset, the patch's region, offset and visibility |
  | building 1 → 2 | 4: the body's region and offset, the patch's region and offset |
  | vehicle 0 → 1 | 3: the scar's region, visibility and position |
  | vehicle 1 → 2 | 5: the scar's region; the loose part's region, visibility, position and flip |
  | vehicle 0 → 2 | 7 |
  | a damaged vehicle's hull frame changes (follow) | 1 at stage 1, 2 at stage 2 (the positions), +1 for the flip only when the hang point changes side (twice a full turn) |

- **One write budget for both layers:** `damage_writes_per_frame` (60) per frame, of which
  `damage_building_writes` (20) are `BuildingLayer`'s and the rest (40) `UnitLayer`'s. It is a fixed
  split, not a counter the two layers share, so the result does not depend on which layer's
  `_process` runs first. In each layer the follow writes go first and are never deferred (an overlay
  stays on its hull); then the queued stage changes are applied oldest first while the next one's
  cost fits what is left of the layer's share, and the rest wait for the next frame. A rupture that
  pushes 40 buildings and vehicles over a line in one tick, or P162's crafted snapshot that drops
  100 vehicles to 40 % at once (300 writes), is spread over frames: 100 vehicle changes at 3 writes,
  40 a frame, take 8 frames, about 0.13 s.
- **The worst frame against ADR 0027 §9's 150:** buildings at most 20; vehicles at most 40 while the
  follow writes fit in their share, so the damage states add at most 60. The other life rows add at
  most about 47 in a full fight (the unit-life plan's table: recoil about 15, rumble 20, walk 10,
  animations 2), so about 107. The follow writes are the one part that is not capped: they come with
  a hull's own frame change, which happens at most every other frame for a turning vehicle (a turn
  rate of 12 rad/s at 60 fps against 22.5° frame steps), but a group order turns a whole group in
  step. A group of 30 damaged vehicles at stage 2 turning in step adds 60 in the frames where their
  frames change: 20 + 60 + 47 = 127; 40 such vehicles reach 147. P162 pins the worst frame on the
  base arena with every vehicle damaged and turned in step; past 150, `damage_loose` (a flag in
  `data/life_settings.tres`, on) drops the loose part, which halves the follow writes. A layer whose
  share the follow writes use up applies no stage change in that frame; the change waits (a delay,
  never a lost stage). The average stays far under 60: a stage changes at most twice per row per
  match.
- **Nodes:** `Damage` per building and `Scar` and `Loose` per vehicle rig are made with the building
  or the rig, so node counts stay flat after warm-up. A damaged vehicle draws one or two more quads
  in the sorted batch; P162 counts them, P147's phone card judges the cost.
- **Work:** the stage check rides on the hp compare `UnitLayer` already does per tick and on a walk
  of at most about 60 building entries; `AirFx` plans at most 64 more quads. Estimated at most
  0.15 ms per frame on the phone in the worst moment, inside ADR 0027 §9's 0.56 ms with the rest of
  the life layers (estimated about 0.3 ms).
- **Page:** at most 3584 at bake scale 1.0 for the cross-faction two-player match, pinned by
  `test_iso_atlas_budget.gd`; P158 and P160 update its `TODAY_*` values.

Status note (2026-11-03, P26ar docs; a lead decision of 2026-11-03 on P156 #294; the text above
stays as accepted): the generator mirrors the `hang` point per hull frame to the side that faces the
camera (`ArtGen.hang_point_px`); the edge-on frames `d00` and `d08` keep the model's side. So the
hang point changes side about **four times per full turn, not twice** (+1 write for the flip each
time). At each of the two switches in a full turn it jumps across the hull; which frames they fall
on depends on the model's side: a point on +y jumps at `d08` to `d09` and `d15` to `d00`, a point on
-y at `d00` to `d01` and `d07` to `d08`. The worst-frame sums above count 2 follow writes per
stage-2 vehicle; a group turning in step across a side switch writes 3 each (about 157 at 30
vehicles, 187 at 40, against ADR 0027 §9's 150). P162's in-step turn must include a side-switch
frame; `damage_loose` off removes both the loose part's position write and its flip write.

### 9. Numbers in data
`data/life_settings.tres` gains `damage_stage_percent` ([50, 25]), `damage_writes_per_frame` (60),
`damage_building_writes` (20; a data test holds it above 0 and under the total), `damage_loose` (on),
and for P148 `damage_emit_ms` and `damage_life_ms` per kind (`soot`, `fire`, `spark`, `exhaust`, a
building's and a vehicle's), `damage_vehicle_fire_scale` (0.6) and `damage_slots` (64). The art's
numbers (`cuts`, `scar_milli`, the `damage` and `hang` points) are sheet fields the generator writes.

## Consequences
- A battle reads at a glance: a base that is losing shows broken roofs, smoke and fire; a tank near
  death is scorched, trails smoke and burns. No sim change, no new draw call.
- The art generator gains damage poses (`hide`, `char`, stage-tagged primitives), more model work for
  sixteen buildings; the patches spend about 268 of the page's 318 free rows, which leaves about 50
  for P153 and P154 (they may not fit; their rows already say they land only if the page has room).
- Building damage sits in the top third of the picture; walls below the cut stay as they were.
- Two layers gain a small view memory (the last-seen stage) and `LifeFx` and `GhostMemoryLayer` gain
  one export each, wired in `main.tscn`.
- `AirFx` gains its second ring; the damage quota grows from 24 to 64.
- Amends (dated notes by the lead's P26ar on acceptance): ADR 0027 §3 (the damage quota, vehicles),
  §4 (the page rows spent; a stage is a part, not a frame), §8 (reduced keeps the stages, drops
  sparks); ADR 0023 §2 ("a damaged building looks intact" withdrawn) and §5 (the part names `dmg1`,
  `dmg2`, the neutral sheet); the unit-life plan's P148 row (reworked here; its 33 % vehicle line
  becomes the two stages).

## Alternatives considered
- **Whole body variants per stage:** 4040 px with both stages, 3646 with stage 2 alone; rejected
  (past the budget; a lower bake scale or a second page is ruled out by ADR 0027 §4).
- **Additive damage decals only, for buildings:** cheap, but a decal can only paint over the
  picture, never take a part away, so nothing can be missing, tilted or fallen; kept as fallback (b)
  for stage 1.
- **Patches without trimming the body:** an overlay cannot erase what it covers, so a hidden chimney
  would still show; rejected for the trimmed body.
- **A per-sprite tint or a shader for burnt vehicles:** splits the one batch; rejected (§4).
- **Overlay sprites from `fx/life_atlas.svg` in `WorldSort`:** a second texture in the sort splits
  the batch at every damaged vehicle; rejected for the neutral sheet on the page.
- **Overlays in `AirFx`:** no sort, so a hull's scorch is drawn over what stands in front; rejected
  (smoke there is fine, it is in the air).
- **`ghost_hp` in the sim's last-seen records:** hashed state for a look; rejected (§1).
- **Stopping or slowing the `anim` at stage 2:** a stop reads as a blackout; a slower loop needs a
  clock per building or a jump; rejected (§3).
- **Hysteresis or a latch:** no case in the sim; rejected (§2).

## Questions for Michael
1. **How much of a building breaks.** A (recommended): both stages are generated pictures of the
   top of the building (about a third of its height: broken roof edges, missing panels, tilted or
   fallen chimneys, masts and stacks, scorch); the walls lower down stay whole, and smoke and fire
   cover them. It fits the page with about 50 px left. B: stage 1 is shared cracks and soot painted
   over the intact building, and only stage 2 is a picture, of up to half its height (166 px left).
   If A does not fit when the art is made, the art row falls back to B by itself.
2. **The vehicles' "darker" look.** A (recommended): no tint of the whole vehicle; a soot patch at
   stage 1, a char patch with an ember seam and a hanging skirt plate or fender at stage 2, plus
   smoke, fire and sparks. B: also a darkened copy of every vehicle picture (16 directions, at half
   resolution); it costs about 268 px of the page and does not fit beside any building stage picture
   (3656 to 3768 of 3584), so the buildings would get no stage pictures. A tint at draw time is not
   an option: it would multiply the draw calls in a battle.

**Answers (Michael, 2026-11-03):** 1 A (both stages are generated pictures of the top third; the
automatic fallback to B stays if A does not fit), 2 A (no vehicle tint; soot patch, char patch with an
ember seam and a hanging plate or fender, plus smoke, fire and sparks).
