extends GdUnitTestSuite
## World v0 setup (ADR 0003 sections 2 and 6): the unit and scenario definitions, the controls
## test scenario and World.from_scenario. Pins ids, positions and type stats.

const SCENARIO_PATH: String = "res://data/scenarios/controls_test.tres"
const TANK_PATH: String = "res://data/units/light_tank.tres"
const MAP_MILLI: int = 48000

var _scenario: ScenarioDef
var _tank: UnitDef
var _world: World


func before_test() -> void:
	_scenario = load(SCENARIO_PATH) as ScenarioDef
	_tank = load(TANK_PATH) as UnitDef
	_world = World.from_scenario(_scenario)


func test_scenario_file_matches_the_plan() -> void:
	assert_object(_scenario).is_not_null()
	assert_that(_scenario.map_size_tiles).is_equal(Vector2i(48, 48))
	assert_int(_scenario.local_player).is_equal(1)
	assert_that(_scenario.camera_start_tile).is_equal(Vector2i(12, 21))
	var owners: Array[int] = []
	var counts: Array[int] = []
	var origins: Array[Vector2i] = []
	for spawn: SpawnDef in _scenario.spawns:
		owners.append(spawn.owner)
		counts.append(spawn.count)
		origins.append(spawn.origin_tile)
		assert_object(spawn.unit).is_same(_tank)
	assert_array(owners).is_equal([1, 2, 2, 2])
	assert_array(counts).is_equal([30, 4, 3, 3])
	assert_array(origins).is_equal(
		[Vector2i(8, 18), Vector2i(34, 10), Vector2i(38, 30), Vector2i(26, 40)]
	)


func test_map_is_48000_milli_square_and_the_clock_starts_at_zero() -> void:
	assert_int(_world.map_w).is_equal(MAP_MILLI)
	assert_int(_world.map_h).is_equal(MAP_MILLI)
	assert_int(_world.tick).is_equal(0)
	assert_int(_world.dropped_commands).is_equal(0)


func test_ids_ascend_from_one_and_owners_follow_spawn_order() -> void:
	assert_int(_world.unit_count()).is_equal(40)
	assert_int(_world.next_id).is_equal(41)
	for i: int in _world.unit_count():
		assert_int(_world.unit_id[i]).is_equal(i + 1)
		assert_int(_world.owner[i]).is_equal(1 if i < 30 else 2)


func test_all_unit_arrays_have_one_entry_per_unit() -> void:
	var count: int = _world.unit_count()
	for column: PackedInt32Array in [
		_world.unit_id,
		_world.owner,
		_world.type_index,
		_world.pos_x,
		_world.pos_y,
		_world.goal_x,
		_world.goal_y,
		_world.order,
	]:
		assert_int(column.size()).is_equal(count)


@warning_ignore("integer_division")
func test_units_sit_on_their_spawn_grid() -> void:
	var index: int = 0
	for spawn: SpawnDef in _scenario.spawns:
		for k: int in spawn.count:
			var x: int = spawn.origin_tile.x * 1000 + 500 + (k % spawn.columns) * spawn.spacing
			var y: int = spawn.origin_tile.y * 1000 + 500 + (k / spawn.columns) * spawn.spacing
			assert_int(_world.pos_x[index]).is_equal(x)
			assert_int(_world.pos_y[index]).is_equal(y)
			index += 1
	assert_int(index).is_equal(_world.unit_count())


## Literal positions, so the grid test above cannot agree with a wrong formula by repeating it.
func test_known_units_have_known_positions() -> void:
	var expected: Dictionary[int, Vector2i] = {
		1: Vector2i(8500, 18500),
		6: Vector2i(16000, 18500),
		7: Vector2i(8500, 20000),
		30: Vector2i(16000, 24500),
		31: Vector2i(34500, 10500),
		35: Vector2i(38500, 30500),
		38: Vector2i(26500, 40500),
		40: Vector2i(30500, 40500),
	}
	for id: int in expected:
		var index: int = _world.index_of(id)
		assert_int(index).is_equal(id - 1)
		assert_int(_world.pos_x[index]).is_equal(expected[id].x)
		assert_int(_world.pos_y[index]).is_equal(expected[id].y)


func test_every_unit_is_inside_the_map() -> void:
	for i: int in _world.unit_count():
		assert_int(_world.pos_x[i]).is_between(0, MAP_MILLI)
		assert_int(_world.pos_y[i]).is_between(0, MAP_MILLI)


func test_units_start_idle_with_the_goal_on_their_position() -> void:
	for i: int in _world.unit_count():
		assert_int(_world.order[i]).is_equal(World.Order.IDLE)
		assert_int(_world.goal_x[i]).is_equal(_world.pos_x[i])
		assert_int(_world.goal_y[i]).is_equal(_world.pos_y[i])


## Four spawns share one UnitDef, so the world holds one type entry holding the file's stats.
func test_one_type_entry_holds_the_light_tank_stats() -> void:
	assert_array(_world.type_ids).is_equal([&"light_tank"])
	assert_int(_tank.speed).is_greater(0)
	assert_array(_world.type_speed).is_equal([_tank.speed])
	assert_array(_world.type_radius).is_equal([_tank.radius])
	assert_array(_world.type_selection_radius).is_equal([_tank.selection_radius])
	assert_array(_world.type_spacing).is_equal([_tank.formation_spacing])
	for i: int in _world.unit_count():
		assert_int(_world.type_index[i]).is_equal(0)


func test_type_index_follows_first_appearance_in_the_spawns() -> void:
	var scout: UnitDef = _unit_def(&"scout", 200)
	var scenario: ScenarioDef = ScenarioDef.new()
	scenario.map_size_tiles = Vector2i(10, 10)
	scenario.spawns.append(_spawn(1, scout, 1, 0, 2))
	scenario.spawns.append(_spawn(2, _tank, 2, 1, 2))
	scenario.spawns.append(_spawn(1, scout, 1, 2, 2))
	var world: World = World.from_scenario(scenario)
	assert_array(world.type_ids).is_equal([&"scout", &"light_tank"])
	assert_int(world.type_speed[0]).is_equal(200)
	assert_int(world.type_speed[1]).is_equal(_tank.speed)
	assert_array(world.type_index).is_equal([0, 1, 1, 0])
	assert_array(world.owner).is_equal([1, 2, 2, 1])


func test_zero_columns_is_read_as_one_column() -> void:
	var scenario: ScenarioDef = ScenarioDef.new()
	scenario.map_size_tiles = Vector2i(10, 10)
	scenario.spawns.append(_spawn(1, _tank, 3, 0, 0))
	var world: World = World.from_scenario(scenario)
	assert_array(world.pos_x).is_equal([500, 500, 500])
	assert_array(world.pos_y).is_equal([500, 1500, 2500])


func test_a_missing_scenario_gives_an_empty_world() -> void:
	var world: World = World.from_scenario(null)
	assert_int(world.unit_count()).is_equal(0)
	assert_int(world.next_id).is_equal(1)


func test_index_of_is_minus_one_for_unknown_ids() -> void:
	for id: int in [-1, 0, 41, 1000]:
		assert_int(_world.index_of(id)).is_equal(-1)
	assert_int(World.new().index_of(1)).is_equal(-1)


func test_add_unit_appends_with_the_next_id() -> void:
	var id: int = _world.add_unit(2, 0, 3000, 4000)
	assert_int(id).is_equal(41)
	assert_int(_world.next_id).is_equal(42)
	assert_int(_world.unit_count()).is_equal(41)
	var index: int = _world.index_of(id)
	assert_int(index).is_equal(40)
	assert_int(_world.owner[index]).is_equal(2)
	assert_int(_world.pos_x[index]).is_equal(3000)
	assert_int(_world.goal_y[index]).is_equal(4000)
	assert_int(_world.order[index]).is_equal(World.Order.IDLE)
	assert_int(_world.add_unit(1, 0, 0, 0)).is_equal(42)


func _unit_def(type_id: StringName, speed: int) -> UnitDef:
	var def: UnitDef = UnitDef.new()
	def.type_id = type_id
	def.speed = speed
	return def


func _spawn(player: int, unit: UnitDef, count: int, origin_x: int, columns: int) -> SpawnDef:
	var spawn: SpawnDef = SpawnDef.new()
	spawn.owner = player
	spawn.unit = unit
	spawn.count = count
	spawn.origin_tile = Vector2i(origin_x, 0)
	spawn.columns = columns
	spawn.spacing = 1000
	return spawn
