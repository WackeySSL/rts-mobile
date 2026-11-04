class_name BuildingDamage
extends RefCounted
## The damage stages of a building's picture (ADR 0028 sections 2, 3 and 5, ADR 0029 sections 2, 3,
## 9 and 12, plan P159), kept out of `BuildingLayer`: which stage an hp is, which picture a sheet
## has for it, how the trimmed body and its `Damage` patch are written, and what a ghost shows.
## All static. Stage 0 is INTAKT (the body), 1 is SKADET (`dmg1`), 2 is KRITISK (`dmg2`).
## The seam (ADR 0029 section 12, the `IsoAtlas.DAMAGE_SCALE` doc block): the patch is a sibling of
## the body at the same position and uses its whole region; the body loses its first
## `IsoAtlas.body_cut_row` texel rows and clips its filter; `show_body` and `trim` are the one place
## that writes it, so the trim is applied again after every `show_frame`.

const PATCH: StringName = &"Damage"  ## The node name of the patch, and of a ghost's patch child.
## The sheet part of each stage's patch: index stage - 1.
const PARTS: Array[StringName] = [&"dmg1", &"dmg2"]
const KRITISK: int = 2
## `IsoSheetDef.anim_kritisk` (P163) is not on the sheet yet: a sheet that has it, as a property or
## as this meta key (a crafted test sheet), says whether the `Anim` runs at KRITISK; else it runs.
const ANIM_KRITISK: StringName = &"anim_kritisk"


## The stage of `hp` of `max_hp` for the lines `percents` (`[P1, P2]`): one for each line the hp is
## strictly under, so exactly P1 percent is intact. Integers; max hp 1 with hp 1 is 0, hp 0 the
## last stage.
static func stage_of(hp: int, max_hp: int, percents: PackedInt32Array) -> int:
	var stage: int = 0
	for line: int in percents:
		if hp * 100 < max_hp * line:
			stage += 1
	return stage


## The picture `sheet` shows for `stage`: the highest stage at or under it that has a patch and a
## cut, 0 for a sheet without damage parts (it shows intact).
static func picture(sheet: IsoSheetDef, stage: int) -> int:
	for k: int in range(mini(stage, PARTS.size()), 0, -1):
		if sheet.has_part(PARTS[k - 1]) and sheet.cuts.size() >= k:
			return k
	return 0


## Whether the `Anim` of `sheet` runs at KRITISK (ADR 0029 section 3).
static func anim_runs(sheet: IsoSheetDef) -> bool:
	if sheet.has_meta(ANIM_KRITISK):
		return bool(sheet.get_meta(ANIM_KRITISK))
	var field: Variant = sheet.get(ANIM_KRITISK)
	return field as bool if field is bool else true


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


## Shows the body frame and trims it for `stage`: the call that follows every frame the body gets.
static func show_body(
	sort: WorldSort, sheet: IsoSheetDef, body: Sprite2D, owner_id: int, stage: int
) -> void:
	sort.show_frame(body, sheet, BuildingLayer.BODY, BuildingLayer.NO_FRAME, owner_id)
	trim(sort, sheet, body, stage)


## Trims `body`, whose region was just written whole, for `stage` (0 un-trims): the region from
## `IsoAtlas.body_cut_row` texels down, the offset moved down by as much, and the filter clipped to
## the region so the cut edge does not bleed.
static func trim(sort: WorldSort, sheet: IsoSheetDef, body: Sprite2D, stage: int) -> void:
	var per_px: Vector2 = sort.texels(sheet, BuildingLayer.BODY)
	body.offset.y = -float(sheet.origin(BuildingLayer.BODY).y) * per_px.y
	var k: int = picture(sheet, stage)
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
## shown; hidden at stage 0.
static func show_patch(
	sort: WorldSort, sheet: IsoSheetDef, patch: Sprite2D, owner_id: int, stage: int
) -> void:
	var k: int = picture(sheet, stage)
	if k == 0:
		patch.visible = false
		return
	sort.dress(patch, sheet, PARTS[k - 1])
	sort.show_frame(patch, sheet, PARTS[k - 1], BuildingLayer.NO_FRAME, owner_id)


## Dresses the ghost sprite `parent` (its body already shown) for `stage`: the body trimmed and a
## `Damage` child, which comes before the `Anim` child (`BuildingAnims.dress_ghost`, called after
## this), at `scale = body_texels / patch_texels` so it draws as the live patch does.
static func dress_ghost(
	parent: Sprite2D, sort: WorldSort, sheet: IsoSheetDef, owner_id: int, stage: int
) -> void:
	trim(sort, sheet, parent, stage)
	var child: Sprite2D = parent.get_node_or_null(NodePath(PATCH)) as Sprite2D
	var k: int = picture(sheet, stage)
	if k == 0 or not parent.visible:
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
	child.texture = sort.atlas.texture()
	var texels: Vector2 = sort.texels(sheet, PARTS[k - 1])
	var want: Vector2 = Vector2(WorldSort.ART_SCALE / texels.x, WorldSort.ART_SCALE / texels.y)
	child.scale = Vector2(want.x / parent.scale.x, want.y / parent.scale.y)
	child.offset = -Vector2(sheet.origin(PARTS[k - 1])) * texels
	sort.show_frame(child, sheet, PARTS[k - 1], BuildingLayer.NO_FRAME, owner_id)


## Hides a ghost's `Anim` where the sheet's does not run at `stage` (call it after
## `BuildingAnims.dress_ghost`).
static func ghost_anim(parent: Sprite2D, sheet: IsoSheetDef, stage: int) -> void:
	var anim: Sprite2D = parent.get_node_or_null(NodePath(BuildingAnims.ANIM_NODE)) as Sprite2D
	if anim != null and anim_hidden_at(sheet, picture(sheet, stage)):
		anim.visible = false
