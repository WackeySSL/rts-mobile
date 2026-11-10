extends GdUnitTestSuite
## The per-player income percent (plan row P173, ADR 0030 section 8): `World.income_percent` scales
## what a tanker's unload pays into the credits, stays out of the state hash and inside defs_hash,
## and travels in the replay (`Replay.FORMAT` 2). No literal pins a defs_hash value: the tests
## compare values with each other.

const Worlds: GDScript = preload("res://tests/sim/support/harvest_worlds.gd")
const MatchScript: GDScript = preload("res://tests/sim/support/match_script.gd")
const Smoke: GDScript = preload("res://tests/smoke/smoke_run.gd")

const UNLOAD: int = World.HarvestMode.UNLOAD
const DOCK_AT: Vector2i = Vector2i(3500, 5500)
## The raised income of the tests: 120 percent.
const RAISED: int = 120


## 12 x 16 tiles with a refinery (player 1, id 1) whose dock is (3 500, 5 500).
func _trip_world() -> World:
	var world: World = Worlds.world(Worlds.grass(12, 16, [Vector2i(3, 7)]))
	Worlds.add_refinery(world, 1, 2, 2)
	return world


## The credits an unloading harvester of player 1 with `cargo` adds, tick by tick until it is empty.
func _payments(world: World, cargo: int) -> Array[int]:
	var id: int = Worlds.add_harvester(world, 1, DOCK_AT.x, DOCK_AT.y, UNLOAD, 0, 1, cargo)
	var paid: Array[int] = []
	while Worlds.cargo_of(world, id) > 0:
		var before: int = world.credits[1]
		Worlds.step(world)
		paid.append(world.credits[1] - before)
	return paid


func test_every_player_is_at_100_unless_a_level_says_otherwise() -> void:
	var world: World = _trip_world()
	assert_array(world.income_percent).is_equal([100, 100, 100])
	WorldLoad.set_income(world, 2, RAISED)
	assert_array(world.income_percent).is_equal([100, 100, RAISED])
	world.prepare()  # Keeps what was set, and sizes by player_count.
	assert_array(world.income_percent).is_equal([100, 100, RAISED])
	var early: World = World.new()
	WorldLoad.set_income(early, 2, RAISED)  # Before prepare(): player_count is 0.
	assert_array(early.income_percent).is_equal([100, 100, RAISED])


func test_at_100_the_unload_and_the_state_are_what_they_were() -> void:
	var plain: World = _trip_world()
	var explicit: World = _trip_world()
	WorldLoad.set_income(explicit, 1, WorldLoad.PERCENT)
	assert_int(explicit.state_hash()).is_equal(plain.state_hash())
	assert_array(_payments(plain, 60)).is_equal([25, 25, 10])  # The shipped 25 per ore.
	assert_array(_payments(explicit, 60)).is_equal([25, 25, 10])
	assert_int(explicit.state_hash()).is_equal(plain.state_hash())


func test_at_120_a_crafted_unload_pays_ore_times_value_times_120_over_100() -> void:
	var world: World = _trip_world()
	WorldLoad.set_income(world, 1, RAISED)
	var ore: int = 4
	var cargo: int = ore * world.credits_per_ore
	var start: int = world.credits[1]
	var paid: Array[int] = _payments(world, cargo)
	var per_unload: int = world.credits_per_ore * RAISED / 100
	assert_array(paid).is_equal([per_unload, per_unload, per_unload, per_unload])
	assert_int(world.credits[1] - start).is_equal(ore * world.credits_per_ore * RAISED / 100)
	# The counted harvest is the ore's value, not the bonus, and player 2 is at 100.
	assert_int(world.stat_harvested[1]).is_equal(cargo)
	var other: World = _trip_world()
	WorldLoad.set_income(other, 1, RAISED)
	var id: int = Worlds.add_harvester(other, 2, DOCK_AT.x, DOCK_AT.y, UNLOAD, 0, 1, 25)
	assert_int(id).is_greater(0)
	var before: int = other.credits[2]
	Worlds.step(other)
	assert_int(other.credits[2] - before).is_equal(other.credits_per_ore)


func test_defs_hash_follows_the_setup_and_the_state_hash_does_not() -> void:
	var base: World = _trip_world()
	var raised: World = _trip_world()
	WorldLoad.set_income(raised, 1, RAISED)
	assert_int(raised.defs_hash()).is_not_equal(base.defs_hash())
	assert_int(raised.state_hash()).is_equal(base.state_hash())
	var other_player: World = _trip_world()
	WorldLoad.set_income(other_player, 2, RAISED)
	assert_int(other_player.defs_hash()).is_not_equal(base.defs_hash())
	assert_int(other_player.defs_hash()).is_not_equal(raised.defs_hash())
	var same: World = _trip_world()
	WorldLoad.set_income(same, 1, RAISED)
	assert_int(same.defs_hash()).is_equal(raised.defs_hash())


func test_a_replay_at_120_replays_and_at_100_reports_defs_differ() -> void:
	var recorded: World = MatchScript.world(7)
	WorldLoad.set_income(recorded, 1, RAISED)
	WorldLoad.set_income(recorded, 2, RAISED)
	var loop: MatchLoop = MatchScript.loop(recorded, 7)
	MatchScript.play(recorded, loop, 90)
	loop.replay.finish(recorded)
	var replay: Replay = Replay.from_bytes(loop.replay.to_bytes())
	assert_object(replay).is_not_null()
	assert_array(replay.income_percent).is_equal([100, RAISED, RAISED])
	var fresh: World = MatchScript.world(7)
	replay.apply_setup(fresh)
	assert_int(Replay.play(replay, fresh, 90)).is_equal(Replay.PLAY_MATCHED)
	assert_int(fresh.state_hash()).is_equal(replay.final_hash)
	var at_100: World = MatchScript.world(7)
	assert_int(Replay.play(replay, at_100, 90)).is_equal(Replay.PLAY_DEFS_DIFFER)
	assert_int(at_100.tick).is_equal(0)


func test_a_format_1_replay_is_refused() -> void:
	var data: Dictionary = bytes_to_var(Replay.begin("", 0, 0).to_bytes())
	assert_object(Replay.from_bytes(var_to_bytes(data))).is_not_null()
	data["format"] = 1
	assert_object(Replay.from_bytes(var_to_bytes(data))).is_null()
	data.erase("income_percent")  # A real format 1 file has no such key.
	assert_object(Replay.from_bytes(var_to_bytes(data))).is_null()


## The balance harness puts each level file's `income_percent` on its seat, before the loop records
## the setup; a dummy seat keeps 100. (The shipped files all say 100 until P183b, so the values are
## read from the files, not pinned.)
func test_the_harness_seats_the_income_percent_of_the_level_files() -> void:
	var easy: AiDifficultyDef = load("res://data/ai/difficulty/easy.tres") as AiDifficultyDef
	var hard: AiDifficultyDef = load("res://data/ai/difficulty/hard.tres") as AiDifficultyDef
	var world: World = Smoke.world_of(1)
	var seats: Array[String] = ["easy", "hard"]
	Smoke.seat_income(world, seats)
	assert_array(world.income_percent).is_equal([100, easy.income_percent, hard.income_percent])
	var dummy: World = Smoke.world_of(1)
	var with_dummy: Array[String] = ["dummy", "hard"]
	Smoke.seat_income(dummy, with_dummy)
	assert_array(dummy.income_percent).is_equal([100, 100, hard.income_percent])
	var loop: MatchLoop = Smoke.loop_of(world, 1)
	assert_array(loop.replay.income_percent).is_equal(world.income_percent)
