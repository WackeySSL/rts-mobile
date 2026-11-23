extends GdUnitTestSuite
## The scripted enemies of the four lessons (plan row P543), played headless on the lesson's own
## scenario and seed through `MatchRunner` (SYNC), the way a lesson's match is seated: the steps
## fire when their triggers hold and on their ticks, so the beats that wait for them
## (`after_ai_step`) are opened, and an idle player's Headquarters outlives the script. The runner
## is never put in the tree, and the director is not involved: its gate is in the director suites.

const LESSON_DIR: String = "res://data/tutorial/"
const LOCAL: int = 1
const FOE: int = 2
## Ticks after a TICK trigger's threshold that its step has to have fired in (one think and the
## wait of an order step for its units).
const SLACK: int = 60
## The tick the test says the player finished the beat `groups` on.
const GROUPS_TICK: int = 900
## The ticks the tests say the player finished `home` (air) and `sell-last` (support) on.
const HOME_TICK: int = 400
const SELL_LAST_TICK: int = 300


func test_basics_trains_then_sends_the_wave_when_the_groups_beat_is_done() -> void:
	var runner: MatchRunner = _play(&"basics", GROUPS_TICK)
	var ai: TutorialAi = runner.controller_of(FOE) as TutorialAi
	assert_bool(ai.has_fired(&"train")).is_true()
	assert_bool(ai.has_fired(&"wave")).is_false()  # No clock opens it, only the beat.
	ai.note_beat(&"groups", GROUPS_TICK)
	runner.run_ticks(2700 - GROUPS_TICK)
	assert_int(ai.fired_tick_of(&"wave")).is_between(GROUPS_TICK + 15, GROUPS_TICK + 15 + SLACK)
	assert_bool(ai.has_fired(&"defend")).is_false()  # Nothing of the player's came near.
	# Three came with the start and three were trained; the wave stands at the player's base.
	assert_int(_count(runner.world, FOE, &"renew_rifle")).is_between(3, 6)
	assert_int(_at_target(runner.world)).is_greater_equal(3)
	assert_int(_count(runner.world, LOCAL, &"headquarters")).is_equal(1)
	assert_int(runner.world.match_end_tick).is_equal(0)


func test_basics_defends_when_the_player_comes_near_its_base() -> void:
	var runner: MatchRunner = _runner(&"basics")
	runner.run_ticks(60)
	var world: World = runner.world
	var squads: PackedInt32Array = PackedInt32Array()
	var type: int = world.type_ids.find(&"rifle_squad")
	for row: int in world.unit_count():
		if world.owner[row] == LOCAL and world.type_index[row] == type:
			squads.append(world.unit_id[row])
	CommandQueue.submit(Command.move(LOCAL, squads, 24000, 24000))
	runner.run_ticks(1500)
	var ai: TutorialAi = runner.controller_of(FOE) as TutorialAi
	assert_bool(ai.has_fired(&"defend")).is_true()
	assert_bool(ai.has_fired(&"wave")).is_false()  # The view opened it, not the beat.


func test_strikes_gathers_the_squads_early_for_the_strike() -> void:
	var ai: TutorialAi = _fired(&"strikes", 400)
	assert_int(ai.fired_tick_of(&"gather")).is_between(150, 150 + SLACK)


func test_air_sends_one_fighter_when_the_home_beat_is_done() -> void:
	var runner: MatchRunner = _play(&"air", HOME_TICK)
	var ai: TutorialAi = runner.controller_of(FOE) as TutorialAi
	assert_bool(ai.has_fired(&"raid")).is_false()  # No clock opens it, only the beat.
	ai.note_beat(&"home", HOME_TICK)
	runner.run_ticks(300)
	assert_int(ai.fired_tick_of(&"raid")).is_between(HOME_TICK + 15, HOME_TICK + 15 + SLACK)


func test_support_sends_the_squads_when_the_sell_last_beat_is_done() -> void:
	var runner: MatchRunner = _play(&"support", SELL_LAST_TICK)
	var ai: TutorialAi = runner.controller_of(FOE) as TutorialAi
	assert_bool(ai.has_fired(&"poke")).is_false()
	ai.note_beat(&"sell-last", SELL_LAST_TICK)
	runner.run_ticks(900)
	var at: int = ai.fired_tick_of(&"poke")
	assert_int(at).is_between(SELL_LAST_TICK + 15, SELL_LAST_TICK + 15 + SLACK)
	assert_int(_count(runner.world, LOCAL, &"headquarters")).is_equal(1)
	assert_int(runner.world.match_end_tick).is_equal(0)


## The same lesson and seed give the same Command log: a lesson replays.
func test_a_lesson_replays_from_its_seed_and_its_beat_ticks() -> void:
	var first: MatchRunner = _with_groups_at(600)
	var second: MatchRunner = _with_groups_at(600)
	assert_array(first.replay.commands).is_equal(second.replay.commands)
	assert_int(first.last_hash).is_equal(second.last_hash)
	assert_int(first.replay.commands.size()).is_greater(0)  # The enemy queued its squads.
	# The wave left on the beat's tick plus its delay, so a later beat means a later wave.
	var later: MatchRunner = _with_groups_at(660)
	assert_array(later.replay.commands).is_not_equal(first.replay.commands)


## A basics match to tick 900 where the player finished `groups` on `tick`.
func _with_groups_at(tick: int) -> MatchRunner:
	var runner: MatchRunner = _play(&"basics", tick)
	(runner.controller_of(FOE) as TutorialAi).note_beat(&"groups", tick)
	runner.run_ticks(900 - tick)
	return runner


## Enemy rifles within 4 tiles of the wave's target tile (11, 10).
func _at_target(world: World) -> int:
	var found: int = 0
	var type: int = world.type_ids.find(&"renew_rifle")
	for row: int in world.unit_count():
		if world.owner[row] != FOE or world.type_index[row] != type:
			continue
		if absi(world.pos_x[row] - 11500) <= 4000 and absi(world.pos_y[row] - 10500) <= 4000:
			found += 1
	return found


func _runner(id: StringName) -> MatchRunner:
	var lesson: TutorialLessonDef = load("%s%s.tres" % [LESSON_DIR, id]) as TutorialLessonDef
	var runner: MatchRunner = auto_free(MatchRunner.new())
	runner.scenario = lesson.scenario
	runner.match_seed = lesson.match_seed
	runner.tick_mode = MatchRunner.TickMode.SYNC
	runner.opponents = [lesson.enemy]
	runner.start()
	return runner


func _play(id: StringName, ticks: int) -> MatchRunner:
	var runner: MatchRunner = _runner(id)
	runner.run_ticks(ticks)
	return runner


func _fired(id: StringName, ticks: int) -> TutorialAi:
	return _play(id, ticks).controller_of(FOE) as TutorialAi


func _count(world: World, player: int, type_id: StringName) -> int:
	var type: int = world.type_ids.find(type_id)
	var found: int = 0
	for row: int in world.unit_count():
		if world.owner[row] == player and world.type_index[row] == type:
			found += 1
	return found
