class_name ProtoBuild
extends RefCounted
## P653 prototype: builds a Godot 3D node tree from an ArtModel's primitives (our own geometry, the
## faces come from ArtMesh.faces, so a box is the same box the SVG generator draws) and gives every
## material a PBR look. Models are in the grid frame (x forward, y right-down, z up); the Godot
## frame is (X, Y, Z) = (gx, z, gy).

const PPU_ART: float = 90.50966799187809  ## 64 * sqrt(2): art px per world unit at 2x.
const BEVEL: float = 0.016  ## Tiles; the soft edge that catches the light.
const TOP_DIV: float = 0.82

## [metallic, roughness, emission(0..1)] per material name.
const PBR: Dictionary = {
	"steel": [0.4, 0.45, 0.0],
	"concrete": [0.0, 0.92, 0.0],
	"rust": [0.25, 0.85, 0.0],
	"iron": [0.45, 0.5, 0.0],
	"lamp": [0.0, 0.3, 1.0],
	"olive": [0.2, 0.55, 0.0],
	"faction": [0.15, 0.48, 0.0],
	"team": [0.12, 0.5, 0.0],
	"glass": [0.3, 0.12, 0.0],
	"slab": [0.0, 0.9, 0.0],
	"hole": [0.0, 0.9, 0.0],
	"rebar": [0.6, 0.7, 0.0],
	"beam": [0.6, 0.6, 0.0],
	"interior": [0.0, 1.0, 0.0],
	"mint": [0.0, 0.4, 0.8],
}

static var _tex_albedo: ImageTexture
static var _tex_normal: ImageTexture
static var _mats: Dictionary = {}


static func g(v: Vector3) -> Vector3:
	return Vector3(v.x, v.z, v.y)


static func _noise_textures() -> void:
	if _tex_albedo != null:
		return
	var n1: FastNoiseLite = FastNoiseLite.new()
	n1.seed = 653
	n1.frequency = 0.035
	n1.fractal_octaves = 4
	var n2: FastNoiseLite = FastNoiseLite.new()
	n2.seed = 1306
	n2.frequency = 0.22
	n2.fractal_octaves = 3
	var size: int = 256
	var alb: Image = Image.create(size, size, false, Image.FORMAT_RGB8)
	var hgt: Image = Image.create(size, size, false, Image.FORMAT_L8)
	var cell: int = 64
	for y: int in size:
		for x: int in size:
			var a: float = n1.get_noise_2d(x, y) * 0.5 + 0.5
			var b: float = n2.get_noise_2d(x, y) * 0.5 + 0.5
			var v: float = clampf(0.80 + 0.16 * a + 0.1 * b, 0.0, 1.0)
			var h: float = b * 0.35 + 0.5
			# panel seams: a 2 px groove every `cell` px, with a rivet at each crossing.
			var gx: int = x % cell
			var gy: int = y % cell
			if gx < 2 or gy < 2:
				v *= 0.62
				h = 0.12
			var rx: float = float(gx - 6)
			var ry: float = float(gy - 6)
			if rx * rx + ry * ry < 6.0:
				v *= 1.12
				h = 0.95
			alb.set_pixel(x, y, Color(v, v, v))
			hgt.set_pixel(x, y, Color(h, h, h))
	hgt.bump_map_to_normal_map(2.0)
	_tex_albedo = ImageTexture.create_from_image(alb)
	_tex_normal = ImageTexture.create_from_image(hgt)


static func material(faction: StringName, name: String, team_hex: String = "") -> Material:
	var key: String = "%s/%s/%s" % [faction, name, team_hex]
	if _mats.has(key):
		return _mats[key]
	_noise_textures()
	var hex: String = ""
	if name == "team":
		hex = team_hex if team_hex != "" else ArtPalette.SENTINEL[1]
	else:
		hex = ArtPalette.tone(faction, StringName(name), ArtPalette.TOP)
	var base: Color = Color(hex)
	if name != "team":
		base = Color(base.r * 0.9, base.g * 0.9, base.b * 0.9)
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = base
	var p: Array = PBR.get(name, [0.2, 0.6, 0.0])
	m.metallic = p[0]
	m.roughness = p[1]
	if p[2] > 0.0:
		m.emission_enabled = true
		m.emission = base
		m.emission_energy_multiplier = 0.35
	m.albedo_texture = _tex_albedo
	m.normal_enabled = true
	m.normal_texture = _tex_normal
	m.normal_scale = 0.8
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * 1.3
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.cull_mode = BaseMaterial3D.CULL_BACK
	m.clearcoat_enabled = (name == "faction" or name == "team" or name == "olive")
	m.clearcoat = 0.35
	m.clearcoat_roughness = 0.25
	_mats[key] = m
	return m


static func black() -> Material:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color.BLACK
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


class Batch:
	extends RefCounted
	var v: PackedVector3Array = PackedVector3Array()
	var n: PackedVector3Array = PackedVector3Array()
	var idx: PackedInt32Array = PackedInt32Array()

	func tri(a: Vector3, an: Vector3, b: Vector3, bn: Vector3, c: Vector3, cn: Vector3, out_n: Vector3) -> void:
		var base: int = v.size()
		v.append_array([a, b, c])
		n.append_array([an, bn, cn])
		var cr: Vector3 = (b - a).cross(c - a)
		if cr.dot(out_n) <= 0.0:
			idx.append_array([base, base + 1, base + 2])
		else:
			idx.append_array([base, base + 2, base + 1])


static func _add_face(bt: Batch, face: ArtMesh.Face, all: Array[ArtMesh.Face], flatten: float) -> void:
	var pts: Array[Vector3] = []
	for p: Vector3 in face.points:
		pts.append(g(p))
	var nn: Vector3 = g(face.normal).normalized()
	if flatten > 0.0:
		for i: int in pts.size():
			pts[i] = Vector3(pts[i].x + flatten * pts[i].y, 0.0005, pts[i].z)
		# a flattened solid: both sides drawn, normals irrelevant.
		for i: int in range(1, pts.size() - 1):
			bt.tri(pts[0], Vector3.UP, pts[i], Vector3.UP, pts[i + 1], Vector3.UP, Vector3.UP)
		return
	var c: Vector3 = Vector3.ZERO
	for p: Vector3 in pts:
		c += p
	c /= pts.size()
	var cnt: int = pts.size()
	var inner: Array[Vector3] = []
	var edge_n: Array[Vector3] = []
	for i: int in cnt:
		var to_c: Vector3 = c - pts[i]
		var d: float = to_c.length()
		inner.append(pts[i] + to_c * minf(BEVEL / maxf(d, 1e-6), 0.45))
		# neighbour normal across edge i -> i+1
		var m: Vector3 = nn
		var a: Vector3 = face.points[i]
		var b: Vector3 = face.points[(i + 1) % cnt]
		for other: ArtMesh.Face in all:
			if other == face:
				continue
			var ha: bool = false
			var hb: bool = false
			for q: Vector3 in other.points:
				if q.is_equal_approx(a):
					ha = true
				if q.is_equal_approx(b):
					hb = true
			if ha and hb:
				m = (nn + g(other.normal).normalized()).normalized()
				break
		edge_n.append(m)
	for i: int in range(1, cnt - 1):
		bt.tri(inner[0], nn, inner[i], nn, inner[i + 1], nn, nn)
	for i: int in cnt:
		var j: int = (i + 1) % cnt
		var m2: Vector3 = edge_n[i]
		bt.tri(pts[i], m2, pts[j], m2, inner[j], nn, nn)
		bt.tri(pts[i], m2, inner[j], nn, inner[i], nn, nn)


## The node of `part` of `model`. `flatten` > 0 gives the shadow geometry (heights dropped along
## +gx by `flatten` per unit of height).
static func build(model: ArtModel, part: StringName, faction: StringName, flatten: float = 0.0, all_parts: bool = false, team_hex: String = "", mount: Vector3 = Vector3.ZERO) -> Node3D:
	var root: Node3D = Node3D.new()
	var per_mat: Dictionary = {}
	var prims: Array[ArtPrim] = []
	if all_parts:
		for pn: StringName in [&"hull", &"turret", &"head"]:
			for p: ArtPrim in model.primitives(pn):
				prims.append(p)
	else:
		prims = model.primitives(part)
	for prim: ArtPrim in prims:
		var shift: Vector3 = Vector3.ZERO
		if all_parts and prim.part != &"hull":
			shift = mount
		var mat_name: String = String(prim.material)
		if prim.shape == &"rod":
			_add_rod(root, prim, faction, flatten, shift, team_hex)
			continue
		if prim.shape == &"sphere":
			_add_sphere(root, prim, faction, flatten, shift, team_hex)
			continue
		if flatten == 0.0 and prim.shape == &"box" and prim.moves.is_empty() and prim.chamfer == 0.0:
			_greeble(root, prim, faction, shift)
		var faces: Array[ArtMesh.Face] = ArtMesh.faces(prim)
		if not per_mat.has(mat_name):
			per_mat[mat_name] = Batch.new()
		var bt: Batch = per_mat[mat_name]
		for face: ArtMesh.Face in faces:
			if shift != Vector3.ZERO:
				var moved: ArtMesh.Face = ArtMesh.Face.new()
				moved.normal = face.normal
				for p: Vector3 in face.points:
					moved.points.append(p + shift)
				_add_face(bt, moved, faces, flatten)
			else:
				_add_face(bt, face, faces, flatten)
	for mat_name: String in per_mat:
		var bt: Batch = per_mat[mat_name]
		if bt.v.is_empty():
			continue
		var arr: Array = []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = bt.v
		arr[Mesh.ARRAY_NORMAL] = bt.n
		arr[Mesh.ARRAY_INDEX] = bt.idx
		var am: ArrayMesh = ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.mesh = am
		mi.material_override = black() if flatten > 0.0 else material(faction, mat_name, team_hex)
		mi.cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if flatten > 0.0
			else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		)
		root.add_child(mi)
	return root


static func _add_sphere(root: Node3D, prim: ArtPrim, faction: StringName, flatten: float, shift: Vector3, team_hex: String) -> void:
	if flatten > 0.0:
		return
	var sm: SphereMesh = SphereMesh.new()
	sm.radius = prim.size.x / 2.0
	sm.height = prim.size.x
	sm.radial_segments = 24
	sm.rings = 12
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = sm
	mi.material_override = material(faction, String(prim.material), team_hex)
	mi.position = g(Vector3(prim.centre.x, prim.centre.y, prim.z0 + prim.size.x / 2.0) + shift)
	root.add_child(mi)


static func _add_rod(root: Node3D, prim: ArtPrim, faction: StringName, flatten: float, shift: Vector3, team_hex: String) -> void:
	if flatten > 0.0:
		return
	var a: Vector3 = g(prim.rod_a + shift)
	var b: Vector3 = g(prim.rod_b + shift)
	var len: float = a.distance_to(b)
	if len < 1e-5:
		return
	var cm: CylinderMesh = CylinderMesh.new()
	cm.top_radius = prim.width / PPU_ART / 2.0
	cm.bottom_radius = cm.top_radius
	cm.height = len
	cm.radial_segments = 8
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = cm
	mi.material_override = material(faction, String(prim.material), team_hex)
	var up: Vector3 = (b - a).normalized()
	var basis: Basis = Basis.looking_at(up if absf(up.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD, Vector3.UP)
	# CylinderMesh runs along +Y; rotate Y to `up`.
	var axis: Vector3 = Vector3.UP.cross(up)
	var ang: float = Vector3.UP.angle_to(up)
	if axis.length() > 1e-6:
		basis = Basis(axis.normalized(), ang)
	else:
		basis = Basis.IDENTITY if up.y > 0.0 else Basis(Vector3.RIGHT, PI)
	mi.transform = Transform3D(basis, (a + b) * 0.5)
	root.add_child(mi)


const GREEBLE_MATS: Array[String] = ["steel", "iron", "olive", "faction", "concrete", "rust"]
const GREEBLE_PLATE: Array[String] = ["steel", "iron", "iron", "rust"]
static var _plate_mesh: BoxMesh


## Raised plates and vent slats on the big faces of a box: the prototype's stand-in for hand
## modelled surface detail. Seeded by the primitive's line, so the bake is repeatable.
static func _greeble(root: Node3D, prim: ArtPrim, faction: StringName, shift: Vector3) -> void:
	var mat_name: String = String(prim.material)
	if mat_name not in GREEBLE_MATS:
		return
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(prim.line) & 0x7fffffff
	var c: Vector3 = Vector3(prim.centre.x, prim.centre.y, prim.z0 + prim.size.z / 2.0) + shift
	var half: Vector3 = prim.size / 2.0
	# faces: axis (0 x, 1 y, 2 z), sign
	for axis: int in 3:
		for sgn: int in [-1, 1]:
			if axis == 2 and sgn < 0:
				continue
			var u_ax: int = (axis + 1) % 3
			var v_ax: int = (axis + 2) % 3
			var du: float = prim.size[u_ax]
			var dv: float = prim.size[v_ax]
			var area: float = du * dv
			var n: int = clampi(int(area * 16.0), 0, 8)
			if n == 0 or minf(du, dv) < 0.07:
				continue
			for _k: int in n:
				var w: float = rng.randf_range(0.05, 0.16)
				var h: float = rng.randf_range(0.05, 0.16)
				w = minf(w, du * 0.5)
				h = minf(h, dv * 0.5)
				var pu: float = rng.randf_range(-du / 2.0 + w / 2.0 + 0.012, du / 2.0 - w / 2.0 - 0.012)
				var pv: float = rng.randf_range(-dv / 2.0 + h / 2.0 + 0.012, dv / 2.0 - h / 2.0 - 0.012)
				var t: float = rng.randf_range(0.007, 0.02)
				var vent: bool = rng.randf() < 0.22 and w > 0.07 and h > 0.07
				var mat2: String = GREEBLE_PLATE[rng.randi() % GREEBLE_PLATE.size()] if rng.randf() < 0.55 else mat_name
				var pieces: int = 3 if vent else 1
				for q: int in pieces:
					var size3: Vector3 = Vector3.ZERO
					size3[axis] = t
					size3[u_ax] = w
					size3[v_ax] = h
					var pos: Vector3 = c
					pos[axis] += sgn * (half[axis] + t / 2.0 - 0.001)
					pos[u_ax] += pu
					pos[v_ax] += pv
					if vent:
						size3[v_ax] = h / 5.0
						pos[v_ax] += (q - 1) * h / 2.6
						mat2 = "iron"
					var bm: BoxMesh = BoxMesh.new()
					bm.size = g(size3).abs()
					var mi: MeshInstance3D = MeshInstance3D.new()
					mi.mesh = bm
					mi.material_override = material(faction, mat2)
					mi.position = g(pos)
					root.add_child(mi)
