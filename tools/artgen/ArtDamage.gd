class_name ArtDamage
extends RefCounted
## The rules of generator v5a that read the geometry of a building's damage stages (ADR 0029
## section 5): the odd-canvas refusal, the ink under every damage and ambient emitter point,
## `anim_kritisk run`, the hash order of `blow`, the stage from which an ambient emitter goes quiet.
## Static helpers, called by `ArtModel` and `ArtGen`.


## The keys (`ArtPrim.key`: the line index of an ordinary primitive) of the intact `glass`
## primitives of `group` in the order `blow` takes them: by an integer hash of the model's id and
## the line, so two runs and two machines agree.
static func blow_order(model: ArtModel, group: StringName) -> Array[int]:
	var panes: Array[int] = []
	for prim: ArtPrim in model.primitives(&"hull"):
		if prim.group == group and prim.material == &"glass":
			panes.append(prim.key())
	var seed: int = _djb2(String(model.art_id))
	panes.sort_custom(
		func(a: int, b: int) -> bool:
			var ha: int = _mix(seed, a)
			var hb: int = _mix(seed, b)
			return ha < hb or (ha == hb and a < b)
	)
	return panes


## The hash of an art id, the seed of the per-line variation (`blow`, `broken`).
static func seed_of(art_id: StringName) -> int:
	return _djb2(String(art_id))


## The hash of `line` under `seed`: where a helper varies by line, it varies by this.
static func line_hash(seed: int, line: int) -> int:
	return _mix(seed, line)


## The first damage stage (1 or 2) whose pose moves or hides `group` (a shift, a turn or a hide),
## 0 for none or for no group: the stage from which an ambient emitter on it goes quiet.
static func quiet(model: ArtModel, group: StringName) -> int:
	# Stage 1 draws the intact picture (ADR 0034), so only stage 2 can move a group.
	for i: int in range(1, ArtModel.DAMAGE_PARTS.size()):
		for move: ArtMove in model.pose_moves(ArtModel.DAMAGE_PARTS[i], 0):
			if group != &"" and move.group == group and move.kind in [&"shift", &"turn", &"hide"]:
				return i + 1
	return 0


## Whether the counts and the ink tests of ADR 0029 section 5 apply: a building with damage poses.
static func staged(model: ArtModel) -> bool:
	return model.category == &"bld" and not model.damage_parts().is_empty()


## What is wrong with a building's damage stages that needs the geometry: an odd body canvas,
## a point or an emitter with no ink under it, `anim_kritisk run` with nothing under the anim.
static func problems(model: ArtModel, body: ArtGen.Layout) -> PackedStringArray:
	var found: PackedStringArray = canvas_problems(model, body)
	if staged(model):
		found.append_array(_ink_problems(model))
	if model.anim_kritisk == &"run":
		var low: Vector2 = _lowest(model)
		if not inked(ArtGen.stage_polys(model, 2), low):
			found.append(
				"%s: anim_kritisk run, but nothing stands under the anim in dmg2" % model.art_id
			)
	return found


## The seam invariant of ADR 0029 section 11 holds for even canvas heights only. `ArtGen._layout`
## rounds every canvas up to even, so this is a guard against a future change of it, not a rule a
## model can break today.
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


## djb2 of the UTF-8 bytes of `text` in 32 bits (the same as `String.hash()` for ASCII), so the
## art does not depend on an engine internal.
static func _djb2(text: String) -> int:
	var h: int = 5381
	for byte: int in text.to_utf8_buffer():
		h = (h * 33 + byte) & 0xFFFFFFFF
	return h


static func _mix(seed: int, line: int) -> int:
	var h: int = (seed ^ (line * 40503 + 12345)) & 0x7FFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7FFFFFFF
	return h ^ (h >> 16)


## Ink under the points: a damage point (of any type) inside a face of the intact picture (what
## SKADET shows, ADR 0034) and of stage 2; an ambient emitter inside a face of
## the intact picture and of each stage it still emits at (before its `quiet` stage).
static func _ink_problems(model: ArtModel) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	var stages: Dictionary[int, Array] = {}
	stages[0] = ArtRender.render(model.primitives(&"hull"), 0.0, model.faction)
	stages[1] = stages[0]  # SKADET shows the intact picture (ADR 0034).
	stages[2] = ArtGen.stage_polys(model, 2)
	for emitter: Array in model.emitter_list():
		var spot: Vector2 = ArtRender.project(emitter[1])
		var label: String = "%s: %s point %s" % [model.art_id, emitter[0], emitter[1]]
		var wanted: Array[int] = []
		if emitter[0] in ArtModel.DAMAGE_POINTS:
			wanted.assign([1, 2])
		elif emitter[0] in ArtModel.AMBIENT:
			var quiet_at: int = quiet(model, emitter[2])
			for stage: int in [0, 1, 2]:
				if stage == 0 or quiet_at == 0 or stage < quiet_at:
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
