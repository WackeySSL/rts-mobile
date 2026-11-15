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
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
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
	await _open(ScreenSizes.ALL[0], [], null)
	assert_bool(_tab().visible).is_false()
	assert_int(_sidebar.tab).is_equal(World.Tab.STRUCTURES)
	# The other faction's aircraft in the match are not ours: still no tab.
	await _open(ScreenSizes.ALL[0], ["renew_fighter"], null)
	assert_bool(_tab().visible).is_false()
	await _open(ScreenSizes.ALL[0], ["fossil_fighter"], null)
	assert_bool(_tab().visible).is_true()


func test_the_flight_tab_is_a_tab_of_the_drawer_at_every_size_and_shows_the_fighter() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size, ["fossil_fighter", "renew_fighter"], null)  # Both factions' aircraft.
		await _assert_tabs(str(size))
		var tab: Button = _tab()
		var icon: TextureRect = tab.find_child("Icon", true, false) as TextureRect
		assert_str(icon.texture.resource_path).is_equal("res://assets/art/svg/icons/tab_flight.svg")
		_tap(tab)
		await await_idle_frame()
		assert_int(_sidebar.tab).override_failure_message(str(size)).is_equal(World.Tab.FLIGHT)
		assert_bool(tab.button_pressed).is_true()
		var shown: Array[String] = []
		for node: Node in _sidebar.find_children("Tile_*", "ItemTile", true, false):
			if (node as Control).is_visible_in_tree():
				shown.append(node.name)
		assert_array(shown).override_failure_message(str(size)).is_equal(["Tile_fossil_fighter"])
		await _assert_tabs(str(size))  # Another tab holds the name now.


## Four tabs on every profile (sideways, upright, the notch design): every visible tab is a 48 dp
## target inside the drawer and the safe area, and the name it shows lies inside it: the open
## tab's, with the others bare icons (`BuildSidebar._fit_tabs`).
func test_four_tabs_fit_every_profile_with_their_names_inside_them() -> void:
	var profiles: Array[UiMetrics] = []
	profiles.append_array(UiProfiles.all().values())
	profiles.append_array(UiProfiles.portrait().values())
	profiles.append_array(UiProfiles.notch_design().values())
	profiles.append(_phone_320())  # 296 dp of safe width: the narrowest phone that is supported.
	for metrics: UiMetrics in profiles:
		await _open(metrics.window_size, ["fossil_fighter"], metrics)
		for open: int in [World.Tab.STRUCTURES, World.Tab.VEHICLES, World.Tab.FLIGHT]:
			_sidebar.select_tab(open)
			await await_idle_frame()
			await _assert_tabs("%s %s tab %d" % [metrics.os_name, metrics.window_size, open])


## With room the names all show: no tab goes bare where four names fit (sideways on a 6-inch phone
## or a tablet), and the open tab alone keeps its name where they do not.
func test_names_show_wherever_the_row_fits_them() -> void:
	await _open(ScreenSizes.ALL[2], ["fossil_fighter"], null)  # The tablet.
	var bare: int = 0
	for label: Label in _sidebar.find_children("Name", "Label", true, false):
		if _tab_of(label).visible:  # The Research tab is not there: no upgrades.
			bare += 0 if label.is_visible_in_tree() else 1
	assert_int(bare).is_equal(0)
	await _open(_phone_320().window_size, ["fossil_fighter"], _phone_320())
	bare = 0
	for label: Label in _sidebar.find_children("Name", "Label", true, false):
		if _tab_of(label).visible:  # The Research tab is not there: no upgrades.
			bare += 0 if label.is_visible_in_tree() else 1
	assert_int(bare).is_equal(3)


func test_selecting_an_own_airfield_opens_the_flight_tab() -> void:
	await _open(ScreenSizes.ALL[3], ["fossil_fighter"], null)
	assert_int(_sidebar.tab).is_equal(World.Tab.STRUCTURES)
	_sidebar.set_selected(PackedInt32Array([AIRFIELD]))
	assert_int(_sidebar.tab).is_equal(World.Tab.FLIGHT)
	assert_bool(_tab().visible).is_true()
	_sidebar.set_selected(PackedInt32Array([FIGHTER]))  # A unit leaves the open tab as it is.
	assert_int(_sidebar.tab).is_equal(World.Tab.FLIGHT)


## The tab button a name label belongs to.
func _tab_of(label: Label) -> Button:
	return label.get_parent().get_parent() as Button


func _tab() -> Button:
	return _main.get_node("Hud").find_child("TabFlight", true, false) as Button


func _tap(control: Control) -> void:
	var at: Vector2 = control.get_global_rect().get_center()
	TouchEvents.press(get_viewport(), 0, at)
	TouchEvents.release(get_viewport(), 0, at)


## A 320 dp wide phone held upright, as `test_command_bar_chips` builds it.
func _phone_320() -> UiMetrics:
	var size: Vector2i = Vector2i(320, 640)
	var stretch: float = minf(size.x / 720.0, size.y / 1280.0)
	return UiMetrics.create("Linux", 96, 1.0, stretch, size, Rect2i())


## Every visible tab: at least 48 dp each way, in the drawer and the safe area, and its name, when
## it shows one, whole inside it; the close button in the drawer too.
func _assert_tabs(why: String) -> void:
	var drawer: Rect2 = _sidebar.get_global_rect()
	var safe: Rect2 = SafeAreaMargin.rect_inside(get_viewport().get_visible_rect(), 0.0)
	var named: int = 0
	for node: Node in _sidebar.find_children("Tab*", "Button", true, false):
		var tab: Button = node as Button
		if not tab.is_visible_in_tree():
			continue
		var rect: Rect2 = tab.get_global_rect()
		var at: String = "%s: %s %s in %s" % [why, tab.name, rect, drawer]
		assert_float(rect.size.x).override_failure_message(at).is_greater_equal(
			UiScale.dp(48.0) - 0.5
		)
		assert_float(rect.size.y).override_failure_message(at).is_greater_equal(
			UiScale.dp(48.0) - 0.5
		)
		assert_bool(drawer.grow(0.5).encloses(rect)).override_failure_message(at).is_true()
		assert_bool(safe.grow(0.5).encloses(rect)).override_failure_message(at).is_true()
		var label: Label = tab.find_child("Name", true, false) as Label
		if not label.visible:
			continue
		named += 1
		var font: Font = label.get_theme_font(&"font")
		var size: int = label.get_theme_font_size(&"font_size")
		var wide: float = font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x
		# The content stands inside the plate's border (`_apply_dp`), so the label's own width is
		# the room the name has, and it never reaches past the tab.
		var room: float = label.size.x
		(
			assert_bool(rect.grow(0.5).encloses(label.get_global_rect()))
			. override_failure_message(at)
			. is_true()
		)
		(
			assert_float(wide)
			. override_failure_message("%s name %s wide in %s" % [at, wide, room])
			. is_less_equal(room + 0.5)
		)
	assert_int(named).override_failure_message(why).is_greater(0)
	var close: Rect2 = _sidebar.find_child("Close", true, false).get_global_rect()
	var gone: String = "%s: close %s, drawer %s" % [why, close, drawer]
	assert_bool(drawer.grow(0.5).encloses(close)).override_failure_message(gone).is_true()
	assert_float(close.size.x).override_failure_message(gone).is_greater_equal(
		UiScale.dp(48.0) - 0.5
	)


## A new main scene at `size` (under `metrics` when given), its match paused; `units` are own
## units of the match whose types join the faction's list (an aircraft of the player's faction
## puts the Flight tab on the drawer).
func _open(size: Vector2i, units: Array[String], metrics: UiMetrics) -> void:
	if _main != null and is_instance_valid(_main):
		remove_child(_main)
		_main.free()
	if metrics != null:
		UiScale.set_override(metrics)
	else:
		UiScale.clear_override()
	get_window().size = size
	await await_idle_frame()
	_main = auto_free((load("res://scenes/main.tscn") as PackedScene).instantiate())
	var spawns: Array[SpawnDef] = [Rig.spawn(1, "fossil_airfield", 8, 8)]
	for unit: String in units:
		var owner_id: int = 2 if unit.begins_with("renew") else 1
		spawns.append(Rig.spawn(owner_id, unit, 12, 12))
	spawns.append(Rig.spawn(2, "renew_hq", 20, 20))
	(_main.get_node("MatchRunner") as MatchRunner).scenario = Rig.scenario(spawns)
	_main.get_node("MatchRunner").paused = true
	add_child(_main)
	await await_idle_frame()
	_sidebar = _main.get_node("Hud").find_child("BuildSidebar", true, false)
	_sidebar.open()
	await await_idle_frame()
	await await_idle_frame()
