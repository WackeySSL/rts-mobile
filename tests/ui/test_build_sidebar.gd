extends GdUnitTestSuite
## The build sidebar's tabs (plan P85, ADR 0019 section 1) in the main scene. Fingers are touches
## through the real GUI. The zone and the layout are in test_build_sidebar_layout.

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const ICONS: String = "res://assets/art/svg/icons/%s.svg"

var _window_size_before: Vector2i
var _main: Node2D
var _sidebar: BuildSidebar
var _controller: PlayerController
var _sent: Array[Command] = []


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


## The override is static state: leaving one behind changes every later suite.
func after_test() -> void:
	MenuRig.end()
	UiScale.clear_override()


## The menu's slide is off for the test (tests/support/menu_rig.gd).
func before_test() -> void:
	MenuRig.begin()


func test_the_structures_tab_is_open_and_a_tap_opens_another_and_tells_it() -> void:
	await _open()
	var opened: Array[int] = []
	_sidebar.tab_selected.connect(func(tab: int) -> void: opened.append(tab))
	assert_int(_sidebar.tab).is_equal(World.Tab.STRUCTURES)
	assert_array(_pressed()).is_equal([true, false, false])
	_tap("TabInfantry")
	assert_int(_sidebar.tab).is_equal(World.Tab.INFANTRY)
	assert_array(_pressed()).is_equal([false, true, false])
	_tap("TabInfantry")  # The open tab stays open, and nothing is told.
	assert_array(_pressed()).is_equal([false, true, false])
	_tap("TabVehicles")
	assert_array(_pressed()).is_equal([false, false, true])
	assert_array(opened).is_equal([World.Tab.INFANTRY, World.Tab.VEHICLES])
	_sidebar.select_tab(World.Tab.STRUCTURES)  # A building selection will do this.
	assert_array(_pressed()).is_equal([true, false, false])
	assert_array(opened).is_equal([World.Tab.INFANTRY, World.Tab.VEHICLES, World.Tab.STRUCTURES])
	for bad: int in [-1, World.TABS, 99]:
		_sidebar.select_tab(bad)
	assert_int(_sidebar.tab).is_equal(World.Tab.STRUCTURES)
	assert_array(opened).has_size(3)


func test_each_tab_has_its_icon_by_name_and_the_open_one_is_a_different_plate() -> void:
	await _open()
	var names: Array[String] = ["TabStructures", "TabInfantry", "TabVehicles"]
	var icons: Array[String] = ["tab_structures", "tab_infantry", "tab_vehicles"]
	for index: int in names.size():
		var button: Button = _node(names[index])
		assert_str(button.icon.resource_path).is_equal(ICONS % icons[index])
		assert_bool(button.toggle_mode).is_true()
		assert_int(button.focus_mode).is_equal(Control.FOCUS_NONE)
	var rest: StyleBoxFlat = _sidebar.get_theme_stylebox(&"normal", &"SidebarTab") as StyleBoxFlat
	var open: StyleBoxFlat = _sidebar.get_theme_stylebox(&"pressed", &"SidebarTab") as StyleBoxFlat
	assert_int(open.border_width_bottom).is_greater(rest.border_width_bottom)  # A shape, not a tint.
	assert_that(_sidebar.get_theme_color(&"icon_pressed_color", &"SidebarTab")).is_not_equal(
		_sidebar.get_theme_color(&"icon_normal_color", &"SidebarTab")
	)


## The sidebar sends no Command, and a finger on it never reaches the map: with units selected a
## tap on the ground orders them, and a tap anywhere on the sidebar does not.
func test_a_touch_on_the_sidebar_orders_nothing_and_a_touch_on_the_map_does() -> void:
	await _open()
	_controller.selection.set_ids(PackedInt32Array([1, 2]))
	_tap("TabVehicles")
	_tap("Items")
	_tap("Status")
	var padding: Vector2 = _sidebar.get_global_rect().position + Vector2(2.0, 2.0)
	TouchEvents.press(get_viewport(), 0, padding)  # The panel's own padding.
	TouchEvents.release(get_viewport(), 0, padding)
	assert_array(_sent).is_empty()
	assert_array(_controller.selection.selected).is_equal([1, 2])
	var ground: Vector2 = Vector2(300.0, 360.0)  # Clear of the sidebar, the units and the HUD.
	TouchEvents.press(get_viewport(), 0, ground)
	TouchEvents.release(get_viewport(), 0, ground)
	assert_array(_sent).has_size(1)


func _pressed() -> Array[bool]:
	var out: Array[bool] = []
	for node_name: String in ["TabStructures", "TabInfantry", "TabVehicles"]:
		out.append((_node(node_name) as Button).button_pressed)
	return out


## By name from the HUD: the status line is the pill's in landscape and the band's in portrait.
func _node(node_name: String) -> Node:
	return _main.get_node("Hud").find_child(node_name, true, false)


## A finger down and up in the middle of `node_name`.
func _tap(node_name: String) -> void:
	var at: Vector2 = (_node(node_name) as Control).get_global_rect().get_center()
	TouchEvents.press(get_viewport(), 0, at)
	TouchEvents.release(get_viewport(), 0, at)


## A new main scene on the 6-inch phone, with the Commands caught.
func _open() -> void:
	var metrics: UiMetrics = UiProfiles.by_name(&"android_6in")
	UiScale.set_override(metrics)
	get_window().size = metrics.window_size
	await await_idle_frame()
	_main = auto_free((load("res://scenes/main.tscn") as PackedScene).instantiate())
	add_child(_main)
	await await_idle_frame()
	_sidebar = _main.get_node("Hud").find_child("BuildSidebar", true, false)
	_controller = _main.get_node("PlayerController")
	_sent.clear()
	_controller.command_sink = func(command: Command) -> void: _sent.append(command)
