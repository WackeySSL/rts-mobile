class_name BuildingDamage
extends RefCounted
## The damage stages of a building's picture (ADR 0028 sections 2, 3 and 5, ADR 0029 sections 2, 3,
## 9 and 12, plan P159), kept out of `BuildingLayer`: which stage an hp is, which picture a sheet
## has for it, how the trimmed body and its `Damage` patch are written, and what a ghost shows.
## All static. Stage 0 is INTAKT (the body), 1 is SKADET (the intact picture too, ADR 0034: only its
## particles tell it from 0), 2 is KRITISK (`dmg2`).
## The seam (ADR 0029 section 12, the `IsoAtlas.DAMAGE_SCALE` doc block): the patch is a sibling of
## the body at the same position and uses its whole region; the body loses its first
## `IsoAtlas.body_cut_row` texel rows and clips its filter; `show_body` and `trim` are the one place
## that writes it, so the trim is applied again after every `show_frame`.

const PATCH: StringName = &"Damage"  ## The node name of the patch, and of a ghost's patch child.
const PATCH_PATH: NodePath = ^"Damage"
## The sheet part of each stage's patch: index stage - 1, the generator's list (the part list stays
## as it is). SKADET draws no patch (ADR 0034): `picture` is 0 there, nothing reads a `dmg1` region.
const PARTS: Array[StringName] = [&"dmg1", &"dmg2"]
const KRITISK: int = 2


## The stage of `hp` of `max_hp` for the lines `percents` (`[P1, P2]`): one for each line the hp is
## strictly under, so exactly P1 percent is intact. Integers; max hp 1 with hp 1 is 0, hp 0 the
## last stage.
static func stage_of(hp: int, max_hp: int, percents: PackedInt32Array) -> int:
	var stage: int = 0
	for line: int in percents:
		if hp * 100 < max_hp * line:
			stage += 1
	return stage


## The picture `sheet` shows for `stage`: 0 (intact) at SKADET, KRITISK when the sheet has its patch
## and cut, 0 for a sheet without (it shows intact). Part lists and `cuts` stay stage-indexed.
static func picture(sheet: IsoSheetDef, stage: int) -> int:
	if stage >= KRITISK and sheet.has_part(PARTS[KRITISK - 1]) and sheet.cuts.size() >= KRITISK:
		return KRITISK
	return 0


## Whether the `Anim` of `sheet` runs at KRITISK (ADR 0029 section 3): the sheet's
## `anim_kritisk`, which the generator writes from the model (default false: hidden).
static func anim_runs(sheet: IsoSheetDef) -> bool:
	return sheet.anim_kritisk


## Whether the `Anim` is hidden at picture stage `stage`.
static func anim_hidden_at(sheet: IsoSheetDef, stage: int) -> bool:
	return stage == KRITISK and not anim_runs(sheet)


## The sprite writes a change of the picture from `from` to `to` costs (ADR 0028 section 8): the
## body's region and offset and the patch's region, offset and visibility (5), the same without the
## patch's visibility between two stages (4), the body and the patch's visibility back to intact
## (3); `anim_write` adds the visibility write of the `Anim`.
static func cost(from: int, to: int, anim_write: bool) -> int:
	var writes: int = 3 if to == 0 else (5 if from == 0 else 4)
	return writes + (1 if anim_write else 0)


## Shows the body frame at `body_base` and trims it for `stage`: the call that follows every frame
## the body gets. `patch_bases` is the atlas base of each stage's patch for the owner (-1: none).
static func show_body(
	sort: WorldSort,
	sheet: IsoSheetDef,
	body: Sprite2D,
	body_base: int,
	patch_bases: PackedInt32Array,
	stage: int
) -> void:
	sort.show_base(body, body_base, 0)
	trim(sort, sheet, body, patch_bases, stage)


## The atlas bases of the two patches for `owner_id`, -1 where the owner's art has none, and
## always for SKADET (ADR 0034).
static func bases_of(sort: WorldSort, sheet: IsoSheetDef, owner_id: int) -> PackedInt32Array:
	var found: PackedInt32Array = PackedInt32Array()
	for stage: int in PARTS.size():
		var part: StringName = PARTS[stage]
		var base: int = -1
		if stage + 1 == KRITISK and sheet.has_part(part):
			base = sort.base_of(sheet, part, BuildingLayer.NO_FRAME, owner_id)
		found.append(base)
	return found


## Trims `body`, whose region was just written whole, for `stage` (0 un-trims): the region from
## `IsoAtlas.body_cut_row` texels down, the offset moved down by as much, and the filter clipped to
## the region so the cut edge does not bleed. A stage whose patch has no region for the owner
## (`patch_bases`) cuts nothing: the body is never trimmed without the patch that covers the cut.
static func trim(
	sort: WorldSort, sheet: IsoSheetDef, body: Sprite2D, patch_bases: PackedInt32Array, stage: int
) -> void:
	var per_px: Vector2 = sort.texels(sheet, BuildingLayer.BODY)
	body.offset.y = -float(sheet.origin(BuildingLayer.BODY).y) * per_px.y
	var k: int = picture(sheet, stage)
	if k > 0 and sort.frame_count_at(patch_bases[k - 1]) < 1:
		k = 0
	body.region_filter_clip_enabled = k > 0
	if k == 0 or not body.visible:
		return
	var region: Rect2 = body.region_rect
	var canvas_h: int = sheet.frame_size(BuildingLayer.BODY).y
	var cut: float = float(IsoAtlas.body_cut_row(sheet.cuts[k - 1], canvas_h, int(region.size.y)))
	cut = minf(cut, region.size.y)
	body.region_rect = Rect2(
		region.position.x, region.position.y + cut, region.size.x, region.size.y - cut
	)
	body.offset.y += cut


## Writes the patch of `stage` on the sibling `patch`: dressed for its part, its whole region
## shown (a table read at `patch_bases`); hidden at stage 0.
static func show_patch(
	sort: WorldSort, sheet: IsoSheetDef, patch: Sprite2D, patch_bases: PackedInt32Array, stage: int
) -> void:
	var k: int = picture(sheet, stage)
	if k == 0:
		patch.visible = false
		return
	sort.dress(patch, sheet, PARTS[k - 1])
	sort.show_base(patch, patch_bases[k - 1], 0)


## Dresses the ghost sprite `parent` (its body already shown) for `stage`: the body trimmed and a
## `Damage` child, which comes before the `Anim` child (`BuildingAnims.dress_ghost`, called after
## this), at `scale = body_texels / patch_texels` so it draws as the live patch does.
static func dress_ghost(
	parent: Sprite2D, sort: WorldSort, sheet: IsoSheetDef, owner_id: int, stage: int
) -> void:
	var bases: PackedInt32Array = bases_of(sort, sheet, owner_id)
	trim(sort, sheet, parent, bases, stage)
	var child: Sprite2D = parent.get_node_or_null(PATCH_PATH) as Sprite2D
	var k: int = picture(sheet, stage)
	if k == 0 or not parent.visible or sort.frame_count_at(bases[k - 1]) < 1:
		if child != null:
			child.visible = false
		return
	if child == null:
		child = Sprite2D.new()
		child.name = PATCH
		child.region_enabled = true
		child.centered = false
		parent.add_child(child)
		parent.move_child(child, 0)
	var texels: Vector2 = sort.texels(sheet, PARTS[k - 1])
	var want: Vector2 = Vector2(WorldSort.ART_SCALE / texels.x, WorldSort.ART_SCALE / texels.y)
	child.scale = Vector2(want.x / parent.scale.x, want.y / parent.scale.y)
	child.offset = -Vector2(sheet.origin(PARTS[k - 1])) * texels
	sort.show_base(child, bases[k - 1], 0)


## Hides a ghost's `Anim` where the sheet's does not run at `stage` (call it after
## `BuildingAnims.dress_ghost`).
static func ghost_anim(parent: Sprite2D, sheet: IsoSheetDef, stage: int) -> void:
	var anim: Sprite2D = parent.get_node_or_null(BuildingAnims.ANIM_PATH) as Sprite2D
	if anim != null and anim_hidden_at(sheet, picture(sheet, stage)):
		anim.visible = false
