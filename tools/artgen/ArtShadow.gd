class_name ArtShadow
extends RefCounted
## Cast shadows (ADR 0023 section 5, canvas Spec 02): every primitive dropped onto the ground
## towards the south-east of the screen (+gx), black at 35 % as one group, about 0.8 x its height
## long. A point at height z lands `REACH x z` tiles further along +gx; a convex solid's shadow is
## the convex hull of its dropped corners, a sphere's an ellipse. The light does not turn with a
## unit, so the unit is turned first and the shadow always falls the same way on the screen.

const REACH: float = 0.8  ## Tiles along +gx per tile of height (Spec 02: about 0.8 x the height).
const COLOUR: String = "#000000"
const OPACITY: String = "0.35"
const SPHERE_POINTS: int = 16
const COLLINEAR: float = 1e-9  ## Square tiles: a corner this close to a line is not a corner.


## One black polygon per primitive that has a shadow, in screen px relative to the model's origin,
## for the model turned by `yaw` degrees.
static func polys(prims: Array[ArtPrim], yaw: float) -> Array[ArtRender.Poly]:
	var out: Array[ArtRender.Poly] = []
	for prim: ArtPrim in prims:
		var ring: Array[Vector2] = _hull(_dropped(prim, yaw))
		if ring.size() < 3:
			continue
		var poly: ArtRender.Poly = ArtRender.Poly.new()
		for point: Vector2 in ring:
			poly.points.append(ArtRender.project(Vector3(point.x, point.y, 0.0)))
		poly.fill = COLOUR
		out.append(poly)
	return out


## The corners of `prim` turned by `yaw` and dropped onto the ground, in tiles.
static func _dropped(prim: ArtPrim, yaw: float) -> Array[Vector2]:
	var found: Array[Vector2] = []
	if prim.shape == &"sphere":
		var radius: float = prim.size.x / 2.0
		var centre: Vector3 = ArtRender.rotate(
			Vector3(prim.centre.x, prim.centre.y, prim.z0 + radius), yaw
		)
		var stretch: float = sqrt(1.0 + REACH * REACH)
		for i: int in SPHERE_POINTS:
			var rim: Vector2 = ArtMesh.dir(i * 360.0 / SPHERE_POINTS)
			found.append(
				Vector2(
					centre.x + REACH * centre.z + radius * stretch * rim.x,
					centre.y + radius * rim.y
				)
			)
		return found
	for face: ArtMesh.Face in ArtMesh.faces(prim):
		for point: Vector3 in face.points:
			var turned: Vector3 = ArtRender.rotate(point, yaw)
			found.append(Vector2(turned.x + REACH * turned.z, turned.y))
	return found


## The convex hull of `points` (Andrew's monotone chain), without collinear corners; fewer than
## three corners when the points lie on a line.
static func _hull(points: Array[Vector2]) -> Array[Vector2]:
	var sorted: Array[Vector2] = []
	for point: Vector2 in points:
		sorted.append(point.snapped(Vector2.ONE * 1e-6))
	sorted.sort_custom(
		func(a: Vector2, b: Vector2) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y)
	)
	var lower: Array[Vector2] = _chain(sorted)
	sorted.reverse()
	var upper: Array[Vector2] = _chain(sorted)
	lower.pop_back()
	upper.pop_back()
	return lower + upper


static func _chain(points: Array[Vector2]) -> Array[Vector2]:
	var chain: Array[Vector2] = []
	for point: Vector2 in points:
		while chain.size() >= 2 and (chain[-1] - chain[-2]).cross(point - chain[-2]) <= COLLINEAR:
			chain.pop_back()
		chain.append(point)
	return chain
