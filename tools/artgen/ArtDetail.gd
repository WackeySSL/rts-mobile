class_name ArtDetail
extends RefCounted
## The detail renderer (ADR 0050 section 1, plan row P631): the faces `ArtRender` draws, dressed
## with more ink. `ArtModel.detail` (0 to 3) sets the level of a model, a primitive's `detail=`
## overrides it. Every extra sits right after the face it dresses, so the draw order is the
## body's. Nothing here is random: each variation is a hash of the art id and the primitive's key
## (`ArtDamage.line_hash`), so two runs give the same bytes. P601's `ArtDetail` was the reference.
##
## What each level may add (nothing is added to a sphere, a rod or a `broken` box):
##   0  nothing: the output is `ArtRender`'s, byte for byte. Elements: svg, g, polygon.
##   1  panel seams: thin black polygons (fill-opacity) along 0.3 tile cells on quad faces.
##      Elements: svg, g, polygon.
##   2  1 plus: cell tints, bolts on small faces (0.04 to 0.25 tile2), the face decals of the model
##      (`ArtDecal`: number, hazard, vent), and metal sheen: a `linearGradient` in `defs` as the
##      fill of a lit (top or left) metal face of 12 x 12 px or more. Elements: svg, defs,
##      linearGradient, stop, g, polygon.
##   3  2 plus: bevels (a light upper and a dark lower edge strip) and contact bands at the foot
##      of vertical faces. Elements as 2. Chips and grime are off (noise at far zoom).
## A key colour is never in a gradient (sheen is for metal materials only), and every extra on a
## key face is black or white at some opacity, so the bake's key swap needs nothing here.
## A gradient is a fill the writer resolves: `sheen_ids` names them `s0`, `s1` ... in first use,
## `defs` writes them (`ArtSvg.frame`); equal stop pairs share one id.

const SHEEN: String = "sheen:"
const SOLIDS: Array[StringName] = [&"box", &"wedge", &"prism"]
const NONE: Array[StringName] = [&"lamp", &"glass", &"mint", &"hole", &"interior"]
const METAL: Array[StringName] = [
	&"steel",
	&"iron",
	&"olive",
	&"titanium",
	&"graphite",
	&"bluegrey",
	&"ceramic",
	&"rust",
	&"beam",
	&"gunmetal",
	&"gunsteel",
	&"gunbody",
]
const CELL_TILES: float = 0.3  ## A panel cell, the tanks' size (ADR 0050 section 1).
const SEAM_PX: float = 1.2
const MIN_PANEL_PX: float = 8.0
const MIN_SHEEN_PX: float = 12.0
const BOLT_AREA: Vector2 = Vector2(0.04, 0.25)  ## Faces in tiles2 that carry bolts.
const HAZARD_TILES: float = 0.08  ## A stripe, 7 px at 2x.
const PAINT_NUMBER: String = "#E9E5D6"
const PAINT_HAZARD: String = "#D8C428"
const CONTACT: Array[Vector2] = [Vector2(0.38, 0.07), Vector2(0.24, 0.09), Vector2(0.12, 0.12)]
## A seven-segment digit in a unit cell: a to g as x0 y0 x1 y1 (y up), and the segments of 0 to 9.
const SEGMENTS: Array[Rect2] = [
	Rect2(0.1, 0.82, 0.8, 0.18),
	Rect2(0.72, 0.52, 0.18, 0.38),
	Rect2(0.72, 0.1, 0.18, 0.38),
	Rect2(0.1, 0.0, 0.8, 0.18),
	Rect2(0.1, 0.1, 0.18, 0.38),
	Rect2(0.1, 0.52, 0.18, 0.38),
	Rect2(0.1, 0.41, 0.8, 0.18),
]
const DIGITS: Array[String] = [
	"abcdef", "bc", "abdeg", "abcdg", "bcfg", "acdfg", "acdefg", "abc", "abcdefg", "abcdfg"
]


## One quad face on screen: its points, the lengths of its two edges in tiles (`lu`, `lv`) and px.
class Quad:
	extends RefCounted
	var sp: PackedVector2Array = PackedVector2Array()
	var lu: float = 0.0
	var lv: float = 0.0
	var su: float = 0.0
	var sv: float = 0.0

	func at(u: float, v: float) -> Vector2:
		return (
			sp[0] * (1.0 - u) * (1.0 - v)
			+ sp[1] * u * (1.0 - v)
			+ sp[2] * u * v
			+ sp[3] * (1.0 - u) * v
		)


## The polygons of `prims` at `yaw` as `ArtRender.render` draws them, plus the detail of each
## primitive's level (its own `detail=`, else the model's). With no level above 0 they are
## `ArtRender`'s and nothing else.
static func render(
	model: ArtModel, prims: Array[ArtPrim], yaw: float, rest: Array[ArtPrim] = []
) -> Array[ArtRender.Poly]:
	var base: Array[ArtRender.Poly] = ArtRender.render(prims, yaw, model.faction, rest)
	var top: int = model.detail
	for prim: ArtPrim in prims:
		top = maxi(top, prim.detail)
	if top <= 0:
		return base
	var decals: Array[ArtDecal] = []
	for line: String in model.decals:
		decals.append(ArtDecal.parse(line))
	var out: Array[ArtRender.Poly] = []
	var meshes: Dictionary = {}
	for poly: ArtRender.Poly in base:
		out.append(poly)
		var prim: ArtPrim = prims[poly.prim] if poly.prim >= 0 else null
		var level: int = 0 if prim == null else _level(model, prim)
		if level <= 0 or prim.shape not in SOLIDS or prim.material in NONE:
			continue
		if not meshes.has(poly.prim):
			meshes[poly.prim] = ArtMesh.faces(prim)
		for face: ArtMesh.Face in meshes[poly.prim]:
			if _same(face, poly, yaw):
				var first: int = out.size()
				_dress(out, poly, prim, face, level, yaw, model, decals)
				for extra: int in range(first, out.size()):
					out[extra].prim = poly.prim
				break
	return out


## The level a primitive is drawn at.
static func _level(model: ArtModel, prim: ArtPrim) -> int:
	return clampi(prim.detail if prim.detail >= 0 else model.detail, 0, ArtPrim.MAX_DETAIL)


## Whether `poly` is the drawing of `face` (the same points in the same order).
static func _same(face: ArtMesh.Face, poly: ArtRender.Poly, yaw: float) -> bool:
	if face.points.size() != poly.points.size():
		return false
	for i: int in face.points.size():
		var at: Vector2 = ArtRender.project(ArtRender.rotate(face.points[i], yaw))
		if not at.is_equal_approx(poly.points[i]):
			return false
	return true


static func _dress(
	out: Array[ArtRender.Poly],
	poly: ArtRender.Poly,
	prim: ArtPrim,
	face: ArtMesh.Face,
	level: int,
	yaw: float,
	model: ArtModel,
	decals: Array[ArtDecal]
) -> void:
	var shade: int = ArtRender.level(ArtRender.rotate(face.normal, yaw))
	if (
		level >= 2
		and prim.material in METAL
		and shade != ArtPalette.RIGHT
		and _span(poly.points, MIN_SHEEN_PX)
	):
		poly.fill = _sheen(model.faction, prim, shade)
	if poly.points.size() != 4:
		return
	var quad: Quad = Quad.new()
	quad.sp = poly.points
	quad.lu = face.points[0].distance_to(face.points[1])
	quad.lv = face.points[0].distance_to(face.points[3])
	quad.su = quad.sp[0].distance_to(quad.sp[1])
	quad.sv = quad.sp[0].distance_to(quad.sp[3])
	var key: int = prim.key() * 16 + face.points.size()
	if quad.su >= MIN_PANEL_PX and quad.sv >= MIN_PANEL_PX:
		_panels(out, quad, prim, key, level)
		if level >= 2 and quad.lu * quad.lv >= BOLT_AREA.x and quad.lu * quad.lv <= BOLT_AREA.y:
			_bolts(out, quad, prim, key)
	if level >= 3:
		_bevel(out, quad)
		_contact(out, quad, face)
	if level >= 2:
		for decal: ArtDecal in decals:
			if decal != null and decal.prim == prim.index and decal.face == _name(face.normal):
				_decal(out, decal, face, yaw, shade, prim)


## Seams along the cells of a face, and at level 2 a tint on some cells.
static func _panels(
	out: Array[ArtRender.Poly], quad: Quad, prim: ArtPrim, key: int, level: int
) -> void:
	var nu: int = maxi(1, roundi(quad.lu / CELL_TILES))
	var nv: int = maxi(1, roundi(quad.lv / CELL_TILES))
	if nu * nv < 2 or quad.lu * quad.lv < 0.03:
		return
	var pu: float = SEAM_PX * 0.5 / quad.su
	var pv: float = SEAM_PX * 0.5 / quad.sv
	for i: int in range(1, nu):
		var u: float = float(i) / nu
		out.append(_ink(_rect(quad, u - pu, 0.0, u + pu, 1.0), "#000000", "0.25"))
	for j: int in range(1, nv):
		var v: float = float(j) / nv
		out.append(_ink(_rect(quad, 0.0, v - pv, 1.0, v + pv), "#000000", "0.25"))
	if level < 2:
		return
	for i: int in nu:
		for j: int in nv:
			var roll: float = _unit(prim.seed, key * 64 + i * 8 + j)
			if roll < 0.3:
				var white: bool = roll < 0.15
				var cell: PackedVector2Array = _rect(
					quad,
					float(i) / nu + pu,
					float(j) / nv + pv,
					float(i + 1) / nu - pu,
					float(j + 1) / nv - pv
				)
				out.append(_ink(cell, "#FFFFFF" if white else "#000000", "0.06"))


## Two bolts on opposite corners of a small face, on the diagonal the hash picks.
static func _bolts(out: Array[ArtRender.Poly], quad: Quad, prim: ArtPrim, key: int) -> void:
	var flip: bool = _unit(prim.seed, key * 64 + 63) < 0.5
	for corner: Vector2 in [
		Vector2(0.14, 0.14 if not flip else 0.86), Vector2(0.86, 0.86 if not flip else 0.14)
	]:
		var at: Vector2 = quad.at(corner.x, corner.y)
		var dot: PackedVector2Array = PackedVector2Array(
			[
				at + Vector2(-1.1, 0),
				at + Vector2(0, -1.1),
				at + Vector2(1.1, 0),
				at + Vector2(0, 1.1)
			]
		)
		out.append(_ink(dot, "#000000", "0.45"))


## A light strip along the highest edge of a face and a dark one along the lowest.
static func _bevel(out: Array[ArtRender.Poly], quad: Quad) -> void:
	if quad.su < 10.0 or quad.sv < 6.0:
		return
	var centre: Vector2 = quad.at(0.5, 0.5)
	var high: int = 0
	var low: int = 0
	for e: int in 4:
		var mid: float = (quad.sp[e].y + quad.sp[(e + 1) % 4].y) * 0.5
		if mid < (quad.sp[high].y + quad.sp[(high + 1) % 4].y) * 0.5:
			high = e
		if mid > (quad.sp[low].y + quad.sp[(low + 1) % 4].y) * 0.5:
			low = e
	for edge: Array in [[high, "#FFFFFF", "0.3"], [low, "#000000", "0.28"]]:
		var a: Vector2 = quad.sp[edge[0]]
		var b: Vector2 = quad.sp[(edge[0] + 1) % 4]
		var inward: Vector2 = (centre - (a + b) * 0.5).normalized() * 1.3
		out.append(_ink(PackedVector2Array([a, b, b + inward, a + inward]), edge[1], edge[2]))


## Three stepped bands of occlusion at the foot of a vertical face that stands on the ground.
static func _contact(out: Array[ArtRender.Poly], quad: Quad, face: ArtMesh.Face) -> void:
	var p: PackedVector3Array = face.points
	if absf(face.normal.z) > 0.3 or p[0].z > 0.06 or absf(p[0].z - p[1].z) > 0.01:
		return
	if p[3].z - p[0].z < 0.06:
		return
	for step: Vector2 in CONTACT:
		var band: PackedVector2Array = PackedVector2Array(
			[
				quad.sp[0],
				quad.sp[1],
				quad.sp[1].lerp(quad.sp[2], step.x),
				quad.sp[0].lerp(quad.sp[3], step.x),
			]
		)
		out.append(_ink(band, "#000000", "%.2f" % step.y))


## The fill of a lit metal face: its tone at the top and at the bottom of the face, both from the
## material's own ladder (`sheen:<top>:<bottom>`; the writer names it).
static func _sheen(faction: StringName, prim: ArtPrim, shade: int) -> String:
	var here: Color = Color(ArtPalette.tone(faction, prim.material, shade))
	var upper: Color = (
		here.lerp(Color.WHITE, 0.1)
		if shade == ArtPalette.TOP
		else here.lerp(Color(ArtPalette.tone(faction, prim.material, ArtPalette.TOP)), 0.5)
	)
	var lower: Color = here.lerp(Color(ArtPalette.tone(faction, prim.material, shade + 1)), 0.5)
	var hexes: PackedStringArray = PackedStringArray()
	for colour: Color in [upper, lower]:
		var hex: String = "#" + colour.to_html(false).to_upper()
		hexes.append(ArtRender._scorch(prim, hex))
	return SHEEN + ":".join(hexes)


## The face a normal belongs to, as `ArtDecal.FACES` says it.
static func _name(normal: Vector3) -> StringName:
	if normal.z > 0.5:
		return &"top"
	if absf(normal.x) >= absf(normal.y):
		return &"front" if normal.x > 0.0 else &"back"
	return &"right" if normal.y > 0.0 else &"left"


## One decal on `face`. The face's first edge is `u` and its fourth point's edge is `v` (up on a
## side, so a figure reads upright and from outside); `uv` is the centre, `size` the width in
## tiles, and the whole decal is scaled down to 90 % of the face when it is larger.
static func _decal(
	out: Array[ArtRender.Poly],
	decal: ArtDecal,
	face: ArtMesh.Face,
	yaw: float,
	shade: int,
	prim: ArtPrim
) -> void:
	var p0: Vector3 = face.points[0]
	var eu: Vector3 = face.points[1] - p0
	var ev: Vector3 = face.points[3] - p0
	var digits: String = str(decal.number) if decal.kind == &"number" else ""
	var w: float = decal.size
	var h: float = {&"number": w / maxi(digits.length(), 1) * 1.7, &"hazard": w * 0.6}.get(
		decal.kind, w * 0.7
	)
	var fit: float = minf(1.0, minf(0.9 * eu.length() / w, 0.9 * ev.length() / h))
	w *= fit
	h *= fit
	var centre: Vector2 = Vector2(
		clampf(decal.uv.x, w / 2.0 / eu.length(), 1.0 - w / 2.0 / eu.length()),
		clampf(decal.uv.y, h / 2.0 / ev.length(), 1.0 - h / 2.0 / ev.length())
	)
	var map: Callable = func(x: float, y: float) -> Vector2:
		var u: float = centre.x + (x - 0.5) * w / eu.length()
		var v: float = centre.y + (y - 0.5) * h / ev.length()
		return ArtRender.project(ArtRender.rotate(p0 + eu * u + ev * v, yaw))
	var box: Callable = func(r: Rect2) -> PackedVector2Array:
		return PackedVector2Array(
			[
				map.call(r.position.x, r.position.y),
				map.call(r.end.x, r.position.y),
				map.call(r.end.x, r.end.y),
				map.call(r.position.x, r.end.y)
			]
		)
	match decal.kind:
		&"number":
			for i: int in digits.length():
				for seg: int in 7:
					if "abcdefg"[seg] in DIGITS[int(digits[i])]:
						var cell: Rect2 = SEGMENTS[seg]
						var r: Rect2 = Rect2(
							(i + cell.position.x) / digits.length(),
							cell.position.y,
							cell.size.x / digits.length(),
							cell.size.y
						)
						out.append(_ink(box.call(r), _paint(PAINT_NUMBER, shade, prim), ""))
		&"hazard":
			out.append(_ink(box.call(Rect2(0, 0, 1, 1)), "#000000", "0.6"))
			_stripes(out, w, h, _paint(PAINT_HAZARD, shade, prim), map)
		_:
			out.append(_ink(box.call(Rect2(0, 0, 1, 1)), "#000000", "0.35"))
			for slot: int in 4:
				out.append(
					_ink(box.call(Rect2(0.1, 0.12 + slot * 0.22, 0.8, 0.1)), "#000000", "0.55")
				)


## Slanted bands of `HAZARD_TILES` across the unit square of a decal that is `w` x `h` tiles.
static func _stripes(
	out: Array[ArtRender.Poly], w: float, h: float, paint: String, map: Callable
) -> void:
	var unit: PackedVector2Array = PackedVector2Array(
		[Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	)
	var period: float = HAZARD_TILES * 2.0
	for k: int in ceili((w + h) / period) + 1:
		var t0: float = k * period - h
		var band: PackedVector2Array = PackedVector2Array(
			[
				Vector2(t0 / w, 0.0),
				Vector2((t0 + HAZARD_TILES) / w, 0.0),
				Vector2((t0 + HAZARD_TILES + h) / w, 1.0),
				Vector2((t0 + h) / w, 1.0)
			]
		)
		for piece: PackedVector2Array in Geometry2D.intersect_polygons(band, unit):
			var mapped: PackedVector2Array = PackedVector2Array()
			for at: Vector2 in piece:
				mapped.append(map.call(at.x, at.y))
			if mapped.size() >= 3:
				out.append(_ink(mapped, paint, ""))


## `hex` painted on a face of level `shade`: the paint at that level's share of the top tone.
static func _paint(hex: String, shade: int, prim: ArtPrim) -> String:
	var k: float = ArtPalette.SHADES[shade]
	var c: Color = Color(hex)
	var lit: String = "#" + Color(c.r * k, c.g * k, c.b * k).to_html(false).to_upper()
	return ArtRender._scorch(prim, lit)


## The rectangle of `quad` from (u0, v0) to (u1, v1) as a polygon.
static func _rect(quad: Quad, u0: float, v0: float, u1: float, v1: float) -> PackedVector2Array:
	return PackedVector2Array([quad.at(u0, v0), quad.at(u1, v0), quad.at(u1, v1), quad.at(u0, v1)])


## An extra polygon without an edge, at `opacity` (empty for solid).
static func _ink(points: PackedVector2Array, fill: String, opacity: String) -> ArtRender.Poly:
	var poly: ArtRender.Poly = ArtRender.Poly.new()
	poly.points = points
	poly.fill = fill
	poly.fill_opacity = opacity
	return poly


## Whether the points span `px` in both directions.
static func _span(points: PackedVector2Array, px: float) -> bool:
	var box: Rect2 = Rect2(points[0], Vector2.ZERO)
	for at: Vector2 in points:
		box = box.expand(at)
	return box.size.x >= px and box.size.y >= px


## A number 0 to 1 from the art seed and a key.
static func _unit(seed: int, key: int) -> float:
	return float(ArtDamage.line_hash(seed, key) & 0xFFFF) / 65535.0


## The sheen fills of `polys` (`sheen:<top>:<bottom>`) mapped to `url(#sN)`, ids in first use.
static func sheen_ids(polys: Array[ArtRender.Poly]) -> Dictionary[String, String]:
	var ids: Dictionary[String, String] = {}
	for poly: ArtRender.Poly in polys:
		if poly.fill.begins_with(SHEEN) and not ids.has(poly.fill):
			ids[poly.fill] = "url(#s%d)" % ids.size()
	return ids


## The `defs` lines of `ids`: one vertical `linearGradient` per entry, two stops each.
static func defs(ids: Dictionary[String, String]) -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	if ids.is_empty():
		return lines
	lines.append("<defs>")
	for fill: String in ids:
		var stops: PackedStringArray = fill.trim_prefix(SHEEN).split(":")
		lines.append(
			(
				'<linearGradient id="%s" x1="0" y1="0" x2="0" y2="1">'
				% ids[fill].trim_prefix("url(#").trim_suffix(")")
			)
		)
		lines.append('<stop offset="0" stop-color="%s"/>' % stops[0])
		lines.append('<stop offset="1" stop-color="%s"/>' % stops[1])
		lines.append("</linearGradient>")
	lines.append("</defs>")
	return lines
