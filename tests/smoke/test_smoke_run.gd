extends GdUnitTestSuite
## The match behind scripts/run-sim-smoke.sh (plan row P95, ADR 0020 question 2 = ja): the Derrick
## League's dummy against the Lumen Accord's on Kestrel Flats for 1,800 ticks, from the seeds 1, 2
## and 3 (what `run-sim-smoke.sh --matches 3` plays). Pinned here: a seed played twice gives the
## same record, report text and checkpoint at every 15th tick; three seeds are three matches with
## three final hashes; neither dummy has a Command dropped; the report and its file have the schema
## the script header lists; the loop stops at the tick that ends a match; a dropped Command fails
## the run. The shell script's flags and exit codes are in `test_run_sim_smoke_script.gd`.
##
## The dummies draw nothing from their streams today, so the seeds differ in the World's own stream
## (spawn jitter and the hash of its state) and not yet in what the dummies do; the hashes still
## differ, and a dummy that starts to draw from its stream changes the matches, not the checks.

const Smoke: GDScript = preload("res://tests/smoke/smoke_run.gd")
const SEEDS: Array[int] = [1, 2, 3]
## 1,800 ticks hold 120 checkpoints: one every 15th tick from tick 15.
const CHECKPOINTS: int = 120
const REPORT_KEYS: Array[String] = [
	"matches",
	"matches_requested",
	"scenario",
	"schema",
	"status",
	"ticks_per_match",
]
const MATCH_KEYS: Array[String] = [
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
	"credits",
	"defeated_tick",
	"harvested",
	"lost_buildings",
	"lost_units",
	"player",
	"units",
]

## The records of the seeds 1, 2 and 3, in that order.
var _records: Array[Dictionary] = []
## The loops of those matches, and the loop of seed 1 played a second time.
var _loops: Array[MatchLoop] = []
var _again_record: Dictionary = {}
var _again_loop: MatchLoop


func before() -> void:
	for match_seed: int in SEEDS:
		var world: World = Smoke.world_of(match_seed)
		var loop: MatchLoop = Smoke.loop_of(world, match_seed)
		Smoke.run(world, loop, Smoke.controllers_of(match_seed), Smoke.TICKS)
		_records.append(Smoke.record_of(world, match_seed, Smoke.ai_ids()))
		_loops.append(loop)
	var again: World = Smoke.world_of(SEEDS[0])
	_again_loop = Smoke.loop_of(again, SEEDS[0])
	Smoke.run(again, _again_loop, Smoke.controllers_of(SEEDS[0]), Smoke.TICKS)
	_again_record = Smoke.record_of(again, SEEDS[0], Smoke.ai_ids())


func test_a_seed_played_twice_gives_the_same_record_report_and_checkpoints() -> void:
	assert_str(JSON.stringify(_again_record)).is_equal(JSON.stringify(_records[0]))
	var again: Array[Dictionary] = [_again_record]
	var first_run: Array[Dictionary] = [_records[0]]
	assert_str(Smoke.report_text(Smoke.report(again, 1))).is_equal(
		Smoke.report_text(Smoke.report(first_run, 1))
	)
	var first: Replay = _loops[0].replay
	var second: Replay = _again_loop.replay
	assert_int(first.checkpoint_ticks.size()).is_equal(CHECKPOINTS)
	assert_array(Array(first.checkpoint_ticks)).is_equal(Array(second.checkpoint_ticks))
	assert_array(Array(first.checkpoint_hashes)).is_equal(Array(second.checkpoint_hashes))


func test_three_seeds_are_three_matches_with_three_final_hashes() -> void:
	var hashes: Dictionary[String, int] = {}
	for index: int in SEEDS.size():
		assert_int(_records[index]["seed"]).is_equal(SEEDS[index])
		hashes[_records[index]["state_hash"]] = index
	assert_int(hashes.size()).is_equal(SEEDS.size())
	# The checkpoints differ from the first one on: the sim stream is in every hash.
	var first_checkpoint: int = _loops[0].replay.checkpoint_hashes[0]
	assert_int(_loops[1].replay.checkpoint_hashes[0]).is_not_equal(first_checkpoint)


func test_neither_dummy_has_a_command_dropped() -> void:
	for record: Dictionary in _records:
		assert_int(record["dropped_commands"]).is_equal(0)
		assert_int(record["spawn_refused"]).is_equal(0)
	assert_array(Array(Smoke.failures(_records))).is_empty()
	assert_str(Smoke.summary(SEEDS.size(), Smoke.failures(_records))).is_equal(
		"run-sim-smoke: OK, 3 matches of 1800 ticks, no dropped commands"
	)


func test_each_match_plays_its_ticks_and_both_dummies_build_and_harvest() -> void:
	for record: Dictionary in _records:
		assert_array([record["ticks"], record["match_end_tick"], record["winner"]]).is_equal(
			[Smoke.TICKS, 0, 0]
		)
		var ais: Array[String] = []
		for player: Dictionary in record["players"]:
			ais.append(player["ai"])
			assert_int(player["built"]).is_greater(0)
			assert_int(player["harvested"]).is_greater(0)
			assert_int(player["defeated_tick"]).is_equal(0)
		assert_array(ais).is_equal(["dummy_fossil", "dummy_renew"])


func test_the_report_has_the_schema_of_the_script_header() -> void:
	var report: Dictionary = Smoke.report(_records, SEEDS.size())
	assert_array(_sorted_keys(report)).is_equal(REPORT_KEYS)
	assert_array([report["schema"], report["status"], report["matches_requested"]]).is_equal(
		[1, "ok", 3]
	)
	assert_array([report["scenario"], report["ticks_per_match"]]).is_equal(
		["res://data/scenarios/skirmish_kestrel_flats.tres", Smoke.TICKS]
	)
	var matches: Array = report["matches"]
	assert_int(matches.size()).is_equal(SEEDS.size())
	for record: Dictionary in matches:
		assert_array(_sorted_keys(record)).is_equal(MATCH_KEYS)
		assert_bool(String(record["state_hash"]).length() == 16).is_true()
		assert_bool(String(record["state_hash"]).is_valid_hex_number()).is_true()
		assert_int(record["players"].size()).is_equal(2)
		for player: Dictionary in record["players"]:
			assert_array(_sorted_keys(player)).is_equal(PLAYER_KEYS)


func test_the_report_file_holds_the_report_text() -> void:
	var report: Dictionary = Smoke.report(_records, SEEDS.size())
	var folder: DirAccess = DirAccess.create_temp("smoke_report_")
	var path: String = folder.get_current_dir().path_join("deep/report.json")
	assert_int(DirAccess.make_dir_recursive_absolute(path.get_base_dir())).is_equal(OK)
	assert_bool(Smoke.write_report(path, report)).is_true()
	var text: String = FileAccess.get_file_as_string(path)
	assert_str(text).is_equal(Smoke.report_text(report))
	assert_bool(text.ends_with("}\n")).is_true()
	var parsed: Dictionary = JSON.parse_string(text)
	assert_array(_sorted_keys(parsed)).is_equal(REPORT_KEYS)
	# JSON has one number type: a parsed int is a float.
	assert_int(int(parsed["matches"][2]["seed"])).is_equal(3)
	assert_str(parsed["matches"][1]["state_hash"]).is_equal(_records[1]["state_hash"])
	# A path in a folder that does not exist cannot be opened.
	var missing: String = folder.get_current_dir().path_join("none/r.json")
	assert_bool(Smoke.write_report(missing, report)).is_false()


func test_a_match_line_names_the_seed_the_winner_the_hash_and_both_players() -> void:
	var record: Dictionary = _records[0]
	var first: Dictionary = record["players"][0]
	var line: String = Smoke.line(record, 1, 3)
	var head: String = "run-sim-smoke: match 1 of 3: seed 1, 1800 ticks, winner none, hash %s, "
	assert_bool(line.begins_with((head + "dropped 0") % record["state_hash"])).is_true()
	assert_bool(line.contains("; player 1 dummy_fossil: %d units, " % first["units"])).is_true()
	assert_bool(line.contains("; player 2 dummy_renew: ")).is_true()


func test_play_is_the_helpers_run_for_a_given_number_of_ticks() -> void:
	var world: World = Smoke.world_of(2)
	Smoke.run(world, Smoke.loop_of(world, 2), Smoke.controllers_of(2), 45)
	var by_hand: Dictionary = Smoke.record_of(world, 2, Smoke.ai_ids())
	assert_str(JSON.stringify(Smoke.play(2, 45))).is_equal(JSON.stringify(by_hand))
	assert_int(by_hand["ticks"]).is_equal(45)


func test_the_loop_stops_at_the_tick_that_ends_the_match() -> void:
	var world: World = Smoke.world_of(1)
	var loop: MatchLoop = Smoke.loop_of(world, 1)
	for row: int in world.unit_count():
		if world.owner[row] == 2 and world.type_foot_w[world.type_index[row]] > 0:
			world.hp[row] = 0
	Smoke.run(world, loop, Smoke.controllers_of(1), 100)
	assert_int(world.match_end_tick).is_greater(0)
	assert_int(world.tick).is_equal(world.match_end_tick)
	assert_int(world.winner).is_equal(1)
	var record: Dictionary = Smoke.record_of(world, 1, Smoke.ai_ids())
	assert_array([record["ticks"], record["match_end_tick"], record["winner"]]).is_equal(
		[world.tick, world.match_end_tick, 1]
	)
	assert_int(record["players"][1]["defeated_tick"]).is_greater(0)
	assert_bool(Smoke.line(record, 1, 1).contains("winner 1, hash")).is_true()


func test_a_dropped_command_fails_the_run_and_the_report() -> void:
	var broken: Dictionary = _records[1].duplicate()
	broken["dropped_commands"] = 2
	var records: Array[Dictionary] = [_records[0], broken]
	var failures: PackedStringArray = Smoke.failures(records)
	assert_array(Array(failures)).is_equal(["seed 2: dropped commands 2"])
	assert_str(Smoke.report(records, 2)["status"]).is_equal("failed")
	assert_str(Smoke.summary(2, failures)).is_equal(
		"run-sim-smoke: FAILED, seed 2: dropped commands 2"
	)


## The keys of `data`, sorted.
func _sorted_keys(data: Dictionary) -> Array[String]:
	var keys: Array[String] = []
	for key: String in data:
		keys.append(key)
	keys.sort()
	return keys
