extends GdUnitTestSuite
## `MapDef.ground_look` is for the view only (plan row P551): the loader never reads it. A match
## on Heron Fords with its look, with none and with a look that does not exist builds the same
## World: the map digest, the state hash, the defs hash and every member the lockstep diff lists.
## A copy with one tile of sand where the shipped map has grass is the control.

const StateDiff: GDScript = preload("res://tests/sim/support/state_diff.gd")
const SCENARIO: String = "res://data/scenarios/skirmish_heron_fords.tres"
const SEED: int = 42


func test_ground_look_moves_no_digest_and_no_hash() -> void:
	var scenario: ScenarioDef = load(SCENARIO) as ScenarioDef
	assert_str(String(scenario.map.ground_look)).is_equal("heron")
	var worlds: Array[World] = []
	for look: StringName in [&"heron", &"", &"nowhere"]:
		var map: MapDef = scenario.map.duplicate() as MapDef
		map.ground_look = look
		worlds.append(_world_on(scenario, map))
	for other: int in [1, 2]:
		assert_int(WorldHash.map_digest(worlds[other])).is_equal(WorldHash.map_digest(worlds[0]))
		assert_int(worlds[other].state_hash()).is_equal(worlds[0].state_hash())
		assert_int(worlds[other].defs_hash()).is_equal(worlds[0].defs_hash())
		assert_str(StateDiff.first(worlds[0], worlds[other])).is_empty()
	var changed: MapDef = scenario.map.duplicate() as MapDef
	var rows: PackedStringArray = changed.rows.duplicate()
	rows[0] = ":" + rows[0].substr(1)
	changed.rows = rows
	var control: World = _world_on(scenario, changed)
	assert_int(WorldHash.map_digest(control)).is_not_equal(WorldHash.map_digest(worlds[0]))
	assert_int(control.state_hash()).is_not_equal(worlds[0].state_hash())


func _world_on(scenario: ScenarioDef, map: MapDef) -> World:
	var copy: ScenarioDef = scenario.duplicate() as ScenarioDef
	copy.map = map
	return World.from_scenario(copy, DetRandom.create(SEED, DetRandom.STREAM_SIM))
