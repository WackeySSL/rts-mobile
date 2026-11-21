extends GdUnitTestSuite
## A step of the scripted enemy whose units are all gone counts as fired (plan row P543e), so the
## card that waits for it still shows and the lesson goes on. In each lesson the player kills every
## unit the step would send before the beat it waits for; the director, on the lesson's own match,
## shows the gated card and ends the lesson. The three waves were stuck here before: no unit, no
## Command, no `has_fired`, no card.

const Rig: GDScript = preload("res://tests/ai/support/ai_rig.gd")
const Tut: GDScript = preload("res://tests/ai/support/tutorial_rig.gd")
const Lesson: GDScript = preload("res://tests/ui/tutorial/support/lesson_rig.gd")
const LESSON_DIR: String = "res://data/tutorial/"
const FOE: int = 2
const NEXT: TutorialConditions.Kind = TutorialConditions.Kind.NEXT
## Ticks played before the units die, and the ticks the lesson is given to go on.
const BEFORE: int = 300
const WAIT: int = 120

var _dir: String = ""


func before_test() -> void:
	_dir = "user://test_dead_steps_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(_dir)
	SaveService.set_path_override(_dir.path_join("save.cfg"))


func after_test() -> void:
	SaveService.clear_path_override()
	for file_name: String in DirAccess.get_files_at(_dir):
		DirAccess.remove_absolute(_dir.path_join(file_name))
	DirAccess.remove_absolute(_dir)
	CommandQueue.clear()


func test_basics_goes_on_when_the_wave_has_no_squad_left() -> void:
	_goes_on(&"basics", &"groups", &"incoming", &"wave", &"renew_rifle")


func test_air_goes_on_when_the_raider_is_shot_down() -> void:
	_goes_on(&"air", &"home", &"raid", &"raid", &"renew_fighter")


func test_support_goes_on_when_the_squads_are_all_killed() -> void:
	_goes_on(&"support", &"sell-last", &"poke", &"poke", &"renew_rifle")


## The rule in the AI alone: squads that were seen and are all dead make the step fired with no
## Command. (Squads that were never there, not trained yet, are waited for: that case is
## `test_an_order_step_with_no_unit_to_send_waits` in test_tutorial_ai.gd.)
func test_a_step_whose_units_were_seen_and_died_fires_with_no_command() -> void:
	var def: TutorialScriptDef = TutorialScriptDef.new()
	(
		def
		. steps
		. append(
			(
				Tut
				. step(
					"go",
					TutorialStepDef.Trigger.TICK,
					TutorialStepDef.Action.ATTACK_MOVE,
					{
						"threshold": 30,
						"action_type": &"rifle_squad",
						"target": TutorialStepDef.Target.TILE,
						"target_tile": Vector2i(5, 6),
					}
				)
			)
		)
	)
	var world: World = Tut.start()
	var loop: MatchLoop = Rig.loop_of(world)
	var ai: TutorialAi = Tut.ai_of(def)
	assert_array(Tut.think(world, ai)).is_empty()  # Tick 0: the squads are seen, the clock is not.
	for row: int in world.unit_count():
		if (
			world.owner[row] == Tut.PLAYER
			and world.type_ids[world.type_index[row]] == &"rifle_squad"
		):
			world.hp[row] = 0
	for _i: int in 31:
		Rig.step(world, loop)
	assert_array(Tut.think(world, ai)).is_empty()
	assert_bool(ai.has_fired(&"go")).is_true()


## The dead step is no early exit: with its squads alive the step still waits for its beat and
## sends them.
func test_a_step_with_units_left_still_sends_them() -> void:
	var runner: MatchRunner = _runner(&"support")
	runner.run_ticks(BEFORE)
	var ai: TutorialAi = runner.controller_of(FOE) as TutorialAi
	assert_bool(ai.has_fired(&"poke")).is_false()
	ai.note_beat(&"sell-last", BEFORE)
	runner.run_ticks(WAIT)
	assert_bool(ai.has_fired(&"poke")).is_true()
	assert_int(runner.replay.commands.size()).is_greater(0)


## `id`'s match to BEFORE ticks, the enemy's `foe_type` units killed, then a director on a lesson of
## two fixture beats (`prev`, done by Next, and `card`, which waits for `step`): the card shows and
## the lesson ends.
func _goes_on(
	id: StringName, prev: StringName, card: StringName, step: StringName, foe_type: StringName
) -> void:
	var runner: MatchRunner = _runner(id)
	runner.run_ticks(BEFORE)
	var world: World = runner.world
	var type: int = world.type_ids.find(foe_type)
	var killed: int = 0
	for row: int in world.unit_count():
		if world.owner[row] == FOE and world.type_index[row] == type:
			world.hp[row] = 0
			killed += 1
	assert_int(killed).override_failure_message(String(id)).is_greater(0)
	runner.run_ticks(5)  # They are removed.
	var director: TutorialDirector = auto_free(TutorialDirector.new())
	director.runner = runner
	var done: Array[StringName] = []
	director.lesson_done.connect(func(lesson_id: StringName) -> void: done.append(lesson_id))
	var gated: TutorialBeatDef = Lesson.beat(String(card), NEXT, {"after_ai_step": step})
	director.start(Lesson.lesson(String(id), [Lesson.beat(String(prev), NEXT), gated]))
	director.advance()
	assert_bool(director.next()).is_true()
	var shown: bool = false
	for _tick: int in WAIT:
		runner.run_ticks(1)
		director.advance()
		if director.current != null and director.current.id == card:
			shown = true
			break
	(
		assert_bool(shown)
		. override_failure_message("%s: the card %s never showed" % [id, card])
		. is_true()
	)
	assert_bool((runner.controller_of(FOE) as TutorialAi).has_fired(step)).is_true()
	assert_bool(director.next()).is_true()
	assert_array(done).is_equal([id])


func _runner(id: StringName) -> MatchRunner:
	var lesson: TutorialLessonDef = load("%s%s.tres" % [LESSON_DIR, id]) as TutorialLessonDef
	var runner: MatchRunner = auto_free(MatchRunner.new())
	runner.scenario = lesson.scenario
	runner.match_seed = lesson.match_seed
	runner.tick_mode = MatchRunner.TickMode.SYNC
	runner.opponents = [lesson.enemy]
	runner.start()
	return runner


## All the field units are dead but one is in production: the step waits for it, then sends it.
func test_a_unit_in_production_is_waited_for_and_then_sent() -> void:
	var rig: Dictionary = _rig(_order_def({"threshold": 20}))
	_think(rig)  # Tick 0: the squads are seen, the clock is not.
	_kill(rig, "rifle_squad")
	_queue(rig, "rifle_squad")
	_run(rig, 25)
	assert_array(_think(rig)).is_empty()
	assert_bool(rig["ai"].has_fired(&"go")).is_false()  # Waits: one is being trained.
	_run(rig, 120)
	var sent: Array[Command] = _think(rig)
	assert_int(sent.size()).is_equal(1)
	assert_int(sent[0].unit_ids.size()).is_equal(1)
	assert_bool(rig["ai"].has_fired(&"go")).is_true()


## Some are killed: the survivors are sent, and the step does not count as gone.
func test_the_survivors_are_sent() -> void:
	var rig: Dictionary = _rig(_order_def({"threshold": 20}))
	_think(rig)
	var world: World = rig["world"]
	var first: int = Rig.row_of(world, Tut.PLAYER, "rifle_squad")
	world.hp[first] = 0
	_run(rig, 25)
	var sent: Array[Command] = _think(rig)
	assert_int(sent.size()).is_equal(1)
	assert_int(sent[0].unit_ids.size()).is_equal(1)


## A step that names no type fires empty once every fighting unit is dead, and a living tanker does
## not hold it (it would never be sent).
func test_a_step_with_no_type_is_not_held_by_a_tanker() -> void:
	var rig: Dictionary = _rig(_order_def({"threshold": 20, "action_type": &""}))
	Rig.add_unit_of(rig["world"], Tut.PLAYER, "harvester", 30000, 30000)
	_think(rig)
	_kill(rig, "rifle_squad")
	_run(rig, 25)
	assert_array(_think(rig)).is_empty()
	assert_bool(rig["ai"].has_fired(&"go")).is_true()


## A type the roster lacks fires empty, and says so.
func test_an_absent_type_fires_empty_with_a_warning() -> void:
	var rig: Dictionary = _rig(_order_def({"threshold": 0, "action_type": &"no_such_unit"}))
	(
		assert_error(func() -> void: _think(rig))
		. is_push_warning("TutorialAi: step go sends no_such_unit, which no roster has")
	)
	assert_bool(rig["ai"].has_fired(&"go")).is_true()


## The producer dies with a squad queued: nothing will ever build it, so the step does not wait.
func test_a_queue_with_no_producer_left_is_not_waited_for() -> void:
	var rig: Dictionary = _rig(_order_def({"threshold": 20}))
	_think(rig)
	_queue(rig, "rifle_squad")
	_kill(rig, "rifle_squad")
	_kill(rig, "barracks")
	_run(rig, 25)
	assert_array(_think(rig)).is_empty()
	assert_bool(rig["ai"].has_fired(&"go")).is_true()


## A type that was only ever a queued item counts as seen: when its producer then dies, the step
## fires instead of waiting for squads that were never on the field.
func test_a_type_seen_only_as_a_queued_item_counts_as_seen() -> void:
	var rig: Dictionary = _rig(_order_def({"threshold": 20}))
	_kill(rig, "rifle_squad")
	_queue(rig, "rifle_squad")
	_think(rig)  # Tick 1: the item is queued, no squad stands, the clock is not due.
	_kill(rig, "barracks")
	_run(rig, 25)
	assert_array(_think(rig)).is_empty()
	assert_bool(rig["ai"].has_fired(&"go")).is_true()


## A QUEUE step of the script that has not fired may still train the type: the step waits.
func test_an_unfired_queue_step_of_the_type_holds_the_step() -> void:
	var def: TutorialScriptDef = _order_def({"threshold": 20})
	def.steps.append(
		Tut.step(
			"train",
			TutorialStepDef.Trigger.TICK,
			TutorialStepDef.Action.QUEUE,
			{"threshold": 9000, "action_type": &"rifle_squad", "count": 1}
		)
	)
	var rig: Dictionary = _rig(def)
	_think(rig)
	_kill(rig, "rifle_squad")
	_run(rig, 25)
	_think(rig)
	assert_bool(rig["ai"].has_fired(&"go")).is_false()


func _order_def(fields: Dictionary) -> TutorialScriptDef:
	var all: Dictionary = {
		"action_type": &"rifle_squad",
		"target": TutorialStepDef.Target.TILE,
		"target_tile": Vector2i(5, 6),
	}
	all.merge(fields, true)
	var def: TutorialScriptDef = TutorialScriptDef.new()
	def.steps.append(
		Tut.step("go", TutorialStepDef.Trigger.TICK, TutorialStepDef.Action.ATTACK_MOVE, all)
	)
	return def


func _rig(def: TutorialScriptDef) -> Dictionary:
	var world: World = Tut.start()
	return {"world": world, "loop": Rig.loop_of(world), "ai": Tut.ai_of(def)}


func _think(rig: Dictionary) -> Array[Command]:
	return Tut.think(rig["world"], rig["ai"])


func _run(rig: Dictionary, ticks: int) -> void:
	for _i: int in ticks:
		Rig.step(rig["world"], rig["loop"])


func _queue(rig: Dictionary, id: String) -> void:
	Rig.step(rig["world"], rig["loop"], [Command.queue(Tut.PLAYER, Rig.type_of(rig["world"], id))])


## Every unit or building of the scripted player of the type `id` dies.
func _kill(rig: Dictionary, id: String) -> void:
	var world: World = rig["world"]
	var type: int = Rig.type_of(world, id)
	for row: int in world.unit_count():
		if world.owner[row] == Tut.PLAYER and world.type_index[row] == type:
			world.hp[row] = 0
	_run(rig, 1)
