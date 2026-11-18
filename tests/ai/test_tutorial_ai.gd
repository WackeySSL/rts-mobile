extends GdUnitTestSuite
## The scripted tutorial opponent (plan row P540, ADR 0044 section 2): steps fire on what its
## `PlayerView` shows, nothing fires on hidden information, the same views give the same Commands
## (two runs and a replay agree), and `AiFactory` builds it from a `TutorialScriptDef`.

const Rig: GDScript = preload("res://tests/ai/support/ai_rig.gd")
const Tut: GDScript = preload("res://tests/ai/support/tutorial_rig.gd")


func test_a_tick_step_queues_its_items_once_it_can() -> void:
	var world: World = Rig.start()
	var loop: MatchLoop = Rig.loop_of(world)
	var ai: TutorialAi = Tut.ai_of(Tut.script_def())
	# No barracks: the QUEUE would be dropped, so nothing is sent and the step stays unfired.
	assert_array(Tut.think(world, ai)).is_empty()
	assert_bool(ai.has_fired(&"train")).is_false()
	Rig.give(world, Tut.PLAYER, "barracks", 31, 26)
	var sent: Array[Command] = Tut.think(world, ai)
	assert_int(sent.size()).is_equal(2)
	for command: Command in sent:
		assert_int(command.type).is_equal(Command.Type.QUEUE)
		assert_int(command.payload[0]).is_equal(Rig.type_of(world, "rifle_squad"))
	assert_bool(ai.has_fired(&"train")).is_true()
	# Fired once: the next think queues nothing more.
	assert_array(Tut.think(world, ai)).is_empty()
	Rig.step(world, loop, sent)
	assert_int(world.dropped_commands).is_equal(0)


func test_an_enemy_near_step_fires_on_a_seen_enemy_and_aims_at_it() -> void:
	var world: World = Tut.start()
	var loop: MatchLoop = Rig.loop_of(world)
	var ai: TutorialAi = Tut.ai_of(Tut.script_def())
	Tut.think(world, ai)
	Rig.settle(world, loop)
	# Nothing of player 1 is near yet: its base is 28 tiles away.
	assert_array(Tut.think(world, ai)).is_empty()
	assert_bool(ai.has_fired(&"wave")).is_false()
	var foe: int = Rig.add_unit_of(world, Tut.FOE, "rifle_squad", 21000, 27500)
	Rig.settle(world, loop)
	var sent: Array[Command] = Tut.think(world, ai)
	assert_int(sent.size()).is_equal(1)
	assert_int(sent[0].type).is_equal(Command.Type.ATTACK_MOVE)
	assert_int(sent[0].unit_ids.size()).is_equal(2)
	var at: Vector2i = _view_pos(world, foe)
	assert_array([sent[0].target_x, sent[0].target_y]).is_equal([at.x, at.y])
	assert_int(ai.fired_tick_of(&"wave")).is_equal(world.tick)


func test_a_step_waits_for_the_step_it_follows_and_its_delay() -> void:
	var world: World = Tut.start()
	var loop: MatchLoop = Rig.loop_of(world)
	var ai: TutorialAi = Tut.ai_of(Tut.script_def())
	Rig.add_unit_of(world, Tut.FOE, "rifle_squad", 21000, 27500)
	Rig.settle(world, loop)
	Tut.think(world, ai)
	var fired: int = ai.fired_tick_of(&"wave")
	assert_int(fired).is_not_equal(TutorialAi.NOT_FIRED)
	assert_bool(ai.has_fired(&"fall_back")).is_false()
	Rig.run(world, loop, [], 29)
	assert_array(Tut.think(world, ai)).is_empty()
	Rig.run(world, loop, [], 1)
	var sent: Array[Command] = Tut.think(world, ai)
	assert_int(sent.size()).is_equal(1)
	assert_int(sent[0].type).is_equal(Command.Type.MOVE)
	# Home: the Headquarters' centre (its top-left tile is (26, 26), 3 x 3).
	assert_array([sent[0].target_x, sent[0].target_y]).is_equal([27500, 27500])
	assert_int(ai.fired_count()).is_equal(3)


func test_nothing_fires_on_an_enemy_the_fog_hides() -> void:
	# Player 1's Headquarters is 28 tiles away: a radius of 40 tiles holds for the World's rows,
	# not for the rows the view shows, so a step that read hidden rows would fire at once.
	var def: TutorialScriptDef = TutorialScriptDef.new()
	def.steps.append(
		Tut.step(
			"far",
			TutorialStepDef.Trigger.ENEMY_NEAR,
			TutorialStepDef.Action.ATTACK_MOVE,
			{"threshold": 1, "trigger_radius_tiles": 40}
		)
	)
	def.steps.append(
		Tut.step(
			"seen",
			TutorialStepDef.Trigger.ENEMY_SEEN,
			TutorialStepDef.Action.ATTACK_MOVE,
			{"threshold": 1}
		)
	)
	def.steps.append(
		Tut.step(
			"foe_hq",
			TutorialStepDef.Trigger.ENEMY_SEEN,
			TutorialStepDef.Action.ATTACK_MOVE,
			{"threshold": 1, "trigger_type": &"headquarters"}
		)
	)
	var world: World = Tut.start()
	var loop: MatchLoop = Rig.loop_of(world)
	var ai: TutorialAi = Tut.ai_of(def)
	Rig.settle(world, loop)
	var view: PlayerView = PlayerView.of(world, Tut.PLAYER)
	assert_int(view.seen_rows.size()).is_equal(0)
	assert_array(Tut.think(world, ai)).is_empty()
	assert_int(ai.fired_count()).is_equal(0)
	# Once the foe's unit is in sight the "seen" steps fire, the type-filtered one still does not.
	Rig.add_unit_of(world, Tut.FOE, "rifle_squad", 21000, 27500)
	Rig.settle(world, loop)
	assert_int(Tut.think(world, ai).size()).is_equal(2)
	assert_array([ai.has_fired(&"far"), ai.has_fired(&"seen"), ai.has_fired(&"foe_hq")]).is_equal(
		[true, true, false]
	)


func test_a_trigger_type_the_roster_lacks_never_holds() -> void:
	var def: TutorialScriptDef = TutorialScriptDef.new()
	def.steps.append(
		Tut.step(
			"ghost",
			TutorialStepDef.Trigger.OWN_AT_LEAST,
			TutorialStepDef.Action.STOP,
			{"threshold": 1, "trigger_type": &"no_such_type"}
		)
	)
	var world: World = Tut.start()
	var ai: TutorialAi = Tut.ai_of(def)
	assert_array(Tut.think(world, ai)).is_empty()
	assert_int(ai.fired_count()).is_equal(0)


func test_credits_and_own_count_triggers_read_the_players_own_state() -> void:
	var def: TutorialScriptDef = TutorialScriptDef.new()
	def.steps.append(
		Tut.step(
			"rich",
			TutorialStepDef.Trigger.CREDITS,
			TutorialStepDef.Action.STOP,
			{"threshold": 100000}
		)
	)
	def.steps.append(
		Tut.step(
			"squads_lost",
			TutorialStepDef.Trigger.OWN_AT_MOST,
			TutorialStepDef.Action.STOP,
			{"threshold": 0, "trigger_type": &"rifle_squad"}
		)
	)
	var world: World = Tut.start()
	var ai: TutorialAi = Tut.ai_of(def)
	assert_array(Tut.think(world, ai)).is_empty()
	assert_int(ai.fired_count()).is_equal(0)


func test_an_order_step_with_no_unit_to_send_waits() -> void:
	var def: TutorialScriptDef = TutorialScriptDef.new()
	def.steps.append(
		Tut.step(
			"tanks",
			TutorialStepDef.Trigger.TICK,
			TutorialStepDef.Action.ATTACK_MOVE,
			{"action_type": &"light_tank", "target": TutorialStepDef.Target.TILE}
		)
	)
	var world: World = Tut.start()
	var ai: TutorialAi = Tut.ai_of(def)
	assert_array(Tut.think(world, ai)).is_empty()
	Rig.add_unit_of(world, Tut.PLAYER, "light_tank", 28000, 31500)
	var sent: Array[Command] = Tut.think(world, ai)
	assert_int(sent.size()).is_equal(1)
	assert_int(sent[0].unit_ids.size()).is_equal(1)
	assert_bool(ai.has_fired(&"tanks")).is_true()


func test_the_count_caps_the_units_sent_to_the_lowest_ids() -> void:
	var def: TutorialScriptDef = TutorialScriptDef.new()
	def.steps.append(
		Tut.step(
			"one",
			TutorialStepDef.Trigger.TICK,
			TutorialStepDef.Action.ATTACK_MOVE,
			{"count": 1, "target": TutorialStepDef.Target.TILE, "target_tile": Vector2i(5, 6)}
		)
	)
	var world: World = Tut.start()
	var sent: Array[Command] = Tut.think(world, Tut.ai_of(def))
	assert_int(sent.size()).is_equal(1)
	assert_int(sent[0].unit_ids.size()).is_equal(1)
	assert_int(sent[0].unit_ids[0]).is_equal(Rig.ids_of(world, Tut.PLAYER, "rifle_squad")[0])
	assert_array([sent[0].target_x, sent[0].target_y]).is_equal([5500, 6500])


func test_it_thinks_on_the_dummys_schedule_and_draws_no_random_number() -> void:
	var def: TutorialScriptDef = Tut.script_def()
	var stream: DetRandom = DetRandom.create(5, DetRandom.STREAM_AI_BASE + 2)
	var before: PackedInt64Array = stream.state()
	var ai: TutorialAi = TutorialAi.create(def, 2, stream)
	assert_object(ai).is_instanceof(AiController)
	assert_int(ai.think_period).is_equal(def.think_period)
	assert_int((def.think_tick + ai.think_offset) % ai.think_period).is_equal(0)
	assert_object(ai.rng).is_same(stream)
	var world: World = Tut.start()
	Tut.think(world, ai)
	var after: PackedInt64Array = stream.state()
	assert_array(Array(after)).is_equal(Array(before))


func test_the_factory_builds_it_and_still_builds_the_dummy() -> void:
	var rng: DetRandom = DetRandom.create(1, DetRandom.STREAM_AI_BASE + 2)
	var made: AiController = AiFactory.create(Tut.script_def(), null, 2, rng)
	assert_object(made).is_instanceof(TutorialAi)
	assert_int(made.player_id).is_equal(2)
	assert_object(AiFactory.create(Rig.dummy_def(), null, 2, rng)).is_instanceof(DummyAi)


func test_two_runs_and_the_replay_agree() -> void:
	var first: Array = _run()
	var second: Array = _run()
	assert_int((first[0] as Array).size()).is_greater(0)
	assert_array(first[0]).is_equal(second[0])
	assert_array(first[1]).is_equal(second[1])
	assert_int(first[2]).is_equal(second[2])
	assert_int(first[3]).is_equal(Replay.PLAY_MATCHED)
	assert_int((first[4] as World).dropped_commands).is_equal(0)


## One run of 600 ticks: player 1's rifle squad walks into player 2's base (so the "wave" fires),
## player 2 plays the script. Returns [encoded commands, checkpoint hashes, final hash, the
## replay's answer, the world].
func _run() -> Array:
	var world: World = Tut.start()
	var loop: MatchLoop = Rig.loop_of(world)
	var ai: TutorialAi = Tut.ai_of(Tut.script_def())
	var scout: int = Rig.ids_of(world, Tut.FOE, "rifle_squad")[0]
	var sent: Array[Command] = []
	for tick: int in 600:
		var now: Array[Command] = []
		if tick == 5:
			now.append(Command.move(Tut.FOE, PackedInt32Array([scout]), 22000, 27500))
		if (world.tick + ai.think_offset) % ai.think_period == 0:
			ai.think(PlayerView.of(world, Tut.PLAYER), now)
		loop.step(world, now)
		sent.append_array(now)
	var encoded: Array = []
	for command: Command in sent:
		encoded.append([command.tick, command.type, command.player_id, command.target_x])
	var replayed: int = Replay.play(loop.replay, Tut.start(), world.tick)
	return [encoded, Array(loop.replay.checkpoint_hashes), world.state_hash(), replayed, world]


func _view_pos(world: World, id: int) -> Vector2i:
	var view: PlayerView = PlayerView.of(world, Tut.PLAYER)
	return view.row_pos(view.row_of(id))
