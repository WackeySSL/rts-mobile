extends GdUnitTestSuite
## The silhouettes of unit rigs behind raised rock walls (ADR 0053 amendment A7, plan P656d3) on
## controls_test (`fog_rig.gd`): 30 own tanks in a block from (8, 18) and 10 red ones, the nearest,
## tank 31, at (34.5, 10.5). Rock is made on the published snapshot's terrain, with placeholder
## wall pieces (`wall_rig.gd`). The shader's output is not headless: `scenes/dev/silhouette_probe`.

const Rig: GDScript = preload("res://tests/view/support/wall_rig.gd")
const FogRig: GDScript = preload("res://tests/view/support/fog_rig.gd")
const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const OWN_ROW: int = 0  ## Tank 1 at (8.5, 18.5), cell (8, 18).
const RED_ROW: int = 30  ## Tank 31 at (34.5, 10.5), cell (34, 10).
const FAR_ROW: int = 29  ## Tank 30 at (13.5, 23.5): the wall below is two cells off.

var _runner: MatchRunner
var _sort: WorldSort
var _walls: WallLayer
var _layer: UnitLayer
var _camera: RtsCamera


func before_test() -> void:
	MenuRig.begin()
	_runner = auto_free(MatchRunner.new())
	_runner.scenario = FogRig.scenario(1)
	_runner.start()
	var snap: MatchSnapshot = _runner.snapshot
	var rock: int = snap.terrain_ids.find(&"rock")
	for cell: Vector2i in [Vector2i(9, 18), Vector2i(35, 10), Vector2i(16, 28)]:
		snap.terrain[cell.y * snap.map_cols + cell.x] = rock
	snap.map_version += 1
	_sort = auto_free(WorldSort.new())
	_sort.runner = _runner
	add_child(_sort)
	_camera = auto_free(RtsCamera.new())
	add_child(_camera)


func after_test() -> void:
	MenuRig.end()
	CommandQueue.clear()


func test_a_silhouette_shows_for_an_own_rig_in_a_near_wall_cell_and_not_elsewhere() -> void:
	_make(true)
	var own: UnitLayer.Rig = _layer.rig(OWN_ROW) as UnitLayer.Rig
	assert_bool(_walls.is_near(18 * 48 + 8)).is_true()  # Tank 1 stands left of the wall at (9, 18).
	assert_bool(own.silhouette.on).is_true()
	for sil: Sprite2D in own.silhouette.sprites:
		assert_bool(sil.visible).is_true()
	var far: UnitLayer.Rig = _layer.rig(FAR_ROW) as UnitLayer.Rig
	assert_bool(far.silhouette.on).is_false()
	for sil: Sprite2D in far.silhouette.sprites:
		assert_bool(sil.visible).is_false()


func test_an_enemy_rig_shows_a_silhouette_only_where_the_local_player_sees_it() -> void:
	_make(true)
	var red: UnitLayer.Rig = _layer.rig(RED_ROW) as UnitLayer.Rig
	assert_bool(red.visible).is_false()  # In the fog.
	assert_bool(red.silhouette.on).is_false()
	for sil: Sprite2D in red.silhouette.sprites:
		assert_bool(sil.visible).is_false()
	FogRig.flip(_runner.snapshot, 1, [Vector2i(34, 10)] as Array[Vector2i], true)
	_layer._process(0.0)
	assert_bool(red.visible).is_true()
	assert_bool(red.silhouette.on).is_true()
	for sil: Sprite2D in red.silhouette.sprites:
		assert_bool(sil.visible).is_true()
	FogRig.flip(_runner.snapshot, 1, [Vector2i(34, 10)] as Array[Vector2i], false)
	_layer._process(0.0)
	assert_bool(red.silhouette.on).is_false()


func test_a_silhouette_copies_the_part_and_stands_at_the_rigs_origin() -> void:
	_make(true)
	var own: UnitLayer.Rig = _layer.rig(OWN_ROW) as UnitLayer.Rig
	for part: int in [UnitLayer.HULL, UnitLayer.TURRET]:
		var from: Sprite2D = own.sprites[part]
		var sil: Sprite2D = own.silhouette.sprites[part]
		assert_object(sil.get_parent()).is_same(own)
		assert_that(sil.position).is_equal(Vector2.ZERO)
		assert_object(sil.texture).is_same(from.texture)
		assert_that(sil.region_rect).is_equal(from.region_rect)
		assert_that(sil.scale).is_equal(from.scale)
		# The part's own place is folded into the offset: both draw at the same px.
		assert_that(sil.position + sil.scale * sil.offset).is_equal(
			from.position + from.scale * from.offset
		)
	# A turn of the turret moves the silhouette's region with it.
	_layer._aim[OWN_ROW] = PI / 2.0
	_layer._heading[OWN_ROW] = PI / 2.0
	_layer._show_hull(OWN_ROW, 1)
	_layer._process(0.0)
	assert_that(own.silhouette.sprites[UnitLayer.HULL].region_rect).is_equal(
		own.sprites[UnitLayer.HULL].region_rect
	)


func test_all_silhouettes_share_one_material_at_z_11_over_the_sorted_world() -> void:
	_make(true)
	var count: int = 0
	for row: int in _layer.rig_count():
		var rig: UnitLayer.Rig = _layer.rig(row) as UnitLayer.Rig
		for sil: Sprite2D in rig.silhouette.sprites:
			count += 1
			assert_object(sil.material).is_same(_sort.silhouette_material())
			assert_int(sil.z_index).is_equal(11)
			assert_bool(sil.z_as_relative).is_false()
			assert_bool(sil.region_enabled).is_true()
	assert_int(count).is_equal(2 * 40)
	assert_int(WorldSort.Z_SILHOUETTE).is_greater(WorldSort.Z_SORT)
	assert_int(WorldSort.Z_SILHOUETTE).is_less(20)  # Under the aircraft.


@warning_ignore("integer_division")
func test_no_node_is_made_after_warm_up_over_300_frames() -> void:
	_make(true)
	var snap: MatchSnapshot = _runner.snapshot
	var nodes: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var made: int = _layer.rigs_made()
	for frame: int in 300:
		# Tank 1 walks across the wall's near cells and back, one cell every ten frames.
		if frame % 10 == 0:
			snap.pos_x[OWN_ROW] = 7500 + (frame / 10 % 6) * 1000
			snap.tick += 1
		_layer._process(0.0)
	assert_int(int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))).is_equal(nodes)
	assert_int(_layer.rigs_made()).is_equal(made)


func test_a_layer_without_the_flag_makes_no_silhouette_node() -> void:
	_make(false)
	var own: UnitLayer.Rig = _layer.rig(OWN_ROW) as UnitLayer.Rig
	assert_object(own.silhouette).is_null()
	assert_int(own.get_child_count()).is_equal(3)  # Shadow, Hull, Turret: nothing added.


func test_a_building_row_has_no_rig_and_so_no_silhouette() -> void:
	_runner.scenario = load("res://data/scenarios/skirmish_curlew_crags.tres")
	_runner.start()
	_make(true)
	var buildings: int = 0
	for row: int in _runner.snapshot.unit_id.size():
		if _layer.rig(row) == null:
			buildings += 1
	assert_int(buildings).is_greater(0)
	var sils: int = 0
	for node: Node in _sort.get_children():
		for child: Node in node.get_children():
			sils += 1 if String(child.name).begins_with("Sil") else 0
	assert_int(sils).is_between(1, 2 * _layer.rig_count())


func test_a_pooled_rig_comes_back_hidden_and_reads_its_cell_again() -> void:
	_make(true)
	var made: int = _layer.rigs_made()
	_runner.snapshot.match_serial += 1  # A new match: every rig goes to the pool and comes back.
	_walls._process(0.0)
	_layer._process(0.0)
	assert_int(_layer.rigs_made()).is_equal(made)
	var again: UnitLayer.Rig = _layer.rig(OWN_ROW) as UnitLayer.Rig
	assert_bool(again.silhouette.on).is_true()
	assert_bool(_layer.walls.is_near(18 * 48 + 8)).is_true()


## Walls from the placeholder pieces, then the unit layer over the same sorted world.
func _make(on: bool) -> void:
	_walls = auto_free(WallLayer.new())
	_walls.runner = _runner
	_walls.world_sort = _sort
	_walls.walls_enabled = on
	_walls.loader = Callable(self, "_pieces")
	add_child(_walls)
	_layer = auto_free(UnitLayer.new())
	_layer.runner = _runner
	_layer.camera = _camera
	_layer.world_sort = _sort
	_layer.walls = _walls
	add_child(_layer)
	_layer.set_process(false)
	_walls._process(0.0)
	_layer._process(0.0)


func _pieces(_look: StringName) -> Dictionary[StringName, Image]:
	return Rig.pieces()


func test_the_shader_compiles_and_has_the_uniforms_the_view_sets() -> void:
	var shader: Shader = load(WorldSort.SILHOUETTE_SHADER) as Shader
	var names: Array[String] = []
	for uniform: Dictionary in shader.get_shader_uniform_list():
		names.append(String(uniform["name"]))
	for want: String in ["wall_mask", "grid_size", "half_w", "half_h", "body_colour"]:
		assert_array(names).contains([want])
	var material: ShaderMaterial = auto_free(WorldSort.new()).silhouette_material()
	assert_float(material.get_shader_parameter("half_w")).is_equal(float(IsoProjection.HALF_W))
	assert_float(material.get_shader_parameter("half_h")).is_equal(float(IsoProjection.HALF_H))
