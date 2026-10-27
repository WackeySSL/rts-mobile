extends GdUnitTestSuite
## Taps on buildings through the real TouchInput, GestureRecognizer and PlayerController in the main
## scene at the six screens (ScreenSizes.ALL: 1280x720, 2400x1080 and 2048x1536, each held both
## ways), with a fake clock (plan P115b, ADR 0019 section 3, ADR 0023 section 3). A tap on a
## building's picture selects it alone, the panel names it and the sidebar opens its tab; a unit at
## the spot is picked first; the building drawn in front wins an overlap; a ground tap lets go of
## it; an enemy building is selected for its info and gets no order, and with an own tank selected a
## tap on it attacks when the sim would take that (the cell under its position is seen) and moves
## when not. A second tap on the selected building takes the sidebar back to its tab. Buildings
## never join a double-tap, a box or "All army".
## On a 32 x 32 map, player 1 the local one: Headquarters id 1 (3x3, tiles 6-8 by 6-8, centre px
## (0, 240)), power plant id 2 (2x2, tiles 9-10 by 6-7, centre px (96, 272), drawn in front of the
## Headquarters), barracks id 3 (2x2, tiles 14-15 by 3-4) and light tank id 4 at tile (5, 5), whose
## centre is px (0, 176), inside the Headquarters' picture; and player 2's Headquarters id 5
## (tiles 20-22 by 20-22).

const Rig: GDScript = preload("res://tests/view/support/building_rig.gd")
const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const SPAWNS: Array[Array] = [
	[1, "headquarters", 6, 6],
	[1, "power_plant", 9, 6],
	[1, "barracks", 14, 3],
	[1, "light_tank", 5, 5],
	[2, "renew_hq", 20, 20],
]
const HQ: int = 1
const PLANT: int = 2
const BARRACKS: int = 3
const TANK: int = 4
const ENEMY_HQ: int = 5
const GROUND_TILE: Vector2i = Vector2i(16, 16)  ## Nothing stands within 5 tiles of it.

var _window_size_before: Vector2i
var _main: Node2D
var _runner: MatchRunner
var _camera: RtsCamera
var _touch: TouchInput
var _controller: PlayerController
var _buildings: BuildingLayer
var _sidebar: BuildSidebar
var _now_ms: int = 0
var _sent: Array[Command] = []


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	get_window().size = ScreenSizes.LANDSCAPE[0]
	await await_idle_frame()
	var spawns: Array[SpawnDef] = []
	for entry: Array in SPAWNS:
		spawns.append(Rig.spawn(entry[0], entry[1], entry[2], entry[3]))
	_main = auto_free((load("res://scenes/main.tscn") as PackedScene).instantiate())
	(_main.get_node("MatchRunner") as MatchRunner).scenario = Rig.scenario(spawns)
	add_child(_main)
	await await_idle_frame()
	_runner = _main.get_node("MatchRunner")
	_runner.paused = true  # Only run_ticks() moves time.
	_camera = _main.get_node("Camera")
	_touch = _main.get_node("TouchInput")
	_controller = _main.get_node("PlayerController")
	_buildings = _main.get_node("BuildingLayer")
	Rig.see(_runner.snapshot, 1, [Vector2i(21, 21)])  # A cell of the enemy Headquarters.
	_sidebar = _main.get_node("Hud/SafeArea/BuildSidebar")
	_now_ms = 0
	_sent.clear()
	_touch.clock = func() -> int: return _now_ms
	_controller.command_sink = func(command: Command) -> void: _sent.append(command)


func after_test() -> void:
	CommandQueue.clear()


func test_a_tap_on_an_own_building_selects_it_alone_names_it_and_opens_its_tab() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _show(size)
		_sidebar.select_tab(World.Tab.VEHICLES)
		_tap_building(HQ, 0.0)  # The footprint's centre.
		var note: String = str(size)
		assert_array(_controller.selection.selected).override_failure_message(note).is_equal([HQ])
		assert_int(_sidebar.tab).override_failure_message(note).is_equal(World.Tab.STRUCTURES)
		assert_array(_panel_texts()).override_failure_message(note).is_equal(["Rigworks", "×1"])
		_tap_building(BARRACKS, 0.0)
		assert_array(_controller.selection.selected).override_failure_message(note).is_equal(
			[BARRACKS]
		)
		assert_int(_sidebar.tab).override_failure_message(note).is_equal(World.Tab.INFANTRY)
		assert_array(_panel_texts()).override_failure_message(note).is_equal(["Bunkhouse", "×1"])
		assert_array(_sent).override_failure_message(note).is_empty()  # Selecting orders nothing.


func test_a_tap_anywhere_on_the_picture_selects_and_a_tap_beside_it_does_not() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _show(size)
		var rise: float = _row(BARRACKS)[3]
		var half: Vector2 = _row(BARRACKS)[2]
		var note: String = str(size)
		# The overhang above the footprint and the edge of the picture's rectangle all hit.
		for offset: Vector2 in [Vector2(0, -0.9 * rise), Vector2(half.x - 3.0, -rise * 0.5)]:
			_controller.selection.clear()
			_tap_building(BARRACKS, 0.0, offset)
			(
				assert_array(_controller.selection.selected)
				. override_failure_message("%s %s" % [note, offset])
				. is_equal([BARRACKS])
			)
		# Past the picture's top and past the side: the ground, so nothing.
		for offset: Vector2 in [Vector2(0, -rise - 4.0), Vector2(half.x + 4.0, -rise * 0.5)]:
			_controller.selection.clear()
			_tap_building(BARRACKS, 0.0, offset)
			(
				assert_array(_controller.selection.selected)
				. override_failure_message("%s %s" % [note, offset])
				. is_empty()
			)


func test_a_unit_at_the_spot_is_picked_before_the_building_behind_it() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _show(size)
		# The tank stands in the Headquarters' picture: the tap on it is the tank's.
		_tap_world(Vector2(0, 176))
		assert_array(_controller.selection.selected).override_failure_message(str(size)).is_equal(
			[TANK]
		)
		# And a tap on the picture, clear of the tank's 48 dp, is the building's.
		_tap_world(Vector2(-60, 200))
		assert_array(_controller.selection.selected).override_failure_message(str(size)).is_equal(
			[HQ]
		)
		assert_array(_sent).is_empty()


func test_the_building_drawn_in_front_wins_where_two_pictures_overlap() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _show(size)
		var note: String = str(size)
		_camera.centre_on(Vector2(48, 250))
		var both: Vector2 = _camera.world_to_screen(Vector2(64, 220))  # In both silhouettes.
		_tap(both)
		assert_array(_controller.selection.selected).override_failure_message(note).is_equal(
			[PLANT]
		)
		_tap(_camera.world_to_screen(Vector2(-50, 200)))  # Only the Headquarters has this.
		assert_array(_controller.selection.selected).override_failure_message(note).is_equal([HQ])
		_tap(_camera.world_to_screen(Vector2(150, 262)))  # Only the power plant has this.
		assert_array(_controller.selection.selected).override_failure_message(note).is_equal(
			[PLANT]
		)


func test_with_own_units_selected_a_tap_on_an_own_building_selects_it_instead() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _show(size)
		_controller.selection.set_ids(PackedInt32Array([TANK]))
		_tap_building(BARRACKS, 0.0)
		assert_array(_controller.selection.selected).override_failure_message(str(size)).is_equal(
			[BARRACKS]
		)
		assert_array(_sent).is_empty()  # No MOVE to the barracks, and no ATTACK.


func test_a_tap_on_the_ground_with_a_building_selected_lets_go_of_it_and_orders_nothing() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _show(size)
		_tap_building(HQ, 0.0)
		assert_array(_controller.selection.selected).is_equal([HQ])
		_tap_world(IsoProjection.cell_centre_px(GROUND_TILE.x, GROUND_TILE.y))
		assert_array(_controller.selection.selected).override_failure_message(str(size)).is_empty()
		assert_array(_sent).override_failure_message(str(size)).is_empty()
		assert_int(_main.get_node("MarkerLayer").active_count()).is_equal(0)  # No chevrons either.
		assert_bool(_panel().visible).is_false()


func test_a_double_tap_on_a_building_selects_it_alone_and_a_box_or_all_army_never_holds_one(
) -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _show(size)
		var note: String = str(size)
		_camera.centre_on(Vector2(0, 208))
		var on_hq: Vector2 = _camera.world_to_screen(Vector2(-60, 200))
		_tap(on_hq, true)
		assert_array(_controller.selection.selected).override_failure_message(note).is_equal([HQ])
		# A box over the tank and the Headquarters' centre holds the tank and not the building.
		_box(
			_camera.world_to_screen(Vector2(-150, 150)), _camera.world_to_screen(Vector2(150, 300))
		)
		assert_array(_controller.selection.selected).override_failure_message(note).is_equal([TANK])
		# A box over the building alone holds no unit, and that clears it: the box never selects one.
		_tap(on_hq)
		_box(_camera.world_to_screen(Vector2(20, 230)), _camera.world_to_screen(Vector2(150, 300)))
		assert_array(_controller.selection.selected).override_failure_message(note).is_empty()
		_tap(on_hq)
		_controller.select_all_army()
		assert_array(_controller.selection.selected).override_failure_message(note).is_equal([TANK])
		assert_array(_sent).is_empty()


func test_an_enemy_building_is_selected_for_its_info_only_where_it_is_seen() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _show(size)
		var note: String = str(size)
		Rig.see(_runner.snapshot, 1, [])
		_tap_building(ENEMY_HQ, 0.0)  # Hidden by the fog: a tap on the ground.
		assert_array(_controller.selection.selected).override_failure_message(note).is_empty()
		Rig.see(_runner.snapshot, 1, [Vector2i(21, 21)])
		_tap_building(ENEMY_HQ, 0.0)
		assert_array(_controller.selection.selected).override_failure_message(note).is_equal(
			[ENEMY_HQ]
		)
		assert_array(_panel_texts()).override_failure_message(note).is_equal(["Grid Hub", "×1"])
		# A ground tap lets go of it, and no order goes anywhere for a building that is not ours.
		_tap_world(IsoProjection.cell_centre_px(GROUND_TILE.x, GROUND_TILE.y))
		assert_array(_controller.selection.selected).override_failure_message(note).is_empty()
		assert_array(_sent).override_failure_message(note).is_empty()


func test_with_an_own_tank_selected_a_tap_on_a_seen_enemy_building_attacks_it() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _show(size)
		var note: String = str(size)
		_controller.selection.set_ids(PackedInt32Array([TANK]))
		_tap_building(ENEMY_HQ, 0.0, Vector2(0, -60))  # On its overhang.
		assert_array(_sent).override_failure_message(note).has_size(1)
		assert_int(_sent[0].type).is_equal(Command.Type.ATTACK)
		assert_int(_sent[0].target_id).is_equal(ENEMY_HQ)
		assert_array(_sent[0].unit_ids).is_equal([TANK])
		assert_array(_controller.selection.selected).is_equal([TANK])  # Ordering keeps it.
		_sent.clear()


func test_with_an_own_tank_selected_a_tap_on_an_enemy_building_seen_only_at_its_edge_is_a_move(
) -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _show(size)
		var note: String = str(size)
		# A corner cell of the enemy Headquarters (tiles 20-22 by 20-22) is seen, the cell under its
		# position (21, 21) is not: the building is drawn, but the sim would drop an attack on it.
		Rig.see(_runner.snapshot, 1, [Vector2i(20, 20)])
		_controller.selection.set_ids(PackedInt32Array([TANK]))
		_tap_building(ENEMY_HQ, 0.0, Vector2(0, -60))  # On its overhang.
		assert_array(_sent).override_failure_message(note).has_size(1)
		assert_int(_sent[0].type).override_failure_message(note).is_equal(Command.Type.MOVE)
		assert_array(_sent[0].unit_ids).is_equal([TANK])
		assert_int(_diamonds()).override_failure_message(note).is_equal(0)  # No attack marker.
		assert_array(_controller.selection.selected).is_equal([TANK])
		# With nothing selected it is still tapped for its info: it is drawn.
		_controller.selection.clear()
		_sent.clear()
		_tap_building(ENEMY_HQ, 0.0)
		assert_array(_controller.selection.selected).override_failure_message(note).is_equal(
			[ENEMY_HQ]
		)
		assert_array(_sent).is_empty()
		Rig.see(_runner.snapshot, 1, [Vector2i(21, 21)])  # Back to the cell under its position.


func test_a_second_tap_on_the_selected_building_takes_the_sidebar_back_to_its_tab() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _show(size)
		var note: String = str(size)
		_tap_building(HQ, 0.0)
		assert_int(_sidebar.tab).override_failure_message(note).is_equal(World.Tab.STRUCTURES)
		_sidebar.select_tab(World.Tab.VEHICLES)  # To queue a tank: the selection stays.
		assert_array(_controller.selection.selected).override_failure_message(note).is_equal([HQ])
		_tap_building(HQ, 0.0)
		assert_array(_controller.selection.selected).override_failure_message(note).is_equal([HQ])
		assert_int(_sidebar.tab).override_failure_message(note).is_equal(World.Tab.STRUCTURES)
		_tap_building(BARRACKS, 0.0)
		_sidebar.select_tab(World.Tab.STRUCTURES)
		_tap_building(BARRACKS, 0.0)
		assert_int(_sidebar.tab).override_failure_message(note).is_equal(World.Tab.INFANTRY)
		assert_array(_sent).override_failure_message(note).is_empty()


func test_selection_changed_fires_again_for_a_tap_on_the_selected_building_and_for_no_other_repeat(
) -> void:
	await _show(ScreenSizes.LANDSCAPE[1])
	var seen: Array[PackedInt32Array] = []
	_controller.selection_changed.connect(func(ids: PackedInt32Array) -> void: seen.append(ids))
	_tap_building(HQ, 0.0)
	assert_array(seen).has_size(1)
	_tap_building(HQ, 0.0)  # The building that is the selection: the sidebar needs to hear it.
	assert_array(seen).has_size(2)
	assert_array(seen[1]).is_equal([HQ])
	_controller.select_all_army()  # The tank: a real change.
	assert_array(seen).has_size(3)
	_controller.select_all_army()  # Not a change, and not a building tap: silent as before.
	assert_array(seen).has_size(3)


func test_a_selected_building_that_is_destroyed_leaves_the_selection() -> void:
	await _show(ScreenSizes.LANDSCAPE[1])
	_tap_building(PLANT, 0.0)
	assert_array(_controller.selection.selected).is_equal([PLANT])
	assert_array(_buildings.selected_ids()).is_equal([PLANT])
	_runner.world.hp[_runner.snapshot.index_of(PLANT)] = 0
	_runner.run_ticks(1)
	assert_array(_controller.selection.selected).is_empty()
	assert_array(_buildings.selected_ids()).is_empty()
	assert_bool(_panel().visible).is_false()


## A size, with the camera back at zoom 1 (a turn rescales the zoom, ADR 0015 section 4), nothing
## selected and the sidebar on its first tab.
func _show(size: Vector2i) -> void:
	get_window().size = size
	await await_idle_frame()
	_camera.zoom = Vector2.ONE
	_controller.selection.clear()
	_sidebar.select_tab(World.Tab.STRUCTURES)
	_sent.clear()


## Centres the camera on building `id` and taps its picture at `offset` px (screen) from the
## footprint's centre, lifted by `lift` of its rise.
func _tap_building(id: int, lift: float, offset: Vector2 = Vector2.ZERO) -> void:
	var node: Node2D = _buildings.building(id)
	_camera.centre_on(node.position)
	var row: Array = _row(id)
	_tap(row[1] + offset + Vector2(0, -lift * row[3]))


## Centres the camera on `world` and taps it.
func _tap_world(world: Vector2) -> void:
	_camera.centre_on(world)
	_tap(_camera.world_to_screen(world))


## [id, screen centre, half, rise] of building `id` on the screen of the camera now, from its node
## and its frame box (which a hidden building has too).
func _row(id: int) -> Array:
	var at: Vector2 = _buildings.building(id).position
	var box: Rect2 = _buildings.frame_box(_runner.snapshot.index_of(id))
	var zoom: float = _camera.zoom.x
	var half: Vector2 = Vector2(0.5 * box.size.x, box.end.y - at.y) * zoom
	return [id, _camera.world_to_screen(at), half, (at.y - box.position.y) * zoom]


## A finger down and up at `at` (base px), then a pause past the double-tap time; `twice` taps again
## inside the double-tap time first.
func _tap(at: Vector2, twice: bool = false) -> void:
	for tap_count: int in 2 if twice else 1:
		TouchEvents.press(get_viewport(), 0, at)
		_now_ms += 50
		_touch._process(0.0)
		TouchEvents.release(get_viewport(), 0, at)
		_now_ms += 100 if twice and tap_count == 0 else 1000


## Holds the long-press time at `from`, drags to `to` and lets go.
func _box(from: Vector2, to: Vector2) -> void:
	TouchEvents.press(get_viewport(), 0, from)
	_now_ms += _touch.settings.long_press_ms
	_touch._process(0.0)  # The frame that sees the hold.
	TouchEvents.drag(get_viewport(), 0, to, to - from)
	TouchEvents.release(get_viewport(), 0, to)
	_now_ms += 1000


## How many diamonds (the attack marker) are on show.
func _diamonds() -> int:
	var count: int = 0
	for mark: Node in _main.get_node("MarkerLayer").get_children():
		if mark is MoveMarkerLayer.Mark and mark.visible and mark.diamond:
			count += 1
	return count


func _panel() -> Control:
	return _main.get_node("Hud/SafeArea/SelectionBand/SelectionPanel")


## The name and the count of the panel's first row.
func _panel_texts() -> Array[String]:
	var row: Node = _panel().get_node("Rows/Row0")
	return [(row.get_node("Name") as Label).text, (row.get_node("Count") as Label).text]
