extends GdUnitTestSuite
## Hold position (plan row P298, ADR 0037 section 15): `STANCE` 9 writes the row column `stance`
## (payload `[0]` normal, `[1]` hold) of the player's own mobile units and touches no order; STOP,
## MOVE, ATTACK and ATTACK_MOVE keep it; an unload leaves the carrier's and resets the squads';
## `PlayerView.own_stance` copies the own rows' stance only. The rules of the TARGETING phase are in
## tests/sim/native/test_targeting_lockstep_hold.gd, under both implementations.

const Layers: GDScript = preload("res://tests/sim/support/layer_worlds.gd")
const CarryRig: GDScript = preload("res://tests/sim/support/carry_rig.gd")
## Rows: 0 and 1 are player 1's guns (ids 1, 2), 2 is an enemy gun (id 3), 3 is a speed-0 post
## of player 1 (id 4).
const GUN: int = Layers.GUN
const POST: int = Layers.POST


func _world() -> World:
	var world: World = Layers.empty()
	world.add_unit(1, GUN, 4000, 6000)
	world.add_unit(1, GUN, 4000, 7000)
	world.add_unit(2, GUN, 15000, 6000)
	world.add_unit(1, POST, 6000, 9000)
	return world


## Runs one tick of `world` with `command`, stamped with that tick.
func _step(world: World, command: Command) -> void:
	command.tick = world.tick
	Sim.step(world, [command])


func _cmd(player: int, ids: Array, payload: Array) -> Command:
	var command: Command = Command.new()
	command.type = Command.Type.STANCE
	command.player_id = player
	command.unit_ids = PackedInt32Array(ids)
	command.payload = PackedInt32Array(payload)
	return command


func test_the_command_has_its_number_and_a_factory() -> void:
	assert_int(Command.Type.STANCE).is_equal(9)
	var hold: Command = Command.stance(1, PackedInt32Array([1, 2]), true)
	assert_array([hold.type, Array(hold.unit_ids), Array(hold.payload)]).is_equal([9, [1, 2], [1]])
	assert_array(Array(Command.stance(1, PackedInt32Array([1]), false).payload)).is_equal([0])


func test_it_sets_and_clears_the_stance_of_own_mobile_units_only() -> void:
	var world: World = _world()
	assert_array(Array(world.stance)).is_equal([0, 0, 0, 0])
	_step(world, _cmd(1, [1, 3, 4, 99], [1]))
	# Id 3 is the enemy's, 4 cannot move, 99 does not exist: skipped silently.
	assert_array(Array(world.stance)).is_equal([1, 0, 0, 0])
	assert_int(world.dropped_commands).is_equal(0)
	_step(world, _cmd(1, [1, 2], [0]))
	assert_array(Array(world.stance)).is_equal([0, 0, 0, 0])


func test_it_is_dropped_with_a_bad_payload_or_no_valid_unit() -> void:
	var bad: Array[Command] = [
		_cmd(1, [1], []),
		_cmd(1, [1], [2]),
		_cmd(1, [1], [-1]),
		_cmd(1, [1], [1, 1]),
		_cmd(1, [3], [1]),
		_cmd(1, [4], [1]),
		_cmd(1, [], [1]),
		_cmd(2, [1], [1]),
	]
	for command: Command in bad:
		var world: World = _world()
		_step(world, command)
		assert_int(world.dropped_commands).is_equal(1)
		assert_array(Array(world.stance)).is_equal([0, 0, 0, 0])


func test_it_touches_no_order_and_stop_move_and_attack_move_keep_it() -> void:
	var world: World = _world()
	_step(world, _cmd(1, [1], [1]))
	_step(world, Command.attack_move(1, PackedInt32Array([1]), 9000, 6000))
	assert_array([world.order[0], world.stance[0]]).is_equal([World.Order.ATTACK_MOVE, 1])
	_step(world, Command.move(1, PackedInt32Array([1]), 8000, 6000))
	assert_array([world.order[0], world.stance[0]]).is_equal([World.Order.MOVE, 1])
	_step(world, Command.stop(1, PackedInt32Array([1])))
	assert_array([world.order[0], world.stance[0]]).is_equal([World.Order.IDLE, 1])
	# A stance given to a row with an order leaves the order alone.
	_step(world, Command.attack_move(1, PackedInt32Array([2]), 9000, 7000))
	_step(world, _cmd(1, [2], [1]))
	assert_array([world.order[1], world.stance[1]]).is_equal([World.Order.ATTACK_MOVE, 1])


func test_the_player_view_copies_the_stance_of_own_rows_only() -> void:
	var world: World = _world()
	world.stance[0] = 1
	world.stance[2] = 1
	var view: PlayerView = PlayerView.of(world, 1)
	assert_int(view.own_stance.size()).is_equal(view.own_rows.size())
	assert_array(Array(view.own_rows)).is_equal([0, 1, 3])
	assert_array(Array(view.own_stance)).is_equal([1, 0, 0])
	# Two worlds that differ only in an enemy's stance give equal views.
	var other: World = _world()
	other.stance[0] = 1
	assert_array(Array(PlayerView.of(other, 1).own_stance)).is_equal(Array(view.own_stance))
	# A copy: a later change to the World does not reach the view.
	world.stance[1] = 1
	assert_array(Array(view.own_stance)).is_equal([1, 0, 0])


func test_an_attack_and_an_unarmed_mobile_unit_keep_or_take_the_stance() -> void:
	var world: World = _world()
	Sim.step(world, [_stamped(world, _cmd(1, [1], [1]))])
	Sim.step(world, [_stamped(world, Command.attack(1, PackedInt32Array([1]), 3))])
	assert_array([world.order[0], world.stance[0]]).is_equal([World.Order.ATTACK, 1])
	# Layers.SCOUT: mobile and unarmed, so a harvester or carrier takes the stance too.
	var scout: int = world.add_unit(1, Layers.SCOUT, 9000, 9000)
	Sim.step(world, [_stamped(world, _cmd(1, [scout], [1]))])
	assert_int(world.stance[world.index_of(scout)]).is_equal(1)


## A held carrier that unloads keeps its stance; the squads come out at 0 (ADR 0037 section 15,
## "0 at spawn and at unload": a stance does not ride in the passenger table).
func test_unloaded_squads_come_out_normal_and_the_carrier_keeps_its_stance() -> void:
	var world: World = CarryRig.world(CarryRig.REACH, 8, [])
	CarryRig.aboard(world, 1, 5)
	CarryRig.aboard(world, 2, 5)
	world.stance[world.index_of(5)] = 1
	CarryRig.step(world, [Command.unload(1, PackedInt32Array([5]), 9500, 2500)])
	for _tick: int in 400:
		CarryRig.step(world)
		if world.pass_count == 0:
			break
	assert_int(world.pass_count).is_equal(0)
	assert_int(world.stance[world.index_of(5)]).is_equal(1)
	for id: int in [1, 2]:
		assert_int(world.stance[world.index_of(id)]).is_equal(0)


func _stamped(world: World, command: Command) -> Command:
	command.tick = world.tick
	return command
