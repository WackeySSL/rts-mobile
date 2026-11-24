class_name ArtDetail
extends RefCounted
## P601 style prototype (exploration, never merged): the same primitives as ArtRender, drawn with
## more ink. Levels: 0 flat three tones (today), 1 continuous face shading, 2 panel cells with
## seams, bolts and hazard stripes, 3 bevels, contact bands, paint chips, grime and ring panels.
## Output is still only svg, g and polygon: no gradient, filter, clip or text.

const TOP_SHADE: float = 1.0
const MID_SHADE: float = 0.82
const LOW_SHADE: float = 0.62
const SEAM: float = 0.5  ## A seam is the panel colour at this factor.
const GAP_PX: float = 1.1  ## Seam width at 2x.
const EMISSIVE: Array[StringName] = [&"glow", &"lamp"]
const PANELLED: Array[StringName] = [
	&"team", &"gunmetal", &"darksteel", &"wornsteel", &"trim", &"hazard"
]
const BOLTED: Array[StringName] = [&"team", &"gunmetal", &"darksteel", &"trim"]
const CELL: Dictionary[StringName, float] = {
	&"team": 0.30, &"gunmetal": 0.22, &"darksteel": 0.2, &"wornsteel": 0.2, &"trim": 0.4
}
const STRIPE_TILES: float = 0.075  ## Hazard stripe width along the face, in tiles.
const MIN_FACE_PX: float = 5.0


## One drawn polygon with the data the PNG bake needs (3D points and normal of a `face`).
class DPoly:
	extends RefCounted
	var points: PackedVector2Array = PackedVector2Array()
	var fill: String = ""
	var stroke: String = ""
	var stroke_px: int = 1
	var opacity: float = 1.0
	var kind: StringName = &"face"
	var prim: int = -1
	var material: StringName = &""
	var pts3: PackedVector3Array = PackedVector3Array()
	var normal: Vector3 = Vector3.ZERO
	var top: bool = false


static func render(
	prims: Array[ArtPrim], yaw: float, faction: StringName, level: int
) -> Array[DPoly]:
	var out: Array[DPoly] = []
	for i: int in ArtRender.draw_order(prims, yaw):
		var prim: ArtPrim = prims[i]
		var sides: Array[DPoly] = []
		var tops: Array[DPoly] = []
		var faces: Array[ArtMesh.Face] = ArtMesh.faces(prim)
		for k: int in faces.size():
			var face: ArtMesh.Face = faces[k]
			var normal: Vector3 = ArtRender.rotate(face.normal, yaw)
			if normal.dot(ArtRender.VIEW) < ArtRender.MIN_FACING:
				continue
			var pts3: PackedVector3Array = PackedVector3Array()
			var sp: PackedVector2Array = PackedVector2Array()
			for point: Vector3 in face.points:
				var turned: Vector3 = ArtRender.rotate(point, yaw)
				pts3.append(turned)
				sp.append(ArtRender.project(turned))
			var is_top: bool = face.normal.z >= 0.5
			var group: Array[DPoly] = _face(prim, i, k, faction, normal, pts3, sp, is_top, level)
			(tops if is_top else sides).append_array(group)
		out.append_array(sides)
		out.append_array(tops)
	return out


static func _shade(normal: Vector3, level: int) -> float:
	var shade: float = ArtRender.LIGHT_BASE + normal.dot(ArtRender.LIGHT)
	if level == 0:
		var lv: int = ArtRender.level(normal)
		return [TOP_SHADE, MID_SHADE, LOW_SHADE][lv]
	return snappedf(clampf(shade, 0.42, 1.04), 0.03)


static func colour(faction: StringName, material: StringName, shade: float) -> Color:
	if material in EMISSIVE:
		return Color(ArtPalette.mid_hex(faction, material)).lightened(0.0)
	if material == ArtPalette.TEAM:
		var keys: Array = ArtPalette.key_override.get(faction, ArtPalette.KEYS[faction])
		var light: Color = Color(keys[0])
		var mid: Color = Color(keys[1])
		var dark: Color = Color(keys[2])
		if shade >= MID_SHADE:
			return mid.lerp(light, clampf((shade - MID_SHADE) / (TOP_SHADE - MID_SHADE), 0.0, 1.0))
		return (
			dark.lerp(mid, clampf((shade - LOW_SHADE) / (MID_SHADE - LOW_SHADE), 0.0, 1.0))
			* (minf(1.0, shade / LOW_SHADE) if shade < LOW_SHADE else 1.0)
		)
	var base: Color = Color(ArtPalette.mid_hex(faction, material))
	var k: float = shade / MID_SHADE
	return Color(
		clampf(base.r * k, 0.0, 1.0), clampf(base.g * k, 0.0, 1.0), clampf(base.b * k, 0.0, 1.0)
	)


static func hex(c: Color) -> String:
	return "#" + c.to_html(false).to_upper()


static func _dark(c: Color, k: float) -> Color:
	return Color(c.r * k, c.g * k, c.b * k)


static func _light(c: Color, k: float) -> Color:
	return c.lerp(Color.WHITE, k)


static func _h(a: int, b: int, c: int, d: int) -> float:
	var v: int = (a * 73856093) ^ (b * 19349663) ^ (c * 83492791) ^ (d * 40503)
	return float(absi(v) % 10007) / 10007.0


static func _bil(sp: PackedVector2Array, u: float, v: float) -> Vector2:
	return (
		sp[0] * (1.0 - u) * (1.0 - v)
		+ sp[1] * u * (1.0 - v)
		+ sp[2] * u * v
		+ sp[3] * (1.0 - u) * v
	)


static func _poly(
	pts: PackedVector2Array, c: Color, kind: StringName, opacity: float = 1.0
) -> DPoly:
	var poly: DPoly = DPoly.new()
	poly.points = pts
	poly.fill = hex(c)
	poly.kind = kind
	poly.opacity = opacity
	poly.stroke_px = 0
	return poly


static func _face(
	prim: ArtPrim,
	pi: int,
	fi: int,
	faction: StringName,
	normal: Vector3,
	pts3: PackedVector3Array,
	sp: PackedVector2Array,
	is_top: bool,
	level: int
) -> Array[DPoly]:
	var mat: StringName = prim.material
	var shade: float = _shade(normal, level)
	var col: Color = colour(faction, mat, shade)
	var out: Array[DPoly] = []
	var base: DPoly = DPoly.new()
	base.points = sp
	base.prim = pi
	base.material = mat
	base.pts3 = pts3
	base.normal = normal
	base.top = is_top
	base.fill = hex(col)
	if mat not in EMISSIVE:
		base.stroke = hex(_light(col, 0.35) if is_top else _dark(col, 0.45))
		if level >= 2:
			base.stroke = hex(_light(col, 0.28) if is_top else _dark(col, 0.4))
	out.append(base)
	if level < 2 or mat not in PANELLED or mat in EMISSIVE:
		return out
	if sp.size() == 4:
		_quad_detail(out, base, prim, pi, fi, faction, mat, col, normal, pts3, sp, is_top, level)
	elif sp.size() >= 5 and is_top:
		_ring_detail(out, base, mat, col, sp, level)
	return out


static func _quad_detail(
	out: Array[DPoly],
	base: DPoly,
	prim: ArtPrim,
	pi: int,
	fi: int,
	faction: StringName,
	mat: StringName,
	col: Color,
	normal: Vector3,
	pts3: PackedVector3Array,
	sp: PackedVector2Array,
	is_top: bool,
	level: int
) -> void:
	var lu: float = pts3[0].distance_to(pts3[1])
	var lv: float = pts3[0].distance_to(pts3[3])
	var su: float = sp[0].distance_to(sp[1])
	var sv: float = sp[0].distance_to(sp[3])
	if su < MIN_FACE_PX or sv < MIN_FACE_PX or lu * lv < 0.006:
		return
	if mat == &"hazard":
		_hazard(out, base, col, sp, lu, lv, pi)
		return
	var cs: float = CELL.get(mat, 0.25)
	var nu: int = maxi(1, roundi(lu / cs))
	var nv: int = maxi(1, roundi(lv / cs))
	if mat == &"team" and lu * lv < 0.03:
		nu = 1
		nv = 1
	base.fill = hex(_dark(col, SEAM))
	var pu: float = GAP_PX * 0.5 / su
	var pv: float = GAP_PX * 0.5 / sv
	var bolted: bool = mat in BOLTED and nu * nv >= 2
	for i: int in nu:
		for j: int in nv:
			var u0: float = float(i) / nu + pu
			var u1: float = float(i + 1) / nu - pu
			var v0: float = float(j) / nv + pv
			var v1: float = float(j + 1) / nv - pv
			var q: PackedVector2Array = PackedVector2Array(
				[_bil(sp, u0, v0), _bil(sp, u1, v0), _bil(sp, u1, v1), _bil(sp, u0, v1)]
			)
			var jitter: float = 1.0 + (_h(pi, fi, i, j) - 0.5) * 0.12
			var cc: Color = Color(
				clampf(col.r * jitter, 0, 1),
				clampf(col.g * jitter, 0, 1),
				clampf(col.b * jitter, 0, 1)
			)
			var cell: DPoly = _poly(q, cc, &"panel")
			cell.prim = pi
			out.append(cell)
			if level >= 3 and su / nu > 9.0 and sv / nv > 6.0:
				_bevel(out, q, cc)
			if bolted:
				for corner: Vector2 in [q[0], q[2]]:
					var toward: Vector2 = (q[0] + q[1] + q[2] + q[3]) * 0.25 - corner
					var at: Vector2 = corner + toward.normalized() * 2.2
					var dot: PackedVector2Array = PackedVector2Array(
						[
							at + Vector2(-0.9, 0),
							at + Vector2(0, -0.9),
							at + Vector2(0.9, 0),
							at + Vector2(0, 0.9)
						]
					)
					out.append(_poly(dot, _dark(cc, 0.42), &"bolt"))
	if level < 3:
		return
	_contact_bands(out, pts3, sp, normal)
	if mat == ArtPalette.TEAM and not is_top and lu * lv > 0.05:
		_chips(out, faction, sp, pi, fi, normal)
	if not is_top and lu * lv > 0.05:
		_streaks(out, sp, pts3, pi, fi)


static func _bevel(out: Array[DPoly], q: PackedVector2Array, c: Color) -> void:
	var centre: Vector2 = (q[0] + q[1] + q[2] + q[3]) * 0.25
	var best: int = 0
	var worst: int = 0
	for e: int in 4:
		var mid: float = (q[e].y + q[(e + 1) % 4].y) * 0.5
		if mid < (q[best].y + q[(best + 1) % 4].y) * 0.5:
			best = e
		if mid > (q[worst].y + q[(worst + 1) % 4].y) * 0.5:
			worst = e
	for pair: Array in [[best, 0.34, 0.9], [worst, -0.5, 0.9]]:
		var e: int = pair[0]
		var a: Vector2 = q[e]
		var b: Vector2 = q[(e + 1) % 4]
		var inward: Vector2 = (centre - (a + b) * 0.5).normalized() * 1.3
		var strip: PackedVector2Array = PackedVector2Array([a, b, b + inward, a + inward])
		var k: float = pair[1]
		var s: DPoly = _poly(strip, _light(c, k) if k > 0.0 else _dark(c, 0.55), &"bevel", 0.5)
		out.append(s)


static func _contact_bands(
	out: Array[DPoly], pts3: PackedVector3Array, sp: PackedVector2Array, normal: Vector3
) -> void:
	if absf(normal.z) > 0.3:
		return
	var order: Array[int] = [0, 1, 2, 3]
	order.sort_custom(func(a: int, b: int) -> bool: return pts3[a].z < pts3[b].z)
	var b0: int = order[0]
	var b1: int = order[1]
	if absf(pts3[b0].z - pts3[b1].z) > 0.01 or pts3[order[2]].z - pts3[b0].z < 0.06:
		return
	var t0: int = -1
	var t1: int = -1
	for n: int in [(b0 + 1) % 4, (b0 + 3) % 4]:
		if n != b1:
			t0 = n
	for n: int in [(b1 + 1) % 4, (b1 + 3) % 4]:
		if n != b0:
			t1 = n
	for step: Array in [[0.38, 0.07], [0.24, 0.09], [0.12, 0.12]]:
		var f: float = step[0]
		var band: PackedVector2Array = PackedVector2Array(
			[sp[b0], sp[b1], sp[b1].lerp(sp[t1], f), sp[b0].lerp(sp[t0], f)]
		)
		out.append(_poly(band, Color.BLACK, &"ao", step[1]))


static func _chips(
	out: Array[DPoly],
	faction: StringName,
	sp: PackedVector2Array,
	pi: int,
	fi: int,
	normal: Vector3
) -> void:
	var steel: Color = _dark(colour(faction, &"wornsteel", _shade(normal, 1)), 0.9)
	for n: int in 3:
		var u: float = _h(pi, fi, n, 1)
		var v: float = _h(pi, fi, n, 2)
		var edge: float = 0.08 * _h(pi, fi, n, 3)
		u = edge if u < 0.5 else 1.0 - edge
		var at: Vector2 = _bil(sp, u, v)
		var r: float = 1.2 + _h(pi, fi, n, 4) * 1.8
		var chip: PackedVector2Array = PackedVector2Array(
			[
				at + Vector2(-r, 0.2),
				at + Vector2(-r * 0.2, -r * 0.8),
				at + Vector2(r, 0),
				at + Vector2(0.2 * r, r * 0.7)
			]
		)
		out.append(_poly(chip, steel, &"chip", 0.9))


static func _streaks(
	out: Array[DPoly], sp: PackedVector2Array, pts3: PackedVector3Array, pi: int, fi: int
) -> void:
	for n: int in 2:
		var u: float = 0.1 + 0.8 * _h(pi, fi, n, 7)
		var len: float = 0.25 + 0.4 * _h(pi, fi, n, 8)
		var top_v: float = 0.0 if pts3[0].z > pts3[3].z else 1.0
		var bot_v: float = 1.0 - top_v
		var a: Vector2 = _bil(sp, u, top_v)
		var b: Vector2 = _bil(sp, u, top_v + (bot_v - top_v) * len)
		var w: Vector2 = _bil(sp, u + 0.05, top_v) - a
		var strip: PackedVector2Array = PackedVector2Array([a, a + w, b + w, b])
		out.append(_poly(strip, Color.BLACK, &"grime", 0.13))


static func _hazard(
	out: Array[DPoly],
	base: DPoly,
	col: Color,
	sp: PackedVector2Array,
	lu: float,
	lv: float,
	pi: int
) -> void:
	var yellow: Color = col
	base.fill = hex(_dark(col, 0.12))
	var period: float = STRIPE_TILES * 2.0
	var count: int = ceili((lu + lv) / period) + 1
	for k: int in count:
		var t0: float = k * period - lv
		var t1: float = t0 + STRIPE_TILES
		var band: PackedVector2Array = PackedVector2Array(
			[
				Vector2(t0 / lu, 0.0),
				Vector2(t1 / lu, 0.0),
				Vector2((t1 + lv) / lu, 1.0),
				Vector2((t0 + lv) / lu, 1.0),
			]
		)
		var unit: PackedVector2Array = PackedVector2Array(
			[Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
		)
		for piece: PackedVector2Array in Geometry2D.intersect_polygons(band, unit):
			var mapped: PackedVector2Array = PackedVector2Array()
			for uv: Vector2 in piece:
				mapped.append(_bil(sp, uv.x, uv.y))
			if mapped.size() >= 3:
				var stripe: DPoly = _poly(mapped, yellow, &"stripe")
				stripe.prim = pi
				out.append(stripe)


## A big n-gon top (an octagon cap): a ring of panels round a centre cap, each a little apart.
static func _ring_detail(
	out: Array[DPoly], base: DPoly, mat: StringName, col: Color, sp: PackedVector2Array, level: int
) -> void:
	var centre: Vector2 = Vector2.ZERO
	for p: Vector2 in sp:
		centre += p
	centre /= sp.size()
	var reach: float = 0.0
	for p: Vector2 in sp:
		reach = maxf(reach, p.distance_to(centre))
	if reach < 14.0:
		return
	base.fill = hex(_dark(col, SEAM))
	var n: int = sp.size()
	var inner: float = 0.5
	var outer: float = 0.93
	var gap_k: float = GAP_PX / reach
	for i: int in n:
		var a: Vector2 = sp[i] - centre
		var b: Vector2 = sp[(i + 1) % n] - centre
		var ia: Vector2 = centre + a * inner
		var ib: Vector2 = centre + b * inner
		var oa: Vector2 = centre + a * outer
		var ob: Vector2 = centre + b * outer
		var along: Vector2 = (ob - oa).normalized() * (GAP_PX * 0.5)
		var shade: float = 1.0 + (_h(i, n, int(reach), 3) - 0.5) * 0.1
		var tint: Color = Color(
			clampf(col.r * shade, 0, 1), clampf(col.g * shade, 0, 1), clampf(col.b * shade, 0, 1)
		)
		var panel: PackedVector2Array = PackedVector2Array(
			[ia + along + (a.normalized() * 0.0), ib - along, ob - along, oa + along]
		)
		var cell: DPoly = _poly(panel, tint, &"panel")
		out.append(cell)
		if level >= 2 and mat in BOLTED:
			var at: Vector2 = centre + (a + b) * 0.5 * 0.8
			var dot: PackedVector2Array = PackedVector2Array(
				[
					at + Vector2(-0.9, 0),
					at + Vector2(0, -0.9),
					at + Vector2(0.9, 0),
					at + Vector2(0, 0.9)
				]
			)
			out.append(_poly(dot, _dark(tint, 0.4), &"bolt"))
	var cap: PackedVector2Array = PackedVector2Array()
	for p: Vector2 in sp:
		cap.append(centre + (p - centre) * (inner - gap_k * 1.2))
	out.append(_poly(cap, _light(col, 0.06), &"panel"))
	if gap_k < 0.0:
		return


## The soft ground shadow of a model turned by `yaw`: six stepped rings of occlusion, a contact
## line and the cast shadow. Black polygons; the writer puts them in one group at one opacity.
static func shadow(prims: Array[ArtPrim], yaw: float) -> Array[DPoly]:
	var out: Array[DPoly] = []
	var outline: Array[Vector2] = ArtShadow._hull(ArtShadow._ground(prims, yaw, ArtShadow.GROUND_Z))
	if outline.size() >= 3:
		for step: int in range(6, 0, -1):
			var ring: Array[Vector2] = ArtShadow._grow(outline, 0.26 * step / 6.0)
			var poly: DPoly = DPoly.new()
			poly.points = ArtShadow._screen(ring).points
			poly.fill = "#000000"
			poly.opacity = 0.2
			poly.stroke_px = 0
			poly.kind = &"shadow"
			out.append(poly)
	for cast: ArtRender.Poly in ArtShadow.polys(prims, yaw):
		var poly2: DPoly = DPoly.new()
		poly2.points = cast.points
		poly2.fill = "#000000"
		poly2.stroke_px = 0
		poly2.kind = &"shadow"
		out.append(poly2)
	return out


static func bounds(polys: Array[DPoly]) -> Rect2:
	var box: Rect2 = Rect2()
	var first: bool = true
	for poly: DPoly in polys:
		for point: Vector2 in poly.points:
			box = Rect2(point, Vector2.ZERO) if first else box.expand(point)
			first = false
	return box


static func _num(value: float) -> String:
	var text: String = "%.1f" % value
	return "0" if text == "-0.0" else text.trim_suffix(".0")


## The SVG text: `g` with polygons, origin applied. `opacity` is the group's (a shadow's).
static func svg(
	comment: String, size: Vector2i, origin: Vector2i, polys: Array[DPoly], opacity: float = 1.0
) -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("<!-- %s -->" % comment)
	lines.append(
		(
			'<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">'
			% [size.x, size.y, size.x, size.y]
		)
	)
	var group: String = 'stroke-width="1" stroke-linejoin="round"'
	if opacity < 1.0:
		group += ' opacity="%s"' % _num(opacity * 100.0 / 100.0)
	lines.append("<g %s>" % group)
	for poly: DPoly in polys:
		var pts: PackedStringArray = PackedStringArray()
		for p: Vector2 in poly.points:
			var at: Vector2 = p + Vector2(origin)
			pts.append("%s,%s" % [_num(at.x), _num(at.y)])
		var extra: String = ""
		if poly.opacity < 1.0:
			extra += ' fill-opacity="%s"' % ("%.2f" % poly.opacity).trim_suffix("0")
		if poly.stroke != "":
			extra += ' stroke="%s"' % poly.stroke
		lines.append('<polygon points="%s" fill="%s"%s/>' % [" ".join(pts), poly.fill, extra])
	lines.append("</g>")
	lines.append("</svg>")
	return "\n".join(lines) + "\n"
