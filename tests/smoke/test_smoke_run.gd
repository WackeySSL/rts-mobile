extends GdUnitTestSuite
## The match behind scripts/run-sim-smoke.sh (plan row P186, ADR 0031 sections 1 to 3): full
## AI-vs-AI matches on the scenario kinds, the cap and its "timeout", AUTO with the implementation
## recorded, the counting from events and `flow_full_ticks`, and the report of schema 2. Pinned
## here: a seed played twice gives the same record, report text and checkpoint at every 15th tick;
## the counting changes no state hash; the report keeps every schema 1 key (the top-level
## `scenario` moved into each match) and holds only ints; a dropped Command fails the run and a
## timeout does not. The shell script's flags and exit codes are in `test_run_sim_smoke_script.gd`.
##
## The matches are short (`TICKS` below): the opponent AI of Phase 4 is built slot by slot, so what
## a long match holds is the balance run's business (GitHub Actions); this suite pins the harness.

const Smoke: GDScript = preload("res://tests/smoke/smoke_run.gd")
const TICKS: int = 900
## 900 ticks hold 60 checkpoints: one every 15th tick from tick 15.
const CHECKPOINTS: int = 60
const REPORT_KEYS: Array[String] = [
	"commit",
	"impl",
	"levels",
	"matches",
	"matches_requested",
	"scenarios",
	"schema",
	"seed_start",
	"status",
	"ticks_per_match",
]
## The keys of a schema 1 report that schema 2 keeps with their meaning (`scenario` moved).
const SCHEMA_1_REPORT_KEYS: Array[String] = [
	"matches", "matches_requested", "schema", "status", "ticks_per_match"
]
const MATCH_KEYS: Array[String] = [
	"dropped_commands",
	"end",
	"flow_full_ticks",
	"match_end_tick",
	"players",
	"scenario",
	"seed",
	"spawn_refused",
	"state_hash",
	"ticks",
	"winner",
]
const SCHEMA_1_MATCH_KEYS: Array[String] = [
	"dropped_commands",
	"match_end_tick",
	"players",
	"seed",
	"spawn_refused",
	"state_hash",
	"ticks",
	"winner",
]
const PLAYER_KEYS: Array[String] = [
	"ai",
	"buildings",
	"built",
	"commands",
	"credits",
	"defeated_tick",
	"faction",
	"free",
	"harvested",
	"kills",
	"level",
	"lost",
	"lost_buildings",
	"lost_units",
	"player",
	"produced",
	"retreats",
	"scouts",
	"seat",
	"spent",
	"strikes",
	"structures",
	"think_work_max",
	"units",
	"waves",
]
const SCHEMA_1_PLAYER_KEYS: Array[String] = [
	"ai",
	"buildings",
	"built",
	"credits",
	"defeated_tick",
	"harvested",
	"lost_buildings",
	"lost_units",
	"player",
	"units",
]
const NORMAL: Array[String] = ["normal", "normal"]
const DUMMIES: Array[String] = ["dummy", "dummy"]

## Seed 1 as the harness plays it: Normal against Normal, `cross`, 900 ticks, twice, with the loops.
var _records: Array[Dictionary] = []
var _loops: Array[MatchLoop] = []
## Seed 1 with the dummies, with the counter (the record) and without it (the hash).
var _dummy_record: Dictionary = {}
var _uncounted_hash: String = ""


func before() -> void:
	var path: String = Smoke.scenario_path("cross", 1)
	for _again: int in 2:
		var world: World = Smoke.world_of(1, path)
		var loop: MatchLoop = Smoke.loop_of(world, 1, path)
		var counter: SmokeCount = SmokeCount.create(2)
		Smoke.attach_impl(world)
		counter.start(world)
		var controllers: Array[AiController] = Smoke.controllers_of(1, path, NORMAL)
		Smoke.run(world, loop, controllers, TICKS, counter)
		var seats: Array[Dictionary] = Smoke.seats_of(path, NORMAL)
		_records.append(Smoke.record_of(world, 1, path, seats, controllers, counter))
		_loops.append(loop)
	_dummy_record = Smoke.play(1, TICKS, "cross", DUMMIES)
	var bare: World = Smoke.world_of(1, path)
	Smoke.attach_impl(bare)
	Smoke.run(bare, Smoke.loop_of(bare, 1, path), Smoke.controllers_of(1, path, DUMMIES), TICKS)
	_uncounted_hash = World.hash_hex(bare.state_hash())


func test_a_seed_played_twice_gives_the_same_record_report_and_checkpoints() -> void:
	assert_str(JSON.stringify(_records[1])).is_equal(JSON.stringify(_records[0]))
	var again: Array[Dictionary] = [_records[1]]
	var first_run: Array[Dictionary] = [_records[0]]
	assert_str(Smoke.report_text(Smoke.report(again, 1, TICKS))).is_equal(
		Smoke.report_text(Smoke.report(first_run, 1, TICKS))
	)
	var first: Replay = _loops[0].replay
	var second: Replay = _loops[1].replay
	assert_int(first.checkpoint_ticks.size()).is_equal(CHECKPOINTS)
	assert_array(Array(first.checkpoint_ticks)).is_equal(Array(second.checkpoint_ticks))
	assert_array(Array(first.checkpoint_hashes)).is_equal(Array(second.checkpoint_hashes))
	# play() is the same match by its own door.
	var played: Dictionary = Smoke.play(1, TICKS, "cross", NORMAL)
	assert_str(JSON.stringify(played)).is_equal(JSON.stringify(_records[0]))


func test_the_scenario_kinds_and_the_cross_alternation() -> void:
	for match_seed: int in [1, 3, 99]:
		assert_str(Smoke.scenario_path("cross", match_seed)).is_equal(Smoke.FLATS)
	for match_seed: int in [2, 4, 100]:
		assert_str(Smoke.scenario_path("cross", match_seed)).is_equal(Smoke.FLATS_MIRRORED)
	# The other kinds ignore the seed.
	for match_seed: int in [1, 2]:
		assert_str(Smoke.scenario_path("derrick", match_seed)).is_equal(Smoke.FLATS)
		assert_str(Smoke.scenario_path("lumen", match_seed)).is_equal(Smoke.FLATS_MIRRORED)
		assert_str(Smoke.scenario_path("fossil-mirror", match_seed)).is_equal(Smoke.FOSSIL_MIRROR)
		assert_str(Smoke.scenario_path("renew-mirror", match_seed)).is_equal(Smoke.RENEW_MIRROR)
	for kind: String in Smoke.KINDS:
		assert_bool(ResourceLoader.exists(Smoke.scenario_path(kind, 1))).is_true()
	# Each faction holds each seat in half of the cross matches; player 1 is always the top seat.
	var factions: Dictionary[String, int] = {}
	for match_seed: int in [1, 2, 3, 4]:
		var seats: Array[Dictionary] = Smoke.seats_of(
			Smoke.scenario_path("cross", match_seed), NORMAL
		)
		assert_array([seats[0]["seat"], seats[1]["seat"]]).is_equal(["top", "bottom"])
		factions[seats[0]["faction"]] = int(factions.get(seats[0]["faction"], 0)) + 1
	assert_array([factions["fossil"], factions["renew"]]).is_equal([2, 2])


func test_the_seats_name_faction_ai_and_level() -> void:
	var cases: Dictionary[String, Array] = {
		"derrick": [["fossil", "opponent_fossil"], ["renew", "opponent_renew"]],
		"lumen": [["renew", "opponent_renew"], ["fossil", "opponent_fossil"]],
		"fossil-mirror": [["fossil", "opponent_fossil"], ["fossil", "opponent_fossil"]],
		"renew-mirror": [["renew", "opponent_renew"], ["renew", "opponent_renew"]],
	}
	for kind: String in cases:
		var seats: Array[Dictionary] = Smoke.seats_of(Smoke.scenario_path(kind, 1), NORMAL)
		for index: int in 2:
			assert_array([seats[index]["faction"], seats[index]["ai"]]).is_equal(cases[kind][index])
			assert_array([seats[index]["player"], seats[index]["level"]]).is_equal(
				[index + 1, "normal"]
			)
	var dummies: Array[Dictionary] = Smoke.seats_of(Smoke.FLATS, DUMMIES)
	assert_array([dummies[0]["ai"], dummies[1]["ai"]]).is_equal(["dummy_fossil", "dummy_renew"])


func test_each_controller_is_built_as_match_runner_builds_it() -> void:
	for match_seed: int in [1, 2]:
		var path: String = Smoke.scenario_path("cross", match_seed)
		var controllers: Array[AiController] = Smoke.controllers_of(match_seed, path, NORMAL)
		assert_int(controllers.size()).is_equal(2)
		for index: int in controllers.size():
			var player: int = index + 1
			var controller: AiController = controllers[index]
			assert_str((controller.get_script() as Script).get_global_name()).is_equal("OpponentAi")
			assert_int(controller.player_id).is_equal(player)
			# The stream of the player and the match seed, never the sim's and never another seed's.
			var stream: DetRandom = DetRandom.create(match_seed, DetRandom.STREAM_AI_BASE + player)
			assert_array(Array(controller.rng.state())).is_equal(Array(stream.state()))
		# One seed gives two players two streams and two think rhythms.
		assert_array(Array(controllers[1].rng.state())).is_not_equal(
			Array(controllers[0].rng.state())
		)
		assert_int(controllers[1].think_offset).is_not_equal(controllers[0].think_offset)
	var one: Array[AiController] = Smoke.controllers_of(1, Smoke.FLATS, NORMAL)
	var two: Array[AiController] = Smoke.controllers_of(2, Smoke.FLATS, NORMAL)
	assert_array(Array(two[0].rng.state())).is_not_equal(Array(one[0].rng.state()))


func test_a_level_picks_the_difficulty_and_dummy_picks_the_dummy() -> void:
	var easy_hard: Array[String] = ["easy", "hard"]
	var hard_easy: Array[String] = ["hard", "easy"]
	var easy: OpponentAi = Smoke.controllers_of(1, Smoke.FLATS, easy_hard)[0] as OpponentAi
	var hard: OpponentAi = Smoke.controllers_of(1, Smoke.FLATS, hard_easy)[0] as OpponentAi
	assert_object(easy).is_not_null()
	assert_str(String(easy.level_id)).is_equal("easy")
	assert_str(String(hard.level_id)).is_equal("hard")
	assert_int(easy.tier).is_not_equal(hard.tier)
	var dummy_normal: Array[String] = ["dummy", "normal"]
	var mixed: Array[AiController] = Smoke.controllers_of(1, Smoke.FLATS, dummy_normal)
	assert_str((mixed[0].get_script() as Script).get_global_name()).is_equal("DummyAi")
	assert_str((mixed[1].get_script() as Script).get_global_name()).is_equal("OpponentAi")
	assert_str(Smoke.def_path("renew", "dummy")).is_equal("res://data/ai/dummy_renew.tres")
	assert_str(Smoke.def_path("renew", "hard")).is_equal("res://data/ai/opponent_renew.tres")


func test_the_cap_ends_a_running_match_as_a_timeout() -> void:
	var record: Dictionary = Smoke.play(2, 45, "derrick", NORMAL)
	(
		assert_array([record["ticks"], record["match_end_tick"], record["winner"], record["end"]])
		. is_equal([45, 0, 0, "timeout"])
	)
	assert_str(record["scenario"]).is_equal(Smoke.FLATS)
	for kind: String in Smoke.KINDS:
		var other: Dictionary = Smoke.play(1, 15, kind, NORMAL)
		assert_str(other["scenario"]).is_equal(Smoke.scenario_path(kind, 1))
		assert_int(other["ticks"]).is_equal(15)
	# A timeout is no failure.
	var records: Array[Dictionary] = [record]
	assert_array(Array(Smoke.failures(records))).is_empty()
	assert_str(Smoke.summary(records, 45, "gdscript", Smoke.failures(records))).is_equal(
		(
			"run-sim-smoke: OK, 1 matches of at most 45 ticks, impl gdscript, 1 timeouts, "
			+ "no dropped commands"
		)
	)


func test_a_match_that_ends_is_a_victory_or_a_draw() -> void:
	var path: String = Smoke.FLATS
	var world: World = Smoke.world_of(1, path)
	var loop: MatchLoop = Smoke.loop_of(world, 1, path)
	for row: int in world.unit_count():
		if world.owner[row] == 2 and world.type_foot_w[world.type_index[row]] > 0:
			world.hp[row] = 0
	var counter: SmokeCount = SmokeCount.create(2)
	counter.start(world)
	Smoke.run(world, loop, Smoke.controllers_of(1, path, NORMAL), 100, counter)
	assert_int(world.match_end_tick).is_greater(0)
	assert_int(world.tick).is_equal(world.match_end_tick)
	assert_int(world.winner).is_equal(1)
	var seats: Array[Dictionary] = Smoke.seats_of(path, NORMAL)
	var controllers: Array[AiController] = Smoke.controllers_of(1, path, NORMAL)
	var record: Dictionary = Smoke.record_of(world, 1, path, seats, controllers, counter)
	(
		assert_array([record["ticks"], record["match_end_tick"], record["winner"], record["end"]])
		. is_equal([world.tick, world.match_end_tick, 1, "victory"])
	)
	assert_int(record["players"][1]["defeated_tick"]).is_greater(0)
	assert_bool(Smoke.line(record, 1, 1).contains("victory, winner 1, hash")).is_true()
	# The losses of the dead buildings were counted from the events.
	(
		assert_int(
			record["players"][1]["lost"].values().reduce(
				func(a: int, b: int) -> int: return a + b, 0
			)
		)
		. is_greater(0)
	)
	# An end with no winner is a draw.
	world.winner = 0
	assert_str(Smoke.end_of(world)).is_equal("draw")
	world.match_end_tick = 0
	assert_str(Smoke.end_of(world)).is_equal("timeout")


func test_auto_picks_native_when_the_library_loads_and_records_it() -> void:
	var native: bool = ClassDB.class_exists(&"SimKernels")
	assert_str(Smoke.impl_name()).is_equal("native" if native else "gdscript")
	assert_array(Smoke.impl_problems()).is_empty()
	var world: World = Smoke.world_of(1, Smoke.FLATS)
	assert_array(Smoke.attach_impl(world)).is_empty()
	assert_bool(world.kernels != null).is_equal(native)
	var report: Dictionary = Smoke.report(_records, 2, TICKS)
	assert_str(report["impl"]).is_equal(Smoke.impl_name())
	assert_bool(["native", "gdscript"].has(report["impl"])).is_true()


func test_the_counting_changes_no_state_hash() -> void:
	assert_str(_dummy_record["state_hash"]).is_equal(_uncounted_hash)
	# The dummies build and harvest, so the counts are not trivially empty.
	var first: Dictionary = _dummy_record["players"][0]
	assert_int(first["structures"].size()).is_greater(0)
	assert_int(first["free"].size()).is_greater(0)
	assert_int(first["commands"]).is_greater(0)


func test_the_counting_reads_spawns_and_free_units_from_events() -> void:
	var world: World = Smoke.world_of(1, Smoke.FLATS)
	var counter: SmokeCount = SmokeCount.create(2)
	counter.start(world)
	# The scenario's rows are free; nothing else is counted at tick 0.
	assert_int(counter.gifts[1]["headquarters"]).is_equal(1)
	assert_int(counter.gifts[2]["renew_hq"]).is_equal(1)
	assert_array(counter.produced[1].keys()).is_empty()
	var refinery: int = world.type_ids.find(&"refinery")
	var harvester: int = world.type_ids.find(&"harvester")
	var rifle: int = world.type_ids.find(&"rifle_squad")
	var turret: int = world.type_ids.find(&"defence_turret")
	# Tick 1: a refinery is placed, its free harvester comes, a second harvester and a rifle squad
	# are produced, an unrelated building is placed.
	world.tick = 1
	world.events = _events(
		[
			_spawned(901, refinery, 1),
			_spawned(902, harvester, 1),
			_spawned(903, harvester, 1),
			_spawned(904, rifle, 1),
			_spawned(905, turret, 2),
		]
	)
	counter.after_step(world)
	assert_dict(counter.structures[1]).is_equal({"refinery": 1})
	assert_dict(counter.structures[2]).is_equal({"defence_turret": 1})
	assert_int(counter.gifts[1]["harvester"]).is_equal(1)
	assert_dict(counter.produced[1]).is_equal({"harvester": 1, "rifle_squad": 1})
	# Tick 2: a harvester alone is produced (the refinery's gift was owed in tick 1 only).
	world.tick = 2
	world.events = _events([_spawned(906, harvester, 1)])
	counter.after_step(world)
	assert_dict(counter.produced[1]).is_equal({"harvester": 2, "rifle_squad": 1})
	assert_int(counter.gifts[1]["harvester"]).is_equal(1)
	# Spent is produced times the type's cost.
	var counts: Dictionary = counter.player_counts(world, 1)
	assert_dict(counts["spent"]).is_equal(
		{"harvester": 2 * world.type_cost[harvester], "rifle_squad": world.type_cost[rifle]}
	)
	assert_array(counts.keys()).contains_exactly_in_any_order(
		["produced", "free", "lost", "kills", "spent", "structures"]
	)


func test_the_counting_credits_kills_to_the_last_shooter_and_the_strike() -> void:
	var world: World = Smoke.world_of(1, Smoke.FLATS)
	var counter: SmokeCount = SmokeCount.create(2)
	counter.start(world)
	var rifle: int = world.type_ids.find(&"rifle_squad")
	var tank: int = world.type_ids.find(&"light_tank")
	var turret: int = world.type_ids.find(&"defence_turret")
	var strike: int = world.type_ids.find(&"fossil_strike")
	world.tick = 1
	world.events = _events(
		[
			_spawned(11, rifle, 1),
			_spawned(12, tank, 1),
			_spawned(21, rifle, 2),
			_spawned(22, rifle, 2),
			_spawned(23, rifle, 2),
			_spawned(24, turret, 1),
			_spawned(25, strike, 1),
		]
	)
	counter.after_step(world)
	# Tick 2: the rifle (11) shoots 21, then the tank (12) shoots 21; 21 dies: the tank's kill. The
	# turret (24) shoots 22 and a shell of 11 is still in flight at 23.
	world.tick = 2
	world.events = _events(
		[
			_record(World.Event.SHOT, 11, 0, 0, 21),
			_record(World.Event.SHOT, 12, 0, 0, 21),
			_record(World.Event.SHOT, 24, 0, 0, 22),
			_record(World.Event.SHOT, 11, 0, 0, 23),
			_record(World.Event.DIED, 21, 0, 0, rifle, 2),
		]
	)
	counter.after_step(world)
	assert_dict(counter.kills[1]).is_equal({"light_tank": 1})
	assert_dict(counter.lost[2]).is_equal({"rifle_squad": 1})
	# Tick 3: 22 dies with no shot this tick: its last shooter was the turret; 23 too: the rifle's.
	world.tick = 3
	world.events = _events(
		[
			_record(World.Event.DIED, 22, 0, 0, rifle, 2),
			_record(World.Event.DIED, 23, 0, 0, rifle, 2),
		]
	)
	counter.after_step(world)
	assert_dict(counter.kills[1]).is_equal({"light_tank": 1, "defence_turret": 1, "rifle_squad": 1})
	assert_dict(counter.lost[2]).is_equal({"rifle_squad": 3})
	# A death nobody shot at is a loss and no kill; a cancelled site is neither.
	world.tick = 4
	world.events = _events(
		[
			_spawned(31, rifle, 2),
			_spawned(32, turret, 2),
			_record(World.Event.DIED, 31, 0, 0, rifle, 2),
			_record(World.Event.DIED, 32, 0, 0, turret, 2, 1),
		]
	)
	counter.after_step(world)
	assert_dict(counter.lost[2]).is_equal({"rifle_squad": 4})
	assert_int(_total(counter.kills[1])).is_equal(3)
	# A rupture lands in tick 8 (the STRIKE record names the landing tick): a row that dies then
	# with no shot at it is the strike building's kill; one that was shot that tick is the shooter's.
	world.tick = 5
	world.events = _events(
		[
			_spawned(41, rifle, 2),
			_spawned(42, rifle, 2),
			_spawned(43, rifle, 1),
			_record(World.Event.STRIKE, 25, 0, 0, 1, 1, 8),
		]
	)
	counter.after_step(world)
	world.tick = 8
	world.events = _events(
		[
			_record(World.Event.SHOT, 11, 0, 0, 42),
			_record(World.Event.DIED, 41, 0, 0, rifle, 2),
			_record(World.Event.DIED, 42, 0, 0, rifle, 2),
			_record(World.Event.DIED, 43, 0, 0, rifle, 1),
		]
	)
	counter.after_step(world)
	assert_dict(counter.kills[1]).is_equal(
		{"light_tank": 1, "defence_turret": 1, "rifle_squad": 2, "fossil_strike": 1}
	)
	# The strike's own player's row that dies then is a loss and no kill.
	assert_dict(counter.lost[1]).is_equal({"rifle_squad": 1})


func test_flow_full_ticks_count_the_steps_after_which_every_slot_is_referenced() -> void:
	var world: World = Smoke.world_of(1, Smoke.FLATS)
	var counter: SmokeCount = SmokeCount.create(2)
	world.events = PackedInt32Array()
	counter.after_step(world)
	assert_int(world.flow.ref_count.size()).is_equal(8)
	assert_int(counter.flow_full_ticks).is_equal(0)
	world.flow.ref_count.fill(1)
	counter.after_step(world)
	counter.after_step(world)
	assert_int(counter.flow_full_ticks).is_equal(2)
	world.flow.ref_count[3] = 0
	counter.after_step(world)
	assert_int(counter.flow_full_ticks).is_equal(2)


func test_the_report_has_schema_2_and_keeps_every_schema_1_key() -> void:
	var report: Dictionary = Smoke.report(_records, 2, TICKS, 1, NORMAL, "cross")
	assert_array(_sorted_keys(report)).is_equal(REPORT_KEYS)
	for key: String in SCHEMA_1_REPORT_KEYS:
		assert_bool(report.has(key)).is_true()
	# The top-level `scenario` moved into each match.
	assert_bool(report.has("scenario")).is_false()
	assert_array([report["schema"], report["status"], report["matches_requested"]]).is_equal(
		[2, "ok", 2]
	)
	assert_array([report["ticks_per_match"], report["seed_start"], report["scenarios"]]).is_equal(
		[TICKS, 1, "cross"]
	)
	assert_array(report["levels"]).is_equal(["normal", "normal"])
	assert_str(report["commit"]).is_equal(
		"local" if OS.get_environment("GITHUB_SHA").is_empty() else OS.get_environment("GITHUB_SHA")
	)
	var matches: Array = report["matches"]
	assert_int(matches.size()).is_equal(2)
	for record: Dictionary in matches:
		assert_array(_sorted_keys(record)).is_equal(MATCH_KEYS)
		for key: String in SCHEMA_1_MATCH_KEYS:
			assert_bool(record.has(key)).is_true()
		assert_str(record["scenario"]).is_equal(Smoke.FLATS)
		assert_bool(String(record["state_hash"]).length() == 16).is_true()
		assert_bool(String(record["state_hash"]).is_valid_hex_number()).is_true()
		assert_int(record["players"].size()).is_equal(2)
		for player: Dictionary in record["players"]:
			assert_array(_sorted_keys(player)).is_equal(PLAYER_KEYS)
			for key: String in SCHEMA_1_PLAYER_KEYS:
				assert_bool(player.has(key)).is_true()
	var first: Dictionary = matches[0]["players"][0]
	assert_array([first["faction"], first["seat"], first["ai"], first["level"]]).is_equal(
		["fossil", "top", "opponent_fossil", "normal"]
	)


func test_every_number_in_the_report_is_an_int() -> void:
	var bad: Array[String] = []
	var both: Array[Dictionary] = [_records[0], _dummy_record]
	_find_floats(Smoke.report(both, 2, TICKS), "report", bad)
	assert_array(bad).is_empty()
	assert_bool(Smoke.report_text(Smoke.report(_records, 2, TICKS)).contains(".0")).is_false()


func test_the_controllers_counters_reach_the_player_entry() -> void:
	var path: String = Smoke.FLATS
	var world: World = Smoke.world_of(1, path)
	var counter: SmokeCount = SmokeCount.create(2)
	var controllers: Array[AiController] = Smoke.controllers_of(1, path, NORMAL)
	controllers[1].waves = 3
	controllers[1].retreats = 2
	controllers[1].scouts = 5
	controllers[1].strikes = 1
	controllers[1].commands = 77
	controllers[1].work_max = 4
	var record: Dictionary = Smoke.record_of(
		world, 1, path, Smoke.seats_of(path, NORMAL), controllers, counter
	)
	var second: Dictionary = record["players"][1]
	(
		assert_array(
			[
				second["waves"],
				second["retreats"],
				second["scouts"],
				second["strikes"],
				second["commands"],
				second["think_work_max"]
			]
		)
		. is_equal([3, 2, 5, 1, 77, 4])
	)
	assert_int(record["players"][0]["waves"]).is_equal(0)
	# A dummy fills `commands` only.
	assert_int(_dummy_record["players"][0]["commands"]).is_greater(0)
	(
		assert_array(
			[
				_dummy_record["players"][0]["waves"],
				_dummy_record["players"][0]["scouts"],
				_dummy_record["players"][0]["think_work_max"]
			]
		)
		. is_equal([0, 0, 0])
	)


func test_the_report_file_holds_the_report_text() -> void:
	var report: Dictionary = Smoke.report(_records, 2, TICKS)
	var folder: DirAccess = DirAccess.create_temp("smoke_report_")
	var path: String = folder.get_current_dir().path_join("deep/report.json")
	assert_int(DirAccess.make_dir_recursive_absolute(path.get_base_dir())).is_equal(OK)
	assert_bool(Smoke.write_report(path, report)).is_true()
	var text: String = FileAccess.get_file_as_string(path)
	assert_str(text).is_equal(Smoke.report_text(report))
	assert_bool(text.ends_with("}\n")).is_true()
	var parsed: Dictionary = JSON.parse_string(text)
	assert_array(_sorted_keys(parsed)).is_equal(REPORT_KEYS)
	assert_str(parsed["matches"][1]["state_hash"]).is_equal(_records[1]["state_hash"])
	# A path in a folder that does not exist cannot be opened.
	var missing: String = folder.get_current_dir().path_join("none/r.json")
	assert_bool(Smoke.write_report(missing, report)).is_false()


func test_a_match_line_names_the_seed_the_end_the_hash_and_both_players() -> void:
	var record: Dictionary = _records[0]
	var line: String = Smoke.line(record, 1, 3)
	var head: String = (
		"run-sim-smoke: match 1 of 3: seed 1, skirmish_kestrel_flats, 900 ticks, "
		+ "timeout, winner none, hash %s, "
	)
	(
		assert_bool(line.begins_with((head + "dropped 0, flow full 0") % record["state_hash"]))
		. is_true()
	)
	assert_bool(line.contains("; player 1 opponent_fossil normal: ")).is_true()
	assert_bool(line.contains("; player 2 opponent_renew normal: ")).is_true()


func test_a_dropped_command_fails_the_run_and_the_report() -> void:
	var broken: Dictionary = _records[1].duplicate()
	broken["dropped_commands"] = 2
	broken["seed"] = 2
	var records: Array[Dictionary] = [_records[0], broken]
	var failures: PackedStringArray = Smoke.failures(records)
	assert_array(Array(failures)).is_equal(["seed 2: dropped commands 2"])
	assert_str(Smoke.report(records, 2, TICKS)["status"]).is_equal("failed")
	assert_str(Smoke.summary(records, TICKS, "gdscript", failures)).is_equal(
		"run-sim-smoke: FAILED, seed 2: dropped commands 2"
	)


## One 8-int record of `events`: kind, then the seven ints after it.
func _record(
	kind: int, a: int = 0, b: int = 0, c: int = 0, d: int = 0, e: int = 0, f: int = 0, g: int = 0
) -> PackedInt32Array:
	return PackedInt32Array([kind, a, b, c, d, e, f, g])


func _spawned(id: int, type: int, player: int) -> PackedInt32Array:
	return _record(World.Event.SPAWNED, id, 0, 0, type, player)


func _events(records: Array[PackedInt32Array]) -> PackedInt32Array:
	var events: PackedInt32Array = PackedInt32Array()
	for entry: PackedInt32Array in records:
		events.append_array(entry)
	return events


func _total(counts: Dictionary) -> int:
	var total: int = 0
	for key: String in counts:
		total += int(counts[key])
	return total


func _find_floats(value: Variant, path: String, found: Array[String]) -> void:
	if value is float:
		found.append(path)
	elif value is Dictionary:
		for key: Variant in value:
			_find_floats(value[key], "%s.%s" % [path, key], found)
	elif value is Array:
		for index: int in value.size():
			_find_floats(value[index], "%s[%d]" % [path, index], found)


## The keys of `data`, sorted.
func _sorted_keys(data: Dictionary) -> Array[String]:
	var keys: Array[String] = []
	for key: String in data:
		keys.append(key)
	keys.sort()
	return keys
