extends GdUnitTestSuite
## The building list and its two parts (plan P84, ADR 0022 sections 1 and 2): every building of the
## snapshot is a box of its footprint plus the texture's rise anchored on the footprint's south
## edge, cut at the middle line of the footprint into a base part (south of the line) and a roof
## part (north of it), all of it regions of one atlas, the roof parts in ascending south row. The
## unit layer and the bar layer leave the rows with a footprint alone. The fog is in
## test_building_layer_fog.gd, the heads in test_building_heads.gd and the crafted units
## north, south and beside a building in test_building_cut.gd. On the base match (Rig).

const Rig: GDScript = preload("res://tests/view/support/building_rig.gd")
const IDS: Array[StringName] = [
	&"headquarters", &"power_plant", &"refinery", &"barracks", &"vehicle_factory", &"defence_turret"
]

var _runner: MatchRunner
var _camera: RtsCamera
var _units: UnitLayer
var _buildings: BuildingLayer


func before_test() -> void:
	_runner = auto_free(Rig.runner())
	_camera = auto_free(RtsCamera.new())
	add_child(_camera)
	_camera.position = Vector2(640, 360)
	_units = auto_free(UnitLayer.new())
	_units.runner = _runner
	_units.camera = _camera
	add_child(_units)
	_units.set_process(false)
	_buildings = auto_free(BuildingLayer.new())
	_buildings.runner = _runner
	_buildings.unit_layer = _units
	add_child(_buildings)
	_buildings.set_process(false)


func after_test() -> void:
	CommandQueue.clear()


func test_the_atlas_holds_the_art_of_every_building_type_and_the_dot_tile() -> void:
	_buildings.sync()
	var atlas: RuntimeAtlas = _buildings.atlas()
	for id: StringName in IDS:
		for layer: String in ["hull", "team"]:
			var region: Rect2i = atlas.region(StringName("%s_%s" % [id, layer]))
			assert_that(region.size).override_failure_message("%s %s" % [id, layer]).is_equal(
				Vector2i(Rig.texture_size(id, layer))
			)
	assert_bool(atlas.has_region(&"defence_turret_turret")).is_true()
	assert_that(atlas.region(&"defence_turret_turret").size).is_equal(Vector2i(64, 112))
	assert_bool(atlas.has_region(&"headquarters_turret")).is_false()
	assert_bool(atlas.has_region(&"ghost_seen")).is_true()
	assert_bool(atlas.has_region(&"light_tank_hull")).is_false()  # A mobile type has no part.
	assert_object(atlas.texture()).is_not_null()


func test_a_match_with_no_building_type_has_no_atlas_and_no_list() -> void:
	_runner = auto_free(Rig.runner(load("res://data/scenarios/controls_test.tres")))
	_buildings.runner = _runner
	_buildings.sync()
	assert_object(_buildings.atlas()).is_null()
	assert_int(_buildings.building_count()).is_equal(0)
	assert_int(_buildings.paint(_buildings, false)).is_equal(0)


func test_every_building_is_listed_in_row_order_with_its_box_on_the_south_edge() -> void:
	var list: Array[Dictionary] = Rig.buildings()
	_buildings.sync()
	var snap: MatchSnapshot = _runner.snapshot
	assert_int(_buildings.building_count()).is_equal(Rig.BUILDINGS)
	for b: int in list.size():
		var row: int = _buildings.building_row(b)
		var origin: Vector2i = list[b][&"origin"]
		var foot: Vector2i = list[b][&"foot"]
		var size: Vector2 = Rig.texture_size(list[b][&"id"])
		assert_str(snap.type_ids[snap.type_index[row]]).is_equal(list[b][&"id"])
		assert_int(snap.owner[row]).is_equal(list[b][&"owner"])
		assert_int(_buildings.building_of(row)).is_equal(b)
		# The box is the footprint plus the texture's rise, anchored on the south edge.
		var want: Rect2 = Rect2(
			origin.x * 64.0, (origin.y + foot.y) * 64.0 - size.y, foot.x * 64.0, size.y
		)
		assert_that(_buildings.sprite_box(b)).is_equal(want)
		assert_float(size.y - foot.y * 64.0).is_equal(48.0)  # The rise, from the texture alone.
		assert_float(size.x).is_equal(foot.x * 64.0)
	assert_int(_buildings.building_of(Rig.OWN_BUILDINGS)).is_equal(-1)  # A unit's row.


func test_each_building_is_cut_at_the_middle_line_of_its_footprint() -> void:
	var list: Array[Dictionary] = Rig.buildings()
	_buildings.sync()
	var atlas: RuntimeAtlas = _buildings.atlas()
	# Base and roof heights by footprint side (ADR 0022 section 2): 3x3 96 and 144, 2x2 64 and 112,
	# 1x1 32 and 80.
	var parts: Dictionary[int, Vector2] = {
		3: Vector2(96, 144), 2: Vector2(64, 112), 1: Vector2(32, 80)
	}
	for b: int in list.size():
		var origin: Vector2i = list[b][&"origin"]
		var foot: Vector2i = list[b][&"foot"]
		var box: Rect2 = _buildings.sprite_box(b)
		var y_mid: float = origin.y * 64.0 + foot.y * 32.0
		var base: Rect2 = _buildings.part_dst(b, false)
		var roof: Rect2 = _buildings.part_dst(b, true)
		assert_float(base.position.y).is_equal(y_mid)
		assert_float(roof.end.y).is_equal(y_mid)
		assert_float(base.end.y).is_equal(box.end.y)  # The south edge of the footprint.
		assert_that(roof.position).is_equal(box.position)
		assert_float(base.size.x).is_equal(box.size.x)
		assert_float(roof.size.x).is_equal(box.size.x)
		assert_float(base.size.y).is_equal(parts[foot.x].x)
		assert_float(roof.size.y).is_equal(parts[foot.x].y)
		# One texel is one world px: each layer's source is its region cut at the same line.
		for layer: int in [BuildingLayer.HULL, BuildingLayer.TEAM]:
			var key: StringName = StringName("%s_%s" % [list[b][&"id"], ["hull", "team"][layer]])
			var region: Rect2 = Rect2(atlas.region(key))
			var base_src: Rect2 = _buildings.part_src(b, layer, false)
			var roof_src: Rect2 = _buildings.part_src(b, layer, true)
			assert_that(base_src.size).is_equal(base.size)
			assert_that(roof_src.size).is_equal(roof.size)
			assert_that(roof_src.position).is_equal(region.position)
			assert_float(base_src.end.y).is_equal(region.end.y)
			assert_float(base_src.position.y).is_equal(roof_src.end.y)  # The two meet at the cut.


func test_the_roof_parts_come_in_ascending_south_row_and_the_base_parts_in_row_order() -> void:
	var list: Array[Dictionary] = Rig.buildings()
	_buildings.sync()
	var want: Array[int] = []
	for b: int in list.size():
		want.append(b)
	want.sort_custom(
		func(first: int, second: int) -> bool:
			var south_first: int = list[first][&"origin"].y + list[first][&"foot"].y
			var south_second: int = list[second][&"origin"].y + list[second][&"foot"].y
			return south_first < south_second or (south_first == south_second and first < second)
	)
	assert_array(Array(_buildings.roof_order())).is_equal(want)
	assert_array(want).is_not_equal(range(list.size()))  # The two orders differ, so this pins one.
	var last_south: int = -1
	for b: int in _buildings.roof_order():
		var south: int = list[b][&"origin"].y + list[b][&"foot"].y
		assert_int(south).is_greater_equal(last_south)
		last_south = south


func test_the_team_layer_takes_the_owners_colour_and_the_hull_stays_white() -> void:
	_buildings.reveal_enemies = true
	_buildings.sync()
	var own: int = Rig.find(Rig.buildings(), &"refinery", 1)
	var enemy: int = Rig.find(Rig.buildings(), &"refinery", 2)
	for roof: bool in [false, true]:
		assert_that(_buildings.part_color(own, BuildingLayer.HULL, roof)).is_equal(Color.WHITE)
		assert_that(_buildings.part_color(enemy, BuildingLayer.HULL, roof)).is_equal(Color.WHITE)
		assert_that(_buildings.part_color(own, BuildingLayer.TEAM, roof)).is_equal(
			_units.team_color(1)
		)
		assert_that(_buildings.part_color(enemy, BuildingLayer.TEAM, roof)).is_equal(
			_units.team_color(2)
		)
	assert_that(_units.team_color(1)).is_not_equal(_units.team_color(2))


func test_the_unit_layer_makes_no_rig_for_a_building_and_every_row_still_answers() -> void:
	_units._process(0.0)
	var snap: MatchSnapshot = _runner.snapshot
	var units: int = snap.unit_count() - Rig.BUILDINGS
	assert_int(units).is_equal(10)
	assert_int(_units.rig_count()).is_equal(units)
	assert_str(_units.get_child(0).name).is_equal("Unit7")  # The first row that is no building.
	assert_bool(_units.is_shown(0)).is_true()  # A building row answers like any own row.
	assert_bool(_units.is_shown(snap.unit_count() - 1)).is_false()  # An enemy squad, in the fog.
	# Selecting a building's id rings nothing; a unit's id rings its rig.
	_units.set_selected(PackedInt32Array([1]))
	assert_bool(_units.is_ringed(0)).is_false()
	_units.set_selected(PackedInt32Array([7]))
	assert_bool(_units.is_ringed(Rig.OWN_BUILDINGS)).is_true()
	# The pick snapshot holds every row, a building's unpickable, and its centre where it stands.
	var pick: PickSnapshot = PickSnapshot.new()
	_units.fill_pick_snapshot(pick, 24.0)
	assert_int(pick.size()).is_equal(snap.unit_count())
	for row: int in snap.unit_count():
		var own_unit: bool = snap.owner[row] == 1 and row >= Rig.OWN_BUILDINGS
		var pickable: int = 1 if own_unit and row < Rig.OWN_BUILDINGS + 5 else 0
		assert_int(pick.pickable[row]).override_failure_message(str(row)).is_equal(pickable)
	var centre: Vector2 = ViewScale.milli_to_px_vec(snap.pos_x[0], snap.pos_y[0])
	assert_that(pick.screen_pos[0]).is_equal(_camera.world_to_screen(centre))
	assert_that(_units.unit_screen_position(0)).is_equal(_camera.world_to_screen(centre))


func test_a_hit_building_gets_no_unit_bar_while_a_hit_unit_does() -> void:
	var bars: HealthBarLayer = auto_free(HealthBarLayer.new())
	bars.runner = _runner
	bars.unit_layer = _units
	add_child(bars)
	bars.set_process(false)
	_units._process(0.0)
	_runner.world.hp[0] -= 100  # The Headquarters.
	_runner.world.hp[Rig.OWN_BUILDINGS] -= 1  # The first harvester.
	_runner.run_ticks(1)
	_units._process(0.0)
	bars._process(0.0)
	assert_int(bars.bar_count()).is_equal(1)
	assert_int(bars.bar_row(0)).is_equal(Rig.OWN_BUILDINGS)
