extends GdUnitTestSuite
## AI determinism (plan row P188, ADR 0031 section 7, ADR 0030 section 5): two opponents play the
## same short match from one seed, twice on the implementation AUTO picks and once on the GDScript
## twin, and the three agree on the Commands, on the state hash at every checkpoint, on the record
## and on what each AI drew and remembers (so a random number that does not come from the AI's own
## stream shows). The log of the first replays without any AI to the same checkpoints. A fourth
## case seats an `OpponentAi` on player 1 of `dev_strikes.tres`, which fires its Deep Bore, drops
## nothing, and whose log replays on the GDScript twin. Three AI matches of 2,700 ticks and one of
## 900 in all; each prints its `flow_full_ticks` (ADR 0030 section 4).
##
## The matches are played by `tests/smoke/smoke_run.gd`, the loop of `MatchRunner` without the
## Node, so this suite and the smoke run cannot drift. No clock is read: the `determinism-arm64`
## job runs this suite too (plan exception 21). On arm64 the native library is compared with the
## GDScript twin, which is the same code on every machine, so x86_64 and arm64 agree through it.
## No case asserts a winner; the 2,700-tick matches are cut by the tick cap and must still run.
## The Dusk Array is not fired here: the fossil AI fires only its own strike type and the Array
## needs a wave in the field (`test_ai_strikes_dusk.gd` covers it on a hand-built World).

const Smoke: GDScript = preload("res://tests/smoke/smoke_run.gd")
const SmokeCount: GDScript = preload("res://tests/smoke/smoke_count.gd")
const Impls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const HashReport: GDScript = preload("res://tests/sim/support/hash_report.gd")
const Rig: GDScript = preload("res://tests/ai/support/opponent_rig.gd")
const AiRig: GDScript = preload("res://tests/ai/support/ai_rig.gd")

const SEED: int = 1
const TICKS: int = 2700
const LEVELS: Array[String] = ["normal", "hard"]
const STRIKE_PATH: String = "res://data/scenarios/dev_strikes.tres"
const STRIKE_TICKS: int = 900
## The strike case's own numbers, so that a tuning row cannot move the shot: the least value a
## shot must hit (the real one is P181's policy) is the floor, and the Deep Bore starts charged.
const STRIKE_MIN_VALUE: int = 1

var _runs: Array[Dictionary] = []


func before() -> void:
	_runs = [_play(""), _play(""), _play(Smoke.IMPL_GDSCRIPT)]
	for at: int in _runs.size():
		_watch(
			_runs[at]["impl"],
			"normal-hard",
			TICKS,
			str(at + 1),
			_runs[at]["counter"].flow_full_ticks
		)


func test_the_library_ran_the_first_two_matches_and_the_twin_the_third() -> void:
	var native: bool = Smoke.impl_name() == Smoke.IMPL_NATIVE
	var mask: int = Impls.expected_mask() if native else 0
	for at: int in _runs.size():
		var world: World = _runs[at]["world"]
		var twin: bool = at == 2
		var label: String = "run %d (%s)" % [at + 1, _runs[at]["impl"]]
		assert_array(_runs[at]["problems"]).override_failure_message(label).is_empty()
		assert_bool(Impls.is_native(world, SimProbe.Phase.FLOW)).is_equal(native and not twin)
		assert_int(world.native_phases).override_failure_message(label).is_equal(
			0 if twin else mask
		)


func test_the_same_seed_twice_gives_the_same_commands_hashes_and_ai_state() -> void:
	var a: Replay = _runs[0]["loop"].replay
	var b: Replay = _runs[1]["loop"].replay
	assert_int(a.checkpoint_hashes.size()).is_equal(TICKS / Replay.CHECKPOINT_PERIOD)
	assert_array(b.checkpoint_ticks).is_equal(a.checkpoint_ticks)
	(
		assert_array(b.checkpoint_hashes)
		. override_failure_message(_difference(_runs[0], _runs[1]))
		. is_equal(a.checkpoint_hashes)
	)
	assert_array(b.commands).is_equal(a.commands)
	assert_dict(_record(_runs[1])).is_equal(_record(_runs[0]))
	assert_int(b.final_hash).is_equal(a.final_hash)
	_assert_same_ai_state(_runs[1], _runs[0], "run 2 against run 1")


func test_each_ai_drew_from_its_own_stream_and_both_players_acted() -> void:
	var replay: Replay = _runs[0]["loop"].replay
	var by_player: Dictionary[int, int] = {}
	for command: Command in _commands(replay):
		by_player[command.player_id] = by_player.get(command.player_id, 0) + 1
	assert_int(by_player.get(1, 0)).is_greater(5)
	assert_int(by_player.get(2, 0)).is_greater(5)
	var controllers: Array[AiController] = _runs[0]["controllers"]
	for at: int in controllers.size():
		var fresh: DetRandom = DetRandom.create(SEED, DetRandom.STREAM_AI_BASE + at + 1)
		(
			assert_array(controllers[at].rng.state())
			. override_failure_message("player %d drew nothing" % (at + 1))
			. is_not_equal(fresh.state())
		)
	for played: Dictionary in _runs:
		assert_int(played["world"].dropped_commands).is_equal(0)
		assert_int(played["world"].tick).is_equal(TICKS)
		assert_int(played["world"].match_end_tick).is_equal(0)


func test_the_log_replays_without_any_ai_to_the_same_checkpoints() -> void:
	var replay: Replay = _runs[0]["loop"].replay
	var world: World = Smoke.world_of(SEED, _runs[0]["path"])
	assert_array(Smoke.attach_impl(world)).is_empty()
	var result: int = Replay.play(replay, world, TICKS)
	(
		assert_int(result)
		. override_failure_message(
			(
				"Replay.play returned %d (-1 matched, a tick is the first checkpoint that differs)"
				% result
			)
		)
		. is_equal(Replay.PLAY_MATCHED)
	)
	assert_int(world.tick).is_equal(TICKS)
	assert_int(world.state_hash()).is_equal(replay.final_hash)
	assert_int(world.dropped_commands).is_equal(0)


func test_the_gdscript_twin_plays_the_match_to_the_same_hashes_and_ai_state() -> void:
	var a: Replay = _runs[0]["loop"].replay
	var b: Replay = _runs[2]["loop"].replay
	(
		assert_array(b.checkpoint_hashes)
		. override_failure_message(_difference(_runs[0], _runs[2]))
		. is_equal(a.checkpoint_hashes)
	)
	assert_array(b.commands).is_equal(a.commands)
	assert_int(b.final_hash).is_equal(a.final_hash)
	assert_dict(_record(_runs[2])).is_equal(_record(_runs[0]))
	_assert_same_ai_state(_runs[2], _runs[0], "the twin against run 1")


func test_an_opponent_on_player_one_fires_the_deep_bore_and_the_log_replays_on_the_twin() -> void:
	var world: World = _strike_world()
	var loop: MatchLoop = Smoke.loop_of(world, SEED, STRIKE_PATH)
	var counter: SmokeCount = SmokeCount.new(2)
	counter.start(world)
	# A copy with the suite's own threshold: the shipped one is P181's policy and a tuning row may
	# move it past the value the enemy base holds.
	var def: OpponentDef = Rig.def_of("fossil").duplicate(true) as OpponentDef
	def.strike_min_value = STRIKE_MIN_VALUE
	var stream: DetRandom = DetRandom.create(SEED, DetRandom.STREAM_AI_BASE + 1)
	var ai: AiController = AiFactory.create(def, Rig.level_of("normal"), 1, stream)
	var controllers: Array[AiController] = [ai]
	var bore_id: int = world.unit_id[AiRig.row_of(world, 1, "fossil_strike")]
	Smoke.run(world, loop, controllers, STRIKE_TICKS, counter)
	loop.replay.finish(world)
	_watch(Smoke.impl_name(), "dev_strikes", STRIKE_TICKS, "strike", counter.flow_full_ticks)
	assert_int(world.tick).is_equal(STRIKE_TICKS)
	assert_int(world.dropped_commands).is_equal(0)
	var shots: Array[Command] = []
	for command: Command in _commands(loop.replay):
		if command.type == Command.Type.SUPERWEAPON:
			shots.append(command)
	# Exactly one: the sim drops a second SUPERWEAPON while the player's rupture is pending, and
	# the Deep Bore needs its whole charge again after the first.
	assert_int(shots.size()).is_equal(1)
	if shots.is_empty():
		return
	assert_int(shots[0].player_id).is_equal(1)
	assert_int(shots[0].target_id).is_equal(bore_id)
	# The sim took it: the Deep Bore charges again from the tick it fired.
	assert_int(world.ready_tick[world.index_of(bore_id)]).is_greater(shots[0].tick)
	var replayed: World = _strike_world()
	assert_array(Smoke.attach_impl(replayed, Smoke.IMPL_GDSCRIPT)).is_empty()
	assert_bool(Impls.is_native(replayed, SimProbe.Phase.FLOW)).is_false()
	var result: int = Replay.play(loop.replay, replayed, STRIKE_TICKS)
	(
		assert_int(result)
		. override_failure_message("Replay.play on the twin returned %d (-1 matched)" % result)
		. is_equal(Replay.PLAY_MATCHED)
	)
	assert_int(replayed.state_hash()).is_equal(loop.replay.final_hash)


## The World of `dev_strikes.tres` on the implementation AUTO picks, with the Deep Bore's charge
## aged past its whole charge, so that a `charge_ticks` change cannot move the shot.
func _strike_world() -> World:
	var world: World = Smoke.world_of(SEED, STRIKE_PATH)
	assert_array(Smoke.attach_impl(world)).is_empty()
	var bore: int = AiRig.row_of(world, 1, "fossil_strike")
	assert_int(bore).is_greater_equal(0)
	if bore >= 0:
		Strike.age_charge(world, bore, world.type_charge_ticks[world.type_index[bore]] + 1)
	return world


## Plays the match of `impl` ("" for AUTO) on the cross scenario of `SEED` for `TICKS` ticks and
## returns what the cases read: the world, the loop (its replay finished), the counter, the
## controllers and seats of the record, the problems of attaching the implementation and `impl`
## as it ran.
func _play(impl: String) -> Dictionary:
	var played: Dictionary = Smoke.start(SEED, Smoke.KIND_CROSS, LEVELS)
	played["problems"] = Smoke.attach_impl(played["world"], impl)
	played["impl"] = impl if not impl.is_empty() else Smoke.impl_name()
	var controllers: Array[AiController] = played["controllers"]
	Smoke.run(played["world"], played["loop"], controllers, TICKS, played["counter"])
	played["loop"].replay.finish(played["world"])
	return played


func _record(played: Dictionary) -> Dictionary:
	var seats: Array[Dictionary] = played["seats"]
	var controllers: Array[AiController] = played["controllers"]
	return Smoke.record_of(
		played["world"], SEED, played["path"], seats, controllers, played["counter"]
	)


## Each AI of `played` has the stream state and every script variable of its memory that the
## AI of `reference` has.
func _assert_same_ai_state(played: Dictionary, reference: Dictionary, label: String) -> void:
	var controllers: Array[AiController] = played["controllers"]
	var references: Array[AiController] = reference["controllers"]
	for at: int in controllers.size():
		var who: String = "%s, player %d" % [label, at + 1]
		(
			assert_array(controllers[at].rng.state())
			. override_failure_message(who + ": the stream state differs")
			. is_equal(references[at].rng.state())
		)
		var memory: AiMemory = (controllers[at] as OpponentAi).memory
		var other: AiMemory = (references[at] as OpponentAi).memory
		for property: Dictionary in memory.get_property_list():
			if (int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
				continue
			var field: String = String(property["name"])
			(
				assert_bool(memory.get(field) == other.get(field))
				. override_failure_message("%s: memory.%s differs" % [who, field])
				. is_true()
			)


## The sections of the state hash that differ at the end, and the first checkpoint tick whose
## hash differs between the two plays (a message for a failing comparison).
func _difference(a: Dictionary, b: Dictionary) -> String:
	var first: Replay = a["loop"].replay
	var second: Replay = b["loop"].replay
	var tick: int = -1
	for at: int in mini(first.checkpoint_hashes.size(), second.checkpoint_hashes.size()):
		if first.checkpoint_hashes[at] != second.checkpoint_hashes[at]:
			tick = first.checkpoint_ticks[at]
			break
	return (
		"first differing checkpoint: tick %d; %s"
		% [tick, HashReport.mismatch(a["world"], b["world"])]
	)


## The Commands of `replay`, in the order they were recorded.
func _commands(replay: Replay) -> Array[Command]:
	var found: Array[Command] = []
	var at: int = 0
	while at < replay.commands.size():
		var command: Command = Command.new()
		at = Command.decode(replay.commands, at, command)
		assert_int(at).is_greater(0)
		if at <= 0:
			break
		found.append(command)
	return found


## A report-only line (no assertion reads it); the values hold no spaces.
func _watch(impl: String, match_name: String, ticks: int, run: String, full_ticks: int) -> void:
	print(
		(
			"WATCH ai flow impl=%s match=%s seed=%d ticks=%d run=%s full_ticks=%d"
			% [impl, match_name, SEED, ticks, run, full_ticks]
		)
	)
