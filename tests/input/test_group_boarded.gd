extends GdUnitTestSuite
## Control groups and boarding (plan P265, ADR 0036 section 8): a squad that boards a carrier ends
## as a DIED record of flag 2, which leaves the live selection only. Groups 1-3 keep it, count only
## the squads on the map, and hold it again after the unload; a real death (flag 0) still leaves
## the groups. Hand-built world of tests/sim/support/carry_rig.gd, ticked by `Sim.step`.

const Rig: GDScript = preload("res://tests/sim/support/carry_rig.gd")
const StrikeRig: GDScript = preload("res://tests/input/support/strike_rig.gd")
const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const CARRIER: int = 5

var _world: World
var _controller: PlayerController
var _column: GroupColumn


func before_test() -> void:
	MenuRig.begin()
	_world = Rig.world()
	_column = auto_free(GroupColumn.new())
	_controller = auto_free(PlayerController.new())
	_controller.settings = InputSettings.new()
	_controller.runner = auto_free(StrikeRig.runner(StrikeRig.snapshot(_world)))
	_controller.group_column = _column
	add_child(_column)
	add_child(_controller)


func after_test() -> void:
	MenuRig.end()


## One tick, published as the runner does, with the controller's `ticked` handler run.
func _tick(commands: Array = []) -> void:
	Rig.step(_world, commands)
	_controller.runner.snapshot = StrikeRig.snapshot(_world)
	_controller.runner.ticked.emit(_world.tick)


func _group_one() -> void:
	_controller.selection.set_ids(PackedInt32Array([1, 2, 3]))
	_controller.assign_group(1)


func test_boarding_leaves_the_live_selection_but_not_the_group_and_the_unload_refills_it() -> void:
	_group_one()
	assert_int(_controller.selection.group_size(1)).is_equal(3)
	Rig.near(_world, 1, 300)
	Rig.near(_world, 2, 300)
	_world.pos_x[_world.index_of(2)] = _world.pos_x[_world.index_of(1)] + 100
	_world.pos_y[_world.index_of(2)] = _world.pos_y[_world.index_of(1)]
	_world.order_target[_world.index_of(1)] = CARRIER
	_world.order_target[_world.index_of(2)] = CARRIER
	for _i: int in 3:
		_tick()
	assert_int(Carry.aboard(_world, CARRIER)).is_equal(2)
	# The live selection holds the squad left on the map; the group holds all three.
	assert_array(Array(_controller.selection.selected)).is_equal([3])
	assert_array(Array(_controller.selection.group(1))).is_equal([1, 2, 3])
	assert_str(_column.badge_text(1)).is_equal("1\n1")  # Only the squad on the map counts.
	_controller.tap_group(1)  # Recalls the squad on the map, not the two aboard.
	assert_array(Array(_controller.selection.selected)).is_equal([3])
	# The carrier unloads: the squads are rows again, the group counts them and recalls them.
	_tick([Command.unload(1, PackedInt32Array([CARRIER]), 3000, 3500)])
	for _i: int in 120:
		_tick()
		if Carry.aboard(_world, CARRIER) == 0:
			break
	assert_int(Carry.aboard(_world, CARRIER)).is_equal(0)
	assert_str(_column.badge_text(1)).is_equal("1\n3")
	_controller.tap_group(1)
	assert_array(Array(_controller.selection.selected)).is_equal([1, 2, 3])


func test_a_real_death_still_leaves_the_groups_and_the_selection() -> void:
	_group_one()
	_controller.selection.set_ids(PackedInt32Array([1, 2, 3]))
	_world.hp[_world.index_of(2)] = 0
	_tick()
	assert_array(Array(_controller.selection.selected)).is_equal([1, 3])
	assert_array(Array(_controller.selection.group(1))).is_equal([1, 3])
	assert_str(_column.badge_text(1)).is_equal("1\n2")


func test_the_selection_model_drops_live_ids_only() -> void:
	var model: SelectionModel = SelectionModel.new()
	model.set_ids(PackedInt32Array([4, 5, 6]))
	model.assign_group(2)
	var changes: Array[int] = [0]
	model.changed.connect(func() -> void: changes[0] += 1)
	model.drop_live(PackedInt32Array([5, 9]))
	assert_array(Array(model.selected)).is_equal([4, 6])
	assert_array(Array(model.group(2))).is_equal([4, 5, 6])
	model.drop_live(PackedInt32Array([9]))
	model.drop_live(PackedInt32Array())
	assert_int(changes[0]).is_equal(1)
