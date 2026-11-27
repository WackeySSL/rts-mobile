class_name DetailTank
extends RefCounted
## P655: the detailed Nordvaern heavy_tank, built from code only. Same footprint, silhouette
## proportions and turret pivot as `assets/art/models/fossil/heavy_tank.tres`. All coordinates in
## this file are in the model's grid frame (x forward, y right-down, z up) and are converted to the
## Godot frame (X, Y, Z) = (gx, z, gy) when a triangle is emitted.

const SHADER: Shader = preload("res://tools/prerender/detail.gdshader")

## name -> [base colour, metallic, roughness, kind]
const MATS: Dictionary = {
	"gun": [Color(0.25, 0.265, 0.29), 0.55, 0.5, 0],
	"steel": [Color(0.42, 0.43, 0.46), 0.6, 0.42, 0],
	"iron": [Color(0.14, 0.135, 0.13), 0.45, 0.62, 0],
	"rubber": [Color(0.045, 0.045, 0.045), 0.0, 0.88, 2],
	"track": [Color(0.085, 0.08, 0.075), 0.5, 0.7, 2],
	"glass": [Color(0.035, 0.07, 0.095), 0.2, 0.08, 3],
	"lamp": [Color(1.0, 0.82, 0.5), 0.0, 0.3, 4],
	"canvas": [Color(0.13, 0.12, 0.085), 0.0, 0.92, 5],
	"rust": [Color(0.27, 0.13, 0.07), 0.3, 0.8, 0],
}

static var _noise: ImageTexture
var _acc: Dictionary = {}
var _mat_cache: Dictionary = {}
var team_hex: String = "#D234D2"
var z_off: float = 0.0
var tris: int = 0
var shift: Vector3 = Vector3.ZERO


class Acc:
	extends RefCounted
	var v: PackedVector3Array = PackedVector3Array()
	var n: PackedVector3Array = PackedVector3Array()
	var c: PackedColorArray = PackedColorArray()
	var idx: PackedInt32Array = PackedInt32Array()


static func g(p: Vector3) -> Vector3:
	return Vector3(p.x, p.z, p.y)


static func _noise_tex() -> ImageTexture:
	if _noise != null:
		return _noise
	var n: FastNoiseLite = FastNoiseLite.new()
	n.seed = 655
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.03
	n.fractal_octaves = 5
	n.fractal_gain = 0.55
	var img: Image = n.get_seamless_image(256, 256, false, false, 0.2, false)
	img.convert(Image.FORMAT_L8)
	img.generate_mipmaps()
	_noise = ImageTexture.create_from_image(img)
	return _noise


func _a(mat: String) -> Acc:
	if not _acc.has(mat):
		_acc[mat] = Acc.new()
	return _acc[mat]


func _tri(a: Acc, p: Array, nrm: Array, e: Array, out_n: Vector3) -> void:
	var base: int = a.v.size()
	var gp: Array[Vector3] = [g(p[0] + shift), g(p[1] + shift), g(p[2] + shift)]
	for i: int in 3:
		a.v.append(gp[i])
		a.n.append(g(nrm[i]))
		a.c.append(Color(e[i], 0.0, 0.0, 1.0))
	var cr: Vector3 = (gp[1] - gp[0]).cross(gp[2] - gp[0])
	if cr.dot(g(out_n)) <= 0.0:
		a.idx.append_array([base, base + 1, base + 2])
	else:
		a.idx.append_array([base, base + 2, base + 1])


static func _key(p: Vector3) -> String:
	return "%d,%d,%d" % [roundi(p.x * 2000.0), roundi(p.y * 2000.0), roundi(p.z * 2000.0)]


static func _edge_key(p: Vector3, q: Vector3) -> String:
	var a: String = _key(p)
	var b: String = _key(q)
	return a + "|" + b if a < b else b + "|" + a


static func plane_through(n: Vector3, p: Vector3) -> Plane:
	var nn: Vector3 = n.normalized()
	return Plane(nn, nn.dot(p))


## Convex solid from outward planes (inside is n.p <= d). Each face gets a bevel strip.
func solid(mat: String, planes: Array[Plane], bevel: float = 0.012) -> void:
	var polys: Array[PackedVector3Array] = []
	for i: int in planes.size():
		var pl: Plane = planes[i]
		var c0: Vector3 = pl.normal * pl.d
		var u: Vector3 = (
			pl
			. normal
			. cross(Vector3.UP if absf(pl.normal.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT)
			. normalized()
		)
		var w: Vector3 = pl.normal.cross(u)
		var pts: PackedVector3Array = [
			c0 + (u + w) * 6.0, c0 + (u - w) * 6.0, c0 + (-u - w) * 6.0, c0 + (-u + w) * 6.0
		]
		for j: int in planes.size():
			if j == i:
				continue
			pts = Geometry3D.clip_polygon(pts, planes[j])
			if pts.size() < 3:
				break
		var clean: PackedVector3Array = PackedVector3Array()
		for p: Vector3 in pts:
			if clean.is_empty() or not clean[clean.size() - 1].is_equal_approx(p):
				clean.append(p)
		if clean.size() > 1 and clean[0].is_equal_approx(clean[clean.size() - 1]):
			clean.remove_at(clean.size() - 1)
		polys.append(clean if clean.size() >= 3 else PackedVector3Array())
	var nb: Dictionary = {}
	for i: int in polys.size():
		var pg: PackedVector3Array = polys[i]
		for k: int in pg.size():
			var ek: String = _edge_key(pg[k], pg[(k + 1) % pg.size()])
			if not nb.has(ek):
				nb[ek] = []
			nb[ek].append(planes[i].normal)
	var a: Acc = _a(mat)
	for i: int in polys.size():
		var pg2: PackedVector3Array = polys[i]
		if pg2.is_empty():
			continue
		var nn: Vector3 = planes[i].normal
		var cnt: int = pg2.size()
		if bevel <= 0.0:
			for k: int in range(1, cnt - 1):
				_tri(a, [pg2[0], pg2[k], pg2[k + 1]], [nn, nn, nn], [0.0, 0.0, 0.0], nn)
			continue
		var cen: Vector3 = Vector3.ZERO
		for p: Vector3 in pg2:
			cen += p
		cen /= cnt
		var inner: Array[Vector3] = []
		for k: int in cnt:
			var to_c: Vector3 = cen - pg2[k]
			inner.append(pg2[k] + to_c * minf(bevel / maxf(to_c.length(), 1e-6), 0.45))
		for k: int in range(1, cnt - 1):
			_tri(a, [inner[0], inner[k], inner[k + 1]], [nn, nn, nn], [0.0, 0.0, 0.0], nn)
		for k: int in cnt:
			var l: int = (k + 1) % cnt
			var m: Vector3 = nn
			for o: Vector3 in nb[_edge_key(pg2[k], pg2[l])]:
				if not o.is_equal_approx(nn):
					m = (nn + o).normalized()
					break
			_tri(a, [pg2[k], pg2[l], inner[l]], [m, m, nn], [1.0, 1.0, 0.0], nn)
			_tri(a, [pg2[k], inner[l], inner[k]], [m, nn, nn], [1.0, 0.0, 0.0], nn)


func box_t(mat: String, xf: Transform3D, size: Vector3, bevel: float = 0.01) -> void:
	var planes: Array[Plane] = []
	for ax: int in 3:
		var col: Vector3 = xf.basis[ax].normalized()
		for s: int in [-1, 1]:
			var n: Vector3 = col * float(s)
			planes.append(Plane(n, n.dot(xf.origin) + size[ax] * 0.5))
	solid(mat, planes, minf(bevel, minf(size.x, minf(size.y, size.z)) * 0.3))


func box(mat: String, c: Vector3, size: Vector3, bevel: float = 0.01) -> void:
	box_t(mat, Transform3D(Basis.IDENTITY, c), size, bevel)


static func frame(dir: Vector3, up_hint: Vector3 = Vector3(0, 0, 1)) -> Basis:
	var x: Vector3 = dir.normalized()
	var up: Vector3 = up_hint if absf(x.dot(up_hint)) < 0.97 else Vector3(0, 1, 0)
	var z: Vector3 = (up - x * x.dot(up)).normalized()
	return Basis(x, z.cross(x), z)


## A long thin box from a to b: w across, h along `up_hint`.
func bar(
	mat: String,
	a: Vector3,
	b: Vector3,
	w: float,
	h: float,
	up_hint: Vector3 = Vector3(0, 0, 1),
	bevel: float = 0.0
) -> void:
	box_t(
		mat,
		Transform3D(frame(b - a, up_hint), (a + b) * 0.5),
		Vector3(a.distance_to(b), w, h),
		bevel
	)


## Cylinder (or cone, r2 >= 0) from a to b with a chamfer ring at both ends.
func cyl(
	mat: String,
	a: Vector3,
	b: Vector3,
	r: float,
	segs: int = 16,
	ch: float = 0.0,
	r2: float = -1.0,
	caps: bool = true
) -> void:
	var ax: Vector3 = b - a
	var len: float = ax.length()
	if len < 1e-6:
		return
	ax /= len
	var u: Vector3 = (
		ax.cross(Vector3.UP if absf(ax.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT).normalized()
	)
	var w: Vector3 = ax.cross(u)
	var rb: float = r2 if r2 >= 0.0 else r
	var chh: float = minf(ch, len * 0.4)
	# rings: [centre, radius, normal axis part, edge flag]
	var rings: Array = []
	if chh > 0.0:
		rings.append([a, r - chh, -1.0, 0.0, true])
		rings.append([a + ax * chh, r, -0.5, 1.0, false])
		rings.append([b - ax * chh, rb, 0.5, 1.0, false])
		rings.append([b, rb - chh, 1.0, 0.0, true])
	else:
		rings.append([a, r, -1.0, 0.0, true])
		rings.append([a, r, 0.0, 0.0, false])
		rings.append([b, rb, 0.0, 0.0, false])
		rings.append([b, rb, 1.0, 0.0, true])
	var acc: Acc = _a(mat)
	var slope: float = (r - rb) / len
	for s: int in segs:
		var t0: float = TAU * float(s) / segs
		var t1: float = TAU * float(s + 1) / segs
		var d0: Vector3 = u * cos(t0) + w * sin(t0)
		var d1: Vector3 = u * cos(t1) + w * sin(t1)
		for r_i: int in 3:
			var ra: Array = rings[r_i]
			var rb2: Array = rings[r_i + 1]
			var cap_a: bool = ra[4] and rb2[4]
			if (r_i == 0 or r_i == 2) and chh <= 0.0:
				continue
			if r_i != 1 and chh <= 0.0:
				continue
			if r_i == 0 and not caps:
				continue
			if r_i == 2 and not caps:
				continue
			var pa0: Vector3 = ra[0] + d0 * ra[1]
			var pa1: Vector3 = ra[0] + d1 * ra[1]
			var pb0: Vector3 = rb2[0] + d0 * rb2[1]
			var pb1: Vector3 = rb2[0] + d1 * rb2[1]
			var na0: Vector3 = (d0 + ax * (ra[2] if r_i != 1 else slope)).normalized()
			var na1: Vector3 = (d1 + ax * (ra[2] if r_i != 1 else slope)).normalized()
			var nb0: Vector3 = (d0 + ax * (rb2[2] if r_i != 1 else slope)).normalized()
			var nb1: Vector3 = (d1 + ax * (rb2[2] if r_i != 1 else slope)).normalized()
			var out_n: Vector3 = (d0 + d1).normalized()
			_tri(acc, [pa0, pa1, pb1], [na0, na1, nb1], [ra[3], ra[3], rb2[3]], out_n)
			_tri(acc, [pa0, pb1, pb0], [na0, nb1, nb0], [ra[3], rb2[3], rb2[3]], out_n)
			if cap_a:
				pass
		if caps:
			var first: Array = rings[0]
			var last: Array = rings[3]
			var cn: Vector3 = -ax
			_tri(
				acc,
				[a, first[0] + d0 * first[1], first[0] + d1 * first[1]],
				[cn, cn, cn],
				[0.0, 0.0, 0.0],
				cn
			)
			_tri(
				acc,
				[b, last[0] + d0 * last[1], last[0] + d1 * last[1]],
				[ax, ax, ax],
				[0.0, 0.0, 0.0],
				ax
			)


func dome(mat: String, c: Vector3, n: Vector3, r: float, segs: int = 6) -> void:
	var nn: Vector3 = n.normalized()
	var u: Vector3 = (
		nn.cross(Vector3.UP if absf(nn.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT).normalized()
	)
	var w: Vector3 = nn.cross(u)
	var acc: Acc = _a(mat)
	var top: Vector3 = c + nn * r * 0.55
	for s: int in segs:
		var t0: float = TAU * float(s) / segs
		var t1: float = TAU * float(s + 1) / segs
		var d0: Vector3 = u * cos(t0) + w * sin(t0)
		var d1: Vector3 = u * cos(t1) + w * sin(t1)
		var m0: Vector3 = (d0 * 0.8 + nn * 0.6).normalized()
		var m1: Vector3 = (d1 * 0.8 + nn * 0.6).normalized()
		_tri(acc, [c + d0 * r, c + d1 * r, top], [m0, m1, nn], [0.6, 0.6, 1.0], nn)


func torus(
	mat: String, c: Vector3, axis: Vector3, big: float, small: float, segs: int = 14, sides: int = 6
) -> void:
	var ax: Vector3 = axis.normalized()
	var u: Vector3 = (
		ax.cross(Vector3.UP if absf(ax.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT).normalized()
	)
	var w: Vector3 = ax.cross(u)
	var acc: Acc = _a(mat)
	for s: int in segs:
		var d0: Vector3 = u * cos(TAU * s / segs) + w * sin(TAU * s / segs)
		var d1: Vector3 = u * cos(TAU * (s + 1) / segs) + w * sin(TAU * (s + 1) / segs)
		for q: int in sides:
			var a0: float = TAU * q / sides
			var a1: float = TAU * (q + 1) / sides
			var n00: Vector3 = d0 * cos(a0) + ax * sin(a0)
			var n01: Vector3 = d0 * cos(a1) + ax * sin(a1)
			var n10: Vector3 = d1 * cos(a0) + ax * sin(a0)
			var n11: Vector3 = d1 * cos(a1) + ax * sin(a1)
			var p00: Vector3 = c + d0 * big + n00 * small
			var p01: Vector3 = c + d0 * big + n01 * small
			var p10: Vector3 = c + d1 * big + n10 * small
			var p11: Vector3 = c + d1 * big + n11 * small
			_tri(acc, [p00, p10, p11], [n00, n10, n11], [0.0, 0.0, 0.0], n00 + n10)
			_tri(acc, [p00, p11, p01], [n00, n11, n01], [0.0, 0.0, 0.0], n00 + n11)


func rivet_line(
	mat: String, a: Vector3, b: Vector3, n: Vector3, count: int, r: float = 0.0075
) -> void:
	for i: int in count:
		var t: float = (float(i) + 0.5) / count
		dome(mat, a.lerp(b, t), n, r)


## Side plane of a prism with plan edge a-b (x, y), leaning in by `tilt`, through height z.
func side_plane(a: Vector2, b: Vector2, tilt: float, z: float) -> Plane:
	var e: Vector2 = b - a
	var n2: Vector2 = Vector2(e.y, -e.x).normalized()
	if n2.dot(Vector2.ZERO - a) > 0.0:
		n2 = -n2
	return plane_through(Vector3(n2.x, n2.y, tilt), Vector3(a.x, a.y, z))


# ---------------------------------------------------------------------------------------------
# Hull
# ---------------------------------------------------------------------------------------------

const TRACK_L: float = 0.485
const TRACK_R: float = 0.095


func _track_at(s: float) -> Array:
	var run: float = 2.0 * TRACK_L
	var arc: float = PI * TRACK_R
	var t: float = s
	if t < run:
		return [Vector2(-TRACK_L + t, 0.0), Vector2(0, -1)]
	t -= run
	if t < arc:
		var a: float = -PI / 2.0 + t / TRACK_R
		return [
			Vector2(TRACK_L, TRACK_R) + Vector2(cos(a), sin(a)) * TRACK_R, Vector2(cos(a), sin(a))
		]
	t -= arc
	if t < run:
		return [Vector2(TRACK_L - t, 2.0 * TRACK_R), Vector2(0, 1)]
	t -= run
	var a2: float = PI / 2.0 + t / TRACK_R
	return [
		Vector2(-TRACK_L, TRACK_R) + Vector2(cos(a2), sin(a2)) * TRACK_R, Vector2(cos(a2), sin(a2))
	]


func _tracks() -> void:
	var perim: float = 4.0 * TRACK_L + TAU * TRACK_R
	var count: int = 74
	var pitch: float = perim / count
	for sd: int in [-1, 1]:
		var yc: float = 0.37 * sd
		for i: int in count:
			var s0: float = (float(i) + 0.5) * pitch
			var tp: Array = _track_at(s0)
			var tp2: Array = _track_at(s0 + 0.004)
			var tp1: Array = _track_at(maxf(s0 - 0.004, 0.0))
			var pos: Vector2 = tp[0]
			var nrm: Vector2 = tp[1]
			var tan2: Vector2 = (tp2[0] - tp1[0]).normalized()
			if tp2[0].is_equal_approx(tp1[0]):
				tan2 = Vector2(nrm.y, -nrm.x)
			var t3: Vector3 = Vector3(tan2.x, 0.0, tan2.y)
			var n3: Vector3 = Vector3(nrm.x, 0.0, nrm.y)
			var bas: Basis = Basis(t3, n3.cross(t3), n3)
			var p3: Vector3 = Vector3(pos.x, yc, pos.y)
			box_t(
				"track", Transform3D(bas, p3 + n3 * 0.0065), Vector3(pitch * 0.9, 0.2, 0.013), 0.003
			)
			box_t(
				"iron", Transform3D(bas, p3 - n3 * 0.004), Vector3(pitch * 0.45, 0.034, 0.016), 0.0
			)
			if tp[1] != Vector2(0, 1):
				for k: int in [-1, 1]:
					box_t(
						"track",
						Transform3D(bas, p3 + n3 * 0.0165 + t3 * (pitch * 0.27 * k)),
						Vector3(0.007, 0.19, 0.008),
						0.0
					)
			if i % 2 == 0 and tp[1] != Vector2(0, 1):
				for k: int in [-1, 1]:
					dome("steel", p3 + n3 * 0.0135 + Vector3(0, 0.09 * k, 0), n3, 0.0045, 5)
		# road wheels
		for wi: int in 6:
			var wx: float = -0.34 + 0.136 * wi
			var wc: float = 0.074
			for disc: Array in [[0.30, 0.345], [0.40, 0.442]]:
				var y0: float = disc[0] * sd
				var y1: float = disc[1] * sd
				cyl("rubber", Vector3(wx, y0, wc), Vector3(wx, y1, wc), 0.062, 20, 0.006)
				cyl(
					"steel",
					Vector3(wx, y0 - 0.002 * sd, wc),
					Vector3(wx, y1 + 0.002 * sd, wc),
					0.042,
					18,
					0.004
				)
			cyl("steel", Vector3(wx, 0.436 * sd, wc), Vector3(wx, 0.455 * sd, wc), 0.03, 14, 0.004)
			cyl("iron", Vector3(wx, 0.452 * sd, wc), Vector3(wx, 0.462 * sd, wc), 0.012, 8, 0.0)
			for bi: int in 5:
				var ba: float = TAU * bi / 5.0
				dome(
					"steel",
					Vector3(wx + cos(ba) * 0.021, 0.449 * sd, wc + sin(ba) * 0.021),
					Vector3(0, sd, 0),
					0.0055,
					5
				)
			# bump stop on the hull side above the wheel
		# sprocket
		var sx: float = -TRACK_L
		var sz: float = TRACK_R
		for ply: Array in [[0.31, 0.33], [0.415, 0.435]]:
			cyl(
				"steel", Vector3(sx, ply[0] * sd, sz), Vector3(sx, ply[1] * sd, sz), 0.07, 22, 0.004
			)
		cyl("steel", Vector3(sx, 0.33 * sd, sz), Vector3(sx, 0.415 * sd, sz), 0.05, 18, 0.0)
		for ti: int in 11:
			var ta: float = TAU * ti / 11.0
			var rad: Vector3 = Vector3(cos(ta), 0.0, sin(ta))
			box_t(
				"steel",
				Transform3D(
					Basis(rad, Vector3(0, 1, 0), Vector3(-rad.z, 0, rad.x) * -1.0),
					Vector3(sx, 0.372 * sd, sz) + rad * 0.075
				),
				Vector3(0.036, 0.1, 0.016),
				0.003
			)
		cyl("iron", Vector3(sx, 0.433 * sd, sz), Vector3(sx, 0.447 * sd, sz), 0.034, 14, 0.004)
		cyl("steel", Vector3(sx, 0.445 * sd, sz), Vector3(sx, 0.456 * sd, sz), 0.016, 8, 0.002)
		for bi2: int in 6:
			var ba2: float = TAU * bi2 / 6.0
			dome(
				"steel",
				Vector3(sx + cos(ba2) * 0.025, 0.435 * sd, sz + sin(ba2) * 0.025),
				Vector3(0, sd, 0),
				0.005,
				5
			)
		# idler
		var ix: float = TRACK_L
		cyl("steel", Vector3(ix, 0.30 * sd, sz), Vector3(ix, 0.44 * sd, sz), 0.083, 24, 0.005)
		cyl("iron", Vector3(ix, 0.436 * sd, sz), Vector3(ix, 0.446 * sd, sz), 0.06, 20, 0.004)
		cyl("steel", Vector3(ix, 0.444 * sd, sz), Vector3(ix, 0.458 * sd, sz), 0.022, 12, 0.003)
		for bi3: int in 6:
			var ba3: float = TAU * bi3 / 6.0
			dome(
				"steel",
				Vector3(ix + cos(ba3) * 0.04, 0.446 * sd, sz + sin(ba3) * 0.04),
				Vector3(0, sd, 0),
				0.006,
				5
			)
		# idler tension arm and return rollers
		bar(
			"iron",
			Vector3(0.30, 0.452 * sd, 0.09),
			Vector3(ix, 0.452 * sd, sz),
			0.012,
			0.02,
			Vector3(0, 0, 1),
			0.002
		)
		for rx: float in [-0.22, 0.04, 0.26]:
			cyl(
				"rubber",
				Vector3(rx, 0.31 * sd, 0.162),
				Vector3(rx, 0.42 * sd, 0.162),
				0.021,
				12,
				0.003
			)


func _skirts() -> void:
	for sd: int in [-1, 1]:
		var xs: Array = [[-0.30, -0.12], [-0.11, 0.07], [0.08, 0.26], [0.27, 0.44]]
		for seg: Array in xs:
			var x0: float = seg[0]
			var x1: float = seg[1]
			var cz: float = 0.168
			box(
				"team",
				Vector3((x0 + x1) * 0.5, 0.479 * sd, cz),
				Vector3(x1 - x0, 0.022, 0.092),
				0.007
			)
			# bolts and hinge pins
			for bxx: float in [x0 + 0.016, x1 - 0.016]:
				for bz: float in [0.12, 0.214]:
					dome("steel", Vector3(bxx, 0.49 * sd, bz), Vector3(0, sd, 0), 0.0065, 6)
			cyl(
				"steel",
				Vector3(x0 + 0.01, 0.489 * sd, 0.2275),
				Vector3(x1 - 0.01, 0.489 * sd, 0.2275),
				0.0055,
				6,
				0.0
			)
			bar(
				"iron",
				Vector3(x0 + 0.01, 0.4915 * sd, 0.172),
				Vector3(x1 - 0.01, 0.4915 * sd, 0.172),
				0.003,
				0.003,
				Vector3(0, 0, 1),
				0.0
			)
		# lower rail and brackets
		bar(
			"steel",
			Vector3(-0.30, 0.484 * sd, 0.1255),
			Vector3(0.44, 0.484 * sd, 0.1255),
			0.014,
			0.007,
			Vector3(0, 0, 1),
			0.002
		)
		for bx: float in [-0.20, 0.0, 0.18, 0.36]:
			box("iron", Vector3(bx, 0.465 * sd, 0.215), Vector3(0.02, 0.03, 0.012), 0.002)


func _hull_body() -> void:
	# lower tub, hidden between the tracks
	box("iron", Vector3(0.05, 0, 0.115), Vector3(1.18, 0.60, 0.17), 0.012)
	# upper hull: z 0.20 .. 0.31, glacis 30 degrees, chamfered corners
	var up: Array[Plane] = [
		Plane(Vector3(0, 0, -1), -0.2),
		Plane(Vector3(0, 0, 1), 0.31),
		plane_through(Vector3(0, 1, 0), Vector3(0, 0.455, 0.2)),
		plane_through(Vector3(0, -1, 0), Vector3(0, -0.455, 0.2)),
		plane_through(Vector3(0, 0.62, 0.78), Vector3(0, 0.37, 0.31)),
		plane_through(Vector3(0, -0.62, 0.78), Vector3(0, -0.37, 0.31)),
		plane_through(Vector3(-0.94, 0, 0.34), Vector3(-0.56, 0, 0.2)),
		plane_through(Vector3(0.5, 0, 0.866), Vector3(0.50, 0, 0.31)),
		plane_through(Vector3(0.72, 0.69, 0.1), Vector3(0.62, 0.30, 0.25)),
		plane_through(Vector3(0.72, -0.69, 0.1), Vector3(0.62, -0.30, 0.25)),
		plane_through(Vector3(-0.72, 0.69, 0.1), Vector3(-0.56, 0.36, 0.25)),
		plane_through(Vector3(-0.72, -0.69, 0.1), Vector3(-0.56, -0.36, 0.25)),
	]
	solid("gun", up, 0.012)
	# lower bow plate (steel), sloped back, with chamfered corners
	var bow: Array[Plane] = [
		Plane(Vector3(0, 0, -1), -0.05),
		Plane(Vector3(0, 0, 1), 0.2),
		plane_through(Vector3(-1, 0, 0), Vector3(0.55, 0, 0.1)),
		plane_through(Vector3(1, 0, 0.5), Vector3(0.775, 0, 0.05)),
		plane_through(Vector3(0, 1, 0), Vector3(0, 0.46, 0.1)),
		plane_through(Vector3(0, -1, 0), Vector3(0, -0.46, 0.1)),
		plane_through(Vector3(0.7, 0.7, 0), Vector3(0.775, 0.30, 0.1)),
		plane_through(Vector3(0.7, -0.7, 0), Vector3(0.775, -0.30, 0.1)),
	]
	solid("gun", bow, 0.012)
	# bow plate studs and tow eyes
	for sd: int in [-1, 1]:
		box("iron", Vector3(0.775, 0.3 * sd, 0.12), Vector3(0.03, 0.05, 0.05), 0.004)
		torus("steel", Vector3(0.80, 0.3 * sd, 0.12), Vector3(1, 0, 0), 0.02, 0.005, 12, 5)
		cyl("steel", Vector3(0.805, 0.3 * sd, 0.1), Vector3(0.805, 0.3 * sd, 0.14), 0.006, 6, 0.0)
		rivet_line(
			"steel",
			Vector3(0.757, 0.12 * sd + 0.08 * sd, 0.07),
			Vector3(0.757, 0.44 * sd, 0.07),
			Vector3(1, 0, 0.5),
			3,
			0.007
		)
		# front mudguards over the idlers
		box_t(
			"gun",
			Transform3D(
				Basis(
					Vector3(cos(-0.2), 0, sin(-0.2)),
					Vector3(0, 1, 0),
					Vector3(-sin(-0.2), 0, cos(-0.2))
				),
				Vector3(0.58, 0.385 * sd, 0.215)
			),
			Vector3(0.26, 0.2, 0.012),
			0.004
		)
		bar(
			"steel",
			Vector3(0.455, 0.29 * sd, 0.222),
			Vector3(0.70, 0.29 * sd, 0.19),
			0.01,
			0.01,
			Vector3(0, 0, 1),
			0.002
		)
		# headlamp in a guard
		box("iron", Vector3(0.67, 0.37 * sd, 0.226), Vector3(0.06, 0.06, 0.03), 0.004)
		box("lamp", Vector3(0.7, 0.37 * sd, 0.229), Vector3(0.012, 0.04, 0.018), 0.0)
		bar(
			"steel",
			Vector3(0.655, 0.34 * sd, 0.252),
			Vector3(0.705, 0.34 * sd, 0.252),
			0.004,
			0.004
		)
		bar(
			"steel",
			Vector3(0.655, 0.40 * sd, 0.252),
			Vector3(0.705, 0.40 * sd, 0.252),
			0.004,
			0.004
		)
		# rear fenders
		box("gun", Vector3(-0.50, 0.385 * sd, 0.2), Vector3(0.2, 0.2, 0.012), 0.004)
		# spare track links on the side wall
		for li: int in 5:
			box(
				"track",
				Vector3(-0.06 + 0.07 * li, 0.428 * sd, 0.264),
				Vector3(0.056, 0.012, 0.03),
				0.003
			)
			box(
				"iron",
				Vector3(-0.06 + 0.07 * li, 0.436 * sd, 0.268),
				Vector3(0.02, 0.006, 0.026),
				0.0
			)
	# glacis: spare links, cable, hatches
	for li2: int in 6:
		box_t(
			"track",
			Transform3D(
				frame(Vector3(0, 1, 0), Vector3(0.5, 0, 0.866)),
				Vector3(0.545 + 0.0, -0.24 + 0.075 * li2, 0.285 - 0.0)
			),
			Vector3(0.05, 0.065, 0.014),
			0.003
		)
	# tow cable loops along the glacis edge
	for sd2: int in [-1, 1]:
		bar(
			"steel",
			Vector3(0.565, 0.18 * sd2, 0.268),
			Vector3(0.655, 0.18 * sd2, 0.2),
			0.009,
			0.009,
			Vector3(0, 0, 1),
			0.0
		)
		bar(
			"steel",
			Vector3(0.565, 0.21 * sd2, 0.268),
			Vector3(0.655, 0.21 * sd2, 0.2),
			0.009,
			0.009,
			Vector3(0, 0, 1),
			0.0
		)
	torus("steel", Vector3(0.61, 0.0, 0.236), Vector3(0.5, 0, 0.866), 0.03, 0.005, 14, 5)
	# top plates, seams and rivets
	for x: float in [-0.44, -0.30, 0.34, 0.48]:
		bar(
			"iron",
			Vector3(x, -0.4, 0.3115),
			Vector3(x, 0.4, 0.3115),
			0.005,
			0.003,
			Vector3(0, 0, 1),
			0.0
		)
	for y: float in [-0.34, 0.34]:
		bar(
			"iron",
			Vector3(-0.54, y, 0.3115),
			Vector3(0.46, y, 0.3115),
			0.005,
			0.003,
			Vector3(0, 0, 1),
			0.0
		)
	for sd3: int in [-1, 1]:
		rivet_line(
			"steel",
			Vector3(-0.50, 0.37 * sd3, 0.31),
			Vector3(0.42, 0.37 * sd3, 0.31),
			Vector3(0, 0, 1),
			18
		)
		rivet_line(
			"steel",
			Vector3(-0.50, 0.3 * sd3, 0.31),
			Vector3(-0.32, 0.3 * sd3, 0.31),
			Vector3(0, 0, 1),
			4
		)
		# side wall panel seams
		for x2: float in [-0.35, -0.12, 0.1, 0.34]:
			bar(
				"iron",
				Vector3(x2, 0.4555 * sd3, 0.205),
				Vector3(x2, 0.4555 * sd3, 0.236),
				0.004,
				0.003,
				Vector3(0, sd3, 0),
				0.0
			)
		rivet_line(
			"steel",
			Vector3(-0.5, 0.436 * sd3, 0.26),
			Vector3(0.5, 0.436 * sd3, 0.26),
			Vector3(0, sd3, 0),
			20,
			0.0055
		)
	# turret ring collar
	cyl("iron", Vector3(0, 0, 0.3), Vector3(0, 0, 0.322), 0.345, 32, 0.004)
	cyl("steel", Vector3(0, 0, 0.318), Vector3(0, 0, 0.326), 0.33, 32, 0.003)
	# driver hatch with hinge, vision blocks
	cyl("steel", Vector3(0.40, -0.19, 0.3), Vector3(0.40, -0.19, 0.325), 0.052, 16, 0.004)
	cyl("gun", Vector3(0.40, -0.19, 0.325), Vector3(0.40, -0.19, 0.337), 0.048, 16, 0.004)
	box("steel", Vector3(0.375, -0.19, 0.335), Vector3(0.02, 0.03, 0.016), 0.003)
	cyl("steel", Vector3(0.435, -0.215, 0.335), Vector3(0.435, -0.165, 0.335), 0.006, 6, 0.0)
	for vi: int in 3:
		box_t(
			"glass",
			Transform3D(
				Basis(Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)),
				Vector3(0.455, -0.235 + 0.045 * vi, 0.318)
			),
			Vector3(0.018, 0.034, 0.016),
			0.002
		)
		box("iron", Vector3(0.452, -0.235 + 0.045 * vi, 0.316), Vector3(0.026, 0.04, 0.016), 0.002)
	# second hatch: radio operator
	cyl("steel", Vector3(0.39, 0.2, 0.3), Vector3(0.39, 0.2, 0.322), 0.045, 16, 0.004)
	cyl("gun", Vector3(0.39, 0.2, 0.322), Vector3(0.39, 0.2, 0.332), 0.041, 16, 0.004)
	bar(
		"steel",
		Vector3(0.37, 0.17, 0.338),
		Vector3(0.37, 0.23, 0.338),
		0.01,
		0.006,
		Vector3(0, 0, 1),
		0.001
	)
	# engine deck: louvres, grille frame and fan hatch
	box("iron", Vector3(-0.40, 0, 0.318), Vector3(0.24, 0.62, 0.014), 0.003)
	for li3: int in 9:
		var lx: float = -0.505 + 0.026 * li3
		box_t(
			"steel",
			Transform3D(
				Basis(Vector3(0.98, 0, 0.2), Vector3(0, 1, 0), Vector3(-0.2, 0, 0.98)),
				Vector3(lx, 0, 0.331)
			),
			Vector3(0.022, 0.5, 0.006),
			0.0015
		)
	box("steel", Vector3(-0.40, 0, 0.3125), Vector3(0.25, 0.012, 0.004), 0.0)
	cyl("iron", Vector3(-0.26, -0.22, 0.31), Vector3(-0.26, -0.22, 0.326), 0.045, 14, 0.003)
	for spk: int in 8:
		var sa: float = TAU * spk / 8.0
		bar(
			"steel",
			Vector3(-0.26, -0.22, 0.329),
			Vector3(-0.26 + cos(sa) * 0.04, -0.22 + sin(sa) * 0.04, 0.329),
			0.004,
			0.003,
			Vector3(0, 0, 1),
			0.0
		)
	# exhaust pipes and heat shields (rear corners)
	for sd4: int in [-1, 1]:
		cyl(
			"iron",
			Vector3(-0.545, 0.36 * sd4, 0.275),
			Vector3(-0.61, 0.38 * sd4, 0.275),
			0.03,
			14,
			0.004
		)
		cyl(
			"steel",
			Vector3(-0.60, 0.38 * sd4, 0.275),
			Vector3(-0.625, 0.385 * sd4, 0.275),
			0.034,
			14,
			0.003
		)
		cyl(
			"iron",
			Vector3(-0.622, 0.386 * sd4, 0.275),
			Vector3(-0.628, 0.387 * sd4, 0.275),
			0.022,
			10,
			0.0
		)
		bar(
			"steel",
			Vector3(-0.50, 0.29 * sd4, 0.318),
			Vector3(-0.50, 0.42 * sd4, 0.318),
			0.07,
			0.006,
			Vector3(0, 0, 1),
			0.002
		)
		for k: int in 3:
			bar(
				"iron",
				Vector3(-0.53 - 0.0 * k, (0.31 + 0.04 * k) * sd4, 0.322),
				Vector3(-0.47, (0.31 + 0.04 * k) * sd4, 0.322),
				0.004,
				0.003,
				Vector3(0, 0, 1),
				0.0
			)
	# rear plate: tow shackles, lamps, plate
	for sd5: int in [-1, 1]:
		box("iron", Vector3(-0.585, 0.33 * sd5, 0.16), Vector3(0.03, 0.05, 0.05), 0.004)
		torus("steel", Vector3(-0.61, 0.33 * sd5, 0.16), Vector3(1, 0, 0), 0.02, 0.005, 12, 5)
		box("lamp", Vector3(-0.575, 0.42 * sd5, 0.25), Vector3(0.012, 0.03, 0.02), 0.0)
	box("iron", Vector3(-0.585, 0.0, 0.24), Vector3(0.02, 0.2, 0.06), 0.004)
	# jerry cans on the rear deck, strapped
	for jc: int in 3:
		var jy: float = -0.30 + 0.065 * jc
		box(
			"rust" if jc == 1 else "canvas",
			Vector3(-0.17, jy + 0.0, 0.345),
			Vector3(0.05, 0.055, 0.07),
			0.005
		)
		box("steel", Vector3(-0.17, jy, 0.383), Vector3(0.04, 0.02, 0.008), 0.002)
		bar(
			"iron",
			Vector3(-0.17, jy - 0.028, 0.33),
			Vector3(-0.17, jy + 0.028, 0.33),
			0.006,
			0.0,
			Vector3(0, 0, 1),
			0.0
		)
	bar(
		"steel",
		Vector3(-0.2, -0.33, 0.352),
		Vector3(-0.14, 0.33 - 0.07, 0.352),
		0.006,
		0.004,
		Vector3(0, 0, 1),
		0.0
	)
	# shovel and pick on the left side wall
	bar(
		"steel",
		Vector3(-0.28, -0.43, 0.264),
		Vector3(0.04, -0.43, 0.264),
		0.008,
		0.006,
		Vector3(0, -1, 0),
		0.0
	)
	box("steel", Vector3(0.07, -0.43, 0.264), Vector3(0.06, 0.004, 0.034), 0.002)
	box("iron", Vector3(-0.12, -0.434, 0.266), Vector3(0.016, 0.01, 0.014), 0.002)
	box("iron", Vector3(-0.2, -0.434, 0.266), Vector3(0.016, 0.01, 0.014), 0.002)


func build_hull() -> void:
	_tracks()
	_skirts()
	_hull_body()


# ---------------------------------------------------------------------------------------------
# Turret (origin on the turret ring, z up from the ring)
# ---------------------------------------------------------------------------------------------


func build_turret() -> void:
	z_off = 0.32
	# ring skirt
	cyl("iron", Vector3(0, 0, 0), Vector3(0, 0, 0.07), 0.31, 32, 0.004)
	cyl("steel", Vector3(0, 0, 0.03), Vector3(0, 0, 0.062), 0.322, 32, 0.004)
	# shell: faceted cast turret, team paint
	var poly: Array[Vector2] = [
		Vector2(0.36, -0.12),
		Vector2(0.36, 0.12),
		Vector2(0.17, 0.285),
		Vector2(-0.20, 0.285),
		Vector2(-0.36, 0.15),
		Vector2(-0.36, -0.15),
		Vector2(-0.20, -0.285),
		Vector2(0.17, -0.285),
	]
	var planes: Array[Plane] = [Plane(Vector3(0, 0, -1), -0.06), Plane(Vector3(0, 0, 1), 0.282)]
	for i: int in poly.size():
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % poly.size()]
		var tilt: float = 0.22
		if a.x == 0.36 and b.x == 0.36:
			planes.append(plane_through(Vector3(0.80, 0, 0.60), Vector3(0.20, 0, 0.282)))
			continue
		planes.append(side_plane(a, b, tilt, 0.06))
		# roof edge chamfer
		var e: Vector2 = b - a
		var n2: Vector2 = Vector2(e.y, -e.x).normalized()
		if n2.dot(Vector2.ZERO - a) > 0.0:
			n2 = -n2
		var ins: Vector2 = a - n2 * 0.045
		planes.append(
			plane_through(Vector3(n2.x * 0.62, n2.y * 0.62, 0.78), Vector3(ins.x, ins.y, 0.282))
		)
	solid("team", planes, 0.011)
	# front mantlet and cradle
	box("gun", Vector3(0.335, 0, 0.145), Vector3(0.06, 0.34, 0.14), 0.01)
	box("steel", Vector3(0.375, 0, 0.145), Vector3(0.04, 0.2, 0.1), 0.008)
	cyl("steel", Vector3(0.37, 0, 0.145), Vector3(0.56, 0, 0.145), 0.042, 18, 0.005)
	cyl("gun", Vector3(0.55, 0, 0.145), Vector3(1.09, 0, 0.145), 0.026, 16, 0.002)
	cyl("steel", Vector3(0.64, 0, 0.145), Vector3(0.78, 0, 0.145), 0.036, 16, 0.004)
	for cx: float in [0.60, 0.86, 0.96]:
		cyl("iron", Vector3(cx, 0, 0.145), Vector3(cx + 0.02, 0, 0.145), 0.031, 14, 0.002)
	cyl("steel", Vector3(1.04, 0, 0.145), Vector3(1.165, 0, 0.145), 0.035, 16, 0.003)
	for sl: float in [1.07, 1.10, 1.13]:
		cyl("iron", Vector3(sl, 0, 0.145), Vector3(sl + 0.012, 0, 0.145), 0.0365, 16, 0.0)
	cyl("glass", Vector3(1.165, 0, 0.145), Vector3(1.1665, 0, 0.145), 0.013, 10, 0.0)
	# mantlet bolts and range-finder
	for sd: int in [-1, 1]:
		for bz: float in [0.1, 0.19]:
			dome("steel", Vector3(0.366, 0.14 * sd, bz), Vector3(1, 0, 0), 0.007, 6)
		box("gun", Vector3(0.26, 0.2 * sd, 0.27), Vector3(0.07, 0.05, 0.05), 0.006)
		box("glass", Vector3(0.298, 0.2 * sd, 0.27), Vector3(0.006, 0.034, 0.03), 0.0)
	# the two lamp posts (the tank's horns)
	for sd2: int in [-1, 1]:
		cyl(
			"steel",
			Vector3(0.16, 0.31 * sd2, 0.095),
			Vector3(0.16, 0.31 * sd2, 0.295),
			0.026,
			12,
			0.003
		)
		cyl(
			"iron",
			Vector3(0.16, 0.31 * sd2, 0.255),
			Vector3(0.16, 0.31 * sd2, 0.268),
			0.032,
			12,
			0.002
		)
		cyl(
			"lamp",
			Vector3(0.16, 0.31 * sd2, 0.295),
			Vector3(0.16, 0.31 * sd2, 0.32),
			0.022,
			12,
			0.003
		)
	# smoke dischargers: 4 tubes per side on a bracket
	for sd3: int in [-1, 1]:
		box("iron", Vector3(0.0, 0.305 * sd3, 0.165), Vector3(0.13, 0.02, 0.028), 0.003)
		for k: int in 4:
			var kx: float = -0.045 + 0.03 * k
			cyl(
				"steel",
				Vector3(kx, 0.31 * sd3, 0.165),
				Vector3(kx + 0.0, 0.345 * sd3, 0.2),
				0.0105,
				8,
				0.0015
			)
			cyl(
				"iron",
				Vector3(kx, 0.343 * sd3, 0.198),
				Vector3(kx, 0.347 * sd3, 0.202),
				0.0075,
				8,
				0.0
			)
	shift = Vector3(0, 0, 0.032)
	# roof: commander cupola with vision blocks and a machine gun
	cyl("steel", Vector3(-0.11, 0.12, 0.248), Vector3(-0.11, 0.12, 0.292), 0.07, 20, 0.004)
	cyl("gun", Vector3(-0.11, 0.12, 0.29), Vector3(-0.11, 0.12, 0.3), 0.062, 20, 0.003)
	for vi: int in 8:
		var va: float = TAU * vi / 8.0
		var vp: Vector3 = Vector3(-0.11 + cos(va) * 0.066, 0.12 + sin(va) * 0.066, 0.272)
		box_t(
			"glass",
			Transform3D(
				Basis(
					Vector3(cos(va), sin(va), 0), Vector3(-sin(va), cos(va), 0), Vector3(0, 0, 1)
				),
				vp
			),
			Vector3(0.012, 0.03, 0.02),
			0.001
		)
	cyl("steel", Vector3(-0.11, 0.12, 0.3), Vector3(-0.11, 0.12, 0.315), 0.012, 8, 0.0)
	box("gun", Vector3(-0.07, 0.12, 0.323), Vector3(0.09, 0.03, 0.03), 0.004)
	cyl("iron", Vector3(-0.025, 0.12, 0.323), Vector3(0.07, 0.12, 0.323), 0.007, 8, 0.0)
	box("steel", Vector3(-0.1, 0.165, 0.318), Vector3(0.04, 0.03, 0.026), 0.003)
	torus("steel", Vector3(-0.11, 0.12, 0.31), Vector3(0, 0, 1), 0.04, 0.004, 16, 5)
	# loader hatch with hinge and handle
	cyl("steel", Vector3(-0.12, -0.13, 0.25), Vector3(-0.12, -0.13, 0.264), 0.064, 18, 0.004)
	cyl("gun", Vector3(-0.12, -0.13, 0.264), Vector3(-0.12, -0.13, 0.275), 0.058, 18, 0.004)
	cyl(
		"steel",
		Vector3(-0.175, -0.13 - 0.03, 0.272),
		Vector3(-0.175, -0.13 + 0.03, 0.272),
		0.006,
		8,
		0.0
	)
	box("steel", Vector3(-0.07, -0.13, 0.284), Vector3(0.026, 0.012, 0.008), 0.002)
	cyl("glass", Vector3(-0.12, -0.13, 0.275), Vector3(-0.12, -0.13, 0.2765), 0.016, 10, 0.0)
	# gunner sight on the roof
	box("gun", Vector3(0.09, -0.14, 0.282), Vector3(0.1, 0.085, 0.06), 0.008)
	box("glass", Vector3(0.1405, -0.14, 0.282), Vector3(0.004, 0.05, 0.034), 0.0)
	box("steel", Vector3(0.04, -0.14, 0.317), Vector3(0.03, 0.05, 0.012), 0.002)
	# roof rivets and seams
	for sx: float in [-0.24, 0.0, 0.12]:
		bar(
			"iron",
			Vector3(sx, -0.19, 0.2515),
			Vector3(sx, 0.19, 0.2515),
			0.004,
			0.003,
			Vector3(0, 0, 1),
			0.0
		)
	rivet_line(
		"steel",
		Vector3(-0.30, -0.23, 0.252),
		Vector3(0.15, -0.23, 0.252),
		Vector3(0, 0, 1),
		9,
		0.0065
	)
	rivet_line(
		"steel",
		Vector3(-0.30, 0.23, 0.252),
		Vector3(0.15, 0.23, 0.252),
		Vector3(0, 0, 1),
		9,
		0.0065
	)
	shift = Vector3.ZERO
	# flank stowage boxes
	box("iron", Vector3(-0.16, 0.312, 0.15), Vector3(0.16, 0.036, 0.075), 0.005)
	for k2: int in 2:
		bar(
			"steel",
			Vector3(-0.2 + 0.08 * k2, 0.334, 0.113),
			Vector3(-0.2 + 0.08 * k2, 0.334, 0.19),
			0.012,
			0.004,
			Vector3(0, 1, 0),
			0.0
		)
		dome("steel", Vector3(-0.2 + 0.08 * k2, 0.336, 0.15), Vector3(0, 1, 0), 0.008, 6)
	box("canvas", Vector3(-0.17, -0.31, 0.16), Vector3(0.2, 0.034, 0.07), 0.01)
	for k3: int in 3:
		bar(
			"iron",
			Vector3(-0.24 + 0.07 * k3, -0.33, 0.125),
			Vector3(-0.24 + 0.07 * k3, -0.33, 0.2),
			0.008,
			0.004,
			Vector3(0, -1, 0),
			0.0
		)
	# rear stowage bin, cage frame, tarp roll
	box("iron", Vector3(-0.44, 0, 0.14), Vector3(0.16, 0.5, 0.13), 0.008)
	for k4: int in 5:
		bar(
			"steel",
			Vector3(-0.525, -0.22 + 0.11 * k4, 0.075),
			Vector3(-0.525, -0.22 + 0.11 * k4, 0.205),
			0.008,
			0.005,
			Vector3(1, 0, 0),
			0.0
		)
	bar(
		"steel",
		Vector3(-0.525, -0.25, 0.1),
		Vector3(-0.525, 0.25, 0.1),
		0.008,
		0.005,
		Vector3(1, 0, 0),
		0.0
	)
	bar(
		"steel",
		Vector3(-0.525, -0.25, 0.18),
		Vector3(-0.525, 0.25, 0.18),
		0.008,
		0.005,
		Vector3(1, 0, 0),
		0.0
	)
	cyl("canvas", Vector3(-0.44, -0.24, 0.235), Vector3(-0.44, 0.24, 0.235), 0.042, 14, 0.004)
	for k5: int in 3:
		var ky: float = -0.16 + 0.16 * k5
		cyl("iron", Vector3(-0.44, ky, 0.235), Vector3(-0.44, ky + 0.012, 0.235), 0.045, 14, 0.0)
	shift = Vector3(0, 0, 0.032)
	# aerial base and whip
	cyl("steel", Vector3(-0.26, -0.2, 0.25), Vector3(-0.26, -0.2, 0.285), 0.018, 10, 0.003)
	cyl("iron", Vector3(-0.26, -0.2, 0.285), Vector3(-0.26, -0.2, 0.46), 0.0035, 6, 0.0)
	# emblem plate on the left cheek (raised, no text)
	cyl("gun", Vector3(0.04, -0.2905, 0.14), Vector3(0.04, -0.2965, 0.14), 0.04, 18, 0.0015)
	cyl("steel", Vector3(0.04, -0.2965, 0.14), Vector3(0.04, -0.2985, 0.14), 0.022, 18, 0.0)


# ---------------------------------------------------------------------------------------------


func _material(name: String) -> ShaderMaterial:
	if _mat_cache.has(name):
		return _mat_cache[name]
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("nz", _noise_tex())
	m.set_shader_parameter("z_off", z_off)
	if name == "team":
		m.set_shader_parameter("base", Color(team_hex))
		m.set_shader_parameter("metal", 0.1)
		m.set_shader_parameter("rough", 0.52)
		m.set_shader_parameter("kind", 1)
	else:
		var d: Array = MATS[name]
		m.set_shader_parameter("base", d[0])
		m.set_shader_parameter("metal", d[1])
		m.set_shader_parameter("rough", d[2])
		m.set_shader_parameter("kind", d[3])
	m.set_shader_parameter("soot_a", Vector3(-0.62, 0.275, 0.38))
	m.set_shader_parameter("soot_b", Vector3(-0.62, 0.275, -0.38))
	_mat_cache[name] = m
	return m


func to_node(shadow_caster: bool = true) -> Node3D:
	var root: Node3D = Node3D.new()
	tris = 0
	for mat: String in _acc:
		var a: Acc = _acc[mat]
		if a.v.is_empty():
			continue
		var arr: Array = []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = a.v
		arr[Mesh.ARRAY_NORMAL] = a.n
		arr[Mesh.ARRAY_COLOR] = a.c
		arr[Mesh.ARRAY_INDEX] = a.idx
		var am: ArrayMesh = ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.mesh = am
		mi.material_override = _material(mat)
		mi.cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			if shadow_caster
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		)
		root.add_child(mi)
		tris += a.idx.size() / 3
	return root


static func make(part: String, hex: String) -> DetailTank:
	var t: DetailTank = DetailTank.new()
	t.team_hex = hex if hex != "" else "#D234D2"
	if part == "hull":
		t.build_hull()
	else:
		t.build_turret()
	return t
