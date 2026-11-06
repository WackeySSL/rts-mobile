extends GdUnitTestSuite
## What test_smoke_run.gd cannot reach (plan row P186, ADR 0031 sections 1 to 3): the real entry
## script run headless with every new flag, a kill that the real sim produces reaching the counter,
## the rupture radius of the kill attribution, and the tick of the first dropped Command.

const Smoke: GDScript = preload("res://tests/smoke/smoke_run.gd")
const SmokeCount: GDScript = preload("res://tests/smoke/smoke_count.gd")
const ENTRY: String = "res://tests/smoke/run_sim_smoke.gd"
const DUMMIES: Array[String] = ["dummy", "dummy"]


## The entry as the shell script starts it, with `args` after the `--`: exit code and output.
func _entry(args: Array[String]) -> Dictionary:
	var launch: PackedStringArray = PackedStringArray(
		["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", ENTRY, "--"]
	)
	launch.append_array(PackedStringArray(args))
	var output: Array = []
	var code: int = OS.execute(OS.get_executable_path(), launch, output, true)
	return {"code": code, "text": String(output[0])}


func test_the_entry_plays_the_seeds_scenario_levels_and_ticks_it_is_given() -> void:
	var folder: DirAccess = DirAccess.create_temp("smoke_entry_")
	var path: String = folder.get_current_dir().path_join("r.json")
	var result: Dictionary = _entry(
		[
			"--matches",
			"2",
			"--seed-start",
			"7",
			"--ticks",
			"15",
			"--levels",
			"easy,dummy",
			"--scenarios",
			"lumen",
			"--report",
			path,
		]
	)
	assert_int(result["code"]).is_equal(0)
	assert_str(result["text"]).contains("run-sim-smoke: OK, 2 matches of at most 15 ticks")
	assert_str(result["text"]).not_contains("SCRIPT ERROR")
	assert_str(result["text"]).not_contains("ERROR:")
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	(
		assert_array(
			[int(report["seed_start"]), report["scenarios"], int(report["ticks_per_match"])]
		)
		. is_equal([7, "lumen", 15])
	)
	assert_array(report["levels"]).is_equal(["easy", "dummy"])
	assert_int(int(report["matches_requested"])).is_equal(2)
	var seeds: Array = []
	for record: Dictionary in report["matches"]:
		seeds.append(int(record["seed"]))
		assert_str(record["scenario"]).is_equal(Smoke.FLATS_MIRRORED)
		assert_int(int(record["ticks"])).is_equal(15)
		assert_array([record["players"][0]["level"], record["players"][1]["level"]]).is_equal(
			["easy", "dummy"]
		)
		# Lumen holds the top seat on the mirrored scenario.
		assert_str(record["players"][0]["faction"]).is_equal("renew")
	assert_array(seeds).is_equal([7, 8])


func test_the_entry_exits_2_on_a_bad_argument() -> void:
	for args: Array in [["--levels", "normal"], ["--ticks", "0"], ["--bogus", "1"]]:
		var arguments: Array[String] = []
		arguments.assign(args)
		assert_int(_entry(arguments)["code"]).is_equal(2)


func test_a_kill_the_sim_makes_reaches_the_counter() -> void:
	var setup: Dictionary = Smoke.start(1, "derrick", DUMMIES)
	var world: World = setup["world"]
	var rifle: int = world.type_ids.find(&"rifle_squad")
	var enemy: int = world.type_ids.find(&"renew_rifle")
	var first: int = -1
	for row: int in world.unit_count():
		if world.owner[row] == 1 and world.type_index[row] == rifle:
			first = row
			break
	assert_int(first).is_greater(-1)
	world.add_unit(2, enemy, world.pos_x[first] + 1500, world.pos_y[first])
	var counter: SmokeCount = setup["counter"]
	Smoke.run(world, setup["loop"], setup["controllers"], 300, counter)
	assert_dict(counter.kills[1]).is_equal({"rifle_squad": 1})
	assert_dict(counter.lost[2]).is_equal({"renew_rifle": 1})


func test_a_rupture_is_credited_only_inside_its_radius() -> void:
	var world: World = Smoke.world_of(1, Smoke.FLATS)
	var radius: int = world.type_strike_radius[Strike.rupture_type(world)]
	assert_int(radius).is_greater(0)
	var counter: SmokeCount = SmokeCount.new(2)
	var rifle: int = world.type_ids.find(&"rifle_squad")
	var tank: int = world.type_ids.find(&"light_tank")
	var strike: int = world.type_ids.find(&"fossil_strike")
	counter.start(world)
	world.tick = 1
	world.events = _events(
		[
			_record(World.Event.SPAWNED, 11, 0, 0, tank, 1),
			_record(World.Event.SPAWNED, 25, 0, 0, strike, 1),
			_record(World.Event.SPAWNED, 41, 0, 0, rifle, 2),
			_record(World.Event.SPAWNED, 42, 0, 0, rifle, 2),
		]
	)
	counter.after_step(world)
	# Both rows were shot at tick 3 by the tank (5 ticks before the landing).
	world.tick = 3
	world.events = _events(
		[
			_record(World.Event.SHOT, 11, 0, 0, 41),
			_record(World.Event.SHOT, 11, 0, 0, 42),
		]
	)
	counter.after_step(world)
	# The strike at (5000, 2000) lands in tick 8: row 41 dies inside the radius, row 42 outside it.
	world.tick = 5
	world.events = _events([_record(World.Event.STRIKE, 25, 5000, 2000, 1, 1, 8)])
	counter.after_step(world)
	world.tick = 8
	world.events = _events(
		[
			_record(World.Event.DIED, 41, 5000 + radius, 2000, rifle, 2),
			_record(World.Event.DIED, 42, 5000, 2000 + radius + 1, rifle, 2),
		]
	)
	counter.after_step(world)
	assert_dict(counter.kills[1]).is_equal({"fossil_strike": 1, "light_tank": 1})
	assert_dict(counter.lost[2]).is_equal({"rifle_squad": 2})


func test_the_tick_of_the_first_dropped_command_is_kept() -> void:
	var world: World = Smoke.world_of(1, Smoke.FLATS)
	var counter: SmokeCount = SmokeCount.new(2)
	for tick: int in [1, 2, 3]:
		world.tick = tick
		world.events = PackedInt32Array()
		counter.after_step(world)
	assert_int(counter.first_drop_tick).is_equal(-1)
	world.tick = 10
	world.dropped_commands = 1
	counter.after_step(world)
	world.tick = 11
	world.dropped_commands = 3
	counter.after_step(world)
	# The step that dropped it ran at tick 9 and left the World at tick 10.
	assert_int(counter.first_drop_tick).is_equal(9)
	var drops: Dictionary[int, int] = {}
	var record: Dictionary = Smoke.play(1, 15, "derrick", DUMMIES, drops)
	assert_int(record["dropped_commands"]).is_equal(0)
	assert_dict(drops).is_empty()


func _record(
	kind: int, a: int = 0, b: int = 0, c: int = 0, d: int = 0, e: int = 0, f: int = 0, g: int = 0
) -> PackedInt32Array:
	return PackedInt32Array([kind, a, b, c, d, e, f, g])


func _events(records: Array[PackedInt32Array]) -> PackedInt32Array:
	var events: PackedInt32Array = PackedInt32Array()
	for entry: PackedInt32Array in records:
		events.append_array(entry)
	return events
