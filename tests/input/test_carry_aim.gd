extends GdUnitTestSuite
## The Board and Unload aims (plan P265, ADR 0036 sections 8 and 12) on hand-built worlds
## (tests/sim/support/carry_rig.gd: squads 1-3 and a tank 4 of player 1, its carrier 5 of two seats,
## an enemy squad 6). `CarryRules` reads the snapshot as the sim's `Carry` reads the World; the aim
## sends exactly one LOAD or UNLOAD, from the check mark, and the sim takes the Command it sent.

const Rig: GDScript = preload("res://tests/sim/support/carry_rig.gd")
const StrikeRig: GDScript = preload("res://tests/input/support/strike_rig.gd")
const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const CARRIER: int = 5

var _world: World
var _aim: CarryAim
var _controller: PlayerController
var _sent: Array[Command] = []
var _refused: int = 0


func before_test() -> void:
	MenuRig.begin()
	_world = Rig.world()
	_sent.clear()
	_refused = 0
	_controller = auto_free(PlayerController.new())
	_controller.settings = InputSettings.new()
	_controller.command_sink = func(command: Command) -> void: _sent.append(command)
	_controller.vibrate = func(_ms: int) -> void: pass
	_aim = auto_free(CarryAim.new())
	_aim.controller = _controller
	_aim.runner = auto_free(StrikeRig.runner(StrikeRig.snapshot(_world)))
	add_child(_aim)
	_aim.refused.connect(func() -> void: _refused += 1)


func after_test() -> void:
	MenuRig.end()


func _read(serial: int = 0) -> void:
	_aim.runner.snapshot = StrikeRig.snapshot(_world, serial)
	_aim.refresh()


func _select(ids: Array) -> void:
	_controller.selection.set_ids(PackedInt32Array(ids))


func test_board_needs_squads_and_a_carrier_with_a_seat_and_unload_a_loaded_carrier() -> void:
	_select([4])  # A tank: not a squad.
	assert_bool(_aim.can_begin(CarryAim.Mode.BOARD)).is_false()
	_select([1, 2])
	assert_bool(_aim.can_begin(CarryAim.Mode.BOARD)).is_true()
	assert_bool(_aim.can_begin(CarryAim.Mode.UNLOAD)).is_false()  # Nothing aboard yet.
	_select([CARRIER])
	assert_bool(_aim.can_begin(CarryAim.Mode.UNLOAD)).is_false()
	Rig.aboard(_world, 1, CARRIER)
	_read()
	assert_bool(_aim.can_begin(CarryAim.Mode.UNLOAD)).is_true()
	_select([2, 3])  # Both seats: one aboard, so the carrier still has one.
	assert_bool(_aim.can_begin(CarryAim.Mode.BOARD)).is_true()
	Rig.aboard(_world, 2, CARRIER)
	_read()
	assert_bool(_aim.can_begin(CarryAim.Mode.BOARD)).is_false()  # No free seat on the map.


func test_board_rings_only_an_own_carrier_with_a_seat_and_the_check_mark_sends_one_load() -> void:
	_select([1, 2, 4])  # The tank is not a squad: it is left out of the LOAD.
	assert_bool(_aim.toggle(CarryAim.Mode.BOARD)).is_true()
	assert_bool(_aim.can_confirm()).is_false()
	for wrong: int in [1, 4, 6, 99, 0]:  # A squad, a tank, an enemy squad, no row, nothing.
		assert_bool(_aim.pick_carrier(wrong)).is_false()
	assert_int(_refused).is_equal(5)
	assert_bool(_aim.confirm()).is_false()  # No carrier ringed: nothing sent, and the aim ends.
	assert_array(_sent).is_empty()
	assert_bool(_aim.is_active()).is_false()
	_aim.toggle(CarryAim.Mode.BOARD)
	assert_bool(_aim.pick_carrier(CARRIER)).is_true()
	assert_int(_aim.carrier_id).is_equal(CARRIER)
	assert_bool(_aim.confirm()).is_true()
	assert_bool(_aim.confirm()).is_false()  # The mode ended first: a second press is a no-op.
	assert_array(_sent).has_size(1)
	var command: Command = _sent[0]
	assert_array([command.type, command.target_id]).is_equal([Command.Type.LOAD, CARRIER])
	assert_array(Array(command.unit_ids)).is_equal([1, 2])
	# The sim takes the Command the aim sent: both squads are marked for the carrier.
	Rig.step(_world, [command])
	assert_int(_world.order_target[_world.index_of(1)]).is_equal(CARRIER)
	assert_int(_world.dropped_commands).is_equal(0)


func test_unload_sets_and_moves_a_point_inside_the_map_and_sends_one_unload() -> void:
	Rig.aboard(_world, 1, CARRIER)
	_read()
	_select([CARRIER, 4])  # The tank is no loaded carrier: it is left out.
	assert_bool(_aim.toggle(CarryAim.Mode.UNLOAD)).is_true()
	_aim.place(Vector2i(8000, 3000))
	_aim.place(Vector2i(-5000, 999999))  # Another tap moves it, held inside the map.
	assert_bool(_aim.has_point).is_true()
	assert_vector(_aim.point).is_equal(Vector2i(0, 5999))
	assert_bool(_aim.confirm()).is_true()
	assert_array(_sent).has_size(1)
	var command: Command = _sent[0]
	assert_int(command.type).is_equal(Command.Type.UNLOAD)
	assert_array(Array(command.unit_ids)).is_equal([CARRIER])
	assert_array([command.target_x, command.target_y]).is_equal([0, 5999])
	Rig.step(_world, [command])
	assert_int(_world.carry_mode[_world.index_of(CARRIER)]).is_equal(1)
	assert_int(_world.dropped_commands).is_equal(0)


func test_a_second_tap_the_x_and_a_check_mark_with_nothing_set_send_nothing() -> void:
	Rig.aboard(_world, 1, CARRIER)
	_read()
	_select([CARRIER])
	_aim.toggle(CarryAim.Mode.UNLOAD)
	assert_bool(_aim.confirm()).is_false()  # No point: nothing sent, the aim ends.
	_aim.toggle(CarryAim.Mode.UNLOAD)
	_aim.place(Vector2i(8000, 3000))
	assert_bool(_aim.toggle(CarryAim.Mode.UNLOAD)).is_false()  # The lit button again: it ends.
	assert_bool(_aim.is_active()).is_false()
	_aim.toggle(CarryAim.Mode.UNLOAD)
	_aim.place(Vector2i(8000, 3000))
	_aim.cancel()  # The X.
	assert_array(_sent).is_empty()
	assert_bool(_aim.has_point).is_false()


func test_the_aim_ends_when_the_selection_the_match_or_another_mode_takes_it_away() -> void:
	_select([1, 2])
	_aim.toggle(CarryAim.Mode.BOARD)
	_aim.pick_carrier(CARRIER)
	_select([4])  # No squad left in the selection.
	_aim.refresh()
	assert_bool(_aim.is_active()).is_false()
	_select([1, 2])
	_aim.toggle(CarryAim.Mode.BOARD)
	_read(1)  # A new match.
	assert_bool(_aim.is_active()).is_false()
	_aim.toggle(CarryAim.Mode.BOARD)
	_aim.pick_carrier(CARRIER)
	_world.hp[_world.index_of(CARRIER)] = 0  # The ringed carrier dies: the ring goes, the aim stays.
	_world.remove_dead()
	_read(1)
	assert_bool(_aim.is_active()).is_true()
	assert_int(_aim.carrier_id).is_equal(0)
	var strike: StrikeAim = auto_free(StrikeAim.new())
	_aim.strike_aim = strike
	strike.changed.connect(_aim._on_other_mode)
	strike.active = true
	strike.changed.emit()  # The strike aim begins: one mode owns the taps.
	assert_bool(_aim.is_active()).is_false()
	assert_array(_sent).is_empty()
