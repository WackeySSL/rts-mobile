extends GdUnitTestSuite
## The lesson files of the tutorial (plan row P543, ADR 0044 section 1): `data/tutorial/<id>.tres`,
## their scenarios (`data/scenarios/tutorial_*.tres` on `data/maps/tutorial_*.tres`) and the
## scripted enemy of each. What a lesson needs to be finishable is read off the data, so a beat
## that nobody could end (a type that is not in the match, an area on rock, a build the credits
## cannot pay, a prompt with no text) fails here and not on the phone:
## - the four lessons load, with no problems, a scenario, an enemy and budgets within the target;
## - every `covers` id is a row of docs/HOW_TO_PLAY.md that is in the game;
## - every beat's kind is a condition kind and its parameters name things that exist in its match;
## - every beat that asks for units or buildings can be satisfied from the start and the credits;
## - every `after_ai_step` is a step of the lesson's enemy, and the enemy's script resolves;
## - every prompt has its English text, and no text is left unused.

const LESSON_DIR: String = "res://data/tutorial/"
const LESSONS: Array[StringName] = [&"basics", &"strikes", &"air", &"support"]
const DOC: String = "res://docs/HOW_TO_PLAY.md"
const LOCAL: int = 1
const FOE: int = 2
## `HudState.Unfold` values a beat may wait for: the drawer, the radar, the economy card, the pause.
const UNFOLDS: Array[int] = [1, 2, 3, 4]
const GROUPS: Array[int] = [1, 2, 3]
const CELL_CENTRE: int = 500
## Kinds that a build or a training ends.
const BUILDS: Array[TutorialConditions.Kind] = [
	TutorialConditions.Kind.OWN_AT_LEAST,
	TutorialConditions.Kind.BUILDING_DONE,
	TutorialConditions.Kind.BUILDING_PLACED,
	TutorialConditions.Kind.PLACING,
]


func test_the_four_lessons_load_with_a_match_of_their_own() -> void:
	for id: StringName in LESSONS:
		var lesson: TutorialLessonDef = _lesson(id)
		assert_object(lesson).override_failure_message(String(id)).is_not_null()
		assert_str(String(lesson.id)).is_equal(String(id))
		assert_array(Array(lesson.problems())).override_failure_message(String(id)).is_empty()
		assert_int(lesson.beats.size()).override_failure_message(String(id)).is_greater(5)
		assert_object(lesson.scenario).override_failure_message(String(id)).is_not_null()
		assert_object(lesson.enemy).override_failure_message(String(id)).is_not_null()
		assert_str(lesson.scenario.resource_path).is_equal(
			"res://data/scenarios/tutorial_%s.tres" % id
		)
		assert_str(lesson.scenario.map.resource_path).starts_with("res://data/maps/tutorial_")
		assert_str(lesson.enemy.resource_path).is_equal("%s%s_enemy.tres" % [LESSON_DIR, id])
		assert_int(lesson.match_seed).is_greater(0)


func test_basics_is_three_minutes_and_the_drills_about_one_or_two() -> void:
	assert_int(_lesson(&"basics").target_s).is_equal(180)
	for id: StringName in [&"strikes", &"air", &"support"]:
		assert_int(_lesson(id).target_s).override_failure_message(String(id)).is_between(60, 90)


## The budgets of a lesson add up to no more than its target (P543f: the sum is pinned).
func test_the_budgets_of_each_lesson_stay_within_its_target() -> void:
	for id: StringName in LESSONS:
		var lesson: TutorialLessonDef = _lesson(id)
		var total: int = 0
		for beat: TutorialBeatDef in lesson.beats:
			total += beat.budget_s
		assert_int(total).override_failure_message(String(id)).is_less_equal(lesson.target_s)
	var basics: int = 0
	for beat: TutorialBeatDef in _lesson(&"basics").beats:
		basics += beat.budget_s
	assert_int(basics).is_equal(180)


## P543f: the move beat marks the ground the squads must reach (a tile inside its area, not the Stop
## button), and the Stop card comes right after it.
func test_the_move_beat_marks_ground_inside_its_area_and_stop_follows() -> void:
	var lesson: TutorialLessonDef = _lesson(&"basics")
	var ids: Array[StringName] = []
	for beat: TutorialBeatDef in lesson.beats:
		ids.append(beat.id)
	var at: int = ids.find(&"move")
	assert_int(at).is_greater_equal(0)
	var move: TutorialBeatDef = lesson.beats[at]
	assert_int(move.anchor).is_equal(TutorialBeatDef.Anchor.TILE)
	assert_bool(move.area.has_point(move.anchor_tile)).is_true()
	assert_array(move.covers).is_equal([&"orders-move"])
	assert_str(String(ids[at + 1])).is_equal("stop")
	var stop: TutorialBeatDef = lesson.beats[at + 1]
	assert_int(stop.anchor).is_equal(TutorialBeatDef.Anchor.CONTROL)
	assert_str(String(stop.anchor_control)).is_equal("Stop")
	assert_array(stop.covers).is_equal([&"orders-stop"])


## P543f: a player may save one squad as a group, so the groups beat asks for one.
func test_the_groups_beat_asks_for_one_squad() -> void:
	for beat: TutorialBeatDef in _lesson(&"basics").beats:
		if beat.kind == TutorialConditions.Kind.GROUP_SAVED:
			assert_int(beat.count).override_failure_message(String(beat.id)).is_equal(1)


## ADR 0048 section 5: a beat whose final target is a drawer card (`Tile_*`) or tab (`Tab*`) has a
## lead-in that opens the drawer, then (for a card) the lead-in that turns on the card's tab, in
## that order. The tab is the one the sidebar files the card's item under (`World.type_tab`), and
## the step's own control is that tab's button (`BuildSidebar.TAB_NAMES`).
func test_a_drawer_target_is_led_in_by_the_drawer_and_its_tab() -> void:
	var checked: int = 0
	for id: StringName in LESSONS:
		var lesson: TutorialLessonDef = _lesson(id)
		var world: World = World.from_scenario(lesson.scenario)
		for beat: TutorialBeatDef in lesson.beats:
			var name: String = String(beat.anchor_control)
			var card: bool = name.begins_with("Tile_")
			if (
				beat.anchor != TutorialBeatDef.Anchor.CONTROL
				or not (card or name.begins_with("Tab"))
			):
				continue
			checked += 1
			var label: String = "%s/%s" % [id, beat.id]
			var opens: int = -1
			var tab: int = -1
			for at: int in beat.lead_in.size():
				var step: TutorialLeadInDef = beat.lead_in[at]
				if step.kind == TutorialConditions.Kind.UNFOLD_OPEN and step.value == 1:
					opens = at if opens < 0 else opens
				if step.kind == TutorialConditions.Kind.DRAWER_TAB:
					tab = at if tab < 0 else tab
			assert_int(opens).override_failure_message(label + " opens no drawer").is_greater_equal(
				0
			)
			var want: int = BuildSidebar.TAB_NAMES.find(name.trim_prefix("Tab"))
			if card:
				var type: int = world.type_ids.find(StringName(name.trim_prefix("Tile_")))
				assert_int(type).override_failure_message(label + " card is no type").is_greater(-1)
				want = world.type_tab[type]
				assert_int(tab).override_failure_message(label + " has no tab step").is_greater(-1)
			if tab >= 0:
				assert_int(opens).override_failure_message(label + " tab before drawer").is_less(
					tab
				)
				var step: TutorialLeadInDef = beat.lead_in[tab]
				assert_int(step.value).override_failure_message(label + " tab value").is_equal(want)
				var button: String = "Tab" + BuildSidebar.TAB_NAMES[step.value]
				(
					assert_str(String(step.anchor_control))
					. override_failure_message(label + " tab control")
					. is_equal(button)
				)
	assert_int(checked).is_greater(5)


func test_every_covers_id_is_a_row_of_the_how_to_play_list() -> void:
	var rows: Array[StringName] = _how_to_play_ids()
	assert_int(rows.size()).is_greater(100)
	for id: StringName in LESSONS:
		var lesson: TutorialLessonDef = _lesson(id)
		assert_int(lesson.covered_ids().size()).override_failure_message(String(id)).is_greater(5)
		for row: StringName in lesson.covered_ids():
			(
				assert_bool(rows.has(row))
				. override_failure_message("%s covers %s" % [id, row])
				. is_true()
			)


func test_every_beat_has_a_condition_kind_and_parameters_that_fit_it() -> void:
	var zooms: int = InputSettings.new().zoom_levels.size()
	for id: StringName in LESSONS:
		var lesson: TutorialLessonDef = _lesson(id)
		var world: World = World.from_scenario(lesson.scenario)
		for beat: TutorialBeatDef in lesson.beats:
			var label: String = "%s/%s" % [id, beat.id]
			(
				assert_bool(TutorialConditions.Kind.values().has(beat.kind))
				. override_failure_message(label)
				. is_true()
			)
			(
				assert_bool(TutorialBeatDef.Anchor.values().has(beat.anchor))
				. override_failure_message(label)
				. is_true()
			)
			assert_int(beat.budget_s).override_failure_message(label).is_greater(0)
			assert_int(beat.delay_ticks).override_failure_message(label).is_greater_equal(0)
			match beat.kind:
				TutorialConditions.Kind.ZOOM_LEVEL:
					assert_int(beat.value).override_failure_message(label).is_between(0, zooms - 1)
				TutorialConditions.Kind.UNFOLD_OPEN, TutorialConditions.Kind.UNFOLD_CLOSED:
					assert_bool(UNFOLDS.has(beat.value)).override_failure_message(label).is_true()
				TutorialConditions.Kind.DRAWER_TAB:
					assert_int(beat.value).override_failure_message(label).is_between(0, 4)
				TutorialConditions.Kind.GROUP_SAVED:
					assert_bool(GROUPS.has(beat.value)).override_failure_message(label).is_true()
				TutorialConditions.Kind.CAMERA_PANNED, TutorialConditions.Kind.HARVESTED:
					assert_int(beat.count).override_failure_message(label).is_greater(0)
				TutorialConditions.Kind.UNITS_IN_AREA:
					_check_area(world, beat, label)
			if beat.anchor == TutorialBeatDef.Anchor.TILE:
				var tile: Vector2i = beat.anchor_tile
				var inside: bool = Rect2i(0, 0, world.map_w, world.map_h).has_point(tile)
				assert_bool(inside).override_failure_message(label + " anchor tile").is_true()


func test_every_beat_that_names_a_type_names_one_of_its_match() -> void:
	for id: StringName in LESSONS:
		var lesson: TutorialLessonDef = _lesson(id)
		var world: World = World.from_scenario(lesson.scenario)
		for beat: TutorialBeatDef in lesson.beats:
			var label: String = "%s/%s" % [id, beat.id]
			if _needs_type(beat.kind):
				assert_str(String(beat.type_id)).override_failure_message(label).is_not_empty()
			if beat.type_id != &"":
				(
					assert_bool(world.type_ids.has(beat.type_id))
					. override_failure_message(label)
					. is_true()
				)


## A lesson can be finished with what its scenario gives and what its credits buy: the units a beat
## wants are on the player's side at the start, or its faction builds them (the producer stands at
## the start or an earlier beat builds it, the requirement is owned) and the sum of what the beats
## buy is within the start credits.
func test_every_beat_can_be_finished_from_the_start_and_the_credits() -> void:
	for id: StringName in LESSONS:
		var lesson: TutorialLessonDef = _lesson(id)
		var world: World = World.from_scenario(lesson.scenario)
		var have: Dictionary[int, int] = _owned_at_start(world)
		var spend: int = 0
		for beat: TutorialBeatDef in lesson.beats:
			var label: String = "%s/%s" % [id, beat.id]
			var type: int = world.type_ids.find(beat.type_id)
			if type < 0:
				continue
			var wanted: int = maxi(beat.count, 1)
			var owned: int = have.get(type, 0)
			match beat.kind:
				TutorialConditions.Kind.SELECTED, TutorialConditions.Kind.UNITS_IN_AREA:
					assert_int(owned).override_failure_message(label).is_greater_equal(wanted)
				_:
					if owned >= wanted or not BUILDS.has(beat.kind):
						continue
					(
						assert_bool(_buildable(world, lesson, type, have))
						. override_failure_message(label)
						. is_true()
					)
					spend += world.type_cost[type] * (wanted - owned)
					have[type] = wanted
		assert_int(spend).override_failure_message(String(id)).is_less_equal(world.start_credits)


func test_every_after_ai_step_is_a_step_of_the_enemy() -> void:
	for id: StringName in LESSONS:
		var lesson: TutorialLessonDef = _lesson(id)
		var ai: TutorialAi = TutorialAi.create(
			lesson.enemy, FOE, DetRandom.create(1, DetRandom.STREAM_AI_BASE + FOE)
		)
		var steps: Array[StringName] = ai.step_ids()
		assert_int(steps.size()).override_failure_message(String(id)).is_greater(0)
		for beat: TutorialBeatDef in lesson.beats:
			if beat.after_ai_step != &"":
				var label: String = "%s/%s waits for %s" % [id, beat.id, beat.after_ai_step]
				assert_bool(steps.has(beat.after_ai_step)).override_failure_message(label).is_true()


## A step that waits for a beat (`BEAT`) names a beat of its lesson, and that beat comes before the
## beat that waits for the step: otherwise the card would wait for a beat it can only reach after.
func test_a_beat_trigger_names_an_earlier_beat_than_the_card_that_waits_for_it() -> void:
	var steps_with_beats: int = 0
	for id: StringName in LESSONS:
		var lesson: TutorialLessonDef = _lesson(id)
		var order: Array[StringName] = []
		for beat: TutorialBeatDef in lesson.beats:
			order.append(beat.id)
		for step: TutorialStepDef in lesson.enemy.steps:
			if step.trigger != TutorialStepDef.Trigger.BEAT:
				continue
			steps_with_beats += 1
			var label: String = "%s/%s waits for %s" % [id, step.id, step.trigger_beat]
			assert_bool(order.has(step.trigger_beat)).override_failure_message(label).is_true()
			assert_int(step.threshold).override_failure_message(label + " delay").is_greater_equal(
				1
			)
			var at: int = order.find(step.trigger_beat)
			for beat: TutorialBeatDef in lesson.beats:
				# A card waits on this step, or on a step that waits (`after_step`) for it.
				if _waits_through(lesson.enemy.steps, beat.after_ai_step, step.id):
					var late: String = "%s: card %s is not after the beat" % [label, beat.id]
					assert_bool(at < order.find(beat.id)).override_failure_message(late).is_true()
	assert_int(steps_with_beats).is_greater(0)


## The enemy is seated through the runner as a match does it (an `AiFactory` controller), and its
## script resolves: every `after_step` names a step, every step id is unique, every type it names is
## in the match, and a QUEUE step has a producer of its own in the scenario.
func test_every_enemy_script_resolves_against_its_match() -> void:
	for id: StringName in LESSONS:
		var lesson: TutorialLessonDef = _lesson(id)
		var world: World = World.from_scenario(lesson.scenario)
		var seen: Array[StringName] = []
		var have: Dictionary[int, int] = _owned_at_start(world, FOE)
		assert_str(String(lesson.enemy.hq_type)).is_equal("renew_hq")
		for step: TutorialStepDef in lesson.enemy.steps:
			var label: String = "%s/%s" % [id, step.id]
			assert_bool(seen.has(step.id)).override_failure_message(label + " repeated").is_false()
			seen.append(step.id)
			if step.after_step != &"":
				(
					assert_bool(seen.has(step.after_step))
					. override_failure_message(label + " after_step")
					. is_true()
				)
			(
				assert_bool(world.type_ids.has(step.action_type))
				. override_failure_message(label)
				. is_true()
			)
			if step.action == TutorialStepDef.Action.QUEUE:
				var type: int = world.type_ids.find(step.action_type)
				var producer: bool = false
				for owned: int in have:
					producer = producer or world.type_produces[owned] == world.type_tab[type]
				assert_bool(producer).override_failure_message(label + " has no producer").is_true()
		var runner: MatchRunner = auto_free(MatchRunner.new())
		runner.scenario = lesson.scenario
		runner.match_seed = lesson.match_seed
		runner.tick_mode = MatchRunner.TickMode.SYNC
		runner.opponents = [lesson.enemy]
		runner.start()
		var ai: TutorialAi = runner.controller_of(FOE) as TutorialAi
		assert_object(ai).override_failure_message(String(id)).is_not_null()
		assert_int(ai.step_count()).is_equal(lesson.enemy.steps.size())


## Two QUEUE steps of one type count each other's items (TutorialAi's header): they stay in script
## order, so that no step waits, through `after_step`, for one that comes after it.
func test_queue_steps_of_one_type_keep_their_script_order() -> void:
	for id: StringName in LESSONS:
		var steps: Array[TutorialStepDef] = _lesson(id).enemy.steps
		for later: int in steps.size():
			for earlier: int in later:
				var a: TutorialStepDef = steps[earlier]
				var b: TutorialStepDef = steps[later]
				var same: bool = a.action == TutorialStepDef.Action.QUEUE and b.action == a.action
				if same and a.action_type == b.action_type:
					var label: String = "%s: %s before %s" % [id, a.id, b.id]
					assert_bool(_waits_for(steps, a, b)).override_failure_message(label).is_false()


func test_every_prompt_has_its_english_text_and_no_text_is_left_over() -> void:
	var used: Array[StringName] = [TutorialText.KICKER]
	for id: StringName in LESSONS:
		var lesson: TutorialLessonDef = _lesson(id)
		used.append(lesson.title_key)
		used.append(lesson.objective_key)
		for beat: TutorialBeatDef in lesson.beats:
			used.append(beat.prompt_key)
	var words: Dictionary[StringName, String] = TutorialText.raw()
	for key: StringName in used:
		assert_bool(words.has(key)).override_failure_message(String(key)).is_true()
		assert_str(words.get(key, "")).override_failure_message(String(key)).is_not_empty()
	for key: StringName in words:
		assert_bool(used.has(key)).override_failure_message("unused " + String(key)).is_true()


## The director registers the table, so the card's tr() gives the English words.
func test_the_director_registers_the_english_table() -> void:
	var director: TutorialDirector = auto_free(TutorialDirector.new())
	director.start(null)
	var key: StringName = &"tutorial.basics.pan"
	assert_str(TranslationServer.translate(key)).is_equal(TutorialText.resolved()[key])


## A prompt is for a first-time player: no data name, file path or code in it.
func test_prompts_hold_no_developer_reference() -> void:
	var words: Dictionary[StringName, String] = TutorialText.resolved()
	for key: StringName in words:
		var text: String = words[key]
		for banned: String in ["`", "data/", ".tres", "res://", "_ms", "_s "]:
			(
				assert_bool(text.contains(banned))
				. override_failure_message("%s: %s" % [key, banned])
				. is_false()
			)


## A prompt names a card as the player sees it (its display name), by `{type_id}` from the defs: a
## placeholder names a unit of the lessons' faction and none is left open, and the type id read as
## words ("Power Plant", "Rifle Squad") is no name in any prompt unless it is a display name.
func test_prompts_name_cards_by_their_display_names() -> void:
	var cards: Dictionary[String, String] = TutorialText.names()
	assert_int(cards.size()).is_greater(20)
	var shown: Dictionary[StringName, String] = TutorialText.resolved()
	var holder: RegEx = RegEx.create_from_string("\\{([a-z_]+)\\}")
	var real: Array[String] = cards.values()
	for key: StringName in TutorialText.raw():
		for hit: RegExMatch in holder.search_all(TutorialText.raw()[key]):
			var type: String = hit.get_string(1)
			assert_bool(cards.has(type)).override_failure_message("%s {%s}" % [key, type]).is_true()
		(
			assert_bool(shown[key].contains("{") or shown[key].contains("}"))
			. override_failure_message(String(key))
			. is_false()
		)
	for type: String in cards:
		for wrong: String in [
			type.capitalize(), type.trim_prefix("fossil_").trim_prefix("renew_").capitalize()
		]:
			if real.has(wrong):
				continue
			var word: RegEx = RegEx.create_from_string("\\b%s\\b" % wrong)  # Not "Strikes".
			for key: StringName in shown:
				var label: String = "%s says %s, the card is %s" % [key, wrong, cards[type]]
				(
					assert_bool(word.search(shown[key]) != null)
					. override_failure_message(label)
					. is_false()
				)


## Two factions that name one type id differently: the first (the player's) keeps its name.
func test_the_first_faction_wins_a_name_clash() -> void:
	var found: Dictionary[String, String] = {}
	for label: String in ["Mine", "Theirs"]:
		var unit: UnitDef = UnitDef.new()
		unit.type_id = &"shared"
		unit.display_name = label
		var faction: FactionDef = FactionDef.new()
		faction.roster.append(unit)
		TutorialText.merge_names(found, faction)
	assert_str(found["shared"]).is_equal("Mine")


## A strike building of a drill is ready when its drill needs it and not before: the Deep Bore has
## its whole charge behind it with a margin, the Skyrig's is still running.
func test_the_strikes_drill_charges_one_building_and_leaves_one_running() -> void:
	var lesson: TutorialLessonDef = _lesson(&"strikes")
	var ready: int = 0
	var charging: int = 0
	for spawn: SpawnDef in lesson.scenario.spawns:
		if not spawn.unit is BuildingDef or spawn.owner != LOCAL:
			continue
		var building: BuildingDef = spawn.unit
		if building.charge_ticks <= 0:
			continue
		if spawn.charge_elapsed_ticks > building.charge_ticks:
			ready += 1  # Charged with a margin.
		elif spawn.charge_elapsed_ticks > 0 and spawn.charge_elapsed_ticks < building.charge_ticks:
			charging += 1
	assert_int(ready).is_equal(1)
	assert_int(charging).is_equal(1)


## Whether the step `from` is the step `target`, or waits for it through its `after_step` chain.
func _waits_through(steps: Array[TutorialStepDef], from: StringName, target: StringName) -> bool:
	var at: StringName = from
	for _hop: int in steps.size() + 1:
		if at == &"":
			return false
		if at == target:
			return true
		var next: int = steps.find_custom(func(one: TutorialStepDef) -> bool: return one.id == at)
		if next < 0:
			return false
		at = steps[next].after_step
	return false


func _lesson(id: StringName) -> TutorialLessonDef:
	return load("%s%s.tres" % [LESSON_DIR, id]) as TutorialLessonDef


func _needs_type(kind: int) -> bool:
	return (
		[
			TutorialConditions.Kind.UNITS_IN_AREA,
			TutorialConditions.Kind.BUILDING_PLACED,
			TutorialConditions.Kind.BUILDING_DONE,
			TutorialConditions.Kind.OWN_AT_LEAST,
		]
		. has(kind)
	)


## An area that is on the map and whose every tile a foot soldier can stand on.
func _check_area(world: World, beat: TutorialBeatDef, label: String) -> void:
	var area: Rect2i = beat.area
	assert_bool(area.has_area()).override_failure_message(label + " area").is_true()
	(
		assert_bool(Rect2i(0, 0, world.map_w, world.map_h).encloses(area))
		. override_failure_message(label + " area")
		. is_true()
	)
	for y: int in range(area.position.y, area.end.y):
		for x: int in range(area.position.x, area.end.x):
			var cell: int = world.cell_of(x * 1000 + CELL_CENTRE, y * 1000 + CELL_CENTRE)
			(
				assert_bool(world.is_passable(cell, World.MoveClass.FOOT))
				. override_failure_message("%s tile %d,%d" % [label, x, y])
				. is_true()
			)


## Rows of each type that `player` owns when the match starts.
func _owned_at_start(world: World, player: int = LOCAL) -> Dictionary[int, int]:
	var have: Dictionary[int, int] = {}
	for row: int in world.unit_count():
		if world.owner[row] == player:
			have[world.type_index[row]] = have.get(world.type_index[row], 0) + 1
	return have


## Whether the local player's faction can build `type`: it is the faction's, a producer of its tab
## is owned (or built by an earlier beat, in `have`), and its requirement is owned.
func _buildable(
	world: World, lesson: TutorialLessonDef, type: int, have: Dictionary[int, int]
) -> bool:
	var faction: StringName = lesson.scenario.factions[LOCAL].id
	if world.type_faction[type] != world.faction_ids.find(faction) or world.type_tab[type] < 0:
		return false
	var need: int = world.type_requires[type]
	if need >= 0 and have.get(need, 0) == 0:
		return false
	for owned: int in have:
		if world.type_produces[owned] == world.type_tab[type]:
			return true
	return false


## Whether `step` waits, through its `after_step` chain, for `target`.
func _waits_for(
	steps: Array[TutorialStepDef], step: TutorialStepDef, target: TutorialStepDef
) -> bool:
	var at: TutorialStepDef = step
	for _hop: int in steps.size():
		if at.after_step == &"":
			return false
		if at.after_step == target.id:
			return true
		var next: int = steps.find_custom(
			func(one: TutorialStepDef) -> bool: return one.id == at.after_step
		)
		if next < 0:
			return false
		at = steps[next]
	return false


## Every id of a row that is in the game (the "Not yet in the game" section is left out).
func _how_to_play_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	var in_table: bool = false
	var later: bool = false
	for line: String in FileAccess.get_file_as_string(DOC).split("\n"):
		if line.begins_with("## "):
			later = line.begins_with("## Not yet")
			in_table = false
		elif line.begins_with("| Id |"):
			in_table = true
		elif in_table and line.begins_with("|---"):
			continue
		elif in_table and line.begins_with("|") and not later:
			var cells: PackedStringArray = line.split("|")
			ids.append(StringName(cells[1].strip_edges()))
	return ids
