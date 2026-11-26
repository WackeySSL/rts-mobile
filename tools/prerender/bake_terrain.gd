extends SceneTree
## P653: one 8 x 8 tile terrain patch (ground variety, a road, a cliff edge, a shore with water)
## built from code (noise-driven height field, vertex colours, boulders) and rendered through the
## ArtGen projection. Jobs: patch, grid (the projection check).

const OUT: String = "/tmp/claude-0/-home-user-rts-mobile/f4088c2f-7ea6-5710-9456-77d97126fbd5/scratchpad/p653/raw/"
const N: int = 8
const RES: int = 56  ## Vertices per tile.
const PLATEAU: float = 0.62
const WATER_Y: float = -0.07
const MARGIN_TOP: int = 150
const MARGIN_BOTTOM: int = 30

var rig: ProtoRig
var n_big: FastNoiseLite
var n_mid: FastNoiseLite
var n_fine: FastNoiseLite
var n_edge: FastNoiseLite


func _initialize() -> void:
	run.call_deferred()


func _mk(seed_: int, freq: float, oct: int) -> FastNoiseLite:
	var f: FastNoiseLite = FastNoiseLite.new()
	f.seed = seed_
	f.frequency = freq
	f.fractal_octaves = oct
	return f


func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var job: String = OS.get_cmdline_user_args()[0]
	n_big = _mk(11, 0.35, 3)
	n_mid = _mk(12, 1.3, 3)
	n_fine = _mk(13, 5.0, 2)
	n_edge = _mk(14, 0.9, 3)
	rig = ProtoRig.new()
	root.add_child(rig)
	rig.setup(true, 0.95)
	rig.sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	rig.sun.directional_shadow_max_distance = 40.0
	RenderingServer.directional_shadow_atlas_set_size(8192, true)
	var t0: int = Time.get_ticks_msec()
	var w: int = N * 128 + 8
	var h: int = N * 64 + MARGIN_TOP + MARGIN_BOTTOM
	var ax: float = N * 64 + 4
	var ay: float = MARGIN_TOP
	if job == "patch":
		var holder: Node3D = Node3D.new()
		holder.add_child(_build_ground())
		holder.add_child(_water())
		_boulders(holder)
		rig.set_node(holder)
		var t1: int = Time.get_ticks_msec()
		var img: Image = await rig.render(w, h, ax, ay, 4.0)
		img.save_png(OUT + "terrain_patch.png")
		var f: FileAccess = FileAccess.open(OUT + "log_terrain.txt", FileAccess.WRITE)
		f.store_string("build_ms=%d render_ms=%d size=%s anchor=%d,%d" % [t1 - t0, Time.get_ticks_msec() - t1, img.get_size(), ax, ay])
		f.close()
		var tiles: Array = []
		for j: int in N:
			for i: int in N:
				var sm: Dictionary = _sample(i + 0.5, j + 0.5)
				tiles.append({"i": i, "j": j, "h": sm.h, "cliff": sm.cliff, "road": sm.road, "sand": sm.sand})
		var f2: FileAccess = FileAccess.open(OUT + "terrain_tiles.json", FileAccess.WRITE)
		f2.store_string(JSON.stringify(tiles))
		f2.close()
	elif job == "grid":
		var holder2: Node3D = Node3D.new()
		holder2.add_child(_grid_plane())
		holder2.add_child(_cube())
		rig.set_node(holder2)
		rig.env.ssao_enabled = false
		var img2: Image = await rig.render(w, h, ax, ay, 1.0)
		img2.save_png(OUT + "grid_check.png")
	quit()


func _grid_plane() -> MeshInstance3D:
	var im: ImmediateMesh = ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in N:
		for j: int in N:
			var c: Color = Color(1, 0, 0) if (i + j) % 2 == 0 else Color(0, 0, 1)
			var a: Vector3 = Vector3(i, 0, j)
			var b: Vector3 = Vector3(i + 1, 0, j)
			var cc: Vector3 = Vector3(i + 1, 0, j + 1)
			var d: Vector3 = Vector3(i, 0, j + 1)
			for p: Vector3 in [a, d, cc, a, cc, b]:
				im.surface_set_color(c)
				im.surface_set_normal(Vector3.UP)
				im.surface_add_vertex(p)
	im.surface_end()
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = im
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	return mi


func _cube() -> MeshInstance3D:
	var bm: BoxMesh = BoxMesh.new()
	bm.size = Vector3(1, 1, 1)
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = bm
	mi.position = Vector3(3.5, 0.5, 3.5)
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0, 1, 0)
	mi.material_override = m
	return mi


func _smooth(a: float, b: float, x: float) -> float:
	return smoothstep(a, b, x)


## Terrain height and colour at ground point (u, v) in tiles.
func _sample(u: float, v: float) -> Dictionary:
	var hgt: float = 0.025 * n_mid.get_noise_2d(u * 1.0, v * 1.0) + 0.012 * n_fine.get_noise_2d(u, v)
	# Cliff: the plateau in the back (small v), its edge wanders.
	var edge: float = 1.95 + 0.45 * n_edge.get_noise_2d(u * 1.0, 7.0) + 0.1 * n_fine.get_noise_2d(u * 1.4, 3.0)
	var d: float = v - edge + 0.04 * n_fine.get_noise_2d(u * 2.0, hgt * 6.0)
	var cliff_t: float = 1.0 - _smooth(-0.04, 0.26, d)
	var strata: float = 0.0
	if cliff_t > 0.0:
		hgt += PLATEAU * cliff_t
		strata = 0.04 * sin(hgt * 38.0 + 3.0 * n_mid.get_noise_2d(u * 2.0, 0.0)) * (1.0 - absf(cliff_t * 2.0 - 1.0) * 0.0)
		hgt += 0.02 * n_mid.get_noise_2d(u * 5.0, v * 5.0) * cliff_t
	# Shore: a depression in the right front, water below WATER_Y.
	var wd: float = Vector2(u - 7.4, v - 4.3).length()
	var wn: float = wd + 0.55 * n_edge.get_noise_2d(u * 1.1, v * 1.1 + 20.0)
	var basin: float = 1.0 - _smooth(1.2, 3.0, wn)
	hgt -= 0.30 * basin
	# Road: along u at v ~ 6.6, wide 1.3 tiles, slightly meandering; flat and a touch raised.
	var road_c: float = 6.55 + 0.18 * sin(u * 0.8)
	var rd: float = absf(v - road_c)
	var road_w: float = _smooth(0.78, 0.60, rd)  # 1 on the road
	var road_edge: float = _smooth(0.95, 0.70, rd)
	hgt = lerpf(hgt, 0.012, road_w * 0.85)
	# Colours.
	var grass: Color = Color(0.36, 0.37, 0.20).lerp(Color(0.46, 0.44, 0.24), 0.5 + 0.5 * n_mid.get_noise_2d(u * 1.7, v * 1.7))
	grass = grass.lerp(Color(0.27, 0.30, 0.16), _smooth(0.1, 0.6, n_big.get_noise_2d(u + 9.0, v + 4.0)))
	var dirt: Color = Color(0.42, 0.33, 0.24)
	var sand: Color = Color(0.74, 0.64, 0.46).lerp(Color(0.64, 0.54, 0.38), 0.5 + 0.5 * n_mid.get_noise_2d(u * 2.0 + 5.0, v * 2.0))
	var rock: Color = Color(0.30, 0.26, 0.22).lerp(Color(0.46, 0.38, 0.29), 0.5 + 0.5 * n_mid.get_noise_2d(u * 3.0, v * 3.0 + 1.0))
	var col: Color = grass
	col = col.lerp(dirt, _smooth(0.15, 0.7, n_big.get_noise_2d(u * 1.3 + 40.0, v * 1.3)) * 0.8)
	# sand bands: round the shore and a drift along the road's far side.
	var sand_t: float = maxf(1.0 - _smooth(1.3, 2.4, wn), 0.0)
	sand_t = maxf(sand_t, _smooth(0.5, 0.9, n_edge.get_noise_2d(u * 0.7 + 60.0, v * 0.7)) * 0.7)
	col = col.lerp(sand, sand_t)
	col = col.lerp(rock, clampf(cliff_t * 1.6, 0.0, 1.0))
	if cliff_t > 0.5:
		col = col.lerp(Color(0.30, 0.28, 0.26), 0.35 + 0.35 * n_fine.get_noise_2d(u * 2.0, v * 6.0))
		col = col * (1.0 + strata * 2.0)
	# plateau top: gravel
	if cliff_t >= 0.98:
		col = rock.lerp(Color(0.34, 0.31, 0.27), 0.5 + 0.5 * n_fine.get_noise_2d(u * 3.0, v * 3.0))
		col = col.lerp(grass * 0.8, _smooth(0.25, 0.7, n_big.get_noise_2d(u * 1.1 + 70.0, v * 1.1)) * 0.7)
	# wet sand and foam at the water line
	if hgt < WATER_Y + 0.05:
		col = col.lerp(Color(0.33, 0.30, 0.24), _smooth(WATER_Y + 0.05, WATER_Y - 0.03, hgt))
	var foam: float = _smooth(0.022, 0.0, absf(hgt - WATER_Y))
	col = col.lerp(Color(0.86, 0.88, 0.84), foam * 0.7)
	# road surface
	var asphalt: Color = Color(0.20, 0.21, 0.22).lerp(Color(0.27, 0.27, 0.27), 0.5 + 0.5 * n_mid.get_noise_2d(u * 2.0, v * 2.0))
	asphalt = asphalt.lerp(Color(0.12, 0.12, 0.13), _smooth(0.55, 0.9, n_fine.get_noise_2d(u * 5.0, v * 5.0)) * 0.6)
	# dashed centre line, worn
	var dash: float = 1.0 if fposmod(u, 0.9) < 0.5 and absf(v - road_c) < 0.028 else 0.0
	asphalt = asphalt.lerp(Color(0.72, 0.58, 0.20), dash * 0.8 * (0.6 + 0.4 * n_fine.get_noise_2d(u * 9.0, v)))
	# crack
	var crack: float = _smooth(0.012, 0.0, absf(v - road_c - 0.22 - 0.1 * n_mid.get_noise_2d(u * 2.0, 5.0))) * 0.5
	asphalt = asphalt.lerp(Color(0.06, 0.06, 0.06), crack)
	col = col.lerp(sand.lerp(dirt, 0.6), road_edge * 0.8)  # gravel shoulder
	col = col.lerp(asphalt, road_w)
	return {"h": hgt, "c": col, "cliff": cliff_t, "road": road_w, "sand": sand_t}


func _build_ground() -> MeshInstance3D:
	var n: int = N * RES + 1
	var verts: PackedVector3Array = PackedVector3Array()
	var cols: PackedColorArray = PackedColorArray()
	var hs: PackedFloat32Array = PackedFloat32Array()
	verts.resize(n * n)
	cols.resize(n * n)
	hs.resize(n * n)
	for j: int in n:
		for i: int in n:
			var u: float = float(i) / RES
			var v: float = float(j) / RES
			var s: Dictionary = _sample(u, v)
			hs[j * n + i] = s.h
			verts[j * n + i] = Vector3(u, s.h, v)
			cols[j * n + i] = s.c
	var norms: PackedVector3Array = PackedVector3Array()
	norms.resize(n * n)
	for j: int in n:
		for i: int in n:
			var hl: float = hs[j * n + maxi(i - 1, 0)]
			var hr: float = hs[j * n + mini(i + 1, n - 1)]
			var hu: float = hs[maxi(j - 1, 0) * n + i]
			var hd: float = hs[mini(j + 1, n - 1) * n + i]
			var du: float = float(mini(i + 1, n - 1) - maxi(i - 1, 0)) / RES
			var dv: float = float(mini(j + 1, n - 1) - maxi(j - 1, 0)) / RES
			norms[j * n + i] = Vector3(-(hr - hl) / du, 1.0, -(hd - hu) / dv).normalized()
	var idx: PackedInt32Array = PackedInt32Array()
	idx.resize((n - 1) * (n - 1) * 6)
	var k: int = 0
	for j: int in n - 1:
		for i: int in n - 1:
			var a: int = j * n + i
			var b: int = a + 1
			var c: int = a + n
			var d: int = c + 1
			# clockwise seen from above (Godot front face is clockwise): a, b, c ; b, d, c
			idx[k] = a
			idx[k + 1] = b
			idx[k + 2] = c
			idx[k + 3] = b
			idx[k + 4] = d
			idx[k + 5] = c
			k += 6
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var am: ArrayMesh = ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = am
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.93
	m.albedo_texture = _grain()
	m.normal_enabled = true
	m.normal_texture = _grain_normal()
	m.normal_scale = 0.9
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * 0.9
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mi.material_override = m
	return mi


var _g: ImageTexture
var _gn: ImageTexture


func _grain_images() -> void:
	if _g != null:
		return
	var a: FastNoiseLite = _mk(21, 0.03, 4)
	var b: FastNoiseLite = _mk(22, 0.25, 3)
	var size: int = 512
	var alb: Image = Image.create(size, size, false, Image.FORMAT_RGB8)
	var hgt: Image = Image.create(size, size, false, Image.FORMAT_L8)
	for y: int in size:
		for x: int in size:
			var va: float = a.get_noise_2d(x, y) * 0.5 + 0.5
			var vb: float = b.get_noise_2d(x, y) * 0.5 + 0.5
			var v: float = clampf(0.50 + 0.28 * va + 0.2 * vb, 0.0, 1.0)
			alb.set_pixel(x, y, Color(v, v, v))
			hgt.set_pixel(x, y, Color(vb, vb, vb))
	hgt.bump_map_to_normal_map(3.0)
	_g = ImageTexture.create_from_image(alb)
	_gn = ImageTexture.create_from_image(hgt)


func _grain() -> ImageTexture:
	_grain_images()
	return _g


func _grain_normal() -> ImageTexture:
	_grain_images()
	return _gn


func _water() -> MeshInstance3D:
	var verts: PackedVector3Array = PackedVector3Array()
	var idx: PackedInt32Array = PackedInt32Array()
	var step: int = 2
	var cells: int = N * RES / step
	for j: int in cells:
		for i: int in cells:
			var low: bool = false
			for dj: int in 2:
				for di: int in 2:
					var u: float = float((i + di) * step) / RES
					var v: float = float((j + dj) * step) / RES
					if _sample(u, v).h < WATER_Y - 0.004:
						low = true
			if not low:
				continue
			var base: int = verts.size()
			var u0: float = float(i * step) / RES
			var v0: float = float(j * step) / RES
			var u1: float = float((i + 1) * step) / RES
			var v1: float = float((j + 1) * step) / RES
			verts.append_array([Vector3(u0, WATER_Y, v0), Vector3(u1, WATER_Y, v0), Vector3(u0, WATER_Y, v1), Vector3(u1, WATER_Y, v1)])
			idx.append_array([base, base + 1, base + 2, base + 1, base + 3, base + 2])
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	var nrm: PackedVector3Array = PackedVector3Array()
	nrm.resize(verts.size())
	nrm.fill(Vector3.UP)
	arr[Mesh.ARRAY_NORMAL] = nrm
	arr[Mesh.ARRAY_INDEX] = idx
	var am: ArrayMesh = ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = am
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = Color(0.07, 0.24, 0.27, 0.9)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	m.roughness = 0.06
	m.metallic_specular = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _boulders(parent: Node3D) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 653
	var spots: Array[Vector3] = []
	for _i: int in 22:
		var u: float = rng.randf_range(0.3, 7.7)
		var v: float = rng.randf_range(0.3, 7.7)
		var s: Dictionary = _sample(u, v)
		var road_c: float = 6.55 + 0.18 * sin(u * 0.8)
		if absf(v - road_c) < 0.75 or s.h < WATER_Y + 0.02:
			continue
		if u > 0.7 and u < 4.1 and v > 2.5 and v < 5.7:  # the building's pad
			continue
		spots.append(Vector3(u, s.h, v))
	var rock_mat: StandardMaterial3D = StandardMaterial3D.new()
	rock_mat.albedo_color = Color(0.40, 0.37, 0.33)
	rock_mat.roughness = 0.9
	rock_mat.albedo_texture = _grain()
	rock_mat.normal_enabled = true
	rock_mat.normal_texture = _grain_normal()
	rock_mat.uv1_triplanar = true
	rock_mat.uv1_scale = Vector3.ONE * 1.8
	for sp: Vector3 in spots:
		var sm: SphereMesh = SphereMesh.new()
		sm.radial_segments = 10
		sm.rings = 6
		sm.radius = 1.0
		sm.height = 2.0
		var arr: Array = sm.get_mesh_arrays()
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		for i: int in vs.size():
			var p: Vector3 = vs[i]
			vs[i] = p * (1.0 + 0.28 * n_fine.get_noise_3d(p.x * 3.0 + sp.x * 7.0, p.y * 3.0, p.z * 3.0 + sp.z * 7.0))
		arr[Mesh.ARRAY_VERTEX] = vs
		var am: ArrayMesh = ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.mesh = am
		mi.material_override = rock_mat
		var r: float = rng.randf_range(0.07, 0.19)
		mi.scale = Vector3(r * rng.randf_range(1.0, 1.5), r * rng.randf_range(0.6, 0.9), r * rng.randf_range(1.0, 1.4))
		mi.rotation.y = rng.randf() * TAU
		mi.position = sp + Vector3(0, r * 0.25, 0)
		parent.add_child(mi)
