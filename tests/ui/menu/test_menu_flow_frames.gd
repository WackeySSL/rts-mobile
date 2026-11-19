extends GdUnitTestSuite
## MenuFlow's wait for the loading card (plan P536): two process frames between `match_loading`
## and the scene (a start from a tap runs before its frame is drawn), and `match_start_finished`
## at the end of each start.

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const FLOW: GDScript = preload("res://game/ui/menu/menu_flow_service.gd")
const SKIRMISH: String = "res://data/scenarios/skirmish_kestrel_flats.tres"
const DUMMY: String = "res://data/ai/dummy_renew.tres"
const LEVEL: String = "res://data/ai/difficulty/hard.tres"


class FakeAds:
	extends Node

	func take_start_credits_bonus() -> int:
		return 0

	func note_match_completed(_seconds: int) -> void:
		pass

	func settle_fullscreen() -> void:
		pass

	func maybe_show_interstitial(_placement: StringName) -> bool:
		return true


var _flow: Node
var _mains: Array[Node] = []


func before_test() -> void:
	MenuRig.begin()
	_mains.clear()
	var ads: FakeAds = auto_free(FakeAds.new())
	add_child(ads)
	_flow = auto_free(FLOW.new())
	add_child(_flow)
	_flow.ads = ads
	_flow.switch_to_main = _enter_main
	_flow.switch_to_menu = func() -> Error: return OK


func after_test() -> void:
	_flow.return_to_menu()
	for main: Node in _mains:
		if is_instance_valid(main):
			main.free()
	MenuRig.end()


func _enter_main(main: Node) -> Error:
	_mains.append(main)
	add_child(main)
	return OK


func _setup() -> MatchSetup:
	var setup: MatchSetup = MatchSetup.new()
	setup.scenario_path = SKIRMISH
	var opponents: Array[AiDef] = [load(DUMMY) as AiDef]
	setup.opponents = opponents
	var levels: Array[AiDifficultyDef] = [load(LEVEL) as AiDifficultyDef]
	setup.opponent_levels = levels
	return setup


func test_two_process_frames_pass_between_match_loading_and_the_scene() -> void:
	var frames: Array[int] = []
	_flow.match_loading.connect(
		func(_s: MatchSetup) -> void: frames.append(Engine.get_process_frames())
	)
	_flow.switch_to_main = func(main: Node) -> Error:
		frames.append(Engine.get_process_frames())
		return _enter_main(main)
	assert_int(await _flow.start_match(_setup())).is_equal(OK)
	assert_int(frames.size()).is_equal(2)
	assert_int(frames[1] - frames[0]).is_greater_equal(2)


func test_match_start_finished_follows_each_way_a_start_ends() -> void:
	var seen: Array[int] = []
	_flow.match_start_finished.connect(func(error: int) -> void: seen.append(error))
	assert_int(await _flow.start_match(_setup())).is_equal(OK)
	assert_array(seen).is_equal([OK])
	_flow.return_to_menu()
	_flow.switch_to_main = func(main: Node) -> Error:
		add_child(main)  # MenuFlow frees it in the tree, which leaves no orphans.
		return ERR_CANT_CREATE
	assert_int(await _flow.start_match(_setup())).is_equal(ERR_CANT_CREATE)
	assert_array(seen).is_equal([OK, ERR_CANT_CREATE])
