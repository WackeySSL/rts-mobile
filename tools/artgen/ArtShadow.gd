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
const AO_REACH: float = 0.3  ## Tiles the occlusion pad reaches past the ground outline.
const AO_STEPS: int = 3  ## Stepped rings, no gradient; the inner ones stack to the darker pad.
const AO_STEP_ALPHA: String = "0.3"  ## Each ring's fill-opacity, inside the group's 35 %.
const CONTACT_PX: int = 2  ## The contact line's width (nothing thinner than 2 px at 2x).
const CONTACT_Z: float = 0.02  ## A primitive that starts below this height stands on the ground.
const GROUND_Z: float = 0.25  ## A primitive that starts below this height touches the ground.
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


## The frame of a shadow part: the occlusion pad and the contact line round the base, then the cast
## shadow over them (ADR 0035 section 4). The pad is `AO_STEPS` nested rings of the ground outline,
## each a little wider (to `AO_REACH`), each a black fill at `AO_STEP_ALPHA` so the rings stack
## darker towards the base; the contact line is `CONTACT_PX` wide and opaque in the group. All of
## it is one group with one opacity: no gradient, and no ink above the ground. `figures` draws one
## contact line per figure of a squad instead of one round them all.
static func frame(
	prims: Array[ArtPrim], yaw: float, figures: bool = false
) -> Array[ArtRender.Poly]:
	var out: Array[ArtRender.Poly] = pad(prims, yaw, figures)
	out.append_array(polys(prims, yaw))
	return out


## The pad rings (widest first), then the contact lines, of `prims` turned by `yaw`. The pad follows
## the outline of everything below `GROUND_Z`, so it also lies under a nose or a rifle that
## overhangs; the contact line follows only what stands on the ground (below `CONTACT_Z`), so it
## runs where the model touches it, round each figure of a squad when `figures` is set. Empty for a
## model with no ground outline.
static func pad(prims: Array[ArtPrim], yaw: float, figures: bool = false) -> Array[ArtRender.Poly]:
	var out: Array[ArtRender.Poly] = []
	var outline: Array[Vector2] = _hull(_ground(prims, yaw, GROUND_Z))
	if outline.size() < 3:
		return out
	for step: int in range(AO_STEPS, 0, -1):
		var ring: Array[Vector2] = _grow(outline, AO_REACH * step / AO_STEPS)
		var poly: ArtRender.Poly = _screen(ring)
		poly.fill = COLOUR
		poly.fill_opacity = AO_STEP_ALPHA
		out.append(poly)
	var buckets: Dictionary[String, Array] = {}
	for prim: ArtPrim in prims:
		var key: String = _figure(prim) if figures else ""
		if not buckets.has(key):
			buckets[key] = [] as Array[ArtPrim]
		buckets[key].append(prim)
	var keys: Array = buckets.keys()
	keys.sort()
	for key: String in keys:
		var typed: Array[ArtPrim] = []
		typed.assign(buckets[key])
		var base: Array[Vector2] = _hull(_ground(typed, yaw, CONTACT_Z))
		if base.size() < 3:
			continue
		var line: ArtRender.Poly = _screen(base)
		line.fill = "none"
		line.stroke = COLOUR
		line.stroke_px = CONTACT_PX
		out.append(line)
	return out


## The figure of a squad a primitive belongs to: the first letter of its group (`a_body` is a).
static func _figure(prim: ArtPrim) -> String:
	return String(prim.group).substr(0, 1)


## The ground points (z ignored) of the primitives that start below `below`, in tiles.
static func _ground(prims: Array[ArtPrim], yaw: float, below: float) -> Array[Vector2]:
	var found: Array[Vector2] = []
	for prim: ArtPrim in prims:
		if prim.z0 >= below:
			continue
		if prim.shape == &"sphere":
			var radius: float = prim.size.x / 2.0
			var centre: Vector3 = ArtRender.rotate(Vector3(prim.centre.x, prim.centre.y, 0.0), yaw)
			for i: int in SPHERE_POINTS:
				var rim: Vector2 = ArtMesh.dir(i * 360.0 / SPHERE_POINTS)
				found.append(Vector2(centre.x + radius * rim.x, centre.y + radius * rim.y))
			continue
		for face: ArtMesh.Face in ArtMesh.faces(prim):
			for point: Vector3 in face.points:
				var turned: Vector3 = ArtRender.rotate(point, yaw)
				found.append(Vector2(turned.x, turned.y))
	return found


## `ring` (convex, any winding) pushed out by `reach` tiles, corners mitred.
static func _grow(ring: Array[Vector2], reach: float) -> Array[Vector2]:
	var grown: Array[Vector2] = []
	var shapes: Array[PackedVector2Array] = Geometry2D.offset_polygon(
		PackedVector2Array(ring), reach, Geometry2D.JOIN_MITER
	)
	if shapes.is_empty():
		push_error("ArtShadow: the offset of a ground outline is empty")
		return ring
	for point: Vector2 in shapes[0]:
		grown.append(point)
	return grown


static func _screen(ring: Array[Vector2]) -> ArtRender.Poly:
	var poly: ArtRender.Poly = ArtRender.Poly.new()
	for point: Vector2 in ring:
		poly.points.append(ArtRender.project(Vector3(point.x, point.y, 0.0)))
	return poly


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
