extends GdUnitTestSuite
## The strike status and the aim (plan P112, ADR 0023 section 10): what `StrikeAim` reads from the
## published snapshot (a strike building of the local player, the first that can fire, the charge,
## the ticks to wait) and the aiming mode. The strike is ready exactly when the sim would take the
## SUPERWEAPON (`Strike.apply_superweapon` is run on the same World to prove it), never while it
## charges, is offline or a rupture of the player's is in the air; a confirm sends exactly one
## Command, a cancel, a missing point and a strike that cannot fire any more send none. The rig is
## strike_rig.gd; the HUD is test_strike_controls', the taps on the map test_strike_taps'.

const Rig: GDScript = preload("res://tests/input/support/strike_rig.gd")

var _world: World
var _aim: StrikeAim
var _controller: PlayerController
var _sent: Array[Command] = []
var _buzzed: Array[int] = []
var _changes: int = 0


func before_test() -> void:
	_world = Rig.world()
	_sent.clear()
	_buzzed.clear()
	_changes = 0
	_controller = auto_free(PlayerController.new())
	_controller.settings = InputSettings.new()
	_controller.command_sink = func(command: Command) -> void: _sent.append(command)
	_controller.vibrate = func(ms: int) -> void: _buzzed.append(ms)
	_aim = auto_free(StrikeAim.new())
	_aim.controller = _controller
	_aim.changed.connect(func() -> void: _changes += 1)
	_read()


## Reads `_world` as it stands, as the next tick's snapshot would be (one match).
func _read(serial: int = 0) -> void:
	if _aim.runner == null:
		_aim.runner = auto_free(Rig.runner(Rig.snapshot(_world, serial)))
	_aim.runner.snapshot = Rig.snapshot(_world, serial)
	_aim.refresh()


func _charge() -> int:
	return _world.type_charge_ticks[Rig.type_of(_world, "fossil_strike")]


func test_a_player_with_no_strike_building_owns_none_and_an_enemys_does_not_count() -> void:
	for id: int in [Rig.BORE_A, Rig.BORE_B, Rig.ARRAY]:  # The enemy's bore is the only one left.
		_world.owner[_world.index_of(id)] = 2
	_read()
	assert_bool(_aim.owned).is_false()
	assert_int(_aim.building_id).is_equal(0)
	assert_bool(_aim.begin()).is_false()
	assert_array(_sent).is_empty()


func test_a_charging_strike_is_owned_follows_the_ring_and_cannot_be_aimed() -> void:
	assert_bool(_aim.owned).is_true()
	assert_int(_aim.building_id).is_equal(0)
	assert_int(_aim.wait).is_equal(_charge())  # Placed at tick 0: ready_tick = 1 + charge.
	assert_float(_aim.share).is_equal_approx(0.0, 0.001)
	_world.tick = _charge() / 2
	_read()
	assert_float(_aim.share).is_equal_approx(0.5, 0.001)
	assert_int(_aim.wait).is_equal(_charge() - _charge() / 2)
	assert_bool(_aim.begin()).is_false()
	assert_bool(_aim.active).is_false()
	assert_bool(_aim.confirm()).is_false()
	assert_array(_sent).is_empty()


## The button is ready on the very tick the sim takes the command, and not a tick earlier: the same
## World is read by the aim and then handed the command.
func test_the_strike_is_ready_exactly_when_the_sim_takes_the_command() -> void:
	var ready_at: int = Rig.fire_tick(_world, Rig.BORE_A)
	for tick: int in range(ready_at - 3, ready_at + 2):
		var made: World = Rig.world()
		made.tick = tick
		_aim.runner.snapshot = Rig.snapshot(made)
		_aim.refresh()
		var taken: bool = Strike.apply_superweapon(
			made, Command.superweapon(1, Rig.BORE_A, 5000, 5000)
		)
		var note: String = "tick %d (ready at %d)" % [tick, ready_at]
		assert_bool(_aim.building_id == Rig.BORE_A).override_failure_message(note).is_equal(taken)
		assert_bool(tick >= ready_at).override_failure_message(note).is_equal(taken)


func test_an_offline_strike_and_a_rupture_in_the_air_hold_every_building() -> void:
	_world.tick = Rig.fire_tick(_world, Rig.BORE_A)
	_read()
	assert_int(_aim.building_id).is_equal(Rig.BORE_A)
	_world.offline_until[_world.index_of(Rig.BORE_A)] = _world.tick + 1 + 7
	_world.offline_until[_world.index_of(Rig.BORE_B)] = _world.tick + 1 + 9
	_world.offline_until[_world.index_of(Rig.ARRAY)] = _world.tick + 1 + 8
	_read()
	assert_int(_aim.building_id).is_equal(0)
	assert_int(_aim.wait).is_equal(7)  # The soonest back.
	assert_float(_aim.share).is_equal_approx(1.0, 0.001)  # Charged, so the ring is full.
	_world.offline_until.fill(0)
	_world.strike_tick[1] = _world.tick + 5  # A rupture of the player's lands in 5 ticks.
	_read()
	assert_array([_aim.building_id, _aim.wait]).is_equal([0, 5])
	_world.strike_tick[1] = 0
	_world.strike_tick[2] = _world.tick + 5  # The enemy's does not hold the player's.
	_read()
	assert_int(_aim.building_id).is_equal(Rig.BORE_A)


func test_the_first_building_that_can_fire_is_the_one_and_the_ring_shows_the_most_charged() -> void:
	var ready_at: int = Rig.fire_tick(_world, Rig.BORE_A)
	_world.tick = ready_at
	_world.ready_tick[_world.index_of(Rig.BORE_A)] += 1000  # Fired a while ago.
	_read()
	assert_int(_aim.building_id).is_equal(Rig.BORE_B)
	_world.ready_tick[_world.index_of(Rig.BORE_B)] += 5000
	_world.ready_tick[_world.index_of(Rig.ARRAY)] += 5000
	_read()
	assert_int(_aim.building_id).is_equal(0)
	var left: int = _world.ready_tick[_world.index_of(Rig.BORE_A)] - (_world.tick + 1)
	assert_int(_aim.wait).is_equal(left)  # Bore A is the soonest.
	assert_float(_aim.share).is_equal_approx(1.0 - float(left) / _charge(), 0.001)
	_world.tick = Rig.fire_tick(_world, Rig.BORE_A)
	_world.ready_tick[_world.index_of(Rig.BORE_A)] = _world.tick + 1  # Both A and B are ready.
	_world.ready_tick[_world.index_of(Rig.BORE_B)] = _world.tick + 1
	_read()
	assert_int(_aim.building_id).is_equal(Rig.BORE_A)  # The first row.


func test_the_circle_is_the_radius_of_the_building_that_fires() -> void:
	_world.tick = Rig.fire_tick(_world, Rig.ARRAY)
	_world.ready_tick[_world.index_of(Rig.BORE_A)] += 5000
	_world.ready_tick[_world.index_of(Rig.BORE_B)] += 5000
	_read()
	assert_int(_aim.building_id).is_equal(Rig.ARRAY)
	var array_type: int = Rig.type_of(_world, "renew_strike")
	assert_int(_aim.radius).is_equal(_world.type_strike_radius[array_type])
	assert_int(_aim.radius).is_not_equal(
		_world.type_strike_radius[Rig.type_of(_world, "fossil_strike")]
	)


func test_a_confirm_sends_exactly_one_superweapon_for_the_ready_building_at_the_point() -> void:
	_world.tick = Rig.fire_tick(_world, Rig.BORE_A)
	_read()
	assert_bool(_aim.begin()).is_true()
	assert_bool(_aim.confirm()).is_false()  # No point yet.
	assert_bool(_aim.active).is_false()  # And it leaves the mode, as any confirm does.
	assert_bool(_aim.begin()).is_true()
	_aim.place(Vector2i(7500, 9500))
	assert_array([_aim.has_point, _aim.point]).is_equal([true, Vector2i(7500, 9500)])
	assert_bool(_aim.confirm()).is_true()
	assert_bool(_aim.confirm()).is_false()  # A second press of the check mark is nothing.
	assert_array(_sent).has_size(1)
	var command: Command = _sent[0]
	(
		assert_array(
			[command.type, command.player_id, command.target_id, command.target_x, command.target_y]
		)
		. is_equal([Command.Type.SUPERWEAPON, 1, Rig.BORE_A, 7500, 9500])
	)
	assert_bool(command.unit_ids.is_empty() and command.payload.is_empty()).is_true()
	assert_array(_buzzed).is_equal([_controller.settings.haptic_ms])
	assert_bool(_aim.active).is_false()
	assert_bool(_aim.has_point).is_false()


func test_a_cancel_sends_nothing_and_a_point_is_held_inside_the_map() -> void:
	_world.tick = Rig.fire_tick(_world, Rig.BORE_A)
	_read()
	_aim.place(Vector2i(100, 100))  # Not aiming: nothing.
	assert_bool(_aim.has_point).is_false()
	_aim.begin()
	_aim.place(Vector2i(-5000, 99999))
	assert_array([_aim.point.x, _aim.point.y]).is_equal([0, Rig.ROWS * 1000 - 1])
	_aim.place(Vector2i(99999, -1))
	assert_array([_aim.point.x, _aim.point.y]).is_equal([Rig.COLS * 1000 - 1, 0])
	_aim.cancel()
	assert_array([_aim.active, _aim.has_point]).is_equal([false, false])
	assert_bool(_aim.confirm()).is_false()
	assert_array(_sent).is_empty()
	assert_array(_buzzed).is_empty()


## The strike goes out of reach while the player aims (a blackout lands on the buildings, a rupture
## of the player's own is in the air): the mode ends with no Command.
func test_a_strike_that_cannot_fire_any_more_ends_the_aim_without_a_command() -> void:
	_world.tick = Rig.fire_tick(_world, Rig.BORE_A)
	_read()
	_aim.begin()
	_aim.place(Vector2i(5000, 5000))
	_world.offline_until[_world.index_of(Rig.BORE_A)] = _world.tick + 1 + 50
	_world.offline_until[_world.index_of(Rig.BORE_B)] = _world.tick + 1 + 50
	_world.offline_until[_world.index_of(Rig.ARRAY)] = _world.tick + 1 + 50
	_read()
	assert_array([_aim.active, _aim.has_point]).is_equal([false, false])
	assert_bool(_aim.confirm()).is_false()
	assert_array(_sent).is_empty()


func test_a_new_match_ends_the_aim_and_a_building_that_dies_leaves_no_strike() -> void:
	_world.tick = Rig.fire_tick(_world, Rig.BORE_A)
	_read(3)
	_aim.begin()
	_aim.place(Vector2i(5000, 5000))
	_read(4)
	assert_bool(_aim.active).is_false()
	assert_bool(_aim.owned).is_true()
	for id: int in [Rig.BORE_A, Rig.BORE_B, Rig.ARRAY]:
		_world.hp[_world.index_of(id)] = 0
	_world.remove_dead()
	_read(4)
	assert_bool(_aim.owned).is_false()
	assert_int(_aim.type_index).is_equal(-1)
	assert_int(_aim.radius).is_equal(0)
	assert_array(_sent).is_empty()


## `changed` follows what the button shows: a tick that moves the wait, the owner or the mode, and
## nothing for a tick that moves none of them.
func test_changed_is_told_when_the_status_or_the_aim_moves_and_not_otherwise() -> void:
	var before: int = _changes
	_read()  # The same tick again.
	assert_int(_changes).is_equal(before)
	_world.tick += 1
	_read()
	assert_int(_changes).is_equal(before + 1)
	_world.tick = Rig.fire_tick(_world, Rig.BORE_A)
	_read()
	var ready_count: int = _changes
	_aim.begin()
	_aim.place(Vector2i(5000, 5000))
	_aim.cancel()
	assert_int(_changes).is_equal(ready_count + 3)
