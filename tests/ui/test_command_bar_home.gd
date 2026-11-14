extends GdUnitTestSuite
## The Home order of the command bar (plan P244, ADR 0036 section 12) in the main scene at the six
## sizes of ScreenSizes.ALL: it shows only while an own aircraft is selected, beside Stop and at
## least 56 x 64 dp (the bar's order size), and one tap sends one REPAIR per airfield with the
## aircraft homed at it, with no aim; a tank alone, a drone squad (which flies low and is no REPAIR
## row) and aircraft with no airfield of the player's have no Home, because a button that does
## nothing never shows. The layout also runs on every UiProfiles profile, sideways, upright and
## with the notch design's insets, and the button is whole or a half-cut cue in the scroll.
## Own: light tank 1, fighter 2, bomber 3, airfield 4, drone squad 5; enemy Headquarters 6.

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const Rig: GDScript = preload("res://tests/view/support/building_rig.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const TANK: int = 1
const FIGHTER: int = 2
const BOMBER: int = 3
const FIELD: int = 4
const DRONE: int = 5
const ENEMY_HQ: int = 6
const SPAWNS: Array[Array] = [
	[1, "light_tank", 14, 14],
	[1, "fossil_fighter", 10, 10],
	[1, "fossil_bomber", 12, 10],
	[1, "fossil_airfield", 6, 6],
	[1, "fossil_drone", 16, 10],
	[2, "renew_hq", 20, 20],
]

var _window_size_before: Vector2i
var _main: Node2D
var _controller: PlayerController
var _bar: CommandBar
var _runner: MatchRunner
var _sent: Array[Command] = []
var _buzzes: int = 0


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


func test_home_shows_only_while_a_selected_aircraft_can_go_and_is_a_full_size_order() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size, null)
		var why: String = str(size)
		_home_at([FIGHTER, BOMBER], FIELD)
		await _select([TANK])
		assert_bool(_home().visible).override_failure_message(why).is_false()
		assert_bool(_stop().visible).is_true()
		await _select([TANK, FIGHTER])
		assert_bool(_home().is_visible_in_tree()).override_failure_message(why).is_true()
		_assert_whole_or_cue(why)
		(
			assert_bool(
				(
					_home().get_global_rect().position.x > _stop().get_global_rect().position.x
					or (_bar.mirror)
				)
			)
			. override_failure_message(why)
			. is_true()
		)
		await _select([])
		assert_bool(_home().visible).is_false()


func test_home_never_shows_where_it_would_do_nothing() -> void:
	await _open(ScreenSizes.ALL[0], null)
	_home_at([FIGHTER], 0)  # No airfield.
	await _select([FIGHTER])
	assert_bool(_home().visible).is_false()
	_home_at([DRONE], FIELD)  # A drone squad flies low: no REPAIR row, whatever its home.
	await _select([DRONE])
	assert_bool(_home().visible).is_false()
	_home_at([FIGHTER], ENEMY_HQ)  # An airfield that is not the player's.
	await _select([FIGHTER])
	assert_bool(_home().visible).is_false()
	_home_at([FIGHTER], FIELD)
	await _select([DRONE, FIGHTER])  # One that can go is enough, and Home sends only its rows.
	assert_bool(_home().visible).is_true()
	_home_at([FIGHTER], 0)  # The airfield is gone at the next tick.
	_runner.ticked.emit(1)
	await await_idle_frame()
	assert_bool(_home().visible).is_false()


func test_home_is_whole_or_a_cut_cue_in_the_bar_on_every_profile() -> void:
	var profiles: Array[UiMetrics] = []
	profiles.append_array(UiProfiles.all().values())
	profiles.append_array(UiProfiles.portrait().values())
	profiles.append_array(UiProfiles.notch_design().values())
	for metrics: UiMetrics in profiles:
		await _open(metrics.window_size, metrics)
		_home_at([FIGHTER], FIELD)
		await _select([FIGHTER])
		var why: String = "%s %s" % [metrics.os_name, metrics.window_size]
		assert_bool(_home().is_visible_in_tree()).override_failure_message(why).is_true()
		_assert_whole_or_cue(why)


func test_a_tap_on_home_sends_one_repair_per_airfield_buzzes_and_keeps_the_selection() -> void:
	for size: Vector2i in [ScreenSizes.ALL[1], ScreenSizes.ALL[4]]:
		await _open(size, null)
		_home_at([FIGHTER, BOMBER], FIELD)
		await _select([FIGHTER, BOMBER, TANK, DRONE])
		_tap(_home())
		var why: String = str(size)
		assert_int(_sent.size()).override_failure_message(why).is_equal(1)
		assert_int(_sent[0].type).is_equal(Command.Type.REPAIR)
		assert_int(_sent[0].target_id).is_equal(FIELD)
		assert_array(_sent[0].unit_ids).is_equal([FIGHTER, BOMBER])
		assert_array(_controller.selection.selected).is_equal([TANK, FIGHTER, BOMBER, DRONE])
		assert_int(_buzzes).override_failure_message(why).is_equal(1)


func _stop() -> Button:
	return _bar.order_button(&"stop")


func _home() -> Button:
	return _bar.order_button(&"home")


## Home is 56 x 64 dp at least and inside the safe area; inside the order scroll, or cut by it with
## part of it showing (the scroll takes touches then: the rule's cue that the orders go on).
func _assert_whole_or_cue(why: String) -> void:
	var rect: Rect2 = _home().get_global_rect()
	assert_float(rect.size.x).override_failure_message(why).is_greater_equal(UiScale.dp(56.0) - 0.5)
	assert_float(rect.size.y).override_failure_message(why).is_greater_equal(UiScale.dp(64.0) - 0.5)
	var scroll: ScrollContainer = _bar.find_child("Orders", true, false) as ScrollContainer
	var clip: Rect2 = scroll.get_global_rect()
	var detail: String = "%s: home %s, orders %s" % [why, rect, clip]
	if not clip.grow(0.5).encloses(rect):
		assert_bool(clip.intersects(rect)).override_failure_message(detail).is_true()
		assert_int(scroll.mouse_filter).override_failure_message(detail).is_equal(
			Control.MOUSE_FILTER_PASS
		)
	var safe: Rect2 = SafeAreaMargin.rect_inside(get_viewport().get_visible_rect(), 0.0)
	assert_bool(safe.grow(0.5).encloses(clip)).override_failure_message(detail).is_true()


## Makes `field` the home of each aircraft of `ids` in the published snapshot.
func _home_at(ids: Array, field: int) -> void:
	for id: int in ids:
		_runner.snapshot.home[_runner.snapshot.index_of(id)] = field


func _select(ids: Array) -> void:
	_controller.selection.set_ids(PackedInt32Array(ids))
	await await_idle_frame()  # The bar publishes its slot on a deferred call, then places.
	await await_idle_frame()


func _tap(control: Control) -> void:
	var at: Vector2 = control.get_global_rect().get_center()
	TouchEvents.press(get_viewport(), 0, at)
	TouchEvents.release(get_viewport(), 0, at)


func _open(size: Vector2i, metrics: UiMetrics) -> void:
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
	_buzzes = 0
	_controller.vibrate = func(_ms: int) -> void: _buzzes += 1
	await await_idle_frame()
