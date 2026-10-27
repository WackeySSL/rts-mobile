class_name ArtRender
extends RefCounted
## One frame of a part (ADR 0023 sections 1 and 5): the primitives turned by a yaw, projected with
## the dimetric 2:1 projection, back faces culled, drawn back to front, lit by the one light.
##
## Model frame: x and y are the grid's gx and gy in tiles, z is up in tiles. At 2x (1 tile =
## 128 x 64 px on the ground) a point is drawn at ((x - y) x 64, (x + y) x 32 - z x Z_PX): the
## ADR's `((gx - gy) x 32, (gx + gy) x 16 - z)` at twice the size, z in tile units of 78.38 px
## (a cube of one tile is 39.2 px high at 1x, Spec 01).


## A drawn polygon in px, relative to the model's origin. An empty `stroke` draws no edge.
class Poly:
	extends RefCounted
	var points: PackedVector2Array = PackedVector2Array()
	var fill: String = ""
	var stroke: String = ""


const Z_PX: float = 78.38367176906169  ## 128 x sqrt(6) / 4: a tile of height at 2x.
const TILE_PX: float = 90.50966799187809  ## One tile's side at 2x: 128 / sqrt(2).
## The direction to the camera: elevation 30 degrees, from the side of +gx and +gy.
const VIEW: Vector3 = Vector3(0.6123724356957945, 0.6123724356957945, 0.5)
const MIN_FACING: float = 0.02  ## A face seen edge-on (below this) is not drawn.
## Spec 02's light from the north-west as a plane: top 100 %, left face 82 %, right face 62 %. The
## weights give those three values for the normals (0, 0, 1), (0, 1, 0) and (1, 0, 0); the cuts sit
## between them, away from every value a box can have at the sixteen yaws.
const LIGHT: Vector3 = Vector3(-0.10, 0.10, 0.28)
const LIGHT_BASE: float = 0.72
const CUT_TOP: float = 0.915
const CUT_LEFT: float = 0.70
## The three discs of a sphere: level, radius and offset of the centre (in sphere radii).
const DISCS: Array[Vector3] = [
	Vector3(2, 1.0, 0.0), Vector3(1, 0.86, -0.10), Vector3(0, 0.5, -0.32)
]
const DISC_POINTS: int = 16


## The screen point of a model-frame point, in px.
static func project(p: Vector3) -> Vector2:
	return Vector2((p.x - p.y) * 64.0, (p.x + p.y) * 32.0 - p.z * Z_PX)


## The face level for a normal in the world: ArtPalette.TOP, LEFT or RIGHT.
static func level(normal: Vector3) -> int:
	var shade: float = LIGHT_BASE + normal.dot(LIGHT)
	if shade >= CUT_TOP:
		return ArtPalette.TOP
	return ArtPalette.LEFT if shade >= CUT_LEFT else ArtPalette.RIGHT


## The polygons of `prims` turned by `yaw` degrees about the origin, back to front.
static func render(prims: Array[ArtPrim], yaw: float, faction: StringName) -> Array[Poly]:
	var turn: Vector2 = ArtMesh.dir(yaw)
	var out: Array[Poly] = []
	for i: int in _order(prims, _unturn(VIEW, turn)):
		var prim: ArtPrim = prims[i]
		if prim.shape == &"sphere":
			out.append_array(_discs(prim, turn, faction))
			continue
		var tops: Array[Poly] = []
		for face: ArtMesh.Face in ArtMesh.faces(prim):
			var normal: Vector3 = _turn(face.normal, turn)
			if normal.dot(VIEW) < MIN_FACING:
				continue
			var is_top: bool = normal.z >= 0.5
			var poly: Poly = Poly.new()
			for point: Vector3 in face.points:
				poly.points.append(project(_turn(point, turn)))
			poly.fill = ArtPalette.tone(faction, prim.material, level(normal))
			poly.stroke = ArtPalette.edge(faction, prim.material, is_top)
			(tops if is_top else out).append(poly)
		out.append_array(tops)
	return out


## `v` turned about the vertical axis by `yaw` degrees (a direction `dNN` is `(NN - 6) x 22.5`).
static func rotate(v: Vector3, yaw: float) -> Vector3:
	return _turn(v, ArtMesh.dir(yaw))


static func bounds(polys: Array[Poly]) -> Rect2:
	var box: Rect2 = Rect2()
	var first: bool = true
	for poly: Poly in polys:
		for point: Vector2 in poly.points:
			box = Rect2(point, Vector2.ZERO) if first else box.expand(point)
			first = false
	return box


static func _turn(v: Vector3, turn: Vector2) -> Vector3:
	return Vector3(v.x * turn.x - v.y * turn.y, v.x * turn.y + v.y * turn.x, v.z)


static func _unturn(v: Vector3, turn: Vector2) -> Vector3:
	return _turn(v, Vector2(turn.x, -turn.y))


## The indices of `prims` from the farthest to the nearest, as seen along `cam` (the direction to
## the camera in the model's frame). A primitive goes before another when their boxes are apart
## along an axis and the other one is on the camera's side, and no axis says the opposite; the rest
## goes by the depth of the centre. Axis-aligned boxes in the model's frame make this exact.
static func _order(prims: Array[ArtPrim], cam: Vector3) -> Array[int]:
	var count: int = prims.size()
	var boxes: Array[AABB] = []
	var depth: PackedFloat64Array = PackedFloat64Array()
	for prim: ArtPrim in prims:
		boxes.append(prim.aabb())
		depth.append(prim.aabb().get_center().dot(cam))
	var before: Array[PackedInt32Array] = []
	for i: int in count:
		before.append(PackedInt32Array())
		for j: int in count:
			if i != j and _is_behind(boxes[j], boxes[i], cam):
				before[i].append(j)
	var order: Array[int] = []
	while order.size() < count:
		var pick: int = _pick(order, before, depth, true)
		order.append(pick if pick >= 0 else _pick(order, before, depth, false))
	return order


## The farthest primitive not yet in `order`; with `need_ready`, one whose predecessors are all in.
static func _pick(
	order: Array[int], before: Array[PackedInt32Array], depth: PackedFloat64Array, need_ready: bool
) -> int:
	var best: int = -1
	for i: int in depth.size():
		var ready: bool = true
		for j: int in before[i]:
			ready = ready and order.has(j)
		if order.has(i) or (need_ready and not ready):
			continue
		if best < 0 or depth[i] < depth[best]:
			best = i
	return best


## True when `a` is farther than `b`: apart along one axis with `b` on the camera's side, and apart
## along no axis the other way round.
static func _is_behind(a: AABB, b: AABB, cam: Vector3) -> bool:
	var a_first: bool = false
	var b_first: bool = false
	for axis: int in 3:
		if absf(cam[axis]) < 1e-6:
			continue
		# Distances measured towards the camera: lo to hi is the box's extent along that way.
		var up: bool = cam[axis] > 0.0
		var a_lo: float = a.position[axis] if up else -a.end[axis]
		var a_hi: float = a.end[axis] if up else -a.position[axis]
		var b_lo: float = b.position[axis] if up else -b.end[axis]
		var b_hi: float = b.end[axis] if up else -b.position[axis]
		a_first = a_first or b_lo - a_hi >= -1e-4
		b_first = b_first or a_lo - b_hi >= -1e-4
	return a_first and not b_first


## A sphere of diameter `size.x` as three discs, the dark one first and the lit one on top, each a
## ring of 16 points; the lit side is the north-west of the screen.
static func _discs(prim: ArtPrim, turn: Vector2, faction: StringName) -> Array[Poly]:
	var radius: float = prim.size.x / 2.0
	var middle: Vector3 = Vector3(prim.centre.x, prim.centre.y, prim.z0 + radius)
	var centre: Vector2 = project(_turn(middle, turn))
	var out: Array[Poly] = []
	for disc: Vector3 in DISCS:
		var poly: Poly = Poly.new()
		var at: Vector2 = centre + Vector2.ONE * disc.z * radius * TILE_PX
		for i: int in DISC_POINTS:
			poly.points.append(
				at + ArtMesh.dir(i * 360.0 / DISC_POINTS) * disc.y * radius * TILE_PX
			)
		poly.fill = ArtPalette.tone(faction, prim.material, int(disc.x))
		if disc.x == ArtPalette.RIGHT:
			poly.stroke = ArtPalette.edge(faction, prim.material, false)
		out.append(poly)
	return out
