class_name ArtMesh
extends RefCounted
## The flat faces of an `ArtPrim`, in the model's frame, each with its outward normal. A box, a
## wedge and a prism are all one solid: a ring of `sides` points at the bottom and the same ring,
## scaled by `taper` and cut by `slope`, at the top, joined by one quad per side. A sphere has no
## faces (`ArtRender` draws it as discs).


## One convex face: its points and the unit normal that points out of the solid.
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
	if prim.shape == &"sphere":
		return found
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
	return found


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
