class_name ArtDamage
extends RefCounted
## The rules of generator v5a that read the geometry of a building's damage stages (ADR 0029
## section 5): the ruin's height and debris limits, the odd-canvas refusal, the ink under every
## damage, ruin and ambient emitter point, `anim_kritisk run`, the hash order of `blow`, the stage
## from which an ambient emitter goes quiet. Static helpers, called by `ArtModel` and `ArtGen`.

const DEBRIS_OUT: float = 0.25  ## A ruin primitive may lie this far outside the footprint, tiles.
const DEBRIS_HIGH: float = 0.1  ## ... at this height at most, tiles.
const RUIN_RISE: float = 0.5  ## The ruin's ink rises this share of the body's canvas at most.


## The line indices of the intact `glass` primitives of `group` in the order `blow` takes them: by
## an integer hash of the model's id and the line, so two runs and two machines agree.
static func blow_order(model: ArtModel, group: StringName) -> Array[int]:
	var panes: Array[int] = []
	for prim: ArtPrim in model.primitives(&"hull"):
		if prim.group == group and prim.material == &"glass":
			panes.append(prim.index)
	var seed: int = String(model.art_id).hash()
	panes.sort_custom(
		func(a: int, b: int) -> bool:
			var ha: int = _mix(seed, a)
			var hb: int = _mix(seed, b)
			return ha < hb or (ha == hb and a < b)
	)
	return panes


## The first damage stage (1 or 2) whose pose moves or hides `group` (a shift, a turn or a hide),
## 0 for none or for no group: the stage from which an ambient emitter on it goes quiet.
static func quiet(model: ArtModel, group: StringName) -> int:
	for i: int in ArtModel.PATCH_PARTS.size():
		for move: ArtMove in model.pose_moves(ArtModel.PATCH_PARTS[i], 0):
			if group != &"" and move.group == group and move.kind in [&"shift", &"turn", &"hide"]:
				return i + 1
	return 0


## Whether the model uses a feature of generator v5 (a ruin, or a gas, spark or ruin point), which
## brings the counts and the ink tests; a model without any is judged by the v4 rules alone.
static func is_v5(model: ArtModel) -> bool:
	var found: bool = model.damage_parts().has(ArtModel.RUIN)
	for emitter: Array in model.emitter_list():
		found = found or emitter[0] in [&"dmg_gas", &"dmg_spark", ArtModel.RUIN]
	return found


## What is wrong with a building's damage stages that needs the geometry: an odd body canvas, the
## ruin, a point or an emitter with no ink under it, `anim_kritisk run` with nothing under the anim.
static func problems(model: ArtModel, body: ArtGen.Layout) -> PackedStringArray:
	var found: PackedStringArray = canvas_problems(model, body)
	var parts: Array[StringName] = model.damage_parts()
	if parts.has(ArtModel.RUIN):
		found.append_array(_ruin_problems(model, body))
	if is_v5(model):
		found.append_array(_ink_problems(model, body, parts))
	if model.anim_kritisk == &"run":
		var low: Vector2 = _lowest(model)
		if not inked(ArtGen.stage_polys(model, 2), low):
			found.append(
				"%s: anim_kritisk run, but nothing stands under the anim in dmg2" % model.art_id
			)
	return found


## The seam invariant of ADR 0029 section 12 holds for even canvas heights only.
static func canvas_problems(model: ArtModel, body: ArtGen.Layout) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	if body.size.y % 2 != 0:
		found.append("%s: the body canvas is %d rows, odd" % [model.art_id, body.size.y])
	return found


## Whether `spot` (px from the model's origin) lies inside the outline of a drawn face.
static func inked(polys: Array[ArtRender.Poly], spot: Vector2) -> bool:
	for poly: ArtRender.Poly in polys:
		if Geometry2D.is_point_in_polygon(spot, poly.points):
			return true
	return false


static func _mix(seed: int, line: int) -> int:
	var h: int = (seed ^ (line * 40503 + 12345)) & 0x7FFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7FFFFFFF
	return h ^ (h >> 16)


## The ruin: it draws something, rises at most half the body's canvas, and its own primitives lie
## at most a quarter tile outside the footprint, and no higher than 0.1 tile where they do.
static func _ruin_problems(model: ArtModel, body: ArtGen.Layout) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	var polys: Array[ArtRender.Poly] = ArtGen.stage_polys(model, 3)
	var box: Rect2 = ArtRender.bounds(polys)
	if polys.is_empty():
		found.append("%s: the ruin draws nothing" % model.art_id)
		return found
	var rise: float = body.size.y - (box.position.y + body.origin.y)
	if rise > body.size.y * RUIN_RISE:
		found.append(
			(
				"%s: the ruin rises %d of the body's %d rows, half at most"
				% [model.art_id, roundi(rise), body.size.y]
			)
		)
	var half: float = model.footprint / 2.0
	for prim: ArtPrim in model.damage_prims(3):
		if prim.damage != 3:
			continue
		var at: AABB = prim.aabb()
		var far: float = maxf(
			maxf(-at.position.x, at.end.x) - half, maxf(-at.position.y, at.end.y) - half
		)
		if far > DEBRIS_OUT + 1e-4:
			found.append(
				"%s: ruin debris `%s` is over a quarter tile off" % [model.art_id, prim.line]
			)
		elif far > 1e-4 and at.end.z > DEBRIS_HIGH + 1e-4:
			found.append(
				(
					"%s: ruin debris `%s` outside the footprint is over 0.1 high"
					% [model.art_id, prim.line]
				)
			)
	return found


## Ink under the points: a damage point (of any type) inside a face of `dmg1` and of `dmg2`, and
## above `dmg1`'s cut; a ruin point inside a face of the ruin; an ambient emitter inside a face of
## each stage it still emits at (before its `quiet` stage, ADR 0029 section 5).
static func _ink_problems(
	model: ArtModel, body: ArtGen.Layout, parts: Array[StringName]
) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	var stages: Dictionary[int, Array] = {}
	for stage: int in [1, 2, 3]:
		stages[stage] = (
			ArtGen.stage_polys(model, stage) if stage < 3 or parts.has(ArtModel.RUIN) else []
		)
	var cut: int = ArtGen.damage_cut(model, 1, body) if parts.has(&"dmg1") else ArtGen.NO_CUT
	for emitter: Array in model.emitter_list():
		var spot: Vector2 = ArtRender.project(emitter[1])
		var label: String = "%s: %s point %s" % [model.art_id, emitter[0], emitter[1]]
		var wanted: Array[int] = []
		if emitter[0] in ArtModel.DAMAGE_POINTS:
			wanted.assign([2] if not parts.has(&"dmg1") else [1, 2])
			if cut != ArtGen.NO_CUT and spot.y + body.origin.y >= cut:
				found.append("%s lies below dmg1's cut, off a SKADET break" % label)
		elif emitter[0] == ArtModel.RUIN:
			wanted.append(3)
		elif emitter[0] in ArtModel.AMBIENT:
			var quiet_at: int = quiet(model, emitter[2])
			for stage: int in [1, 2]:
				if quiet_at == 0 or stage < quiet_at:
					wanted.append(stage)
		for stage: int in wanted:
			var typed: Array[ArtRender.Poly] = []
			typed.assign(stages[stage])
			if not inked(typed, spot):
				found.append("%s has no ink under it at stage %d" % [label, stage])
	return found


## The lowest vertex of the `anim` element over all its frames (the larger y, then the smaller x).
static func _lowest(model: ArtModel) -> Vector2:
	var low: Vector2 = Vector2(0.0, -INF)
	for frame: int in model.pose_frames(ArtPrim.ANIM):
		for poly: ArtRender.Poly in ArtRender.render(
			model.frame_prims(ArtPrim.ANIM, frame), 0.0, model.faction
		):
			for point: Vector2 in poly.points:
				if point.y > low.y or (point.y == low.y and point.x < low.x):
					low = point
	return low
