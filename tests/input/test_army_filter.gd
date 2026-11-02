extends GdUnitTestSuite
## The army filter by gestures (plan P87, ADR 0019 section 3): "All army" and a box that holds any
## unit that fights leave tankers out, a box with only tankers selects them, a double-tap on a
## tanker selects the tankers on screen, and no building joins any of them. Through the real
## TouchInput, GestureRecognizer, PlayerController and ArmyBar in the main scene at the six screens
## (ScreenSizes.ALL), with a fake clock. The scene is `OrdersRig`'s: player 1 has two tankers, a
## light tank and a rifle squad, apart from the tank by 2 tiles or more, and six buildings.

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const Rig: GDScript = preload("res://tests/input/support/orders_rig.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const TANKERS: Array[int] = [Rig.TANKER_A, Rig.TANKER_B]

var _window_size_before: Vector2i
var _rig: Rig = Rig.new()


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	MenuRig.begin()
	get_window().size = ScreenSizes.LANDSCAPE[0]
	await await_idle_frame()
	_rig = Rig.new()
	var scene: Node2D = auto_free((load("res://scenes/main.tscn") as PackedScene).instantiate())
	(scene.get_node("MatchRunner") as MatchRunner).scenario = Rig.scenario()
	add_child(scene)
	await await_idle_frame()
	_rig.bind(scene)


func after_test() -> void:
	MenuRig.end()
	CommandQueue.clear()


func test_all_army_selects_the_units_that_fight_and_leaves_tankers_and_buildings_out() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _show(size)
		_press_all_army()
		(
			assert_array(_rig.controller.selection.selected)
			. override_failure_message(str(size))
			. is_equal([Rig.TANK, Rig.RIFLE])
		)
		assert_array(_rig.sent).is_empty()  # Selecting orders nothing.


func test_all_army_with_tankers_alone_on_the_map_selects_nothing() -> void:
	await _show(ScreenSizes.LANDSCAPE[1])
	for id: int in [Rig.TANK, Rig.RIFLE]:
		_rig.runner.world.hp[_rig.runner.snapshot.index_of(id)] = 0
	_rig.runner.run_ticks(1)
	_rig.controller.selection.set_ids(PackedInt32Array(TANKERS))
	_press_all_army()
	assert_array(_rig.controller.selection.selected).is_empty()


func test_a_box_with_a_unit_that_fights_among_tankers_leaves_the_tankers_out() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _show(size)
		var note: String = str(size)
		_rig.box_around([Rig.TANKER_A, Rig.TANKER_B, Rig.RIFLE])
		assert_array(_rig.controller.selection.selected).override_failure_message(note).is_equal(
			[Rig.RIFLE]
		)
		_rig.box_around([Rig.TANKER_A, Rig.TANKER_B, Rig.TANK, Rig.RIFLE])
		assert_array(_rig.controller.selection.selected).override_failure_message(note).is_equal(
			[Rig.TANK, Rig.RIFLE]
		)
		assert_array(_rig.sent).override_failure_message(note).is_empty()


func test_a_box_with_tankers_only_selects_them() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _show(size)
		var note: String = str(size)
		_rig.box_around([Rig.TANKER_A, Rig.TANKER_B])
		assert_array(_rig.controller.selection.selected).override_failure_message(note).is_equal(
			TANKERS
		)
		_rig.controller.selection.clear()
		_rig.box_around([Rig.TANKER_B])
		assert_array(_rig.controller.selection.selected).override_failure_message(note).is_equal(
			[Rig.TANKER_B]
		)


func test_a_double_tap_on_a_tanker_selects_the_tankers_on_screen_and_none_other() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _show(size)
		var note: String = str(size)
		_rig.camera.centre_on(_between(Rig.TANKER_A, Rig.TANKER_B))
		_rig.tap(_rig.units.unit_screen_position(_rig.runner.snapshot.index_of(Rig.TANKER_A)), true)
		assert_array(_rig.controller.selection.selected).override_failure_message(note).is_equal(
			TANKERS
		)
		_rig.controller.selection.clear()
		_rig.camera.centre_on(_between(Rig.TANK, Rig.RIFLE))
		_rig.tap(_rig.units.unit_screen_position(_rig.runner.snapshot.index_of(Rig.TANK)), true)
		assert_array(_rig.controller.selection.selected).override_failure_message(note).is_equal(
			[Rig.TANK]
		)


func test_a_tap_on_a_tanker_selects_it_alone_as_before() -> void:
	await _show(ScreenSizes.PORTRAIT[2])
	_rig.tap_unit(Rig.TANKER_A)
	assert_array(_rig.controller.selection.selected).is_equal([Rig.TANKER_A])


func test_a_box_over_a_building_and_all_army_never_hold_one() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _show(size)
		var note: String = str(size)
		_rig.tap_building(Rig.BARRACKS)
		_press_all_army()
		assert_array(_rig.controller.selection.selected).override_failure_message(note).is_equal(
			[Rig.TANK, Rig.RIFLE]
		)
		_rig.tap_building(Rig.BARRACKS)
		var footprint: Vector2 = _rig.buildings.building(Rig.BARRACKS).position
		_rig.box(
			_rig.camera.world_to_screen(footprint) - Vector2(30.0, 30.0),
			_rig.camera.world_to_screen(footprint) + Vector2(30.0, 30.0)
		)
		assert_array(_rig.controller.selection.selected).override_failure_message(note).is_empty()


## A size, with the camera back at zoom 1, nothing selected and nothing recorded.
func _show(size: Vector2i) -> void:
	get_window().size = size
	await await_idle_frame()
	_rig.reset()


func _press_all_army() -> void:
	var button: Button = _rig.main.get_node("Hud/SafeArea/ArmyBand/ArmyBar/AllArmy")
	button.pressed.emit()


## The world px halfway between the places of units `a` and `b`.
func _between(a: int, b: int) -> Vector2:
	var snap: MatchSnapshot = _rig.runner.snapshot
	var from: int = snap.index_of(a)
	var to: int = snap.index_of(b)
	return IsoProjection.ground_to_px(snap.pos_x[from], snap.pos_y[from]).lerp(
		IsoProjection.ground_to_px(snap.pos_x[to], snap.pos_y[to]), 0.5
	)
