extends GdUnitTestSuite
## The Home order of the command bar (plan P244, ADR 0036 section 12) in the main scene at the six
## sizes of ScreenSizes.ALL: it shows only while an own aircraft is selected, beside Stop and at
## least 56 x 64 dp (the bar's order size), and one tap sends one REPAIR per airfield with the
## aircraft homed at it, with no aim; a tank alone has no Home. Own: light tank 1, fighter 2,
## bomber 3; enemy Headquarters 4 (it stands in for an airfield: any live row will do).

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const Rig: GDScript = preload("res://tests/view/support/building_rig.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const TANK: int = 1
const FIGHTER: int = 2
const BOMBER: int = 3
const FIELD: int = 4
const SPAWNS: Array[Array] = [
	[1, "light_tank", 14, 14],
	[1, "fossil_fighter", 10, 10],
	[1, "fossil_bomber", 12, 10],
	[2, "renew_hq", 20, 20],
]

var _window_size_before: Vector2i
var _main: Node2D
var _controller: PlayerController
var _bar: CommandBar
var _runner: MatchRunner
var _sent: Array[Command] = []


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	MenuRig.begin()


func after_test() -> void:
	MenuRig.end()
	UiScale.clear_override()
	CommandQueue.clear()


func test_home_shows_only_with_an_own_aircraft_selected_and_is_a_full_size_order() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size)
		var why: String = str(size)
		await _select([TANK])
		assert_bool(_home().visible).override_failure_message(why).is_false()
		assert_bool(_stop().visible).is_true()
		await _select([TANK, FIGHTER])
		assert_bool(_home().is_visible_in_tree()).override_failure_message(why).is_true()
		var rect: Rect2 = _home().get_global_rect()
		assert_float(rect.size.x).override_failure_message(why).is_greater_equal(
			UiScale.dp(56.0) - 0.5
		)
		assert_float(rect.size.y).override_failure_message(why).is_greater_equal(
			UiScale.dp(64.0) - 0.5
		)
		assert_bool(_home().get_index() > _stop().get_index()).is_true()
		var safe: Rect2 = SafeAreaMargin.rect_inside(get_viewport().get_visible_rect(), 0.0)
		(
			assert_bool(safe.encloses(rect) or _bar_scrolls(rect))
			. override_failure_message("%s %s" % [why, rect])
			. is_true()
		)
		await _select([])
		assert_bool(_home().visible).is_false()


func test_a_tap_on_home_sends_one_repair_per_airfield_and_keeps_the_selection() -> void:
	for size: Vector2i in [ScreenSizes.ALL[1], ScreenSizes.ALL[4]]:
		await _open(size)
		var snap: MatchSnapshot = _runner.snapshot
		snap.home[snap.index_of(FIGHTER)] = FIELD
		snap.home[snap.index_of(BOMBER)] = FIELD
		await _select([FIGHTER, BOMBER, TANK])
		_tap(_home())
		var why: String = str(size)
		assert_int(_sent.size()).override_failure_message(why).is_equal(1)
		assert_int(_sent[0].type).is_equal(Command.Type.REPAIR)
		assert_int(_sent[0].target_id).is_equal(FIELD)
		assert_array(_sent[0].unit_ids).is_equal([FIGHTER, BOMBER])
		assert_array(_controller.selection.selected).is_equal([TANK, FIGHTER, BOMBER])


func _stop() -> Button:
	return _bar.order_button(&"stop")


func _home() -> Button:
	return _bar.order_button(&"home")


## Whether the bar's order scroll holds the button (it scrolls sideways when the orders overflow).
func _bar_scrolls(rect: Rect2) -> bool:
	return _bar.get_global_rect().intersects(rect)


func _select(ids: Array) -> void:
	_controller.selection.set_ids(PackedInt32Array(ids))
	await await_idle_frame()  # The bar publishes its slot on a deferred call, then places.
	await await_idle_frame()


func _tap(control: Control) -> void:
	var at: Vector2 = control.get_global_rect().get_center()
	TouchEvents.press(get_viewport(), 0, at)
	TouchEvents.release(get_viewport(), 0, at)


func _open(size: Vector2i) -> void:
	if _main != null and is_instance_valid(_main):
		remove_child(_main)
		_main.free()
	UiScale.clear_override()
	get_window().size = size
	await await_idle_frame()
	_main = auto_free((load("res://scenes/main.tscn") as PackedScene).instantiate())
	var spawns: Array[SpawnDef] = []
	for entry: Array in SPAWNS:
		spawns.append(Rig.spawn(entry[0], entry[1], entry[2], entry[3]))
	_runner = _main.get_node("MatchRunner")
	_runner.scenario = Rig.scenario(spawns)
	_runner.paused = true
	add_child(_main)
	await await_idle_frame()
	_controller = _main.get_node("PlayerController")
	_bar = _main.get_node("Hud").find_child("CommandBar", true, false) as CommandBar
	_sent.clear()
	_controller.command_sink = func(command: Command) -> void: _sent.append(command)
	await await_idle_frame()
