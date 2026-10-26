extends GdUnitTestSuite
## What a finger does to the build sidebar's item tiles (plan P85b, ADR 0019 section 1), through the
## real GUI in the main scene: a tap on an available tile is one QUEUE of its type, a hold of
## `long_press_ms` on a tile with items queued is one CANCEL of the last of them, a tile that cannot
## take an item shakes and sends nothing, a drag in the row scrolls it and sends nothing, and a lone
## own producer that is selected opens the tab it builds. The orders also run in the sim, the way
## the player sends them. Time is a clock the suite owns, so a hold is `long_press_ms` of it and no
## real time passes.

const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const Sw: GDScript = preload("res://tests/ui/support/sidebar_world.gd")
const Rig: GDScript = preload("res://tests/sim/support/production_worlds.gd")
const BASE: Array[String] = [
	"headquarters", "power_plant", "barracks", "refinery", "vehicle_factory"
]

var _window_size_before: Vector2i
var _main: Node2D
var _runner: MatchRunner
var _sidebar: BuildSidebar
var _controller: PlayerController
var _sent: Array[Command] = []
var _buzzed: Array[int] = []
var _now_ms: int = 0
var _hold_ms: int = 0


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


## The override is static state: leaving one behind changes every later suite.
func after_test() -> void:
	UiScale.clear_override()
	HudLayout.bottom_zone_dp = 0.0


func test_a_tap_on_an_available_tile_is_one_queue_of_its_type_with_the_haptic() -> void:
	await _open(&"android_6in")
	var world: World = Sw.world()
	Sw.own(world, BASE)
	await _publish(world)
	_controller.selection.set_ids(PackedInt32Array([1]))  # A tap is no order for the selection.
	var expected: Array[int] = []
	for pick: Array in [
		[World.Tab.STRUCTURES, "power_plant"],
		[World.Tab.INFANTRY, "rifle_squad"],
		[World.Tab.INFANTRY, "rocket_squad"],
		[World.Tab.VEHICLES, "harvester"],
		[World.Tab.VEHICLES, "artillery"],
	]:
		_sidebar.select_tab(pick[0])
		await _settle()
		_tap(pick[1])
		expected.append(Sw.type_of(world, pick[1]))
		assert_int(_sent.size()).is_equal(expected.size())
		var command: Command = _sent[-1]
		assert_int(command.type).is_equal(Command.Type.QUEUE)
		assert_int(command.player_id).is_equal(1)
		assert_array(command.payload).is_equal([expected[-1]])
	assert_array(_buzzed).is_equal([15, 15, 15, 15, 15])
	assert_array(_controller.selection.selected).is_equal([1])
	var quiet: InputSettings = _controller.settings.duplicate() as InputSettings
	quiet.haptics_enabled = false  # The haptic can be turned off.
	_controller.settings = quiet
	_tap("artillery")
	assert_int(_sent.size()).is_equal(6)
	assert_array(_buzzed).has_size(5)


func test_a_hold_cancels_the_last_queued_item_of_the_tile_and_a_release_after_it_is_no_tap(
) -> void:
	await _open(&"android_6in")
	var world: World = Sw.world()
	Sw.own(world, BASE)
	Sw.enqueue(world, World.Tab.INFANTRY, ["rifle_squad", "rocket_squad", "rifle_squad"])
	Sw.enqueue(world, World.Tab.VEHICLES, ["light_tank", "harvester"])
	await _publish(world)
	_sidebar.select_tab(World.Tab.INFANTRY)
	await _settle()
	_hold("rifle_squad")
	assert_int(_sent.size()).is_equal(1)  # Not one QUEUE for the release.
	_assert_cancel(_sent[0], World.Tab.INFANTRY, 2)
	_hold("rocket_squad")
	_assert_cancel(_sent[1], World.Tab.INFANTRY, 1)
	_sidebar.select_tab(World.Tab.VEHICLES)
	await _settle()
	_hold("light_tank")
	_assert_cancel(_sent[2], World.Tab.VEHICLES, 0)
	_hold("harvester")
	_assert_cancel(_sent[3], World.Tab.VEHICLES, 1)
	assert_int(_sent.size()).is_equal(4)
	assert_array(_buzzed).is_equal([15, 15, 15, 15])
	for command: Command in _sent:
		assert_int(command.player_id).is_equal(1)


func test_a_hold_on_a_tile_with_nothing_queued_sends_nothing_not_even_when_it_is_let_go() -> void:
	await _open(&"android_6in")
	var world: World = Sw.world()
	Sw.own(world, BASE)
	Sw.enqueue(world, World.Tab.INFANTRY, ["rifle_squad"])
	await _publish(world)
	_sidebar.select_tab(World.Tab.INFANTRY)
	await _settle()
	_hold("rocket_squad")  # Available, none queued.
	assert_array(_sent).is_empty()
	_sidebar.select_tab(World.Tab.VEHICLES)
	world = Sw.world()
	Sw.own(world, ["headquarters"])
	await _publish(world)
	_hold("light_tank")  # Locked, none queued.
	assert_array(_sent).is_empty()
	assert_array(_buzzed).is_empty()


func test_a_tile_that_cannot_take_an_item_shakes_on_a_tap_and_sends_nothing() -> void:
	await _open(&"android_6in")
	var world: World = Sw.world()
	Sw.own(world, ["headquarters", "power_plant", "barracks"])
	world.credits[1] = 350
	var rifles: Array[String] = ["rifle_squad", "rifle_squad", "rifle_squad", "rifle_squad"]
	Sw.enqueue(world, World.Tab.INFANTRY, rifles + ["rifle_squad"])
	await _publish(world)
	var cases: Array = [
		[World.Tab.STRUCTURES, "vehicle_factory"],  # Locked: no refinery.
		[World.Tab.STRUCTURES, "barracks"],  # Unaffordable: 400 of 350.
		[World.Tab.INFANTRY, "rocket_squad"],  # Full: five of five.
		[World.Tab.VEHICLES, "light_tank"],  # Locked: no factory.
	]
	for pick: Array in cases:
		_sidebar.select_tab(pick[0])
		await _settle()
		var tile: ItemTile = _tile(pick[1])
		_tap(pick[1])
		assert_int(tile.shakes).override_failure_message(pick[1]).is_equal(1)
		_tap(pick[1])
		assert_int(tile.shakes).override_failure_message(pick[1]).is_equal(2)
	assert_array(_sent).is_empty()
	assert_array(_buzzed).is_empty()


## A ready structure shows ready and sends nothing here: placement mode (plan P86) takes the tap.
func test_a_tap_on_a_ready_structure_sends_nothing_and_a_hold_on_it_cancels_it() -> void:
	await _open(&"android_6in")
	var world: World = Sw.world()
	Sw.own(world, BASE)
	var plant: int = Sw.type_of(world, "power_plant")
	Sw.enqueue(world, World.Tab.STRUCTURES, ["power_plant"], world.type_build_ticks[plant] * 100)
	await _publish(world)
	assert_int(_tile("power_plant").state).is_equal(ItemTile.State.READY)
	_tap("power_plant")
	assert_array(_sent).is_empty()
	assert_int(_tile("power_plant").shakes).is_equal(0)
	_hold("power_plant")
	assert_int(_sent.size()).is_equal(1)
	_assert_cancel(_sent[0], World.Tab.STRUCTURES, 0)


## A drag beyond the slop scrolls the row, sends nothing and ends the touch as neither a tap nor a
## hold, whether the finger stays on its tile or leaves it (a tile with an item queued and money to
## queue another: a tap or a hold would send one); a finger that only wobbles still taps. The
## portrait row scrolls sideways, at 360 dp where five tiles do not fit.
func test_a_scroll_drag_in_the_portrait_row_sends_nothing_and_a_wobble_still_taps() -> void:
	await _open(&"web_phone_portrait")
	var world: World = Sw.world()
	Sw.own(world, BASE)
	Sw.enqueue(world, World.Tab.STRUCTURES, ["power_plant"])
	await _publish(world)
	var items: ScrollContainer = _sidebar.find_child("Items", true, false)
	assert_int(items.scroll_horizontal).is_equal(0)
	assert_int(items.horizontal_scroll_mode).is_equal(ScrollContainer.SCROLL_MODE_SHOW_NEVER)
	assert_int(items.vertical_scroll_mode).is_equal(ScrollContainer.SCROLL_MODE_DISABLED)
	var tile: ItemTile = _tile("power_plant")
	var at: Vector2 = tile.get_global_rect().get_center()
	for by: float in [UiScale.dp(20.0), UiScale.dp(60.0)]:  # On its tile, then off it.
		var before: int = items.scroll_horizontal
		_press(tile, at)
		TouchEvents.drag(get_viewport(), 0, at + Vector2(-by / 2.0, 0.0), Vector2(-by / 2.0, 0.0))
		TouchEvents.drag(get_viewport(), 0, at + Vector2(-by, 0.0), Vector2(-by / 2.0, 0.0))
		_now_ms += _hold_ms * 2  # As long as a hold, but it was a scroll.
		tile._process(0.0)
		TouchEvents.release(get_viewport(), 0, at + Vector2(-by, 0.0))
		await await_idle_frame()
		assert_array(_sent).is_empty()
		assert_array(_buzzed).is_empty()
		assert_int(items.scroll_horizontal).is_greater(before)
		assert_int(items.scroll_vertical).is_equal(0)
		at = tile.get_global_rect().get_center()  # It moved with the row.
	var wobble: float = UiScale.dp(4.0)  # Well inside the slop: a tap with a shaky finger.
	var again: Vector2 = _tile("barracks").get_global_rect().get_center()
	_press(_tile("barracks"), again)
	TouchEvents.drag(get_viewport(), 0, again + Vector2(wobble, 0.0), Vector2(wobble, 0.0))
	TouchEvents.drag(get_viewport(), 0, again, Vector2(-wobble, 0.0))
	TouchEvents.release(get_viewport(), 0, again)
	assert_int(_sent.size()).is_equal(1)
	assert_int(_sent[0].type).is_equal(Command.Type.QUEUE)
	assert_array(_sent[0].payload).is_equal([Sw.type_of(world, "barracks")])


func test_a_scroll_drag_in_the_landscape_grid_goes_down_and_sends_nothing() -> void:
	await _open(&"web_phone_small")  # 304 dp tall: three rows of tiles do not fit.
	var world: World = Sw.world()
	Sw.own(world, BASE)
	Sw.enqueue(world, World.Tab.STRUCTURES, ["power_plant"])
	await _publish(world)
	var items: ScrollContainer = _sidebar.find_child("Items", true, false)
	assert_int(items.vertical_scroll_mode).is_equal(ScrollContainer.SCROLL_MODE_SHOW_NEVER)
	assert_int(items.horizontal_scroll_mode).is_equal(ScrollContainer.SCROLL_MODE_DISABLED)
	var tile: ItemTile = _tile("power_plant")
	var at: Vector2 = tile.get_global_rect().get_center()
	var by: float = UiScale.dp(20.0)  # Beyond the slop, and the finger stays on its tile.
	_press(tile, at)
	TouchEvents.drag(get_viewport(), 0, at + Vector2(0.0, -by), Vector2(0.0, -by))
	_now_ms += _hold_ms * 2
	tile._process(0.0)
	TouchEvents.release(get_viewport(), 0, at + Vector2(0.0, -by))
	await await_idle_frame()
	assert_array(_sent).is_empty()
	assert_array(_buzzed).is_empty()
	assert_int(items.scroll_vertical).is_greater(0)
	assert_int(items.scroll_horizontal).is_equal(0)
	var last: Vector2 = _tile("defence_turret").get_global_rect().get_center()
	_press(_tile("defence_turret"), last)  # A drag back down, from the last row.
	TouchEvents.drag(get_viewport(), 0, last + Vector2(0.0, 3.0 * by), Vector2(0.0, 3.0 * by))
	TouchEvents.release(get_viewport(), 0, last + Vector2(0.0, 3.0 * by))
	assert_int(items.scroll_vertical).is_equal(0)  # Which can go no further than the top.
	assert_array(_sent).is_empty()


## The hook the building selection calls (plan P84d): the ids a selection holds. A lone own
## building that produces a tab opens it; units, other players' buildings, a building that
## produces nothing, a mixed selection and an empty one leave the tab as it is.
func test_a_lone_own_producer_that_is_selected_opens_the_tab_it_builds() -> void:
	await _open(&"android_6in")
	var world: World = Sw.world()
	var own: PackedInt32Array = Sw.own(world, BASE + ["defence_turret"])
	var foes: PackedInt32Array = Sw.own(world, ["barracks"], 2)
	var rifle: int = world.add_unit(1, Sw.type_of(world, "rifle_squad"), 20500, 12500)
	await _publish(world)
	var opened: Array[int] = []
	_sidebar.tab_selected.connect(func(tab: int) -> void: opened.append(tab))
	_controller.selection.set_ids(PackedInt32Array([own[2]]))  # The barracks, through the signal.
	assert_int(_sidebar.tab).is_equal(World.Tab.INFANTRY)
	_sidebar.set_selected(PackedInt32Array([own[4]]))  # The vehicle factory, through the hook.
	assert_int(_sidebar.tab).is_equal(World.Tab.VEHICLES)
	_controller.selection.set_ids(PackedInt32Array([own[0]]))  # The Headquarters.
	assert_int(_sidebar.tab).is_equal(World.Tab.STRUCTURES)
	assert_array(opened).is_equal([World.Tab.INFANTRY, World.Tab.VEHICLES, World.Tab.STRUCTURES])
	_sidebar.select_tab(World.Tab.VEHICLES)
	for ids: Array in [
		[own[1]], [own[5]], [foes[0]], [rifle], [own[2], rifle], [own[2], own[4]], []
	]:
		_sidebar.set_selected(PackedInt32Array(ids))
		assert_int(_sidebar.tab).override_failure_message(str(ids)).is_equal(World.Tab.VEHICLES)
	_sidebar.set_selected(PackedInt32Array([999]))  # An id that is not on the map.
	assert_int(_sidebar.tab).is_equal(World.Tab.VEHICLES)
	assert_array(_sent).is_empty()
	assert_array(_tiles_shown()).is_equal(["light_tank", "heavy_tank", "harvester", "artillery"])


## The orders as the sim takes them: a tap pays and queues, a hold on the tile of an earlier item
## gives its price back, and the tiles then show the new bank and queue.
func test_the_orders_run_in_the_sim_a_tap_pays_and_a_hold_pays_back() -> void:
	await _open(&"android_6in")
	var world: World = Sw.world()
	Sw.own(world, BASE)
	await _publish(world)
	_sidebar.select_tab(World.Tab.INFANTRY)
	await _settle()
	_tap("rifle_squad")
	_tap("rocket_squad")
	_tap("rifle_squad")
	Rig.step(world, _sent)
	assert_int(world.credits[1]).is_equal(2000 - 100 - 300 - 100)
	assert_array(Rig.items(world, 1, World.Tab.INFANTRY)).is_equal(
		[
			Sw.type_of(world, "rifle_squad"),
			Sw.type_of(world, "rocket_squad"),
			Sw.type_of(world, "rifle_squad")
		]
	)
	assert_int(world.dropped_commands).is_equal(0)
	_sent.clear()
	await _publish(world)
	assert_int(_tile("rifle_squad").queued).is_equal(2)
	_hold("rifle_squad")  # The last rifle squad, the third item.
	Rig.step(world, _sent)
	assert_int(world.credits[1]).is_equal(2000 - 100 - 300)
	assert_array(Rig.items(world, 1, World.Tab.INFANTRY)).is_equal(
		[Sw.type_of(world, "rifle_squad"), Sw.type_of(world, "rocket_squad")]
	)
	assert_int(world.dropped_commands).is_equal(0)
	await _publish(world)
	assert_int(_tile("rifle_squad").queued).is_equal(1)


func _grid() -> GridContainer:
	return _sidebar.find_children("*", "GridContainer", true, false)[0]


func _tiles_shown() -> Array[String]:
	var ids: Array[String] = []
	for node: Node in _grid().get_children():
		if (node as Control).visible:
			ids.append(node.name.trim_prefix("Tile_"))
	return ids


func _assert_cancel(command: Command, tab: int, slot: int) -> void:
	assert_int(command.type).is_equal(Command.Type.CANCEL)
	assert_array(command.payload).is_equal([tab, slot])


func _tile(id: String) -> ItemTile:
	return _sidebar.find_child("Tile_" + id, true, false) as ItemTile


## A finger down on the tile, with the suite's clock in it.
func _press(tile: ItemTile, at: Vector2) -> void:
	tile.clock = func() -> int: return _now_ms
	TouchEvents.press(get_viewport(), 0, at)


func _tap(id: String) -> void:
	var at: Vector2 = _tile(id).get_global_rect().get_center()
	_press(_tile(id), at)
	_now_ms += 50
	TouchEvents.release(get_viewport(), 0, at)
	_now_ms += 1000


## A finger that rests on the tile for `long_press_ms`: a HoldButton sees the hold on a frame, which
## `_process` stands in for.
func _hold(id: String) -> void:
	var tile: ItemTile = _tile(id)
	var at: Vector2 = tile.get_global_rect().get_center()
	_press(tile, at)
	_now_ms += _hold_ms
	tile._process(0.0)
	TouchEvents.release(get_viewport(), 0, at)
	_now_ms += 1000


## Publishes the world's snapshot as the match's latest, reads it and lets the layout settle.
func _publish(world: World) -> void:
	_runner.snapshot = Sw.snapshot(world)
	_sidebar.refresh()
	await _settle()


func _settle() -> void:
	await await_idle_frame()
	await await_idle_frame()


## A new main scene on a profile, its match paused, with the Commands and the buzzes caught.
func _open(profile: StringName) -> void:
	var metrics: UiMetrics = UiProfiles.by_name(profile)
	UiScale.set_override(metrics)
	get_window().size = metrics.window_size
	await await_idle_frame()
	_main = auto_free((load("res://scenes/main.tscn") as PackedScene).instantiate())
	_main.get_node("MatchRunner").paused = true
	add_child(_main)
	await await_idle_frame()
	# The sidebar reads a runner of its own: the map's layers have no art for a building before P84.
	_runner = auto_free(MatchRunner.new())
	_runner.scenario = _main.get_node("MatchRunner").scenario
	_sidebar = _main.get_node("Hud").find_child("BuildSidebar", true, false)
	_sidebar.runner = _runner
	_controller = _main.get_node("PlayerController")
	_hold_ms = _controller.settings.long_press_ms
	_sent.clear()
	_buzzed.clear()
	_now_ms = 0
	_controller.command_sink = func(command: Command) -> void: _sent.append(command)
	_controller.vibrate = func(ms: int) -> void: _buzzed.append(ms)
