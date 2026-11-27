class_name BakeMesh
extends RefCounted
## The bake tool's mesh builder (ADR 0053 section 5): triangles gathered per material, in the
## model's grid frame (x forward, y right-down, z up) and handed to Godot as (X, Y, Z) = (gx, z,
## gy). Faces come from `ArtMesh` (a box is the same box the SVG generator draws) or from planes,
## and each gets a bevel strip that catches the light. Winding follows the vertex normals, which
## always point out of the solid. A model over `TRIANGLE_CAP` is refused, never cut short.

const TRIANGLE_CAP: int = 60000  ## ADR 0053 section 7: at most this many triangles per model.
const BEVEL: float = 0.012  ## Tiles; the width of a bevel strip.
const _KEY_SCALE: float = 2000.0  ## Two corners closer than 1/2000 tile are one corner.


## What `to_node` turns into one surface of one material.
class Batch:
	extends RefCounted
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var edges: PackedFloat32Array = PackedFloat32Array()  ## 1 on a bevel's outer rim, else 0.
	var indices: PackedInt32Array = PackedInt32Array()


var id: StringName = &""
var triangles: int = 0  ## Counted past the cap too, so the refusal can name the real count.
var batches: Dictionary = {}  ## Material name -> Batch.
var offset: Vector3 = Vector3.ZERO  ## Added to every point, grid frame (a repeat, a mount).


func _init(model_id: StringName = &"") -> void:
	id = model_id


## A grid-frame point in the Godot frame.
static func to_godot(p: Vector3) -> Vector3:
	return Vector3(p.x, p.z, p.y)


## The refusal text of a model over the cap, naming its id and count; empty when it fits.
func cap_error() -> String:
	if triangles <= TRIANGLE_CAP:
		return ""
	return "%s: %d triangles, over the cap of %d" % [id, triangles, TRIANGLE_CAP]


## One triangle of `mat`: three points, their normals and bevel flags. The winding is chosen so
## that the face looks along the normals.
func tri(
	mat: StringName, p: PackedVector3Array, n: PackedVector3Array, edge: PackedFloat32Array
) -> void:
	triangles += 1
	if triangles > TRIANGLE_CAP:
		return
	if not batches.has(mat):
		batches[mat] = Batch.new()
	var batch: Batch = batches[mat]
	var base: int = batch.vertices.size()
	for i: int in 3:
		batch.vertices.append(to_godot(p[i] + offset))
		batch.normals.append(to_godot(n[i]).normalized())
		batch.edges.append(edge[i])
	var cross: Vector3 = (p[1] - p[0]).cross(p[2] - p[0])
	var flip: bool = cross.dot(n[0] + n[1] + n[2]) < 0.0
	batch.indices.append_array([base, base + (2 if flip else 1), base + (1 if flip else 2)])


## Polygons (convex, counter-clockwise or not) with their outward normals, each as a flat top and
## a bevel strip along its rim. A rim leans towards the face across the edge, so a box edge
## shades like a rounded one.
func shell(
	mat: StringName, polys: Array[PackedVector3Array], normals: PackedVector3Array, bevel: float
) -> void:
	var across: Dictionary = {}
	for i: int in polys.size():
		for k: int in polys[i].size():
			var key: String = _edge_key(polys[i][k], polys[i][(k + 1) % polys[i].size()])
			if not across.has(key):
				across[key] = []
			across[key].append(i)
	for i: int in polys.size():
		var poly: PackedVector3Array = polys[i]
		var sides: PackedVector3Array = PackedVector3Array()
		for k: int in poly.size():
			var key: String = _edge_key(poly[k], poly[(k + 1) % poly.size()])
			sides.append(_lean(normals, across[key], i))
		if poly.size() >= 3:
			_face(mat, poly, normals[i], sides, bevel)


## A convex solid from outward planes (inside is `n . p <= d`), bevelled on every face.
func solid(mat: StringName, planes: Array[Plane], bevel: float = BEVEL) -> void:
	var polys: Array[PackedVector3Array] = []
	var normals: PackedVector3Array = PackedVector3Array()
	for i: int in planes.size():
		var hint: Vector3 = Vector3.UP if absf(planes[i].normal.y) < 0.9 else Vector3.RIGHT
		var u: Vector3 = planes[i].normal.cross(hint).normalized()
		var w: Vector3 = planes[i].normal.cross(u)
		var centre: Vector3 = planes[i].normal * planes[i].d
		var pts: PackedVector3Array = [
			centre + (u + w) * 6.0,
			centre + (u - w) * 6.0,
			centre - (u + w) * 6.0,
			centre - (u - w) * 6.0
		]
		for j: int in planes.size():
			if j != i and pts.size() >= 3:
				pts = Geometry3D.clip_polygon(pts, planes[j])
		polys.append(_clean(pts))
		normals.append(planes[i].normal)
	shell(mat, polys, normals, bevel)


## The faces of one `ArtPrim` (a box, wedge or prism), bevelled.
func art_prim(mat: StringName, prim: ArtPrim, bevel: float = BEVEL) -> void:
	var polys: Array[PackedVector3Array] = []
	var normals: PackedVector3Array = PackedVector3Array()
	for face: ArtMesh.Face in ArtMesh.faces(prim):
		polys.append(face.points)
		normals.append(face.normal.normalized())
	shell(mat, polys, normals, bevel)


## The Godot node of the gathered triangles, one surface per material of `materials` (name ->
## Material). Null for a model over the cap: the caller reports `cap_error()`.
func to_node(materials: Dictionary, casts_shadow: bool = true) -> Node3D:
	if cap_error() != "":
		return null
	var root: Node3D = Node3D.new()
	for mat: StringName in batches:
		var batch: Batch = batches[mat]
		var colours: PackedColorArray = PackedColorArray()
		for flag: float in batch.edges:
			colours.append(Color(flag, 0.0, 0.0, 1.0))
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = batch.vertices
		arrays[Mesh.ARRAY_NORMAL] = batch.normals
		arrays[Mesh.ARRAY_COLOR] = colours
		arrays[Mesh.ARRAY_INDEX] = batch.indices
		var mesh: ArrayMesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var instance: MeshInstance3D = MeshInstance3D.new()
		instance.mesh = mesh
		instance.material_override = materials.get(mat)
		instance.cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			if casts_shadow
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		)
		root.add_child(instance)
	return root


func _face(
	mat: StringName, poly: PackedVector3Array, n: Vector3, sides: PackedVector3Array, bevel: float
) -> void:
	var count: int = poly.size()
	var flat: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0])
	if bevel <= 0.0:
		for k: int in range(1, count - 1):
			tri(mat, [poly[0], poly[k], poly[k + 1]], [n, n, n], flat)
		return
	var centre: Vector3 = Vector3.ZERO
	for p: Vector3 in poly:
		centre += p / count
	var inner: PackedVector3Array = PackedVector3Array()
	for p: Vector3 in poly:
		var to_centre: Vector3 = centre - p
		inner.append(p + to_centre * minf(bevel / maxf(to_centre.length(), 1e-6), 0.45))
	var rim: PackedFloat32Array = PackedFloat32Array([1.0, 1.0, 0.0])
	var rim_in: PackedFloat32Array = PackedFloat32Array([1.0, 0.0, 0.0])
	for k: int in range(1, count - 1):
		tri(mat, [inner[0], inner[k], inner[k + 1]], [n, n, n], flat)
	for k: int in count:
		var l: int = (k + 1) % count
		var s: Vector3 = sides[k]
		tri(mat, [poly[k], poly[l], inner[l]], [s, s, n], rim)
		tri(mat, [poly[k], inner[l], inner[k]], [s, n, n], rim_in)


## The normal an edge of face `own` leans to: the mean with the other face on that edge.
func _lean(normals: PackedVector3Array, faces: Array, own: int) -> Vector3:
	for other: int in faces:
		if other != own and not normals[other].is_equal_approx(normals[own]):
			return (normals[own] + normals[other]).normalized()
	return normals[own]


static func _key(p: Vector3) -> Vector3i:
	return Vector3i((p * _KEY_SCALE).round())


static func _edge_key(a: Vector3, b: Vector3) -> String:
	var ka: Vector3i = _key(a)
	var kb: Vector3i = _key(b)
	return "%s|%s" % ([ka, kb] if ka < kb else [kb, ka])


## A clipped polygon without repeated corners; empty when it collapsed.
static func _clean(pts: PackedVector3Array) -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	for p: Vector3 in pts:
		if out.is_empty() or not out[out.size() - 1].is_equal_approx(p):
			out.append(p)
	if out.size() > 1 and out[0].is_equal_approx(out[out.size() - 1]):
		out.remove_at(out.size() - 1)
	return out if out.size() >= 3 else PackedVector3Array()
