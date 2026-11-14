extends GdUnitTestSuite
## The map marks of the Board and Unload aims (plan P265b): nothing shows before a carrier is ringed
## or a point is set, the chevron's anchor stands on the ground point at any zoom, the ring is
## centred on the carrier (its rig where the layer has a unit layer, else its snapshot point) and
## follows it, and the layer clears after the check mark and after the X. Hand-built worlds of
## tests/sim/support/carry_rig.gd (squads 1-3, a tank 4, a carrier 5), and the main scene.

const Rig: GDScript = preload("res://tests/sim/support/carry_rig.gd")
const StrikeRig: GDScript = preload("res://tests/input/support/strike_rig.gd")
const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const BuildingRig: GDScript = preload("res://tests/view/support/building_rig.gd")
const CARRIER: int = 5

var _world: World
var _aim: CarryAim
var _layer: CarryMarkLayer
var _controller: PlayerController
var _sent: Array[Command] = []


func before_test() -> void:
	MenuRig.begin()
	_world = Rig.world()
	_sent.clear()
	_controller = auto_free(PlayerController.new())
	_controller.settings = InputSettings.new()
	_controller.command_sink = func(command: Command) -> void: _sent.append(command)
	_controller.vibrate = func(_ms: int) -> void: pass
	_aim = auto_free(CarryAim.new())
	_aim.controller = _controller
	_aim.runner = auto_free(StrikeRig.runner(StrikeRig.snapshot(_world)))
	add_child(_aim)
	_layer = auto_free(CarryMarkLayer.new())
	_layer.aim = _aim
	_layer.runner = _aim.runner
	add_child(_layer)


func after_test() -> void:
	MenuRig.end()


func _read() -> void:
	_aim.runner.snapshot = StrikeRig.snapshot(_world)
	_aim.refresh()


func _select(ids: Array) -> void:
	_controller.selection.set_ids(PackedInt32Array(ids))


func test_nothing_shows_before_a_carrier_is_ringed_or_a_point_is_set() -> void:
	assert_int(_layer.marks()).is_equal(0)
	_select([1, 2])
	_aim.toggle(CarryAim.Mode.BOARD)
	assert_int(_layer.marks()).is_equal(0)
	assert_vector(_layer.ring_centre()).is_equal(Vector2.INF)
	_aim.pick_carrier(CARRIER)
	assert_int(_layer.marks()).is_equal(1)
	_aim.cancel()
	Rig.aboard(_world, 1, CARRIER)
	_read()
	_select([CARRIER])
	_aim.toggle(CarryAim.Mode.UNLOAD)
	assert_int(_layer.marks()).is_equal(0)
	_aim.place(Vector2i(8000, 3000))
	assert_int(_layer.marks()).is_equal(1)


func test_the_chevron_anchor_is_the_ground_point_at_two_zooms() -> void:
	var at: Vector2 = IsoProjection.ground_to_px(8000, 3000)
	for unit: float in [1.0, 0.5]:
		var box: Rect2 = CarryMarkLayer.chevron_rect(at, unit)
		var tip: Vector2 = box.position + CarryMarkLayer.MARK_ANCHOR * box.size
		assert_vector(tip).is_equal_approx(at, Vector2.ONE * 0.001)
		assert_float(box.size.x).is_equal_approx(CarryMarkLayer.MARK_DP * unit, 0.001)


func test_the_ring_follows_the_carrier_and_the_layer_clears_after_confirm_and_x() -> void:
	_select([1, 2])
	_aim.toggle(CarryAim.Mode.BOARD)
	_aim.pick_carrier(CARRIER)
	var before: Vector2 = _layer.ring_centre()
	assert_vector(before).is_equal(
		IsoProjection.ground_to_px(
			_world.pos_x[_world.index_of(CARRIER)], _world.pos_y[_world.index_of(CARRIER)]
		)
	)
	_world.pos_x[_world.index_of(CARRIER)] += 3000
	_read()
	assert_vector(_layer.ring_centre()).is_not_equal(before)
	_aim.confirm()
	assert_int(_layer.marks()).is_equal(0)
	assert_vector(_layer.ring_centre()).is_equal(Vector2.INF)
	_aim.toggle(CarryAim.Mode.BOARD)
	_aim.pick_carrier(CARRIER)
	_aim.cancel()
	assert_int(_layer.marks()).is_equal(0)


func test_the_ring_stands_on_the_drawn_rig_of_the_carrier_in_the_main_scene() -> void:
	var spawns: Array[SpawnDef] = [
		BuildingRig.spawn(1, "rifle_squad", 14, 14),
		BuildingRig.spawn(1, "fossil_transport", 10, 20),
		BuildingRig.spawn(2, "renew_hq", 24, 24),
	]
	var main: Node2D = auto_free((load("res://scenes/main.tscn") as PackedScene).instantiate())
	(main.get_node("MatchRunner") as MatchRunner).scenario = BuildingRig.scenario(spawns)
	main.get_node("MatchRunner").paused = true
	add_child(main)
	await await_idle_frame()
	var aim: CarryAim = main.get_node("CarryAim")
	var layer: CarryMarkLayer = main.get_node("CarryMarkLayer")
	var controller: PlayerController = main.get_node("PlayerController")
	controller.selection.set_ids(PackedInt32Array([1]))
	assert_bool(aim.toggle(CarryAim.Mode.BOARD)).is_true()
	assert_bool(aim.pick_carrier(2)).is_true()
	var snap: MatchSnapshot = (main.get_node("MatchRunner") as MatchRunner).snapshot
	var rig: Node2D = (main.get_node("UnitLayer") as UnitLayer).rig(snap.index_of(2))
	assert_object(rig).is_not_null()
	assert_vector(layer.ring_centre()).is_equal_approx(
		layer.to_local(rig.global_position), Vector2.ONE * 0.01
	)
