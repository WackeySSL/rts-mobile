extends GdUnitTestSuite
## The Flight tab of the build drawer (plan P244, ADR 0036 section 2) in the main scene at the six
## sizes of ScreenSizes.ALL: there is none while the faction has no aircraft to build, so today's
## three tabs stay as they were; with a fighter in the roster it is a fourth tab of the drawer's
## tab size inside the drawer, a tap opens it and shows the fighter's card, and selecting an own
## airfield (which produces on it) opens it too. Own: Derrick League airfield 1 (a complete
## building) and fighter 2.

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const Rig: GDScript = preload("res://tests/view/support/building_rig.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const AIRFIELD: int = 1
const FIGHTER: int = 2

var _window_size_before: Vector2i
var _main: Node2D
var _sidebar: BuildSidebar


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	MenuRig.begin()


func after_test() -> void:
	MenuRig.end()
	UiScale.clear_override()


func test_there_is_no_flight_tab_while_the_faction_builds_no_aircraft() -> void:
	await _open(ScreenSizes.ALL[0], false)
	var tab: Button = _tab()
	assert_bool(tab.visible).is_false()
	assert_int(_sidebar.tab).is_equal(World.Tab.STRUCTURES)


func test_the_flight_tab_is_a_tab_of_the_drawer_at_every_size_and_shows_the_fighter() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size, true)
		var why: String = str(size)
		var tab: Button = _tab()
		assert_bool(tab.is_visible_in_tree()).override_failure_message(why).is_true()
		var rect: Rect2 = tab.get_global_rect()
		assert_float(rect.size.x).override_failure_message(why).is_greater_equal(
			UiScale.dp(48.0) - 0.5
		)
		assert_float(rect.size.y).override_failure_message(why).is_greater_equal(
			UiScale.dp(48.0) - 0.5
		)
		(
			assert_bool(_sidebar.get_global_rect().encloses(rect))
			. override_failure_message("%s %s in %s" % [why, rect, _sidebar.get_global_rect()])
			. is_true()
		)
		var safe: Rect2 = SafeAreaMargin.rect_inside(get_viewport().get_visible_rect(), 0.0)
		assert_bool(safe.encloses(rect)).override_failure_message(why).is_true()
		var icon: TextureRect = tab.find_child("Icon", true, false) as TextureRect
		assert_str(icon.texture.resource_path).is_equal("res://assets/art/svg/icons/tab_flight.svg")
		_tap(tab)
		await await_idle_frame()
		assert_int(_sidebar.tab).override_failure_message(why).is_equal(World.Tab.FLIGHT)
		assert_bool(tab.button_pressed).is_true()
		var shown: Array[String] = []
		for node: Node in _sidebar.find_children("Tile_*", "ItemTile", true, false):
			if (node as Control).is_visible_in_tree():
				shown.append(node.name)
		assert_array(shown).override_failure_message(why).is_equal(["Tile_fossil_fighter"])


func test_selecting_an_own_airfield_opens_the_flight_tab() -> void:
	await _open(ScreenSizes.ALL[3], true)
	assert_int(_sidebar.tab).is_equal(World.Tab.STRUCTURES)
	_sidebar.set_selected(PackedInt32Array([AIRFIELD]))
	assert_int(_sidebar.tab).is_equal(World.Tab.FLIGHT)
	assert_bool(_tab().visible).is_true()
	_sidebar.set_selected(PackedInt32Array([FIGHTER]))  # A unit leaves the open tab as it is.
	assert_int(_sidebar.tab).is_equal(World.Tab.FLIGHT)


func _tab() -> Button:
	return _main.get_node("Hud").find_child("TabFlight", true, false) as Button


func _tap(control: Control) -> void:
	var at: Vector2 = control.get_global_rect().get_center()
	TouchEvents.press(get_viewport(), 0, at)
	TouchEvents.release(get_viewport(), 0, at)


## A new main scene at `size`, its match paused; with `air` the roster holds the fighter.
func _open(size: Vector2i, air: bool) -> void:
	if _main != null and is_instance_valid(_main):
		remove_child(_main)
		_main.free()
	UiScale.clear_override()
	get_window().size = size
	await await_idle_frame()
	_main = auto_free((load("res://scenes/main.tscn") as PackedScene).instantiate())
	var spawns: Array[SpawnDef] = [Rig.spawn(1, "fossil_airfield", 8, 8)]
	if air:  # A type in the match, in the roster or not, is a card.
		spawns.append(Rig.spawn(1, "fossil_fighter", 12, 12))
	spawns.append(Rig.spawn(2, "renew_hq", 20, 20))
	var scenario: ScenarioDef = Rig.scenario(spawns)
	if air:
		scenario.roster.append(load("res://data/units/fossil_fighter.tres") as UnitDef)
	(_main.get_node("MatchRunner") as MatchRunner).scenario = scenario
	_main.get_node("MatchRunner").paused = true
	add_child(_main)
	await await_idle_frame()
	_sidebar = _main.get_node("Hud").find_child("BuildSidebar", true, false)
	_sidebar.open()
	await await_idle_frame()
	await await_idle_frame()
