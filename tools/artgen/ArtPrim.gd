class_name ArtPrim
extends RefCounted
## One primitive of an `ArtModel` (ADR 0023 section 5), parsed from one line of its `prims`:
##
##   <shape> <part> <material> <cx> <cy> <z0> <sx> <sy> <sz> [sides=N] [taper=T] [slope=S] [axis=A]
##                                                          [group=NAME] [damage=K]
##
## Lengths are tiles in the model's frame (a unit faces +x; a building's origin is its footprint's
## centre). `cx cy` is the centre on the ground, `z0` the bottom, `sx sy sz` the extent along x, y
## and z. Shapes: `box`; `wedge`, a box whose top slopes down towards +x by `slope` (default 1);
## `prism`, a ring of `sides` (default 12, width across the flats) that `taper` scales at the top
## and `axis` (x, y or z, default z) lays along its length (sx, sy or sz); `sphere` of diameter sx.
## `damage=K` (1 or 2, a hull primitive of a building) draws the primitive only from damage stage K
## on, so the intact picture has none of them (ADR 0028 section 3).
## `group` names the pose group the primitive belongs to (ADR 0027 section 4): a pose moves the
## primitives of a group together, see `ArtMove`. `moved` returns the primitive as a pose frame
## places it, which `aabb`, `ArtMesh.faces` and `ArtRender` all read.

const SHAPES: Array[StringName] = [&"box", &"wedge", &"prism", &"sphere"]
const PARTS: Array[StringName] = [&"hull", &"turret", &"head"]
## The moving element of a building (or of a vehicle): only the pose part `anim` draws it, and it
## is not a part with frames of its own.
const ANIM: StringName = &"anim"
const ALL_PARTS: Array[StringName] = [&"hull", &"turret", &"head", &"anim"]
const AXES: String = "xyz"
const FIELDS: int = 9

var shape: StringName = &"box"
var part: StringName = &"hull"
var material: StringName = &""
var centre: Vector2 = Vector2.ZERO
var z0: float = 0.0
var size: Vector3 = Vector3.ONE
var sides: int = 4
var taper: float = 1.0
var slope: float = 0.0
var axis: int = 2
var group: StringName = &""
var damage: int = 0  ## The stage it appears from; 0 is always drawn.
var hidden: bool = false  ## A `hide` move of a damage pose: not drawn.
var char_percent: float = 0.0  ## A `char` move: faces mixed this far towards the char colour.
var line: String = ""  ## What it was parsed from, which `moved` parses again.
var moves: Array[ArtMove] = []  ## Applied in order after the rest placement; see `moved`.


## The primitive of a line, or null when the line is not one (a wrong count, an unknown shape or
## part, a number that is not one, an option that does not belong).
static func parse(line: String) -> ArtPrim:
	var words: PackedStringArray = line.split(" ", false)
	if words.size() < FIELDS or StringName(words[0]) not in SHAPES:
		return null
	if StringName(words[1]) not in ALL_PARTS:
		return null
	var prim: ArtPrim = ArtPrim.new()
	prim.line = line
	prim.shape = StringName(words[0])
	prim.part = StringName(words[1])
	prim.material = StringName(words[2])
	var nums: PackedFloat64Array = PackedFloat64Array()
	for i: int in range(3, FIELDS):
		if not words[i].is_valid_float():
			return null
		nums.append(words[i].to_float())
	prim.centre = Vector2(nums[0], nums[1])
	prim.z0 = nums[2]
	prim.size = Vector3(nums[3], nums[4], nums[5])
	if prim.size.x <= 0.0 or prim.size.y <= 0.0 or prim.size.z <= 0.0:
		return null
	if prim.shape == &"wedge":
		prim.slope = 1.0
	prim.sides = 12 if prim.shape == &"prism" else 4
	for i: int in range(FIELDS, words.size()):
		if not prim._set_option(words[i]):
			return null
	return prim


## The box that holds the primitive, in the model's frame, after its moves (the box of the moved
## corners of the rest box).
func aabb() -> AABB:
	var box: AABB = _rest_box()
	if moves.is_empty():
		return box
	var moved_box: AABB = AABB(place(box.position), Vector3.ZERO)
	for i: int in 8:
		var corner: Vector3 = box.get_endpoint(i)
		moved_box = moved_box.expand(place(corner))
	return moved_box


## The primitive as a pose frame places it: a new one, parsed from its line again, that carries
## `by`'s moves of its group, or this one when it has no group or none of the moves is for it.
func moved(by: Array[ArtMove]) -> ArtPrim:
	var mine: Array[ArtMove] = []
	for move: ArtMove in by:
		if group != &"" and move.group == group:
			mine.append(move)
	if mine.is_empty():
		return self
	var copy: ArtPrim = ArtPrim.parse(line)
	copy.moves = mine
	for move: ArtMove in mine:
		copy.hidden = copy.hidden or move.kind == &"hide"
		if move.kind == &"char":
			copy.char_percent = maxf(copy.char_percent, move.char_percent)
	return copy


## `point` of the model's frame after the moves.
func place(point: Vector3) -> Vector3:
	for move: ArtMove in moves:
		point = move.place(point)
	return point


## A direction (a face's normal) after the moves: only their turns act on it.
func spin(direction: Vector3) -> Vector3:
	for move: ArtMove in moves:
		direction = move.spin(direction)
	return direction


## The box of the primitive at rest. A ring of 6 (or any count that has no vertex on the ring's
## second axis) is longer along it than its size says; the box allows for that.
func _rest_box() -> AABB:
	var s: Vector3 = size
	if shape == &"prism":
		var f: Vector2 = Vector2.ZERO
		for i: int in sides:
			var a: float = (i + 0.5) * TAU / sides
			f = f.max(Vector2(absf(cos(a)), absf(sin(a))))
		f *= 1.0 / cos(PI / sides)
		match axis:
			0:
				s = Vector3(s.x, s.y * f.x, s.z * f.y)
			1:
				s = Vector3(s.x * f.y, s.y, s.z * f.x)
			_:
				s = Vector3(s.x * f.x, s.y * f.y, s.z)
	return AABB(Vector3(centre.x - s.x / 2.0, centre.y - s.y / 2.0, z0 + (size.z - s.z) / 2.0), s)


## Applies one `key=value` option; false when the key or the value is not allowed for the shape.
func _set_option(word: String) -> bool:
	var pair: PackedStringArray = word.split("=")
	if pair.size() != 2 or not (pair[1].is_valid_float() or pair[0] in ["axis", "group"]):
		return false
	var value: float = pair[1].to_float()
	var allowed: bool = false
	match pair[0]:
		"axis":
			axis = AXES.find(pair[1])
			allowed = pair[1].length() == 1 and axis >= 0 and shape == &"prism"
		"sides":
			sides = int(value)
			allowed = shape == &"prism" and sides >= 3 and sides <= 24
		"group":
			group = StringName(pair[1])
			allowed = pair[1].is_valid_identifier()
		"damage":
			damage = int(value)
			allowed = pair[1].is_valid_int() and damage >= 1 and damage <= 2
		"taper":
			taper = value
			allowed = taper > 0.0 and shape != &"sphere"
		"slope":
			slope = value
			allowed = absf(slope) <= 1.0 and shape in [&"box", &"wedge"]
	return allowed
