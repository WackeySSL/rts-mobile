extends GdUnitTestSuite
## Where the opponent AI builds on Heron Fords and Curlew Crags (plan row P555): two computer
## opponents play a fixed seed for a few minutes of game on each of the four scenarios of a map.
## Every building they have then stands on buildable ground and none overlaps another (the sim's
## placement rule answers each PLACE, so a tile of rock, water, ore or an occupied one never takes
## a building), and every refinery is reachable by the harvester's class from an ore field, so a
## refinery on the sand below the centre mesa's ramp serves it and one in a closed pocket would not.

const Rig: GDScript = preload("res://tests/ai/support/ai_rig.gd")
const Opp: GDScript = preload("res://tests/ai/support/opponent_rig.gd")
const Kestrel: GDScript = preload("res://tests/sim/support/kestrel_rig.gd")

const STEMS: Array[String] = [
	"res://data/scenarios/skirmish_heron_fords",
	"res://data/scenarios/skirmish_curlew_crags",
]
const SUFFIXES: Array[String] = ["", "_mirrored", "_fossil_mirror", "_renew_mirror"]
const SEED: int = 7
## About three minutes of game: both sides have a refinery and a barracks by then.
const TICKS: int = 2700
const HARVESTER: Dictionary[StringName, StringName] = {
	&"fossil": &"harvester", &"renew": &"renew_tanker"
}
const REFINERY: Dictionary[StringName, StringName] = {
	&"fossil": &"refinery", &"renew": &"renew_refinery"
}

var _world: World
var _controllers: Array = []
var _duels: Dictionary[String, Dictionary] = {}


func test_the_ai_never_has_a_command_refused_and_every_building_stands_on_buildable_ground(
) -> void:
	for stem: String in STEMS:
		for suffix: String in SUFFIXES:
			var path: String = stem + suffix + ".tres"
			_duel(path)
			# The AI asks the sim's own rule before every PLACE, so none may come back refused.
			assert_int(_duels[path]["places"]).override_failure_message(path).is_greater(4)
			assert_int(_world.dropped_commands).override_failure_message(path).is_equal(0)
			var taken: Dictionary[int, int] = {}
			var count: int = 0
			for player: int in [1, 2]:
				for row: int in Kestrel.building_rows(_world, player):
					count += 1
					_take(row, taken, path)
			assert_int(count).override_failure_message(path).is_greater(6)


func test_every_refinery_is_reachable_from_an_ore_field_by_the_harvesters_class() -> void:
	for stem: String in STEMS:
		for suffix: String in SUFFIXES:
			var path: String = stem + suffix + ".tres"
			_duel(path)
			var scenario: ScenarioDef = load(path) as ScenarioDef
			for player: int in [1, 2]:
				var faction: StringName = scenario.factions[player].id
				var refineries: int = _check_refineries(player, faction, path)
				assert_int(refineries).override_failure_message(path).is_greater(0)


func test_the_staging_point_is_open_ground_on_the_own_side_of_the_map() -> void:
	for stem: String in STEMS:
		for suffix: String in SUFFIXES:
			var path: String = stem + suffix + ".tres"
			_duel(path)
			for controller: OpponentAi in _controllers:
				var memory: AiMemory = controller.memory
				var cell: int = memory.staging_y * _world.map_cols + memory.staging_x
				var note: String = "%s: player %d" % [path, controller.player_id]
				assert_bool(memory.has_staging()).override_failure_message(note).is_true()
				for move_class: int in [World.MoveClass.FOOT, World.MoveClass.TRACKED]:
					(
						assert_bool(_world.is_passable(cell, move_class))
						. override_failure_message(note)
						. is_true()
					)
				var home: int = memory.home_y * _world.map_cols + memory.home_x
				var gap_home: int = _gap(cell, home)
				var gap_enemy: int = _gap(cell, _world.map_cols * _world.map_rows - 1 - home)
				assert_int(gap_home).override_failure_message(note).is_less(gap_enemy)


## Plays every scenario once for all the tests: the World, the controllers and the PLACE Commands
## the two sent.
func before() -> void:
	for stem: String in STEMS:
		for suffix: String in SUFFIXES:
			var path: String = stem + suffix + ".tres"
			var scenario: ScenarioDef = load(path) as ScenarioDef
			var world: World = World.from_scenario(
				scenario, DetRandom.create(SEED, DetRandom.STREAM_SIM)
			)
			var loop: MatchLoop = Rig.loop_of(world, SEED)
			var controllers: Array = []
			for player: int in [1, 2]:
				controllers.append(
					Opp.opponent(String(scenario.factions[player].id), "normal", player, SEED)
				)
			var places: int = 0
			for command: Command in Rig.run(world, loop, controllers, TICKS):
				places += 1 if command.type == Command.Type.PLACE else 0
			_duels[path] = {"world": world, "controllers": controllers, "places": places}


## Makes the played World and controllers of `path` the suite's.
func _duel(path: String) -> void:
	_world = _duels[path]["world"]
	_controllers = _duels[path]["controllers"]


## Every footprint tile of building `row` is buildable ground and not one of an earlier building.
func _take(row: int, taken: Dictionary[int, int], path: String) -> void:
	var type: int = _world.type_index[row]
	var origin: Vector2i = _world.footprint_origin(row)
	for dy: int in _world.type_foot_h[type]:
		for dx: int in _world.type_foot_w[type]:
			var cell: int = (origin.y + dy) * _world.map_cols + origin.x + dx
			var note: String = "%s: building row %d, tile %d" % [path, row, cell]
			(
				assert_int(_world.terrain_buildable[_world.terrain[cell]])
				. override_failure_message(note)
				. is_equal(1)
			)
			assert_bool(taken.has(cell)).override_failure_message(note).is_false()
			taken[cell] = row


## Checks each refinery of `player`; returns how many there are.
@warning_ignore("integer_division")
func _check_refineries(player: int, faction: StringName, path: String) -> int:
	var harvester: int = Rig.type_of(_world, String(HARVESTER[faction]))
	var move_class: int = _world.type_move_class[harvester]
	var refineries: int = 0
	for row: int in Kestrel.building_rows(_world, player):
		if _world.type_ids[_world.type_index[row]] != REFINERY[faction]:
			continue
		refineries += 1
		var type: int = _world.type_index[row]
		var origin: Vector2i = _world.footprint_origin(row)
		var below: Vector2i = Vector2i(
			origin.x + _world.type_foot_w[type] / 2, origin.y + _world.type_foot_h[type]
		)
		var found: bool = false
		for cells: PackedInt32Array in Kestrel.ore_fields(_world):
			var goal: Vector2i = Vector2i(cells[0] % _world.map_cols, cells[0] / _world.map_cols)
			var flow: FlowField = Kestrel.field(_world, goal, move_class)
			found = found or Kestrel.reaches(flow, _world.map_cols, below)
		assert_bool(found).override_failure_message(path).is_true()
	return refineries


## The squared distance between two cells in tiles.
@warning_ignore("integer_division")
func _gap(first: int, second: int) -> int:
	var dx: int = first % _world.map_cols - second % _world.map_cols
	var dy: int = first / _world.map_cols - second / _world.map_cols
	return dx * dx + dy * dy
