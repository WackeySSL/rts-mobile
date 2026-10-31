extends GdUnitTestSuite
## The sorted world (plan P114, ADR 0023 section 2): the z table of both scenes, the sort of a
## unit against a building's footprint, the one atlas every sorted sprite draws from whatever the
## mix of types and owners, the players of the atlas (factions from the scenario, the triads), the
## bake that a restart does not repeat, the stand-in for art that is not there, and the rows of
## buildings, which have no rig. The rig contract is test_unit_layer.gd's, the turns are
## test_unit_layer_aim.gd's and test_unit_layer_turn.gd's.
## The sort itself runs in the engine, which a headless test cannot see: what is pinned is its two
## inputs, the node's `y_sort_enabled` and the y of each child, a rig's position or a building's
## footprint centre (`(c + r + n) * 16` px for an n x n footprint at tile (c, r)).

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const Frames: GDScript = preload("res://tests/view/support/rig_frames.gd")
const MAIN_SCENE: String = "res://scenes/main.tscn"
const ARENA_SCENE: String = "res://scenes/dev/perf_arena.tscn"
const RULES: String = "res://data/rules.tres"
## ADR 0023 section 2: the absolute z of the layers that both scenes hold, bottom to top.
const TABLE: Dictionary[String, int] = {
	"MapView": 0,
	"GroundLayer": 0,
	"DecalLayer": 1,
	"FogLayer": 4,
	"GhostMemoryLayer": 5,
	"WorldSort": 10,
	"HealthBarLayer": 30,
	"ProjectileLayer": 40,
	"EffectsLayer": 50,
}
const FOOT: Vector2i = Vector2i(10, 10)  ## The origin tile of the footprints the sort cases use.

var _runner: MatchRunner
var _camera: RtsCamera
var _layer: UnitLayer


func before_test() -> void:
	MenuRig.begin()
	_camera = auto_free(RtsCamera.new())
	add_child(_camera)


func after_test() -> void:
	MenuRig.end()
	CommandQueue.clear()


func test_the_sort_node_sorts_its_children_by_y_at_z_10() -> void:
	var sort: WorldSort = auto_free(WorldSort.new())
	assert_bool(sort.y_sort_enabled).is_true()
	assert_int(sort.z_index).is_equal(10)
	assert_bool(sort.z_as_relative).is_false()
	assert_int(WorldSort.Z_SORT).is_equal(10)
	assert_int(WorldSort.Z_SHADOW).is_equal(2)  # Unit shadows, under the rings at 3 and the fog at 4.
	assert_int(WorldSort.Z_RING).is_equal(3)


func test_both_scenes_hold_the_z_table_of_adr_0023_with_the_sort_between_fog_and_bars() -> void:
	# Read from the scene files, so that no scene is instantiated and run for it.
	for path: String in [MAIN_SCENE, ARENA_SCENE]:
		var state: SceneState = (load(path) as PackedScene).get_state()
		for layer_name: String in TABLE:
			var z: int = _scene_value(state, layer_name, &"z_index", 0)
			assert_int(z).override_failure_message("%s in %s" % [layer_name, path]).is_equal(
				TABLE[layer_name]
			)
			if TABLE[layer_name] > 0:  # The scene says absolute, so a parent's z does not move it.
				var absolute: bool = not _scene_value(state, layer_name, &"z_as_relative", true)
				assert_bool(absolute).override_failure_message(layer_name).is_true()
		assert_bool(_scene_value(state, "WorldSort", &"y_sort_enabled", false)).is_true()
		var own: Variant = _scene_value(state, "UnitLayer", &"world_sort", null)
		assert_that(own).is_equal(NodePath("../WorldSort"))  # The rigs stand in the scene's sort.
		# P115: the buildings too, their shadows in the scene's decal layer, and their bars.
		var buildings: Variant = _scene_value(state, "BuildingLayer", &"world_sort", null)
		assert_that(buildings).is_equal(NodePath("../WorldSort"))
		var decals: Variant = _scene_value(state, "BuildingLayer", &"decals", null)
		assert_that(decals).is_equal(NodePath("../DecalLayer"))
		var bars: Variant = _scene_value(state, "HealthBarLayer", &"building_layer", null)
		assert_that(bars).is_equal(NodePath("../BuildingLayer"))
		# P114b: the shells and the effects take their muzzle heights from the scene's sheets.
		for layer_name: String in ["ProjectileLayer", "EffectsLayer"]:
			var sheets: Variant = _scene_value(state, layer_name, &"world_sort", null)
			assert_that(sheets).override_failure_message(layer_name).is_equal(
				NodePath("../WorldSort")
			)
		var names: Array[String] = _root_children(state)
		assert_int(names.find("WorldSort")).is_greater(names.find("MapView"))
		assert_int(names.find("WorldSort")).is_less(names.find("UnitLayer"))
	var main: SceneState = (load(MAIN_SCENE) as PackedScene).get_state()
	assert_int(_scene_value(main, "MarkerLayer", &"z_index", 0)).is_equal(70)


func test_a_unit_east_or_south_of_a_footprint_sorts_after_it_and_north_or_west_before() -> void:
	for size: int in [1, 2, 3]:  # A 1x1, a 2x2 and a 3x3 footprint at tile (10, 10).
		var key: float = (
			IsoProjection.ground_to_px((FOOT.x * 2 + size) * 500, (FOOT.y * 2 + size) * 500).y
		)
		# The y of the footprint's centre, which is where its node stands: (c + r + n) * 16 px.
		assert_float(key).is_equal(float(FOOT.x + FOOT.y + size) * 16.0)
		var cases: Array[Array] = []  # [position, after the building?]
		for step: int in range(1, 8):
			var along: int = step * size * 1000 / 8  # Strictly inside the footprint's span.
			cases.append(
				[Vector2i((FOOT.x + size) * 1000 + 250 * step, FOOT.y * 1000 + along), true]
			)
			cases.append(
				[Vector2i(FOOT.x * 1000 + along, (FOOT.y + size) * 1000 + 250 * step), true]
			)
			cases.append([Vector2i(FOOT.x * 1000 + along, FOOT.y * 1000 - 250 * step), false])
			cases.append([Vector2i(FOOT.x * 1000 - 250 * step, FOOT.y * 1000 + along), false])
		_open_units(cases.size())
		for row: int in cases.size():
			var at: Vector2i = cases[row][0]
			_set_position(row, at)
		_layer._process(0.0)
		for row: int in cases.size():
			var after: bool = cases[row][1]
			var y: float = _layer.rig(row).position.y
			(
				assert_bool(y > key if after else y < key)
				. override_failure_message(
					(
						"%dx%d footprint, unit at %s: y %s against %s"
						% [size, size, cases[row][0], y, key]
					)
				)
				. is_true()
			)
		# A unit stands at its projected ground point and nowhere else: its y is its sort key.
		assert_float(_layer.rig(0).position.y).is_equal(
			IsoProjection.ground_to_px(cases[0][0].x, cases[0][0].y).y
		)
		_free_layer()


func test_every_sorted_sprite_is_on_the_atlas_texture_in_white_whatever_the_mix() -> void:
	# Both factions, three types each and two owners each in the sort: types and owners interleave.
	var scenario: ScenarioDef = _scenario(
		[
			_spawn(1, "light_tank", 5, 5),
			_spawn(2, "renew_tank", 8, 5),
			_spawn(1, "rifle_squad", 5, 8),
			_spawn(2, "renew_rifle", 8, 8),
			_spawn(1, "rocket_squad", 5, 11),
			_spawn(2, "renew_scout", 8, 11),
			_spawn(1, "heavy_tank", 5, 14),
			_spawn(2, "renew_tank", 8, 14),
		]
	)
	scenario.factions = _factions()
	_open(scenario)
	_layer.set_selected(PackedInt32Array([1, 2]))
	var atlas: IsoAtlas = _layer.world_sort.atlas
	assert_bool(atlas.is_empty()).is_false()
	assert_int(_layer.rig_count()).is_equal(8)
	var sprites: Array[Sprite2D] = []
	for sprite: Node in _layer.world_sort.find_children("*", "Sprite2D", true, false):
		if sprite.name != &"Ring":  # The ring is a ground mark with its own texture, at z 3.
			sprites.append(sprite)
	var turrets: int = 0  # A shadow and a hull each, and a turret for the types whose sheet has one.
	for row: int in _runner.snapshot.unit_count():
		var snap: MatchSnapshot = _runner.snapshot
		turrets += (
			1
			if _layer.world_sort.sheet(snap.type_ids[snap.type_index[row]]).has_part(&"turret")
			else 0
		)
	assert_int(turrets).is_between(4, 8)
	assert_int(sprites.size()).is_equal(8 * 2 + turrets)
	for sprite: Sprite2D in sprites:
		var why: String = "%s of %s" % [sprite.name, sprite.get_parent().name]
		assert_object(sprite.texture).override_failure_message(why).is_same(atlas.texture())
		assert_that(sprite.modulate).override_failure_message(why).is_equal(Color.WHITE)
		assert_that(sprite.self_modulate).override_failure_message(why).is_equal(Color.WHITE)
		assert_object(sprite.material).override_failure_message(why).is_null()
		assert_bool(sprite.visible).override_failure_message(why).is_true()
		assert_bool(sprite.region_rect.has_area()).override_failure_message(why).is_true()
		assert_bool(sprite.region_enabled).override_failure_message(why).is_true()
	assert_object(_layer.rig(0).get_node("Ring").texture).is_not_same(atlas.texture())


func test_players_take_their_factions_from_the_scenario_and_the_triads_by_their_number() -> void:
	var scenario: ScenarioDef = _scenario(
		[_spawn(1, "light_tank", 5, 5), _spawn(2, "renew_tank", 8, 5)]
	)
	scenario.factions = _factions()
	_open(scenario)
	var atlas: IsoAtlas = _layer.world_sort.atlas
	assert_bool(atlas.region(&"light_tank", &"hull", 6, 0).has_area()).is_true()
	assert_bool(atlas.region(&"renew_tank", &"hull", 6, 1).has_area()).is_true()
	assert_bool(atlas.region(&"renew_tank", &"hull", 6, 0).has_area()).is_false()
	assert_bool(atlas.region(&"light_tank", &"hull", 6, 1).has_area()).is_false()
	assert_int(_layer.world_sort.slot_of(1)).is_equal(0)
	assert_int(_layer.world_sort.slot_of(2)).is_equal(1)
	assert_int(_layer.world_sort.slot_of(0)).is_equal(0)  # Neutral and past the end: the nearest.
	assert_int(_layer.world_sort.slot_of(9)).is_equal(1)
	for row: int in 2:
		assert_int(Frames.dir(_layer, row, &"hull")).is_equal(6)
		assert_int(Frames.dir(_layer, row, &"shadow")).is_equal(6)
	# A scenario that lists no factions gives each player the faction of its own first type, so a
	# mirror match is two fossil players in two triads, and two other factions are each their own.
	_free_layer()
	_open(_scenario([_spawn(1, "light_tank", 5, 5), _spawn(2, "light_tank", 8, 5)]))
	atlas = _layer.world_sort.atlas
	assert_bool(atlas.region(&"light_tank", &"hull", 6, 0).has_area()).is_true()
	assert_bool(atlas.region(&"light_tank", &"hull", 6, 1).has_area()).is_true()
	(
		assert_bool(
			atlas.region(&"light_tank", &"hull", 6, 0) != atlas.region(&"light_tank", &"hull", 6, 1)
		)
		. is_true()
	)
	_free_layer()
	_open(_scenario([_spawn(1, "light_tank", 5, 5), _spawn(2, "renew_tank", 8, 5)]))
	atlas = _layer.world_sort.atlas
	assert_bool(atlas.region(&"renew_tank", &"hull", 6, 1).has_area()).is_true()
	assert_bool(atlas.region(&"renew_tank", &"hull", 6, 0).has_area()).is_false()


func test_the_atlas_holds_only_the_art_the_scenario_registers_and_a_restart_bakes_nothing() -> void:
	_open(_scenario([_spawn(1, "light_tank", 5, 5), _spawn(2, "light_tank", 8, 5)]))
	var sort: WorldSort = _layer.world_sort
	var atlas: IsoAtlas = sort.atlas
	assert_object(sort.sheet(&"light_tank")).is_not_null()
	assert_object(sort.sheet(&"heavy_tank")).is_null()  # Not registered, so not baked.
	assert_bool(atlas.region(&"heavy_tank", &"hull", 6, 0).has_area()).is_false()
	_runner.start()  # Another match of the same scenario: the same art and players.
	_layer._process(0.0)
	assert_object(sort.atlas).is_same(atlas)
	assert_object(sort.bake(_runner.scenario)).is_same(atlas)  # Asked for again, as the arena does.
	# Another scenario with other art is baked afresh.
	_runner.scenario = _scenario([_spawn(1, "heavy_tank", 5, 5), _spawn(2, "light_tank", 8, 5)])
	_runner.start()
	_layer._process(0.0)
	assert_object(sort.atlas).is_not_same(atlas)
	assert_bool(sort.atlas.region(&"heavy_tank", &"hull", 6, 0).has_area()).is_true()
	assert_int(Frames.dir(_layer, 0, &"hull")).is_equal(6)
	# A scenario with no unit has no art at all, and no error.
	_runner.scenario = _scenario([])
	_runner.start()
	_layer._process(0.0)
	assert_bool(sort.atlas.is_empty()).is_true()
	assert_int(_layer.rig_count()).is_equal(0)


func test_art_that_is_not_in_the_atlas_is_stood_in_for_by_a_marker_drawn_by_draw() -> void:
	var grunt: UnitDef = UnitDef.new()  # A type with no sheet.
	grunt.type_id = &"grunt_test"
	var spawn: SpawnDef = _spawn(2, "light_tank", 8, 5)
	spawn.unit = grunt
	_open(_scenario([_spawn(1, "light_tank", 5, 5), spawn]))
	var sort: WorldSort = _layer.world_sort
	assert_array(_child_names(_layer.rig(0))).is_equal([&"Shadow", &"Hull", &"Turret"])  # Art.
	var rig: Node2D = _layer.rig(1)
	assert_array(_child_names(rig)).is_equal([&"Marker"])  # None: no sprite, one drawn ellipse.
	var marker: Node2D = rig.get_node("Marker")
	assert_str(marker.get_script().get_instance_base_type()).is_equal("Node2D")
	assert_that(marker.colour).is_equal(sort.mid_colour(2))
	assert_that(marker.colour).is_not_equal(Color.WHITE)
	assert_float(marker.radius).is_equal_approx(
		IsoProjection.ellipse_px(_runner.snapshot.type_selection_radius[1]).x, 0.001
	)
	assert_that(_layer.unit_screen_position(1)).is_equal(
		_camera.world_to_screen(IsoProjection.ground_to_px(8500, 5500))
	)
	_layer.set_selected(PackedInt32Array([2]))  # It is selected, turns and is picked like a rig.
	assert_array(_child_names(rig)).is_equal([&"Marker", &"Ring"])
	var pick: PickSnapshot = PickSnapshot.new()
	_layer.fill_pick_snapshot(pick, 24.0)
	assert_int(pick.pickable[1]).is_equal(1)
	# An atlas that did not bake gives every rig the marker, over sprites that show nothing.
	sort.atlas = IsoAtlas.new()
	_runner.start()
	_layer._process(0.0)
	assert_int(_layer.rig_count()).is_equal(2)
	for row: int in 2:
		assert_bool(_layer.rig(row).has_node("Marker")).is_true()
		assert_object(_layer.rig(row).get_node("Marker").get_parent()).is_same(_layer.rig(row))
	for sprite: Sprite2D in _layer.rig(0).find_children("*", "Sprite2D", false, false):
		assert_object(sprite.texture).is_null()


func test_a_building_row_has_no_rig_no_ring_no_pick_and_no_bar_and_units_stay_in_row_order(
) -> void:
	var scenario: ScenarioDef = _scenario(
		[
			_spawn(1, "light_tank", 4, 8),
			_spawn(2, "headquarters", 7, 2),
			_spawn(2, "light_tank", 10, 8)
		]
	)
	scenario.map_size_tiles = Vector2i(16, 12)
	scenario.player_count = 2
	_open(scenario)
	var snap: MatchSnapshot = _runner.snapshot
	assert_array(snap.type_foot_w).is_equal(PackedInt32Array([0, 3]))
	assert_int(snap.unit_count()).is_equal(3)
	assert_int(_layer.rig_count()).is_equal(2)  # The two tanks.
	assert_int(_layer.world_sort.get_child_count()).is_equal(2)
	assert_object(_layer.rig(0)).is_not_null()
	assert_object(_layer.rig(1)).is_null()  # The Headquarters is row 1: BuildingLayer draws it.
	assert_object(_layer.rig(2)).is_not_null()
	assert_str(_layer.rig(2).name).is_equal("Unit3")
	_layer.set_selected(PackedInt32Array([1, 2, 3]))  # A building takes no ring.
	assert_array(_layer._ringed).is_equal(PackedInt32Array([0, 2]))
	var pick: PickSnapshot = PickSnapshot.new()
	_layer.fill_pick_snapshot(pick, 24.0)
	assert_array(pick.ids).is_equal(PackedInt32Array([1, 2, 3]))
	assert_array(pick.pickable).is_equal(PackedByteArray([1, 0, 1]))
	# A building's row answers where its position, the footprint centre, is.
	assert_that(pick.screen_pos[1]).is_equal(_layer.unit_screen_position(1))
	# A hit building gets no unit bar, a hit tank does.
	var bars: HealthBarLayer = auto_free(HealthBarLayer.new())
	bars.runner = _runner
	bars.unit_layer = _layer
	add_child(bars)
	bars.set_process(false)
	snap.hp[1] -= 100
	snap.hp[2] -= 100
	_layer.sync_rows()
	_layer._note_hits(snap)  # The layer saw both hp drops this frame.
	bars._process(0.0)
	var drawn: Array[int] = []
	for bar: int in bars.bar_count():
		drawn.append(bars.bar_row(bar))
	assert_array(drawn).is_equal([0, 2])  # The selected tanks; the damaged tank is among them.
	_layer.set_selected(PackedInt32Array())
	_layer._note_hits(snap)
	bars._process(0.0)
	assert_int(bars.bar_count()).is_equal(1)  # Only the damaged tank; the building has none.
	assert_int(bars.bar_row(0)).is_equal(2)


func _open(scenario: ScenarioDef) -> void:
	_runner = auto_free(MatchRunner.new())
	_runner.scenario = scenario
	_runner.paused = true
	_runner.start()
	_layer = auto_free(UnitLayer.new())
	_layer.runner = _runner
	_layer.camera = _camera
	add_child(_layer)
	_layer.set_process(false)
	_layer._process(0.0)


## `count` tanks of owner 1 in a column, to be moved by `_set_position`.
func _open_units(count: int) -> void:
	var spawn: SpawnDef = _spawn(1, "light_tank", 2, 2)
	spawn.count = count
	spawn.columns = 1
	spawn.spacing = 1000
	_open(_scenario([spawn]))


## Writes both positions of row `row` of the published snapshot (the layer draws alpha 0).
func _set_position(row: int, at: Vector2i) -> void:
	var snap: MatchSnapshot = _runner.snapshot
	snap.pos_x[row] = at.x
	snap.pos_y[row] = at.y
	snap.prev_pos_x[row] = at.x
	snap.prev_pos_y[row] = at.y


func _free_layer() -> void:
	remove_child(_layer)
	_layer.free()
	_runner.free()


## The value a scene file sets on the node called `node_name`, `fallback` when it sets none.
func _scene_value(
	state: SceneState, node_name: String, prop: StringName, fallback: Variant
) -> Variant:
	for index: int in state.get_node_count():
		if state.get_node_name(index) != node_name:
			continue
		for at: int in state.get_node_property_count(index):
			if state.get_node_property_name(index, at) == prop:
				return state.get_node_property_value(index, at)
	return fallback


## The names of the root's own children, in scene order.
func _root_children(state: SceneState) -> Array[String]:
	var names: Array[String] = []
	for index: int in state.get_node_count():
		if str(state.get_node_path(index, true)) == ".":  # Its parent is the scene's root.
			names.append(state.get_node_name(index))
	return names


func _child_names(node: Node) -> Array:
	return node.get_children().map(func(n: Node) -> StringName: return n.name)


## The factions of a two-player match, indexed by player: entry 0 is unused.
func _factions() -> Array[FactionDef]:
	var factions: Array[FactionDef] = [null]
	for id: String in ["fossil", "renew"]:
		factions.append(load("res://data/factions/%s.tres" % id) as FactionDef)
	return factions


func _scenario(spawns: Array[SpawnDef]) -> ScenarioDef:
	var scenario: ScenarioDef = ScenarioDef.new()
	scenario.rules = load(RULES) as RulesDef
	scenario.spawns = spawns
	return scenario


func _spawn(owner_id: int, unit: String, x: int, y: int) -> SpawnDef:
	var spawn: SpawnDef = SpawnDef.new()
	spawn.owner = owner_id
	spawn.unit = load("res://data/units/%s.tres" % unit)
	spawn.count = 1
	spawn.origin_tile = Vector2i(x, y)
	return spawn
