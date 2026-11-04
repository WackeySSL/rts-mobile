class_name ArtPrim
extends RefCounted
## One primitive of an `ArtModel` (ADR 0023 section 5), parsed from one line of its `prims`:
##
##   <shape> <part> <material> <cx> <cy> <z0> <sx> <sy> <sz> [sides=N] [taper=T] [slope=S] [axis=A]
##                                              [teeth=N] [low=F] [group=NAME] [damage=K]
##   rod <part> <material> <x0> <y0> <z0> <x1> <y1> <z1> <width> [bend=DEG] [group=NAME]
##                                              [damage=K]
##   petals <part> <material> <cx> <cy> <z> <diameter> <n> <tilt> [group=NAME] [damage=K]
##
## Lengths are tiles in the model's frame (a unit faces +x; a building's origin is its footprint's
## centre). `cx cy` is the centre on the ground, `z0` the bottom, `sx sy sz` the extent along x, y
## and z. Shapes: `box`; `wedge`, a box whose top slopes down towards +x by `slope` (default 1);
## `prism`, a ring of `sides` (default 12, width across the flats) that `taper` scales at the top
## and `axis` (x, y or z, default z) lays along its length (sx, sy or sz); `sphere` of diameter sx;
## `broken`, `rod` and the helper `petals` (generator v5b, below).
## `damage=K` (1 or 2, a hull primitive of a building) draws the primitive only from damage stage K
## on, so the intact picture has none of them (ADR 0028 section 3).
## `group` names the pose group the primitive belongs to (ADR 0027 section 4): a pose moves the
## primitives of a group together, see `ArtMove`. `moved` returns the primitive as a pose frame
## places it, which `aabb`, `ArtMesh.faces` and `ArtRender` all read.

const SHAPES: Array[StringName] = [&"box", &"wedge", &"prism", &"sphere", &"broken", &"rod"]
## `broken` (ADR 0029 section 5, generator v5b) is a box whose top edge, along its longer
## horizontal axis, is a zigzag of `teeth=N` points (2 to 12, default 5) between `low=f` (above 0,
## below 1, default 0.5) and the full height, the heights from a hash of the art id and the line.
## `rod <part> <material> x0 y0 z0 x1 y1 z1 width` is a stroke of `width` art px from one point to
## another with no outline, ordered at its midpoint; `bend=<degrees>` (at most 90) turns the half
## towards x1 y1 z1 about the horizontal axis (up x direction), right-handed: a vertical rod's far
## half swings towards +x, a rod that runs along +x droops. `petals` (hull and anim only) is a
## helper line, `parse_all` expands it into `n` (3 to 16) thin plates round the opening, each turned
## outward by `tilt` degrees (above 0, at most 90) about its base, and an `interior` disc in it.
const PETAL_THICK: float = 0.04
const PETAL_FILL: float = 0.9  ## The share of its sector a plate's width covers.
const MIN_ROD_PX: float = 2.0
const PETAL_DISC: float = 0.03  ## Its height, 2.4 px at 2x.
const PETAL_PARTS: Array[StringName] = [&"hull", &"anim"]
const SUB_STEP: int = 65536  ## `key`: the step of a helper's primitives.
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
var teeth: int = 5  ## `broken`: points on the top edge.
var low: float = 0.5  ## `broken`: the lowest tooth, as a fraction of the height.
var rod_a: Vector3 = Vector3.ZERO  ## `rod`: its ends, in tiles.
var rod_b: Vector3 = Vector3.ZERO
var width: float = 0.0  ## `rod`: its width in art px.
var bend: float = 0.0  ## `rod`: degrees.
var seed: int = 0  ## The djb2 of the art id, set by `ArtModel`: the hash of `broken`.
var fixed: Array[ArtMove] = []  ## Placement before `moves` (the turn of a petal plate).
var sub: int = 0  ## The place of a primitive among those one `petals` line expands to.
var source: String = ""  ## The `petals` line a plate or disc came from.
var index: int = 0  ## The line of the model it was parsed from, set by `ArtModel`.
var line: String = ""  ## What it was parsed from, which `moved` parses again.
var moves: Array[ArtMove] = []  ## Applied in order after the rest placement; see `moved`.


## The primitive of a line, or null when the line is not one (a wrong count, an unknown shape or
## part, a number that is not one, an option that does not belong).
static func parse(line: String) -> ArtPrim:
	var words: PackedStringArray = line.split(" ", false)
	if words.size() < FIELDS or StringName(words[0]) not in SHAPES:
		return null
	if words[0] == "rod":
		return _parse_rod(words, line)
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


## The primitives of a line: `parse`'s one, or the plates and the disc a `petals` line expands to,
## each plate a box line placed by a turn about its base and then about the opening's centre. Empty
## when the line is not valid.
static func parse_all(line: String) -> Array[ArtPrim]:
	var words: PackedStringArray = line.split(" ", false)
	var found: Array[ArtPrim] = []
	if words.size() < 1 or words[0] != "petals":
		var one: ArtPrim = parse(line)
		if one != null:
			found.append(one)
		return found
	if words.size() < 9:
		return found
	for i: int in range(3, 9):
		if not words[i].is_valid_float():
			return found
	var count: int = words[7].to_int()
	var tilt: float = words[8].to_float()
	var diameter: float = words[6].to_float()
	if StringName(words[1]) not in PETAL_PARTS or not words[7].is_valid_int():
		return found
	if count < 3 or count > 16 or diameter <= 0.0 or tilt <= 0.0 or tilt > 90.0:
		return found
	var centre: Vector3 = Vector3(words[3].to_float(), words[4].to_float(), words[5].to_float())
	var opts: String = " ".join(words.slice(9))
	var head: String = "%s %s" % [words[1], words[2]]
	var disc: ArtPrim = parse(
		(
			"prism %s interior %s %s %s %s %s %s sides=16 %s"
			% [words[1], centre.x, centre.y, centre.z, diameter, diameter, PETAL_DISC, opts]
		)
	)
	if disc == null:
		return found
	found.append(disc)
	for k: int in count:
		var plate: ArtPrim = parse(
			(
				"box %s %s %s %s %s %s %s %s"
				% [
					head,
					centre.x + diameter / 2.0,
					centre.y,
					centre.z,
					PETAL_THICK,
					diameter * PI / count * PETAL_FILL,
					diameter / 2.0,
					opts
				]
			)
		)
		if plate == null:
			return []
		var base: Vector3 = Vector3(centre.x + diameter / 2.0, centre.y, centre.z)
		plate.fixed = [ArtMove.turned(1, tilt, base), ArtMove.turned(2, k * 360.0 / count, centre)]
		plate.sub = k + 1
		found.append(plate)
	for prim: ArtPrim in found:
		prim.source = line
	return found


## The box that holds the primitive, in the model's frame, after its moves (the box of the moved
## corners of the rest box). A rod is its midpoint: it is ordered there.
func aabb() -> AABB:
	if shape == &"rod":
		return AABB(place((rod_a + rod_b) / 2.0), Vector3.ZERO)
	var box: AABB = _rest_box()
	if moves.is_empty() and fixed.is_empty():
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
	copy.fixed = fixed
	copy.seed = seed
	copy.index = index
	copy.sub = sub
	copy.source = source
	for move: ArtMove in mine:
		copy.hidden = copy.hidden or move.kind == &"hide"
		if move.kind == &"char":
			copy.char_percent = maxf(copy.char_percent, move.char_percent)
	return copy


## `point` of the model's frame after the moves.
func place(point: Vector3) -> Vector3:
	for move: ArtMove in fixed:
		point = move.place(point)
	for move: ArtMove in moves:
		point = move.place(point)
	return point


## A direction (a face's normal) after the moves: only their turns act on it.
func spin(direction: Vector3) -> Vector3:
	for move: ArtMove in fixed:
		direction = move.spin(direction)
	for move: ArtMove in moves:
		direction = move.spin(direction)
	return direction


## A key of the primitive that is unique in its model (`index` is shared by the primitives of one
## `petals` line; it is the line number for messages). It equals `index` for any other primitive.
func key() -> int:
	return index + sub * SUB_STEP


## What a message calls the primitive: the line it was written in.
func label() -> String:
	return source if source != "" else line


## A rod's points at rest, in tiles: its ends and the middle, where `bend` turns the upper half.
func rod_path() -> PackedVector3Array:
	var middle: Vector3 = (rod_a + rod_b) / 2.0
	var half: Vector3 = rod_b - middle
	if bend == 0.0:
		return PackedVector3Array([rod_a, rod_b])
	var axis: Vector3 = Vector3(0.0, 0.0, 1.0).cross(rod_b - rod_a)
	axis = axis.normalized() if axis.length() > 1e-6 else Vector3(0.0, 1.0, 0.0)
	var turn: Vector2 = ArtMesh.dir(bend)
	half = half * turn.x + axis.cross(half) * turn.y + axis * axis.dot(half) * (1.0 - turn.x)
	return PackedVector3Array([rod_a, middle, middle + half])


## `broken`'s heights at its `teeth` points, as fractions of the height: high and low in turn, each
## from the hash of the art id and the line, between `low` and 1.
func tooth_fractions() -> PackedFloat64Array:
	var found: PackedFloat64Array = PackedFloat64Array()
	for i: int in teeth:
		var r: float = (ArtDamage.line_hash(seed, index * 16 + i) & 0xFFFF) / 65535.0
		found.append(low + (1.0 - low) * ((0.6 + 0.4 * r) if i % 2 == 0 else 0.4 * r))
	return found


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
			allowed = taper > 0.0 and shape in [&"box", &"wedge", &"prism"]
		"teeth":
			teeth = int(value)
			allowed = pair[1].is_valid_int() and teeth >= 2 and teeth <= 12 and shape == &"broken"
		"low":
			low = value
			allowed = low > 0.0 and low < 1.0 and shape == &"broken"
		"bend":
			bend = value
			allowed = absf(bend) <= 90.0 and shape == &"rod"
		"slope":
			slope = value
			allowed = absf(slope) <= 1.0 and shape in [&"box", &"wedge"]
	return allowed


## The rod of a line of 10 words and the options: its ends, its width (at least `MIN_ROD_PX`).
static func _parse_rod(words: PackedStringArray, line: String) -> ArtPrim:
	if words.size() < 10 or StringName(words[1]) not in ALL_PARTS:
		return null
	var nums: PackedFloat64Array = PackedFloat64Array()
	for i: int in range(3, 10):
		if not words[i].is_valid_float():
			return null
		nums.append(words[i].to_float())
	var prim: ArtPrim = ArtPrim.new()
	prim.line = line
	prim.shape = &"rod"
	prim.part = StringName(words[1])
	prim.material = StringName(words[2])
	prim.rod_a = Vector3(nums[0], nums[1], nums[2])
	prim.rod_b = Vector3(nums[3], nums[4], nums[5])
	prim.width = nums[6]
	prim.centre = Vector2(prim.rod_a.x + prim.rod_b.x, prim.rod_a.y + prim.rod_b.y) / 2.0
	prim.z0 = minf(prim.rod_a.z, prim.rod_b.z)
	if prim.rod_a.is_equal_approx(prim.rod_b) or prim.width < MIN_ROD_PX:
		return null
	for i: int in range(10, words.size()):
		if not prim._set_option(words[i]):
			return null
	return prim
