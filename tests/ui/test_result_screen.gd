extends GdUnitTestSuite
## The result screen (plan P90, ADR 0019 section 6): when the runner emits `match_ended` it covers
## the HUD with Victory, Defeat or Draw as an emblem and a word, the match time and the per-player
## stats of the published snapshot. At the six test sizes and on the phone browsers its panel, its
## emblem and its two buttons lie inside the safe rect, the buttons are at least 48 dp each way (64
## dp high), and the panel fits without a scroll. "Play again" opens a new main scene of the same
## scenario and opponents, "Back" the dev menu. The Surrender button that leads here is
## test_surrender's, the wheel and the fingers already down under the screen are
## test_modal_input's, the routes are test_skirmish_routes'.

const MatchRig: GDScript = preload("res://tests/ui/support/match_rig.gd")
const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const MIN_DP: float = 48.0
const BUTTON_DP: float = 64.0
const TOLERANCE_PX: float = 0.5
## Open ground at 1280x720, left of the panel and clear of the Dev button and the group column.
const GROUND_POINT: Vector2 = Vector2(80, 300)
## Each outcome: who surrenders, the word, the emblem file and the theme colour of its tint.
const OUTCOMES: Array[Array] = [
	[[1], "DEFEAT", "glyph_defeat", &"defeat"],
	[[2], "VICTORY", "glyph_victory", &"victory"],
	[[1, 2], "DRAW", "glyph_draw", &"draw"],
]

var _window_size_before: Vector2i
var _main: Node


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	MenuRig.begin()


## The override and the queue are static state: leaving them changes every later suite.
func after_test() -> void:
	MenuRig.end()
	UiScale.clear_override()
	CommandQueue.clear()
	var tree: SceneTree = get_tree()
	if tree.current_scene != null:
		tree.current_scene.free()
		tree.current_scene = null


func test_the_screen_is_hidden_while_the_match_runs_and_covers_the_hud_when_it_ends() -> void:
	_main = auto_free(await MatchRig.open(self))
	var screen: ResultScreen = _screen()
	assert_bool(screen.visible).is_false()
	(_main.get_node("MatchRunner") as MatchRunner).run_ticks(30)
	assert_bool(screen.visible).is_false()
	MatchRig.end(_main, [1])
	assert_bool(screen.visible).is_true()
	assert_bool(screen.get_rect().is_equal_approx(get_viewport().get_visible_rect())).is_true()
	var hud: Node = _main.get_node("Hud")
	assert_int(hud.get_children().find(screen)).is_equal(hud.get_child_count() - 1)  # On top.


func test_each_outcome_shows_its_word_and_its_emblem_in_its_colour() -> void:
	for outcome: Array in OUTCOMES:
		_main = await MatchRig.open(self)
		var surrenderers: Array[int] = []
		surrenderers.assign(outcome[0])
		MatchRig.end(_main, surrenderers)
		var screen: ResultScreen = _screen()
		var runner: MatchRunner = _main.get_node("MatchRunner")
		var label: String = str(outcome[1])
		assert_int(runner.snapshot.winner).override_failure_message(label).is_equal(
			0 if surrenderers.size() == 2 else 3 - surrenderers[0]
		)
		assert_str(_title(screen).text).override_failure_message(label).is_equal(outcome[1])
		var emblem: TextureRect = _emblem(screen)
		assert_str(emblem.texture.resource_path).override_failure_message(label).ends_with(
			"%s.svg" % outcome[2]
		)
		assert_that(emblem.modulate).override_failure_message(label).is_equal(
			screen.get_theme_color(outcome[3], &"ResultScreen")
		)
		_main.free()
		CommandQueue.clear()
		await await_idle_frame()


## The three tints are the ones STYLE.md gives the glyphs, and differ, so the emblem's shape and the
## word are not the only things that tell the outcomes apart; neither is the colour alone.
func test_the_emblem_tints_are_the_style_guides_and_differ() -> void:
	_main = auto_free(await MatchRig.open(self))
	var screen: ResultScreen = _screen()
	var tints: Dictionary[StringName, Color] = {
		&"victory": Color("30A46C"), &"defeat": Color("E5484D"), &"draw": Color("9AA5B1")
	}
	for tint_name: StringName in tints:
		var got: Color = screen.get_theme_color(tint_name, &"ResultScreen")
		assert_str(got.to_html(false)).is_equal(tints[tint_name].to_html(false))


func test_the_time_and_the_stats_are_the_published_snapshots() -> void:
	_main = auto_free(await MatchRig.open(self))
	var runner: MatchRunner = _main.get_node("MatchRunner")
	runner.run_ticks(44)
	runner.world.stat_built[1] = 12
	runner.world.stat_lost_units[1] = 3
	runner.world.stat_lost_buildings[1] = 1
	runner.world.stat_harvested[1] = 4500
	runner.world.stat_built[2] = 7
	runner.world.stat_lost_units[2] = 9
	runner.world.stat_lost_buildings[2] = 2
	runner.world.stat_harvested[2] = 1250
	MatchRig.end(_main, [1])
	var screen: ResultScreen = _screen()
	assert_int(runner.snapshot.match_end_tick / Sim.TICK_RATE).is_equal(3)
	assert_str(_time(screen).text).is_equal("Match time 0:03")
	var grid: GridContainer = _grid(screen)
	assert_int(grid.columns).is_equal(3)  # The names, then one column per player.
	(
		assert_array(_texts(grid))
		. is_equal(
			[
				"",
				"You",
				"Enemy",
				"Units built",
				"12",
				"7",
				"Units lost",
				"3",
				"9",
				"Buildings lost",
				"1",
				"2",
				"Credits harvested",
				"4500",
				"1250",
			]
		)
	)


## "You" is the player the scenario names, whichever it is: with player 2 local, player 1's
## surrender is a victory and the column of player 2 is the one headed "You".
func test_the_local_player_is_the_one_the_scenario_names() -> void:
	for case: Array in [[1, "VICTORY", ["", "Enemy", "You"]], [2, "DEFEAT", ["", "Enemy", "You"]]]:
		_main = auto_free(await MatchRig.open(self, MatchRig.DERRICK, 2))
		var runner: MatchRunner = _main.get_node("MatchRunner")
		runner.world.stat_built[1] = 5
		runner.world.stat_built[2] = 9
		MatchRig.end(_main, [case[0]])
		var texts: Array[String] = _texts(_grid(_screen()))
		assert_str(_title(_screen()).text).override_failure_message(str(case)).is_equal(case[1])
		assert_array(texts.slice(0, 3)).is_equal(case[2])
		assert_array(texts.slice(3, 6)).is_equal(["Units built", "5", "9"])
		_main.free()
		CommandQueue.clear()
		await await_idle_frame()


## A long match shows minutes: 61 s is 1:01.
func test_a_match_of_over_a_minute_shows_minutes_and_seconds() -> void:
	_main = auto_free(await MatchRig.open(self))
	var runner: MatchRunner = _main.get_node("MatchRunner")
	runner.run_ticks(61 * Sim.TICK_RATE - 1 - runner.snapshot.tick)  # The frames played some.
	MatchRig.end(_main, [2])
	assert_int(runner.snapshot.match_end_tick).is_equal(61 * Sim.TICK_RATE)
	assert_str(_time(_screen()).text).is_equal("Match time 1:01")


func test_the_panel_and_the_buttons_fit_the_six_sizes() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		get_window().size = size
		await await_idle_frame()
		_main = await MatchRig.open(self)
		MatchRig.end(_main, [1])
		await await_idle_frame()
		_check_layout(_screen(), str(size))
		_main.free()
		CommandQueue.clear()
		await await_idle_frame()


## The phone browsers and the cutouts: the panel fits sideways in the 331 dp of a phone browser
## without a scroll (the banner and the table stand side by side), and upright in 360 dp.
func test_the_phone_browsers_and_the_cutouts_keep_everything_inside_without_a_scroll() -> void:
	var landscape: UiMetrics = UiProfiles.by_name(&"android_6in")
	var portrait: UiMetrics = UiProfiles.by_name(&"android_6in_portrait")
	var cases: Dictionary[String, UiMetrics] = {
		"web_phone": UiProfiles.by_name(&"web_phone"),
		"web_phone_small": UiProfiles.by_name(&"web_phone_small"),
		"web_phone_portrait": UiProfiles.by_name(&"web_phone_portrait"),
		"landscape cutout": UiProfiles.with_safe_area(landscape, Rect2i(152, 0, 2248, 1080)),
		"portrait cutout": UiProfiles.with_safe_area(portrait, Rect2i(0, 100, 1080, 2237)),
	}
	for label: String in cases:
		UiScale.set_override(cases[label])
		get_window().size = cases[label].window_size
		await await_idle_frame()
		_main = await MatchRig.open(self)
		MatchRig.end(_main, [1])
		await await_idle_frame()
		var screen: ResultScreen = _screen()
		_check_layout(screen, label)
		var scroll: ScrollContainer = _first(screen, "ScrollContainer") as ScrollContainer
		(
			assert_float(scroll.get_v_scroll_bar().max_value)
			. override_failure_message(label)
			. is_less_equal(scroll.get_v_scroll_bar().page + TOLERANCE_PX)
		)
		_main.free()
		CommandQueue.clear()
		UiScale.clear_override()
		await await_idle_frame()


## Sideways the banner and the table stand side by side, upright one above the other, and a turn
## of the window moves the screen between the two without a new match.
func test_the_body_follows_a_turn_of_the_window() -> void:
	get_window().size = ScreenSizes.LANDSCAPE[1]
	await await_idle_frame()
	_main = auto_free(await MatchRig.open(self))
	MatchRig.end(_main, [1])
	var screen: ResultScreen = _screen()
	for size: Vector2i in [
		ScreenSizes.LANDSCAPE[1], ScreenSizes.PORTRAIT[1], ScreenSizes.LANDSCAPE[1]
	]:
		get_window().size = size
		await await_idle_frame()
		await await_idle_frame()
		var body: BoxContainer = _grid(screen).get_parent() as BoxContainer
		assert_bool(body.vertical).override_failure_message(str(size)).is_equal(size.y > size.x)
		assert_bool(screen.visible).is_true()
		var banner: Rect2 = body.get_child(0).get_global_rect()
		var table: Rect2 = _grid(screen).get_global_rect()
		if size.y > size.x:
			assert_float(table.position.y).is_greater_equal(banner.end.y - TOLERANCE_PX)
		else:
			assert_float(table.position.x).is_greater_equal(banner.end.x - TOLERANCE_PX)


## The screen takes every touch: with units selected, a tap on the ground orders nothing, and the
## HUD's Dev button under the screen does not press.
func test_a_tap_on_the_map_or_the_hud_under_the_screen_does_nothing() -> void:
	get_window().size = ScreenSizes.LANDSCAPE[0]
	await await_idle_frame()
	_main = auto_free(await MatchRig.open(self))
	var controller: PlayerController = _main.get_node("PlayerController")
	var sent: Array[Command] = []
	controller.command_sink = func(command: Command) -> void: sent.append(command)
	(_main.get_node("TouchInput") as TouchInput).clock = func() -> int: return 0
	controller.selection.set_ids(MatchRig.units_of(_main, 1))
	TouchEvents.press(get_viewport(), 0, GROUND_POINT)  # The control: the same tap moves them.
	TouchEvents.release(get_viewport(), 0, GROUND_POINT)
	await await_idle_frame()
	assert_array(sent).has_size(1)
	sent.clear()
	MatchRig.end(_main, [1])
	var dev: Button = _main.find_child("DevButton", true, false)
	var pressed: Array[int] = [0]
	dev.pressed.connect(func() -> void: pressed[0] += 1)
	for at: Vector2 in [GROUND_POINT, dev.get_global_rect().get_center()]:
		TouchEvents.press(get_viewport(), 0, at)
		TouchEvents.release(get_viewport(), 0, at)
		await await_idle_frame()
	assert_array(sent).is_empty()
	assert_int(pressed[0]).is_equal(0)


## Play again: a new main scene of the same scenario with the same dummy, a match of its own whose
## screen is hidden again.
func test_play_again_opens_a_new_match_of_the_same_scenario_and_opponents() -> void:
	for scenario_path: String in [MatchRig.DERRICK, MatchRig.LUMEN]:
		var tree: SceneTree = get_tree()
		var old: Node = await MatchRig.open(self, scenario_path)
		remove_child(old)
		tree.root.add_child(old)
		tree.current_scene = old
		MatchRig.end(old, [1])
		var old_runner: MatchRunner = old.get_node("MatchRunner")
		var dummy_id: StringName = old_runner.opponents[0].id
		var button: Button = _screen_of(old).find_child("PlayAgainButton", true, false)
		button.pressed.emit()
		await await_idle_frame()
		await await_idle_frame()
		var again: Node = tree.current_scene
		assert_bool(again != old).is_true()
		assert_str(again.scene_file_path).is_equal(DevRoutes.MAIN_SCENE)
		var runner: MatchRunner = again.get_node("MatchRunner")
		assert_str(runner.scenario.resource_path).is_equal(scenario_path)
		assert_int(runner.opponents.size()).is_equal(1)
		assert_str(str(runner.opponents[0].id)).is_equal(str(dummy_id))
		assert_int(runner.match_serial).is_equal(1)  # Its own, first match.
		assert_int(runner.snapshot.match_end_tick).is_equal(0)
		assert_bool(_screen_of(again).visible).is_false()
		again.free()
		tree.current_scene = null
		CommandQueue.clear()


func test_back_opens_the_dev_menu() -> void:
	var tree: SceneTree = get_tree()
	var old: Node = await MatchRig.open(self)
	remove_child(old)
	tree.root.add_child(old)
	tree.current_scene = old
	MatchRig.end(old, [2])
	(_screen_of(old).find_child("BackButton", true, false) as Button).pressed.emit()
	await await_idle_frame()
	await await_idle_frame()
	assert_str(tree.current_scene.scene_file_path).is_equal(DevRoutes.DEV_MENU_SCENE)


## No ad on the result screen (admob-policy): none of its scripts names an ad service, and the
## row leaves no hook for one.
func test_the_screen_has_no_ad_and_no_hook_for_one() -> void:
	for path: String in [
		"res://game/ui/ResultScreen.gd",
		"res://game/ui/ModalFrame.gd",
		"res://game/ui/ConfirmDialog.gd"
	]:
		var text: String = FileAccess.get_file_as_string(path).to_lower()
		for word: String in ["adservice", "admob", "interstitial", "rewarded"]:
			(
				assert_bool(text.contains(word))
				. override_failure_message("%s: %s" % [path, word])
				. is_false()
			)


## The screen's panel, emblem and buttons inside the safe rect, the buttons at least 48 dp each way
## and 64 dp high, the two apart, and the text at 14 sp or more.
func _check_layout(screen: ResultScreen, label: String) -> void:
	var safe: Rect2 = UiScale.safe_rect_base()
	var floor_px: float = UiScale.dp(MIN_DP) - TOLERANCE_PX
	var panel: Rect2 = screen.column.get_parent().get_global_rect()
	assert_bool(screen.visible).override_failure_message(label).is_true()
	(
		assert_bool(safe.encloses(panel))
		. override_failure_message("%s: panel %s" % [label, panel])
		. is_true()
	)
	var rects: Array[Rect2] = []
	for button_name: String in ["PlayAgainButton", "BackButton"]:
		var button: Button = screen.find_child(button_name, true, false)
		var rect: Rect2 = button.get_global_rect()
		var where: String = "%s: %s %s" % [label, button_name, rect]
		(
			assert_bool(rect.size.x >= floor_px and rect.size.y >= floor_px)
			. override_failure_message(where)
			. is_true()
		)
		assert_float(rect.size.y).override_failure_message(where).is_greater_equal(
			UiScale.dp(BUTTON_DP) - TOLERANCE_PX
		)
		assert_bool(safe.encloses(rect)).override_failure_message(where).is_true()
		assert_bool(panel.encloses(rect)).override_failure_message(where).is_true()
		assert_int(button.get_theme_font_size("font_size")).is_greater_equal(
			roundi(UiScale.dp(14.0))
		)
		rects.append(rect)
	assert_bool(rects[0].intersects(rects[1])).override_failure_message(label).is_false()
	var emblem: Rect2 = _emblem(screen).get_global_rect()
	(
		assert_bool(safe.encloses(emblem))
		. override_failure_message("%s: emblem %s" % [label, emblem])
		. is_true()
	)
	assert_float(emblem.size.x).override_failure_message(label).is_greater_equal(floor_px)
	for cell: Node in _grid(screen).get_children():
		var rect: Rect2 = (cell as Control).get_global_rect()
		(
			assert_bool(safe.encloses(rect))
			. override_failure_message("%s: cell %s" % [label, rect])
			. is_true()
		)


func _screen() -> ResultScreen:
	return _screen_of(_main)


func _screen_of(main: Node) -> ResultScreen:
	return main.get_node("Hud/ResultScreen")


## The first node of class `type_name` below `screen`, in tree order.
func _first(screen: Node, type_name: String) -> Node:
	var found: Array[Node] = screen.find_children("*", type_name, true, false)
	return found[0] if not found.is_empty() else null


func _grid(screen: ResultScreen) -> GridContainer:
	return _first(screen, "GridContainer") as GridContainer


func _emblem(screen: ResultScreen) -> TextureRect:
	return _first(screen, "TextureRect") as TextureRect


## The title is the label beside the emblem: the first label of its row.
func _title(screen: ResultScreen) -> Label:
	return _emblem(screen).get_parent().get_child(1) as Label


## The time is the label under the title's row.
func _time(screen: ResultScreen) -> Label:
	return _emblem(screen).get_parent().get_parent().get_child(1) as Label


## The text of every cell of `grid`, in order.
func _texts(grid: GridContainer) -> Array[String]:
	var out: Array[String] = []
	for cell: Node in grid.get_children():
		out.append((cell as Label).text)
	return out
