extends GdUnitTestSuite
## World v4, the construction layout (plan row P128, ADR 0026 sections 1 and 10, exception 10): the
## row column `build_left` and the three rule ints `construct_start_hp_percent`,
## `construct_refund_percent` and `construction_sites_max`, each in exactly the lists the ADR names;
## what is state (the column, in the hash) and what is not (the rule ints, in `defs_hash`); and the
## perf arena and the base arena, which place no structure, keeping the column at its start value
## for 300 ticks (the golden hashes pin all 900). The rules of a
## site are in test_site_place, test_site_build and test_site_unfinished. The layout re-pin itself
## is pinned where the hashes are (test_world_hash's TICK_0_SEED_1, data/dev/perf_gate.tres through
## tests/perf/test_golden_hashes). Numbers are literals, so no data file can agree with a wrong
## rule.

const HashBytes: GDScript = preload("res://tests/perf/support/hash_bytes.gd")
const ARENA_PATH: String = "res://data/scenarios/perf_arena.tres"
const RULES_PATH: String = "res://data/dev/arena/rules.tres"
const RULES: Dictionary[StringName, int] = {
	&"construct_start_hp_percent": 10,
	&"construct_refund_percent": 75,
	&"construction_sites_max": 1,
}


func test_the_layout_version_and_the_new_column_are_the_contract() -> void:
	assert_array([World.STATE_FORMAT, World.HASH_OTHER_SECTIONS]).is_equal([7, 8])
	# `ammo` (P232) and `carry_mode` (P262) follow build_left.
	assert_int(World.ROW_ARRAYS.size()).is_equal(29)
	assert_array(World.ROW_ARRAYS.slice(-5)).is_equal(
		[&"ready_tick", &"offline_until", &"build_left", &"ammo", &"carry_mode"]
	)
	var names: PackedStringArray = World.hash_section_names()
	assert_array(names.slice(-7)).is_equal(
		["carry_mode", "projectiles", "fog", "players", "ore", "ghosts", "passengers"]
	)
	assert_int(names.size()).is_equal(World.ROW_ARRAYS.size() + World.HASH_OTHER_SECTIONS)
	# One shape list, and an int32 table of the World.
	var lists: Array = [World.ROW_ARRAYS, World.TYPE_ARRAYS, World.WEAPON_ARRAYS]
	lists.append_array([World.PROJECTILE_ARRAYS, World.MAP_ARRAYS, World.SCRATCH_ARRAYS])
	lists.append_array([World.RUNTIME_ARRAYS, World.PLAYER_ARRAYS, World.ORE_ARRAYS])
	lists.append_array([World.GHOST_ARRAYS, World.DERIVED_ARRAYS, World.SETUP_ARRAYS])
	lists.append_array([World.PAD_ARRAYS, World.UPGRADE_ARRAYS, World.PASSENGER_ARRAYS])
	var found: int = 0
	for list: Array in lists:
		if list.has(&"build_left"):
			found += 1
	assert_int(found).is_equal(1)
	assert_int(typeof(World.new().build_left)).is_equal(TYPE_PACKED_INT32_ARRAY)


## The three rule ints end RULE_SCALARS (so `defs_hash` sees them) and UNHASHED_SCALARS (so the
## state hash does not), in RulesDef's order, with the file's values, in a hand-built World too.
func test_the_three_rule_ints_sit_before_the_sale_ints_in_both_lists_and_equal_the_file() -> void:
	var names: Array[StringName] = RULES.keys()
	for list: Array[StringName] in [World.RULE_SCALARS, World.UNHASHED_SCALARS]:
		var at: int = list.find(names[0])  # Found by name: later rules move nothing here.
		assert_array(list.slice(at, at + names.size())).is_equal(names)
	assert_bool(World.HASHED_SCALARS.has(&"construct_start_hp_percent")).is_false()
	var file: RulesDef = load(RULES_PATH) as RulesDef
	var made: World = World.new()
	for rule_name: StringName in RULES:
		assert_int(made.get(rule_name)).override_failure_message(rule_name).is_equal(
			RULES[rule_name]
		)
		assert_int(file.get(rule_name)).override_failure_message(rule_name).is_equal(
			RULES[rule_name]
		)
		assert_int(RulesDef.new().get(rule_name)).override_failure_message(rule_name).is_equal(
			RULES[rule_name]
		)


## A scenario's rules reach the World through `copy_rules`, and a World without them keeps the
## defaults.
func test_copy_rules_carries_the_three_ints_to_the_world() -> void:
	var rules: RulesDef = RulesDef.new()
	rules.construct_start_hp_percent = 33
	rules.construct_refund_percent = 50
	rules.construction_sites_max = 3
	var scenario: ScenarioDef = ScenarioDef.new()
	scenario.rules = rules
	var made: World = World.from_scenario(scenario)
	(
		assert_array(
			[
				made.construct_start_hp_percent,
				made.construct_refund_percent,
				made.construction_sites_max
			]
		)
		. is_equal([33, 50, 3])
	)
	var plain: World = World.from_scenario(ScenarioDef.new())
	(
		assert_array(
			[
				plain.construct_start_hp_percent,
				plain.construct_refund_percent,
				plain.construction_sites_max
			]
		)
		. is_equal([10, 75, 1])
	)


## A new row is complete (0), `add_building` too, and the compaction that removes a dead row moves
## the column with the others.
func test_add_unit_starts_the_column_at_zero_and_a_removal_compacts_it() -> void:
	var made: World = World.new()
	made.type_ids.append(&"unit")
	made.player_count = 1
	made.prepare()
	for _i: int in 4:
		made.add_unit(1, 0, 1000, 1000)
	assert_array(made.build_left).is_equal([0, 0, 0, 0])
	for row: int in 4:
		made.build_left[row] = 500 * (row + 1)
	made.hp[1] = 0
	made.remove_dead()
	assert_array(made.unit_id).is_equal([1, 3, 4])
	assert_array(made.build_left).is_equal([500, 1500, 2000])


## The column is state: it moves its own section and no other, and the byte stream that the perf
## suite's helper rebuilds from the shape lists (an independent walk) hashes to state_hash(). The
## rule ints are not state: they move defs_hash and leave the state hash alone. The perf arena
## places no structure, so every row of it is complete.
func test_the_column_is_state_and_the_rule_ints_are_not() -> void:
	var base: World = _arena()
	var pending: int = 0
	for value: int in base.build_left:
		pending += absi(value)
	assert_int(pending).is_equal(0)
	var written: World = _arena()
	written.build_left[written.build_left.size() - 1] = 90
	var names: PackedStringArray = World.hash_section_names()
	var differing: Array[String] = []
	var left: PackedInt64Array = base.hash_parts()
	var right: PackedInt64Array = written.hash_parts()
	for index: int in names.size():
		if left[index] != right[index]:
			differing.append(names[index])
	assert_array(differing).is_equal(["build_left"])
	assert_int(written.state_hash()).is_not_equal(base.state_hash())
	assert_int(HashBytes.digest(HashBytes.stream(written))).is_equal(written.state_hash())
	var defs: int = base.defs_hash()
	for rule_name: StringName in RULES:
		var other: World = _arena()
		other.set(rule_name, RULES[rule_name] + 1)
		assert_int(other.state_hash()).override_failure_message(rule_name).is_equal(
			base.state_hash()
		)
		assert_int(other.defs_hash()).override_failure_message(rule_name).is_not_equal(defs)


## The two arenas place no structure, so no row of either is ever a site: the column is all zeros
## at every golden tick of the first 300 (behaviour did not move; the golden hashes pin the rest).
func test_the_arenas_never_write_the_column() -> void:
	for path: String in [ARENA_PATH, "res://data/scenarios/perf_bases.tres"]:
		var scenario: ScenarioDef = load(path) as ScenarioDef
		var made: World = World.from_scenario(scenario, DetRandom.create(42, DetRandom.STREAM_SIM))
		var loop: MatchLoop = MatchLoop.create(scenario, path, 42, made)
		var queued: Array[Command] = []
		for _tick: int in 300:
			loop.step(made, queued)
			if made.tick % 150 == 0:
				var pending: int = 0
				for value: int in made.build_left:
					pending += absi(value)
				(
					assert_int(pending)
					. override_failure_message("%s, tick %d" % [path, made.tick])
					. is_equal(0)
				)
				assert_int(made.build_left.size()).is_equal(made.unit_count())


func _arena() -> World:
	return World.from_scenario(load(ARENA_PATH) as ScenarioDef)
