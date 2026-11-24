extends GdUnitTestSuite
## The command bar never runs under BUILD (plan row P581): at the six sizes of ScreenSizes.ALL,
## with a minelayer, a damaged tank a Weld Shed serves and a fighter that has an airfield selected
## (Stop, Home, Repair and Mine at once), and with every order of the bar forced on (the widest
## the bar can ever be), no button of the bar overlaps BUILD and all of them stand inside the safe
## area and the bar's rect, at least 48 dp each way; Stop is stacked above Clear.
## Own: Shot Truck 1 (a minelayer), light tank 2 (hurt), Weld Shed 3, fighter 4, airfield 5.

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const Rig: GDScript = preload("res://tests/view/support/building_rig.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const SPAWNS: Array[Array] = [
	[1, "fossil_shot_truck", 14, 14],
	[1, "light_tank", 15, 14],
	[1, "fossil_weld_shed", 16, 14],
	[1, "fossil_fighter", 10, 10],
	[1, "fossil_airfield", 6, 6],
]
const IDS: Array[int] = [1, 2, 4]

var _window_size_before: Vector2i
var _main: Node2D
var _controller: PlayerController
var _bar: CommandBar
var _runner: MatchRunner


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	MenuRig.begin()


func after_test() -> void:
	MenuRig.end()
	UiScale.clear_override()
	HudLayout.bottom_zone_dp = 0.0
	CommandQueue.clear()


## The six sizes at the default scale (null metrics), then every phone profile with its own dp.
func _cases() -> Array[Array]:
	var cases: Array[Array] = []
	for size: Vector2i in ScreenSizes.ALL:
		cases.append([size, null, str(size)])
	var profiles: Dictionary[StringName, UiMetrics] = {}
	profiles.merge(UiProfiles.all())
	profiles.merge(UiProfiles.portrait())
	profiles.merge(UiProfiles.notch_design())
	for name: StringName in profiles:
		var metrics: UiMetrics = profiles[name]
		cases.append([metrics.window_size, metrics, str(name)])
	return cases


func test_the_natural_selection_never_runs_under_build() -> void:
	for entry: Array in _cases():
		await _open(entry[0], entry[1])
		_runner.snapshot.hp[_runner.snapshot.index_of(2)] /= 2
		_runner.snapshot.home[_runner.snapshot.index_of(4)] = 5
		await _select(IDS)
		for id: String in ["stop", "home", "repair", "mine"]:
			(
				assert_bool(_bar.order_button(StringName(id)).is_visible_in_tree())
				. override_failure_message("%s %s" % [entry[2], id])
				. is_true()
			)
		_assert_clear(entry[2])


func test_every_order_forced_on_never_runs_under_build() -> void:
	for entry: Array in _cases():
		await _open(entry[0], entry[1])
		_runner.snapshot.hp[_runner.snapshot.index_of(2)] /= 2
		await _select(IDS)
		for order: Dictionary in CommandBar.ORDERS:
			if order["for"] != &"building":  # Mend and Sell show for a lone building only.
				_bar.order_button(order["id"]).visible = true
		await await_idle_frame()
		await await_idle_frame()
		_assert_clear(entry[2] + " all")


func test_stop_stands_above_clear_in_one_column() -> void:
	for entry: Array in _cases():
		await _open(entry[0], entry[1])
		await _select(IDS)
		var stop: Rect2 = _bar.order_button(&"stop").get_global_rect()
		var clear: Rect2 = _bar.find_child("Deselect", true, false).get_global_rect()
		var why: String = "%s stop %s clear %s" % [entry[2], stop, clear]
		assert_float(stop.end.y).override_failure_message(why).is_less_equal(clear.position.y + 0.5)
		(
			assert_float(absf(stop.position.x - clear.position.x))
			. override_failure_message(why)
			. is_less(1.0)
		)


## The chips and "+N" keep their own height on the bar's bottom line (P581, Michael's phone, a
## building's chip stood the full 106 dp beside 48 dp keys): with one building and with three unit
## types, each shown chip is no taller than `CHIP_H_DP` and ends where Clear ends.
func test_chips_keep_their_height_on_the_bottom_line() -> void:
	for entry: Array in _cases():
		await _open(entry[0], entry[1])
		for ids: Array in [[3], IDS]:
			await _select(ids)
			var clear: Rect2 = _bar.find_child("Deselect", true, false).get_global_rect()
			var shown: int = 0
			for child: Node in _bar.find_children("*", "PanelContainer", true, false):
				var chip: Control = child as Control
				if not (chip.name.begins_with("Chip") or chip.name == "More"):
					continue
				if not chip.is_visible_in_tree():
					continue
				shown += 1
				var rect: Rect2 = chip.get_global_rect()
				var why: String = "%s %s %s: %s clear %s" % [entry[2], ids, chip.name, rect, clear]
				assert_float(rect.size.y).override_failure_message(why).is_less_equal(
					UiScale.dp(CommandBar.CHIP_H_DP) + 0.5
				)
				(
					assert_float(absf(rect.end.y - clear.end.y))
					. override_failure_message(why)
					. is_less_equal(1.0)
				)
			assert_int(shown).override_failure_message("%s %s" % [entry[2], ids]).is_greater(0)


## The bar is short (64 dp) with no Stop and one row, tall (106 dp) with Stop or a second row.
func test_the_bar_is_short_without_stop_and_tall_with_stop_or_a_second_row() -> void:
	var wrapped: int = 0
	for entry: Array in _cases():
		await _open(entry[0], entry[1])
		var why: String = entry[2]
		await _select([3])  # The Weld Shed: CLEAR, Mend, Sell, no Stop.
		var orders: OrderFlow = _bar.find_child("Orders", true, false) as OrderFlow
		var tall: bool = orders.rows() > 1
		assert_float(_bar.size.y).override_failure_message(why + " building").is_equal_approx(
			UiScale.dp(HudCorners.BAR_DP.y if tall else HudCorners.BAR_SHORT_DP), 1.5
		)
		_assert_clear(why + " building")
		await _select([])
		await _select(IDS)  # Units: Stop shows.
		assert_float(_bar.size.y).override_failure_message(why + " units").is_equal_approx(
			UiScale.dp(HudCorners.BAR_DP.y), 1.5
		)
		_assert_clear(why + " units")
		await _select([3])
		for order: Dictionary in CommandBar.ORDERS:  # The five orders a selection can show at once.
			if order["id"] != &"stop":  # Mend and Sell hide: no selection shows them with these.
				_bar.order_button(order["id"]).visible = order["for"] != &"building"
		await await_idle_frame()
		await await_idle_frame()
		tall = orders.rows() > 1
		wrapped += 1 if tall else 0
		assert_float(_bar.size.y).override_failure_message(why + " forced").is_equal_approx(
			UiScale.dp(HudCorners.BAR_DP.y if tall else HudCorners.BAR_SHORT_DP), 1.5
		)
		_assert_clear(why + " forced")
	assert_int(wrapped).override_failure_message("no size wrapped the forced orders").is_greater(0)


func _assert_clear(why: String) -> void:
	var build: Control = _main.get_node("Hud").find_child("BuildButton", true, false)
	var build_rect: Rect2 = build.get_global_rect()
	var safe: Rect2 = SafeAreaMargin.rect_inside(get_viewport().get_visible_rect(), 0.0)
	var buttons: Array[Button] = [_bar.find_child("Deselect", true, false)]
	for order: Dictionary in CommandBar.ORDERS:
		buttons.append(_bar.order_button(order["id"]))
	for button: Button in buttons:
		if not button.is_visible_in_tree():
			continue
		var rect: Rect2 = button.get_global_rect()
		var detail: String = (
			"%s: %s %s build %s bar %s"
			% [why, button.name, rect, build_rect, _bar.get_global_rect()]
		)
		assert_bool(rect.intersects(build_rect)).override_failure_message(detail).is_false()
		assert_bool(safe.grow(0.5).encloses(rect)).override_failure_message(detail).is_true()
		(
			assert_bool(_bar.get_global_rect().grow(0.5).encloses(rect))
			. override_failure_message(detail)
			. is_true()
		)
		(
			assert_float(minf(rect.size.x, rect.size.y))
			. override_failure_message(detail)
			. is_greater_equal(UiScale.dp(48.0) - 0.5)
		)


func _select(ids: Array) -> void:
	_controller.selection.set_ids(PackedInt32Array(ids))
	await await_idle_frame()
	await await_idle_frame()


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
	await await_idle_frame()
