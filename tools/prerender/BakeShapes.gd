class_name BakeShapes
extends RefCounted
## Primitives on top of `BakeMesh` (P655's, rewritten): oriented boxes and bars from planes, and
## the round ones, cylinder or cone, dome and torus. Round shapes carry smooth normals that point
## away from their axis, so a facet never shows as a flat patch.

const DOME_RISE: float = 0.55  ## A dome rises this share of its radius.


## An oriented box: `xf` places its centre and axes, `size` is its extent along each axis.
static func box_t(
	m: BakeMesh, mat: StringName, xf: Transform3D, size: Vector3, bevel: float = BakeMesh.BEVEL
) -> void:
	var planes: Array[Plane] = []
	for axis: int in 3:
		for sign: int in [-1, 1]:
			var n: Vector3 = xf.basis[axis].normalized() * float(sign)
			planes.append(Plane(n, n.dot(xf.origin) + size[axis] * 0.5))
	m.solid(mat, planes, minf(bevel, minf(size.x, minf(size.y, size.z)) * 0.3))


static func box(
	m: BakeMesh, mat: StringName, centre: Vector3, size: Vector3, bevel: float = BakeMesh.BEVEL
) -> void:
	box_t(m, mat, Transform3D(Basis.IDENTITY, centre), size, bevel)


## A long thin box from `a` to `b`: `w` across, `h` along z.
static func bar(
	m: BakeMesh, mat: StringName, a: Vector3, b: Vector3, w: float, h: float, bevel: float = 0.0
) -> void:
	var x: Vector3 = (b - a).normalized()
	var up: Vector3 = Vector3.BACK if absf(x.z) < 0.97 else Vector3.UP
	var z: Vector3 = (up - x * x.dot(up)).normalized()
	var basis: Basis = Basis(x, z.cross(x), z)
	box_t(m, mat, Transform3D(basis, (a + b) * 0.5), Vector3(a.distance_to(b), w, h), bevel)


## A cylinder from `a` to `b`, a cone when `radius2` is at least 0, with `chamfer` ring at both
## ends when it has caps.
static func cylinder(
	m: BakeMesh,
	mat: StringName,
	a: Vector3,
	b: Vector3,
	radius: float,
	segs: int = 16,
	chamfer: float = 0.0,
	radius2: float = -1.0,
	caps: bool = true
) -> void:
	var length: float = a.distance_to(b)
	if length < 1e-6:
		return
	var axis: Vector3 = (b - a) / length
	var end_r: float = radius2 if radius2 >= 0.0 else radius
	var ch: float = minf(chamfer, length * 0.4) if caps else 0.0
	# Each ring: centre, radius, the axial lean of its normal and its bevel flag.
	var rings: Array[Array] = [[a, radius, 0.0, 0.0], [b, end_r, 0.0, 0.0]]
	if ch > 0.0:
		rings = [
			[a, radius - ch, -1.0, 0.0],
			[a + axis * ch, radius, -0.5, 1.0],
			[b - axis * ch, end_r, 0.5, 1.0],
			[b, end_r - ch, 1.0, 0.0],
		]
	var slope: float = (radius - end_r) / length
	var frame: Array[Vector3] = _frame(axis)
	for s: int in segs:
		var d0: Vector3 = _around(frame, s, segs)
		var d1: Vector3 = _around(frame, s + 1, segs)
		for band: int in rings.size() - 1:
			var lean: bool = rings.size() == 2 or band == 1
			_quad(m, mat, rings[band], rings[band + 1], [d0, d1], axis, slope if lean else NAN)
		if caps:
			_cap(m, mat, rings[0], [d0, d1], -axis)
			_cap(m, mat, rings[rings.size() - 1], [d0, d1], axis)


## A shallow dome on the disc of `radius` at `centre`, facing `normal`.
static func dome(
	m: BakeMesh, mat: StringName, centre: Vector3, normal: Vector3, radius: float, segs: int = 6
) -> void:
	var n: Vector3 = normal.normalized()
	var frame: Array[Vector3] = _frame(n)
	var top: Vector3 = centre + n * radius * DOME_RISE
	for s: int in segs:
		var d0: Vector3 = _around(frame, s, segs)
		var d1: Vector3 = _around(frame, s + 1, segs)
		var n0: Vector3 = (d0 * 0.8 + n * 0.6).normalized()
		var n1: Vector3 = (d1 * 0.8 + n * 0.6).normalized()
		m.tri(
			mat,
			[centre + d0 * radius, centre + d1 * radius, top],
			[n0, n1, n],
			PackedFloat32Array([0.6, 0.6, 1.0])
		)


## A ring of tube radius `small` round `axis`, its centre circle of radius `big`.
static func torus(
	m: BakeMesh,
	mat: StringName,
	centre: Vector3,
	axis: Vector3,
	big: float,
	small: float,
	segs: int = 14,
	sides: int = 6
) -> void:
	var ax: Vector3 = axis.normalized()
	var frame: Array[Vector3] = _frame(ax)
	var flat: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0])
	for s: int in segs:
		var d: Array[Vector3] = [_around(frame, s, segs), _around(frame, s + 1, segs)]
		for q: int in sides:
			var corner: Array[Vector3] = []  # p00, p01, p10, p11 and their normals
			var normal: Array[Vector3] = []
			for i: int in 4:
				var a: float = TAU * float(q + i % 2) / sides
				var n: Vector3 = d[i / 2] * cos(a) + ax * sin(a)
				normal.append(n)
				corner.append(centre + d[i / 2] * big + n * small)
			m.tri(mat, [corner[0], corner[2], corner[3]], [normal[0], normal[2], normal[3]], flat)
			m.tri(mat, [corner[0], corner[3], corner[1]], [normal[0], normal[3], normal[1]], flat)


## Two unit vectors across `axis`.
static func _frame(axis: Vector3) -> Array[Vector3]:
	var hint: Vector3 = Vector3.UP if absf(axis.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var u: Vector3 = axis.cross(hint).normalized()
	return [u, axis.cross(u)]


static func _around(frame: Array[Vector3], step: int, steps: int) -> Vector3:
	var t: float = TAU * float(step) / steps
	return frame[0] * cos(t) + frame[1] * sin(t)


## The band between two rings over one segment; `slope` is NAN for a chamfer, which leans by its
## rings instead.
static func _quad(
	m: BakeMesh,
	mat: StringName,
	r0: Array,
	r1: Array,
	d: Array[Vector3],
	axis: Vector3,
	slope: float
) -> void:
	var p: Array[Vector3] = []
	var n: Array[Vector3] = []
	var e: Array[float] = []
	for i: int in 4:
		var ring: Array = r1 if i >= 2 else r0
		var dir: Vector3 = d[i % 2]
		p.append(ring[0] + dir * ring[1])
		n.append((dir + axis * (ring[2] if is_nan(slope) else slope)).normalized())
		e.append(ring[3])
	m.tri(mat, [p[0], p[1], p[3]], [n[0], n[1], n[3]], PackedFloat32Array([e[0], e[1], e[3]]))
	m.tri(mat, [p[0], p[3], p[2]], [n[0], n[3], n[2]], PackedFloat32Array([e[0], e[3], e[2]]))


static func _cap(
	m: BakeMesh, mat: StringName, ring: Array, d: Array[Vector3], normal: Vector3
) -> void:
	var flat: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0])
	m.tri(
		mat,
		[ring[0], ring[0] + d[0] * ring[1], ring[0] + d[1] * ring[1]],
		[normal, normal, normal],
		flat
	)
