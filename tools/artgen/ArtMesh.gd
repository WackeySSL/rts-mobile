class_name ArtMesh
extends RefCounted
## The flat faces of an `ArtPrim`, in the model's frame, each with its outward normal. A box, a
## wedge and a prism are all one solid: a ring of `sides` points at the bottom and the same ring,
## scaled by `taper` and cut by `slope`, at the top, joined by one quad per side. A sphere has no
## faces (`ArtRender` draws it as discs), a rod none (it is a stroke). A `broken` box is concave:
## its front and back are polygons with a zigzag top, and each tooth segment is a quad oriented
## against a point below its own middle. A primitive with moves (a pose frame, `ArtPrim.moved`) has
## its faces placed by them, after the rest faces are built.


## One flat face (convex, except the front and back of a `broken` box): its points and the unit
## normal that points out of the solid.
class Face:
	extends RefCounted
	var points: PackedVector3Array = PackedVector3Array()
	var normal: Vector3 = Vector3.UP


## A unit vector at `degrees`, rounded to 1e-9 so that two libm builds cannot disagree on a digit.
static func dir(degrees: float) -> Vector2:
	var radians: float = deg_to_rad(degrees)
	return Vector2(snappedf(cos(radians), 1e-9), snappedf(sin(radians), 1e-9))


static func faces(prim: ArtPrim) -> Array[Face]:
	var found: Array[Face] = []
	if prim.shape in [&"sphere", &"rod"]:
		return found
	if prim.shape == &"broken":
		_broken(prim, found)
		return _placed(prim, found)
	var dims: Vector3 = _dims(prim)
	var sides: int = prim.sides
	var circ: float = 0.5 / cos(PI / sides)
	var bottom: PackedVector3Array = PackedVector3Array()
	var top: PackedVector3Array = PackedVector3Array()
	# The mean of the corners lies inside a convex solid. The middle of the box does not do: a wedge
	# of slope 1 has its sloped face through it, and a normal oriented against it is a coin toss.
	var inside: Vector3 = Vector3.ZERO
	for i: int in sides:
		var ring: Vector2 = dir((i + 0.5) * 360.0 / sides) * circ
		var u: float = ring.x * dims.x
		var v: float = ring.y * dims.y
		var t: float = u / dims.x + 0.5
		var drop: float = prim.slope * t if prim.slope >= 0.0 else -prim.slope * (1.0 - t)
		bottom.append(_local(prim, u, v, 0.0))
		top.append(_local(prim, u * prim.taper, v * prim.taper, dims.z * (1.0 - drop)))
		inside += bottom[i] + top[i]
	inside /= 2.0 * sides
	for i: int in sides:
		var j: int = (i + 1) % sides
		_add(found, PackedVector3Array([bottom[i], bottom[j], top[j], top[i]]), inside)
	_add(found, top, inside)
	_add(found, bottom, inside)
	return _placed(prim, found)


## `found` with the faces placed by the moves of `prim`.
static func _placed(prim: ArtPrim, found: Array[Face]) -> Array[Face]:
	if not prim.moves.is_empty() or not prim.fixed.is_empty():
		for face: Face in found:
			for i: int in face.points.size():
				face.points[i] = prim.place(face.points[i])
			face.normal = prim.spin(face.normal)
	return found


## The faces of a `broken` box: the front and the back as polygons with the zigzag top, the two
## ends, the bottom, and one quad per tooth segment.
static func _broken(prim: ArtPrim, found: Array[Face]) -> void:
	var along_x: bool = prim.size.x >= prim.size.y
	var length: float = prim.size.x if along_x else prim.size.y
	var half: float = (prim.size.y if along_x else prim.size.x) / 2.0
	var fractions: PackedFloat64Array = prim.tooth_fractions()
	var last: int = prim.teeth - 1
	var at: PackedFloat64Array = PackedFloat64Array()
	var top: PackedFloat64Array = PackedFloat64Array()
	for i: int in prim.teeth:
		at.append(-length / 2.0 + length * i / last)
		top.append(fractions[i] * prim.size.z)
	var pt: Callable = func(t: float, v: float, w: float) -> Vector3:
		return (
			Vector3(prim.centre.x + t, prim.centre.y + v, prim.z0 + w)
			if along_x
			else Vector3(prim.centre.x + v, prim.centre.y + t, prim.z0 + w)
		)
	var inside: Vector3 = pt.call(0.0, 0.0, prim.size.z * prim.low / 2.0)
	for side: float in [-half, half]:
		var ring: PackedVector3Array = PackedVector3Array([pt.call(at[0], side, 0.0)])
		ring.append(pt.call(at[last], side, 0.0))
		for i: int in range(last, -1, -1):
			ring.append(pt.call(at[i], side, top[i]))
		_add(found, ring, inside)
	for i: int in last:
		var quad: PackedVector3Array = PackedVector3Array(
			[
				pt.call(at[i], -half, top[i]),
				pt.call(at[i + 1], -half, top[i + 1]),
				pt.call(at[i + 1], half, top[i + 1]),
				pt.call(at[i], half, top[i]),
			]
		)
		_add(found, quad, pt.call((at[i] + at[i + 1]) / 2.0, 0.0, 0.0))
	for end: int in [0, last]:
		var cap: PackedVector3Array = PackedVector3Array(
			[
				pt.call(at[end], -half, 0.0),
				pt.call(at[end], half, 0.0),
				pt.call(at[end], half, top[end]),
				pt.call(at[end], -half, top[end]),
			]
		)
		_add(found, cap, inside)
	var floor_ring: PackedVector3Array = PackedVector3Array(
		[
			pt.call(at[0], -half, 0.0),
			pt.call(at[last], -half, 0.0),
			pt.call(at[last], half, 0.0),
			pt.call(at[0], half, 0.0),
		]
	)
	_add(found, floor_ring, inside)


## The extent along the ring's two axes and along its length: (u, v, w).
static func _dims(prim: ArtPrim) -> Vector3:
	var s: Vector3 = prim.size
	match prim.axis:
		0:
			return Vector3(s.y, s.z, s.x)
		1:
			return Vector3(s.z, s.x, s.y)
	return s


## The model-frame point of ring coordinates (u, v) and length w; axis x lays the ring in y-z, axis
## y in z-x, axis z (up) in x-y.
static func _local(prim: ArtPrim, u: float, v: float, w: float) -> Vector3:
	var c: Vector2 = prim.centre
	var s: Vector3 = prim.size
	match prim.axis:
		0:
			return Vector3(c.x - s.x / 2.0 + w, c.y + u, prim.z0 + s.z / 2.0 + v)
		1:
			return Vector3(c.x + v, c.y - s.y / 2.0 + w, prim.z0 + s.z / 2.0 + u)
	return Vector3(c.x + u, c.y + v, prim.z0 + w)


## Adds the face of `ring` (points that coincide are dropped; a face without an area is not one),
## its normal turned away from `inside`, a point inside the solid.
static func _add(found: Array[Face], ring: PackedVector3Array, inside: Vector3) -> void:
	var face: Face = Face.new()
	for point: Vector3 in ring:
		if face.points.is_empty() or not face.points[-1].is_equal_approx(point):
			face.points.append(point)
	if face.points.size() > 1 and face.points[0].is_equal_approx(face.points[-1]):
		face.points.remove_at(face.points.size() - 1)
	var normal: Vector3 = Vector3.ZERO
	var mean: Vector3 = Vector3.ZERO
	for i: int in face.points.size():
		var a: Vector3 = face.points[i]
		var b: Vector3 = face.points[(i + 1) % face.points.size()]
		normal += Vector3(
			(a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y)
		)
		mean += a / face.points.size()
	if face.points.size() < 3 or normal.length() < 1e-9:
		return
	face.normal = normal.normalized()
	if face.normal.dot(mean - inside) < 0.0:
		face.normal = -face.normal
	found.append(face)
