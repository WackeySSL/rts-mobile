extends GdUnitTestSuite
## MenuFlow hands the local seat's faction (and the snapshot's facts) to the MatchSummary
## (ADR 0054 section 3, plan P673b), for a skirmish end and for a finished lesson.

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const SKIRMISH: String = "res://data/scenarios/skirmish_kestrel_flats.tres"
const DUMMY: String = "res://data/ai/dummy_renew.tres"
const LEVEL: String = "res://data/ai/difficulty/hard.tres"

var _flow: Node
var _mains: Array[Node] = []


func before_test() -> void:
	MenuRig.begin()
	_mains.clear()
	_flow = auto_free((load("res://game/ui/menu/menu_flow_service.gd") as GDScript).new())
	add_child(_flow)
	_flow.switch_to_main = _enter_main
	_flow.switch_to_menu = func() -> Error: return OK


func after_test() -> void:
	_flow.return_to_menu()
	for main: Node in _mains:
		if is_instance_valid(main):
			remove_child(main)
			main.free()
	MenuRig.end()


func _enter_main(main: Node) -> Error:
	_mains.append(main)
	add_child(main)
	return OK


func _setup(lesson: StringName = &"") -> MatchSetup:
	var setup: MatchSetup = MatchSetup.new()
	setup.scenario_path = SKIRMISH
	setup.opponents = [load(DUMMY) as AiDef]
	setup.opponent_levels = [load(LEVEL) as AiDifficultyDef]
	setup.lesson_id = lesson
	setup.match_seed = 4242
	return setup


func test_an_ended_match_carries_the_local_seats_faction() -> void:
	await _flow.start_match(_setup())
	var scenario: ScenarioDef = _flow.current_setup().scenario()
	CommandQueue.submit(Command.surrender(scenario.local_player))
	_flow.current_runner().run_ticks(1)
	var summary: MatchSummary = _flow.last_summary()
	assert_str(summary.faction).is_equal(scenario.factions[scenario.local_player].id)
	assert_str(summary.faction).is_equal("fossil")
	assert_array(summary.standing_types).contains([&"headquarters"])


func test_a_finished_lesson_carries_the_faction_and_the_standing_types() -> void:
	await _flow.start_match(_setup(&"basics"))
	var scored: Array[MatchSummary] = []
	_flow.match_scored.connect(
		func(summary: MatchSummary, _a: XpAward) -> void: scored.append(summary)
	)
	await _flow.finish_lesson()
	assert_int(scored.size()).is_equal(1)
	var summary: MatchSummary = scored[0]
	assert_str(summary.outcome).is_equal(MatchSummary.OUTCOME_WIN)
	assert_str(summary.faction).is_equal("fossil")
	assert_array(summary.standing_types).contains([&"headquarters"])
