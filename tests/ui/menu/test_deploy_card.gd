extends GdUnitTestSuite
## The deploy card (plan P536): it shows on MenuFlow's `match_loading`, names the map, covers the
## start and goes away when the match is ready or the start failed. A fake flow stands in for
## MenuFlow where the order of the frames is the point; a real MenuFlow covers the failure.

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const SKIRMISH: String = "res://data/scenarios/skirmish_kestrel_flats.tres"
const DUMMY: String = "res://data/ai/dummy_renew.tres"
const LEVEL: String = "res://data/ai/difficulty/hard.tres"
const MAP_ID: StringName = &"kestrel_flats"
const TOLERANCE_PX: float = 0.5
const FLOW: GDScript = preload("res://game/ui/menu/menu_flow_service.gd")


class FakeFlow:
	extends Node
	signal match_loading(setup: MatchSetup)
	signal match_start_finished(error: Error)
	var runner: MatchRunner = null

	func current_runner() -> MatchRunner:
		return runner if is_instance_valid(runner) else null


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


var _window_size_before: Vector2i
var _card: DeployCard
var _fake: FakeFlow


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	MenuRig.begin()
	_fake = auto_free(FakeFlow.new())
	add_child(_fake)
	_card = _make_card(_fake)


func after_test() -> void:
	UiScale.clear_override()
	MenuRig.end()


func _make_card(flow: Node) -> DeployCard:
	var card: DeployCard = auto_free(DeployCard.new())
	add_child(card)
	card.attach(flow)
	return card


func _setup(map_id: StringName = MAP_ID) -> MatchSetup:
	var setup: MatchSetup = MatchSetup.new()
	setup.scenario_path = SKIRMISH
	var opponents: Array[AiDef] = [load(DUMMY) as AiDef]
	setup.opponents = opponents
	var levels: Array[AiDifficultyDef] = [load(LEVEL) as AiDifficultyDef]
	setup.opponent_levels = levels
	setup.map_id = map_id
	return setup


func _frames(count: int) -> void:
	for _i: int in count:
		await await_idle_frame()


func _runner_in_tree() -> MatchRunner:
	var runner: MatchRunner = auto_free(MatchRunner.new())
	add_child(runner)
	return runner


func test_it_is_hidden_until_the_signal_and_names_the_map() -> void:
	assert_bool(_card.is_showing()).is_false()
	await _frames(3)
	assert_bool(_card.is_showing()).is_false()
	_fake.match_loading.emit(_setup())
	assert_bool(_card.is_showing()).is_true()
	assert_str(_card.map_name()).is_equal("KESTREL FLATS")


func test_a_setup_without_a_map_shows_the_card_with_no_name() -> void:
	_fake.match_loading.emit(_setup(&""))
	assert_bool(_card.is_showing()).is_true()
	assert_str(_card.map_name()).is_equal("")


func test_a_late_signal_shows_the_card_whenever_it_comes() -> void:
	# A row may await before it emits: the card has no clock of its own before the signal.
	await _frames(10)
	_fake.match_loading.emit(_setup())
	assert_bool(_card.is_showing()).is_true()
	await _frames(1)
	assert_bool(_card.is_showing()).is_true()


func test_it_goes_when_the_new_match_stands_in_the_tree() -> void:
	_fake.match_loading.emit(_setup())
	await _frames(1)
	assert_bool(_card.is_showing()).is_true()
	_fake.runner = _runner_in_tree()
	await _frames(1)
	assert_bool(_card.is_showing()).override_failure_message("hid before the start ended").is_true()
	_fake.match_start_finished.emit(OK)
	await _frames(1)
	assert_bool(_card.is_showing()).is_false()


func test_a_restart_does_not_mistake_the_old_match_for_the_new_one() -> void:
	_fake.runner = _runner_in_tree()  # The match that is being replaced.
	_fake.match_loading.emit(_setup())
	await _frames(1)
	assert_bool(_card.is_showing()).is_true()
	_fake.match_start_finished.emit(OK)
	await _frames(1)
	assert_bool(_card.is_showing()).override_failure_message("the old match ended it").is_true()
	_fake.runner = _runner_in_tree()
	await _frames(1)
	assert_bool(_card.is_showing()).is_false()


func test_an_error_hides_the_card_at_once() -> void:
	_fake.match_loading.emit(_setup())
	_fake.match_start_finished.emit(ERR_CANT_CREATE)
	assert_bool(_card.is_showing()).is_false()


func test_the_backstop_hides_a_card_whose_start_never_ends() -> void:
	_fake.match_loading.emit(_setup())
	await _frames(DeployCard.HARD_FRAMES + 2)
	assert_bool(_card.is_showing()).is_false()


func test_a_paused_tree_does_not_freeze_the_card() -> void:
	assert_int(_card.process_mode).is_equal(Node.PROCESS_MODE_ALWAYS)


func test_a_failed_start_through_the_real_menu_flow_clears_the_card() -> void:
	var flow: Node = auto_free(FLOW.new())
	add_child(flow)
	var ads: FakeAds = auto_free(FakeAds.new())
	add_child(ads)
	flow.ads = ads
	flow.switch_to_main = func(main: Node) -> Error:
		add_child(main)  # MenuFlow frees it in the tree, which leaves no orphans.
		return ERR_CANT_CREATE
	flow.switch_to_menu = func() -> Error: return OK
	var card: DeployCard = _make_card(flow)
	var shown: Array[bool] = []
	flow.match_loading.connect(func(_s: MatchSetup) -> void: shown.append(card.is_showing()))
	var error: Error = await flow.start_match(_setup())
	assert_int(error).is_equal(ERR_CANT_CREATE)
	assert_array(shown).is_equal([true])
	assert_bool(card.is_showing()).is_false()
	assert_object(flow.current_runner()).is_null()


func test_a_good_start_through_the_real_menu_flow_clears_the_card_when_the_match_is_in() -> void:
	var flow: Node = auto_free(FLOW.new())
	add_child(flow)
	var ads: FakeAds = auto_free(FakeAds.new())
	add_child(ads)
	flow.ads = ads
	var mains: Array[Node] = []
	flow.switch_to_main = func(main: Node) -> Error:
		mains.append(main)
		add_child(main)
		return OK
	flow.switch_to_menu = func() -> Error: return OK  # Never the real menu scene.
	var card: DeployCard = _make_card(flow)
	var inside: Array[bool] = []  # The card while the scene is handed over and while it enters.
	flow.switch_to_main = func(main: Node) -> Error:
		mains.append(main)
		inside.append(card.is_showing())
		var runner: MatchRunner = main.get_node("MatchRunner")
		runner.tree_entered.connect(func() -> void: inside.append(card.is_showing()))
		add_child(main)
		return OK
	assert_int(await flow.start_match(_setup())).is_equal(OK)
	assert_array(inside).is_equal([true, true])
	await _frames(2)
	assert_bool(card.is_showing()).is_false()
	flow.return_to_menu()
	for main: Node in mains:
		main.free()
	await _frames(2)


func test_the_card_covers_the_screen_inside_the_safe_area_at_the_six_sizes() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		var profile: UiMetrics = _profile_with_window(size)
		UiScale.set_override(profile)
		get_window().size = size
		await _frames(1)
		_fake.match_loading.emit(_setup())
		await _frames(1)
		var label: String = str(size)
		var root: Control = _card.get_node("Root") as Control
		var full: Rect2 = get_viewport().get_visible_rect()
		(
			assert_bool(root.get_global_rect().encloses(full.grow(-TOLERANCE_PX)))
			. override_failure_message(label)
			. is_true()
		)
		var box: Rect2 = _content_rect()
		(
			assert_bool(UiScale.safe_rect_base().grow(TOLERANCE_PX).encloses(box))
			. override_failure_message(label + " safe")
			. is_true()
		)
		assert_float(box.get_center().x).override_failure_message(label).is_equal_approx(
			full.get_center().x, 2.0
		)
		UiScale.clear_override()
		_fake.match_start_finished.emit(ERR_CANT_CREATE)


func test_it_takes_every_touch_and_has_no_ad_and_no_animation() -> void:
	var root: Control = _card.get_node("Root") as Control
	assert_int(root.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	assert_object(_card.find_child("*Ad*", true, false)).is_null()
	assert_int(_card.find_children("*", "AnimationPlayer", true, false).size()).is_equal(0)
	var tweens: int = get_tree().get_processed_tweens().size()
	_fake.match_loading.emit(_setup())
	await _frames(2)
	assert_int(get_tree().get_processed_tweens().size()).is_equal(tweens)


## The union of the icon and the labels: the visible content of the card.
func _content_rect() -> Rect2:
	var box: Rect2 = Rect2()
	var first: bool = true
	for node: Node in _card.find_children("*", "Control", true, false):
		if node is TextureRect or (node is Label and (node as Label).visible):
			var rect: Rect2 = (node as Control).get_global_rect()
			box = rect if first else box.merge(rect)
			first = false
	return box


func _profile_with_window(size: Vector2i) -> UiMetrics:
	for profiles: Dictionary[StringName, UiMetrics] in [UiProfiles.all(), UiProfiles.portrait()]:
		for profile_name: StringName in profiles:
			if profiles[profile_name].window_size == size:
				return profiles[profile_name]
	return null
