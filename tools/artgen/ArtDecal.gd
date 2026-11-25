class_name ArtDecal
extends RefCounted
## One face decal of an `ArtModel` (ADR 0050 section 1, P630), parsed from one line of its `decals`:
##
##   <kind> <prim> <face> <u> <v> <size> [n=NUMBER]
##
## `kind` is `number` (a painted figure, `n=` 0 to 99, required), `hazard` (a striped patch) or
## `vent` (a slotted one). `prim` is the line of the model's `prims` it sits on: one box, wedge or
## prism line, not a rod, a `petals` line or a macro. `face` is `top`, `front` (+x), `back` (-x),
## `left` (-y) or `right` (+y). `u v` place its centre on the face as fractions 0 to 1 (u along the
## face's first axis, v up it or along it), `size` is its width in tiles (above 0, at most 2).
## Nothing draws a decal yet: the detail renderer (P631) does, so a model with decals has the same
## frames as one without.

const KINDS: Array[StringName] = [&"number", &"hazard", &"vent"]
const FACES: Array[StringName] = [&"top", &"front", &"back", &"left", &"right"]
const MAX_SIZE: float = 2.0
const MAX_NUMBER: int = 99

var kind: StringName = &"number"
var prim: int = 0
var face: StringName = &"top"
var uv: Vector2 = Vector2(0.5, 0.5)
var size: float = 0.2
var number: int = -1  ## `number`'s figure; -1 for the other kinds.


## The decal of a line, or null when it is not one: a wrong count, a number that is not one, a kind
## or face that is unknown, a `u v` outside 0 to 1, a size outside (0, 2], `n=` missing on a
## `number` or on any other kind, or out of range.
static func parse(line: String) -> ArtDecal:
	var words: PackedStringArray = line.split(" ", false)
	if words.size() < 6 or words.size() > 7:
		return null
	var decal: ArtDecal = ArtDecal.new()
	decal.kind = StringName(words[0])
	decal.face = StringName(words[2])
	if decal.kind not in KINDS or decal.face not in FACES or not words[1].is_valid_int():
		return null
	for i: int in range(3, 6):
		if not words[i].is_valid_float():
			return null
	decal.prim = words[1].to_int()
	decal.uv = Vector2(words[3].to_float(), words[4].to_float())
	decal.size = words[5].to_float()
	if (
		decal.prim < 0
		or decal.uv.x < 0.0
		or decal.uv.x > 1.0
		or decal.uv.y < 0.0
		or decal.uv.y > 1.0
	):
		return null
	if decal.size <= 0.0 or decal.size > MAX_SIZE:
		return null
	if words.size() == 7:
		if decal.kind != &"number" or not words[6].begins_with("n="):
			return null
		var figure: String = words[6].trim_prefix("n=")
		if not figure.is_valid_int() or figure.to_int() < 0 or figure.to_int() > MAX_NUMBER:
			return null
		decal.number = figure.to_int()
	return decal if (decal.kind == &"number") == (decal.number >= 0) else null
