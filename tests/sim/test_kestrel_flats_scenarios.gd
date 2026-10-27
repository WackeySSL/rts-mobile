extends GdUnitTestSuite
## The two Kestrel Flats skirmish scenarios (plan row P79, ADR 0023 section 6): player 1 in the
## north-west, player 2 in the south-east, each with a Headquarters and two rifle squads of its
## faction, the factions listed by player, and the second scenario the first with the factions
## swapped. The start footprints are valid ground by Placement's own rule, and a run of 1,800 ticks
## with no Commands drops nothing, under both implementations.

const Rig: GDScript = preload("res://tests/sim/support/kestrel_rig.gd")
const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const RULES_PATH: String = "res://data/rules.tres"
const FOSSIL_PATH: String = "res://data/factions/fossil.tres"
const RENEW_PATH: String = "res://data/factions/renew.tres"
const TICKS: int = 1800
## Per scenario, the faction of players 1 and 2 and the blocks of its spawns: owner, type id, count,
## origin tile, columns, spacing and jitter. No block has jitter, so no seed reaches a position.
const FACTION_FILES: Dictionary[String, Array] = {
	Rig.SKIRMISH_PATH: [FOSSIL_PATH, RENEW_PATH],
	Rig.MIRRORED_PATH: [RENEW_PATH, FOSSIL_PATH],
}
const BLOCKS: Dictionary[String, Array] = {
	Rig.SKIRMISH_PATH:
	[
		[1, "headquarters", 1, Vector2i(7, 7), 1, 1000, 0],
		[1, "rifle_squad", 2, Vector2i(11, 11), 2, 2000, 0],
		[2, "renew_hq", 1, Vector2i(54, 54), 1, 1000, 0],
		[2, "renew_rifle", 2, Vector2i(50, 52), 2, 2000, 0],
	],
	Rig.MIRRORED_PATH:
	[
		[1, "renew_hq", 1, Vector2i(7, 7), 1, 1000, 0],
		[1, "renew_rifle", 2, Vector2i(11, 11), 2, 2000, 0],
		[2, "headquarters", 1, Vector2i(54, 54), 1, 1000, 0],
		[2, "rifle_squad", 2, Vector2i(50, 52), 2, 2000, 0],
	],
}


func _both() -> Array[Array]:
	return SimImpls.CASES.duplicate(true)


## The Reason of the building in `row` as if it were still to be placed: its footprint tiles get the
## cost their terrain gives (the building closed them), and the fog's explored mask is left out
## (`fog_player_count` 0), so that only the ground, the units, the reach and the cap decide.
func _reason(world: World, row: int) -> int:
	var input: PlacementInput = PlacementInput.of_world(world)
	var type: int = world.type_index[row]
	var origin: Vector2i = world.footprint_origin(row)
	var classes: int = World.MoveClass.size()
	var cells: int = world.map_cols * world.map_rows
	var costs: PackedByteArray = world.move_cost.duplicate()
	for y: int in range(origin.y, origin.y + world.type_foot_h[type]):
		for x: int in range(origin.x, origin.x + world.type_foot_w[type]):
			var cell: int = y * world.map_cols + x
			for move_class: int in classes:
				costs[move_class * cells + cell] = world.terrain_cost[
					world.terrain[cell] * classes + move_class
				]
	input.move_cost = costs
	input.fog_player_count = 0
	return Placement.reason(input, world.owner[row], type, origin.x, origin.y)


func test_each_scenario_is_a_two_player_skirmish_on_kestrel_flats_with_the_shared_rules() -> void:
	for path: String in Rig.PATHS:
		var scenario: ScenarioDef = load(path) as ScenarioDef
		assert_str(scenario.map.resource_path).override_failure_message(path).is_equal(Rig.MAP_PATH)
		assert_str(scenario.rules.resource_path).override_failure_message(path).is_equal(RULES_PATH)
		assert_array(scenario.map.validate()).is_empty()
		assert_that(scenario.map_size_tiles).is_equal(Vector2i(Rig.SIZE, Rig.SIZE))
		assert_int(scenario.player_count).is_equal(2)
		assert_int(scenario.local_player).is_equal(1)
		assert_that(scenario.camera_start_tile).is_equal(Vector2i(8, 8))
		assert_array(scenario.orders).is_empty()
		assert_array(scenario.roster).is_empty()


func test_the_factions_are_listed_by_player_and_the_second_scenario_swaps_them() -> void:
	for path: String in Rig.PATHS:
		var scenario: ScenarioDef = load(path) as ScenarioDef
		var paths: Array = FACTION_FILES[path]
		assert_int(scenario.factions.size()).is_equal(3)
		assert_object(scenario.factions[0]).is_null()
		for player: int in [1, 2]:
			assert_str(scenario.factions[player].resource_path).is_equal(paths[player - 1])
	var first: ScenarioDef = load(Rig.SKIRMISH_PATH) as ScenarioDef
	assert_str(String(first.factions[1].id)).is_equal("fossil")
	assert_str(String(first.factions[2].id)).is_equal("renew")
	assert_str(first.factions[1].display_name).is_equal("Derrick League")
	assert_str(first.factions[2].display_name).is_equal("Lumen Accord")
	var second: ScenarioDef = load(Rig.MIRRORED_PATH) as ScenarioDef
	assert_object(second.factions[1]).is_same(first.factions[2])
	assert_object(second.factions[2]).is_same(first.factions[1])


func test_each_side_starts_with_a_headquarters_and_two_rifle_squads_of_its_faction() -> void:
	for path: String in Rig.PATHS:
		var scenario: ScenarioDef = load(path) as ScenarioDef
		var blocks: Array = []
		for spawn: SpawnDef in scenario.spawns:
			var block: Array = [spawn.owner, String(spawn.unit.type_id), spawn.count]
			blocks.append(block + [spawn.origin_tile, spawn.columns, spawn.spacing, spawn.jitter])
		assert_array(blocks).override_failure_message(path).is_equal(BLOCKS[path])
		var world: World = Rig.world(path)
		assert_int(world.unit_count()).is_equal(6)
		assert_array(Array(world.owner)).is_equal([1, 1, 1, 2, 2, 2])
		# Each unit is of the faction its player is listed with, and nothing else is on the map.
		for row: int in world.unit_count():
			var faction: FactionDef = scenario.factions[world.owner[row]]
			(
				assert_str(String(world.faction_ids[world.type_faction[world.type_index[row]]]))
				. is_equal(String(faction.id))
			)
		for player: int in [1, 2]:
			assert_int(world.credits[player]).is_equal(world.start_credits)


func test_the_two_sides_are_a_half_turn_of_each_other() -> void:
	for path: String in Rig.PATHS:
		var world: World = Rig.world(path)
		var turned: Array[Vector2i] = []
		var theirs: Array[Vector2i] = []
		var turn: int = Rig.SIZE * World.MILLI_PER_TILE
		for row: int in world.unit_count():
			var at: Vector2i = Vector2i(world.pos_x[row], world.pos_y[row])
			if world.owner[row] == 1:
				turned.append(Vector2i(turn, turn) - at)
			else:
				theirs.append(at)
		turned.sort()
		theirs.sort()
		assert_array(theirs).override_failure_message(path).is_equal(turned)
		# The Headquarters of one side and the other have one footprint, a half turn apart.
		var one: Vector2i = world.footprint_origin(Rig.building_rows(world, 1)[0])
		var two: Vector2i = world.footprint_origin(Rig.building_rows(world, 2)[0])
		assert_that(two).is_equal(Vector2i(Rig.SIZE - 3, Rig.SIZE - 3) - one)


func test_every_start_footprint_passes_the_placement_rule_for_its_owner() -> void:
	for path: String in Rig.PATHS:
		var world: World = Rig.world(path)
		var checked: int = 0
		for player: int in [1, 2]:
			for row: int in Rig.building_rows(world, player):
				assert_int(_reason(world, row)).override_failure_message(path).is_equal(
					Placement.Reason.OK
				)
				checked += 1
		assert_int(checked).is_equal(2)


## The check above is not vacuous: the same rule says no to a Headquarters on the other kinds of
## ground a start footprint could have been put on, and to one that a unit stands on.
func test_the_placement_check_refuses_rock_ore_water_and_a_unit_in_the_way() -> void:
	var world: World = Rig.world(Rig.SKIRMISH_PATH)
	var hq: int = world.type_index[Rig.building_rows(world, 1)[0]]
	var input: PlacementInput = PlacementInput.of_world(world)
	input.fog_player_count = 0
	# Origin tiles of a 3x3 footprint: on the pocket's rock wall, on player 1's north ore field, on
	# the north-east lake, and on the tile player 1's first rifle squad stands on (11, 11).
	var probes: Dictionary[Vector2i, int] = {
		Vector2i(38, 18): Placement.Reason.GROUND,
		Vector2i(16, 4): Placement.Reason.GROUND,
		Vector2i(54, 5): Placement.Reason.GROUND,
		Vector2i(11, 11): Placement.Reason.OCCUPIED,
		Vector2i(12, 8): Placement.Reason.OK,
	}
	for origin: Vector2i in probes:
		var reason: int = Placement.reason(input, 1, hq, origin.x, origin.y)
		assert_int(reason).override_failure_message(str(origin)).is_equal(probes[origin])


@warning_ignore("integer_division")
func test_a_run_of_1800_ticks_without_commands_drops_nothing(
	impl: int, _test_parameters := _both()
) -> void:
	var none: Array[Command] = []
	for path: String in Rig.PATHS:
		var scenario: ScenarioDef = load(path) as ScenarioDef
		var world: World = Rig.world(path)
		assert_array(SimImpls.use(world, impl)).is_empty()
		for phase: int in SimImpls.EXPECTED_PHASES:
			var native: bool = SimImpls.is_native(world, phase)
			assert_bool(native).is_equal(impl == SimImpls.Impl.NATIVE)
		var loop: MatchLoop = MatchLoop.create(scenario, path, Rig.SEED, world)
		var hp: PackedInt32Array = world.hp.duplicate()
		for _tick: int in TICKS:
			loop.step(world, none)
		assert_int(world.tick).is_equal(TICKS)
		assert_int(world.dropped_commands).override_failure_message(path).is_equal(0)
		assert_int(world.spawn_refused).is_equal(0)
		assert_int(world.projectile_overflow).is_equal(0)
		# Nothing happened to either side: no end, no loss, no row gained or lost, no damage.
		assert_array([world.match_end_tick, world.winner]).is_equal([0, 0])
		assert_array(Array(world.defeated_tick)).is_equal([0, 0, 0])
		assert_array(Array(world.hp)).is_equal(Array(hp))
		assert_int(world.unit_count()).is_equal(6)
		assert_array(loop.replay.commands).is_empty()
		assert_int(loop.replay.checkpoint_hashes.size()).is_equal(TICKS / Replay.CHECKPOINT_PERIOD)
