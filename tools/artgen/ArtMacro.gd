class_name ArtMacro
extends RefCounted
## Macro lines of a model's `prims` (ADR 0050 section 1, P630): one line that `ArtPrim.parse_all`
## expands to several box and prism primitives, as `petals` does, so a model gets shorter. They add
## no drawing code: what a macro draws is what its primitives draw.
##
##   <macro> <part> <material> <cx> <cy> <z0> <sx> <sy> <sz> [<option>=<value> ...]
##
## `cx cy z0 sx sy sz` are the macro's box, as for a primitive. Every macro takes `group`, `damage`
## and `detail`, which its primitives all carry, and:
##   tracks   a belt box with `wheels=N` (2 to 12, default 5) road wheels, `wheel=<material>`
##            (default the belt's); sx is the length, sy the width, sz the height
##   wheels   `n=N` (1 to 8, default 2) axles over the length sx, a wheel on each side of the gauge
##            sy (the width over both), of diameter sz and `w=<tiles>` wide (default 0.1)
##   grille   a plate with `bars=N` (2 to 16, default 4) slats on it, `bar=<material>`; the slats
##            run along the longer of sx and sy
##   hatch    a ring and its lid, `lid=<material>`; a round one, so sx equals sy (the diameter)
##   pylon    a foot, a tapering shaft (`taper=T`, default 0.7) and a `cap=<material>` head

const NAMES: Array[StringName] = [&"tracks", &"wheels", &"grille", &"hatch", &"pylon"]
const COMMON: PackedStringArray = ["group", "damage", "detail"]
## The options each macro has besides the common ones.
const OPTIONS: Dictionary = {
	"tracks": ["wheels", "wheel"],
	"wheels": ["n", "w"],
	"grille": ["bars", "bar"],
	"hatch": ["lid"],
	"pylon": ["taper", "cap"],
}
const MATERIAL_OPTIONS: PackedStringArray = ["wheel", "bar", "lid", "cap"]
const DEFAULT_GRILLE_BARS: int = 4
const DEFAULT_WHEEL_WIDTH: float = 0.1
const DEFAULT_TAPER: float = 0.7


## The primitives of a macro line, each parsed from a box or prism line of its own, with `sub` 1, 2,
## ... and `source` the macro line; empty when the line is not a valid macro.
static func expand(line: String) -> Array[ArtPrim]:
	var words: PackedStringArray = line.split(" ", false)
	var none: Array[ArtPrim] = []
	if words.size() < ArtPrim.FIELDS or StringName(words[0]) not in NAMES:
		return none
	if StringName(words[1]) not in ArtPrim.ALL_PARTS:
		return none
	var n: PackedFloat64Array = PackedFloat64Array()
	for i: int in range(3, ArtPrim.FIELDS):
		if not words[i].is_valid_float():
			return none
		n.append(words[i].to_float())
	if n[3] <= 0.0 or n[4] <= 0.0 or n[5] <= 0.0:
		return none
	var opts: Dictionary[String, String] = {}
	var common: Array[String] = []
	var seen: Dictionary[String, bool] = {}
	for i: int in range(ArtPrim.FIELDS, words.size()):
		var pair: PackedStringArray = words[i].split("=")
		if pair.size() != 2 or seen.has(pair[0]):
			return none
		seen[pair[0]] = true
		if pair[0] in COMMON:
			common.append(words[i])
		elif pair[0] in (OPTIONS[words[0]] as Array):
			opts[pair[0]] = pair[1]
		else:
			return none
		if pair[0] not in MATERIAL_OPTIONS and pair[0] not in ["group"]:
			if not pair[1].is_valid_float():
				return none
	var lines: Array[String] = _lines(StringName(words[0]), words[1], words[2], n, opts)
	var found: Array[ArtPrim] = []
	var tail: String = " ".join(common)
	for k: int in lines.size():
		var prim: ArtPrim = ArtPrim.parse((lines[k] + " " + tail).strip_edges())
		if prim == null:
			return none
		prim.sub = k + 1
		prim.source = line
		found.append(prim)
	return found


## The primitive lines of a macro, [] when its numbers or options are out of range.
static func _lines(
	name: StringName,
	part: String,
	mat: String,
	n: PackedFloat64Array,
	o: Dictionary[String, String]
) -> Array[String]:
	var c: Vector3 = Vector3(n[0], n[1], n[2])
	var s: Vector3 = Vector3(n[3], n[4], n[5])
	var lines: Array[String] = []
	match name:
		&"tracks":
			var count: int = int(o.get("wheels", "5"))
			if count < 2 or count > 12:
				return lines
			lines.append(_box(part, mat, c, s))
			var d: float = minf(s.z * 0.8, s.x / count * 0.9)
			for i: int in count:
				var x: float = c.x - s.x / 2.0 + s.x * (i + 0.5) / count
				lines.append(
					_ring(
						part,
						o.get("wheel", mat),
						Vector3(x, c.y, c.z + (s.z - d) / 2.0),
						d,
						s.y * 1.04
					)
				)
		&"wheels":
			var axles: int = int(o.get("n", "2"))
			var width: float = float(o.get("w", str(DEFAULT_WHEEL_WIDTH)))
			if axles < 1 or axles > 8 or width <= 0.0 or width * 2.0 >= s.y or s.z > s.x:
				return lines
			for i: int in axles:
				var x: float = (
					c.x
					if axles == 1
					else c.x - s.x / 2.0 + s.z / 2.0 + (s.x - s.z) * i / (axles - 1)
				)
				for side: float in [-1.0, 1.0]:
					var y: float = c.y + side * (s.y - width) / 2.0
					lines.append(_ring(part, mat, Vector3(x, y, c.z), s.z, width))
		&"grille":
			var bars: int = int(o.get("bars", str(DEFAULT_GRILLE_BARS)))
			if bars < 2 or bars > 16:
				return lines
			var plate: float = s.z * 0.4
			lines.append(_box(part, mat, c, Vector3(s.x, s.y, plate)))
			var along_x: bool = s.x >= s.y
			var pitch: float = (s.y if along_x else s.x) / bars
			for i: int in bars:
				var off: float = -(s.y if along_x else s.x) / 2.0 + pitch * (i + 0.5)
				var at: Vector3 = (
					Vector3(c.x, c.y + off, c.z + plate)
					if along_x
					else Vector3(c.x + off, c.y, c.z + plate)
				)
				var size: Vector3 = (
					Vector3(s.x, pitch * 0.5, s.z - plate)
					if along_x
					else Vector3(pitch * 0.5, s.y, s.z - plate)
				)
				lines.append(_box(part, o.get("bar", mat), at, size))
		&"hatch":
			if not is_equal_approx(s.x, s.y):
				return lines
			lines.append(
				(
					"prism %s %s %s %s %s %s %s %s sides=12"
					% _f([part, mat, c.x, c.y, c.z, s.x, s.y, s.z * 0.6])
				)
			)
			lines.append(
				(
					"prism %s %s %s %s %s %s %s %s sides=12"
					% _f(
						[
							part,
							o.get("lid", mat),
							c.x,
							c.y,
							c.z + s.z * 0.6,
							s.x * 0.8,
							s.y * 0.8,
							s.z * 0.4
						]
					)
				)
			)
		&"pylon":
			var taper: float = float(o.get("taper", str(DEFAULT_TAPER)))
			if taper <= 0.0:
				return lines
			lines.append(_box(part, mat, c, Vector3(s.x, s.y, s.z * 0.2)))
			lines.append(
				(
					"box %s %s %s %s %s %s %s %s taper=%s"
					% _f(
						[
							part,
							mat,
							c.x,
							c.y,
							c.z + s.z * 0.2,
							s.x * 0.6,
							s.y * 0.6,
							s.z * 0.65,
							taper
						]
					)
				)
			)
			lines.append(
				_box(
					part,
					o.get("cap", mat),
					Vector3(c.x, c.y, c.z + s.z * 0.85),
					Vector3(s.x * 0.5, s.y * 0.5, s.z * 0.15)
				)
			)
	return lines


static func _box(part: String, mat: String, at: Vector3, size: Vector3) -> String:
	return "box %s %s %s %s %s %s %s %s" % _f([part, mat, at.x, at.y, at.z, size.x, size.y, size.z])


## A wheel: a 10-sided ring of `diameter`, `width` along y, its bottom at `at.z`.
static func _ring(part: String, mat: String, at: Vector3, diameter: float, width: float) -> String:
	return (
		"prism %s %s %s %s %s %s %s %s sides=10 axis=y"
		% _f([part, mat, at.x, at.y, at.z, diameter, width, diameter])
	)


## `values` with every number written with four decimals at most, so a line is always the same.
static func _f(values: Array) -> Array:
	var out: Array = []
	for v: Variant in values:
		out.append(String.num(v, 4) if v is float else v)
	return out
