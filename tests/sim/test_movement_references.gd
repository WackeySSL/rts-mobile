extends GdUnitTestSuite
## Flow field references and ATTACK fields (P37b; ADR 0008 section 3). References are derived: the
## cache recounts each slot's references from the World's `field` column, so a new order, STOP,
## arrival, stall, a line that turned clear and a death all release a slot by no longer pointing at
## it, and a slot nobody references is the one a new key takes. An ATTACK unit's field is keyed on
## the tile its target stood in and re-keyed when the target moves more than `attack_rekey_milli`.
## Maps are built in code (GridWorld).

const GridWorld: GDScript = preload("res://tests/sim/support/grid_world.gd")
const FieldCadence: GDScript = preload("res://tests/sim/support/field_cadence.gd")
const MOVE: int = World.Order.MOVE
const ATTACK: int = World.Order.ATTACK
const IDLE: int = World.Order.IDLE
const DIRECT: int = World.NavMode.DIRECT
const FIELD: int = World.NavMode.FIELD


## A 24 x 12 map: a wall in column 8 with a gap in rows 10 and 11, and a wall across column 18. The
## cache has 3 slots and four tanks ask for four different fields (goals more than 4000 apart or
## out of each other's sight). Unit 4 is east of the first wall with its goal behind the second:
## its field never reaches it, so it presses on the wall and stalls. Unit 1 asks last (ticks 1, 2, 3
## and 4 are the turns of units 4, 3, 2 and 1), finds every slot referenced and waits, DIRECT with
## an unchecked line. The first slot that no row points at any more (a stall, or a line that turned
## clear) is the one its next key takes; the slots with references keep their keys. Then STOP, a
## death and the arrival release the others. After every step the cache's counts equal the rows
## that point at each slot.
func test_references_are_derived_and_an_unreferenced_slot_is_evicted_first() -> void:
	var rock: Array[Vector2i] = []
	for row: int in 12:
		rock.append(Vector2i(18, row))
		if row < 10:
			rock.append(Vector2i(8, row))
	var world: World = GridWorld.from_rows(GridWorld.grass(24, 12, rock))
	world.flow.configure(world.map_cols, world.map_rows, World.MoveClass.size(), 3)
	var goals: Array[Vector2i] = [
		Vector2i(10500, 1500), Vector2i(16500, 4500), Vector2i(10500, 9500), Vector2i(19500, 5500)
	]
	var starts: Array[Vector2i] = [
		Vector2i(3500, 1500), Vector2i(3500, 3500), Vector2i(3500, 5500), Vector2i(12500, 5500)
	]
	var orders: Array[Command] = []
	for index: int in 4:
		world.add_unit(1, 0, starts[index].x, starts[index].y)
		var ids: PackedInt32Array = PackedInt32Array([index + 1])
		orders.append(_stamped(Command.move(1, ids, goals[index].x, goals[index].y), 0))
	Sim.step(world, orders)
	var tick: int = 1
	while tick < 8:
		Sim.step(world, [])
		tick += 1
	_assert_derived(world, "after the orders")
	assert_array([world.order[0], world.nav_mode[0], world.field[0]]).is_equal([MOVE, DIRECT, -1])
	assert_int(world.nav_cell[0]).is_equal(-1)
	assert_array(world.nav_mode.slice(1, 4)).is_equal([FIELD, FIELD, FIELD])
	assert_array(world.flow.status).is_equal([2, 2, 2])
	# Step until unit 1 gets a slot. Every tick: the counts are derived, and the slot it takes is
	# one that no row pointed at when the tick began, while the keys of the others do not change.
	var stalled_at: int = -1
	while world.field[0] == -1 and tick < 400:
		var pointed: PackedInt32Array = world.field.duplicate()
		var keys: PackedInt32Array = world.flow.key_goal.duplicate()
		Sim.step(world, [])
		tick += 1
		_assert_derived(world, "tick %d" % tick)
		stalled_at = tick if stalled_at == -1 and world.order[3] == IDLE else stalled_at
		if world.field[0] != -1:
			(
				assert_bool(world.field[0] in pointed)
				. override_failure_message("took a slot in use")
				. is_false()
			)
			for slot: int in 3:
				if slot != world.field[0]:
					assert_int(world.flow.key_goal[slot]).is_equal(keys[slot])
	var taken: int = world.field[0]
	assert_int(taken).is_greater(-1)
	assert_int(world.flow.key_goal[taken]).is_equal(world.cell_of(goals[0].x, goals[0].y))
	# Unit 4 stalls on the wall some time later at the latest: IDLE, no field, no reference.
	while world.order[3] != IDLE and tick < 400:
		Sim.step(world, [])
		tick += 1
		_assert_derived(world, "tick %d" % tick)
	assert_array([world.order[3], world.field[3], world.pos_x[3] < 18000]).is_equal(
		[IDLE, -1, true]
	)
	# STOP releases unit 2's slot.
	var held: int = world.field[1]
	assert_int(held).is_greater(-1)
	Sim.step(world, [_stamped(Command.stop(1, PackedInt32Array([2])), tick)])
	tick += 1
	_assert_derived(world, "after STOP")
	assert_array([world.field[1], world.flow.refs(held)]).is_equal([-1, 0])
	# A death: unit 3 (row 2, DIRECT by now, no field) dies and the rows move up; the others keep
	# their fields and the counts stay derived. A death of a unit that holds a slot is the next test.
	assert_int(world.field[2]).is_equal(-1)
	world.hp[2] = 0
	Sim.step(world, [])
	tick += 1
	assert_int(world.unit_count()).is_equal(3)
	assert_int(world.field[0]).is_equal(taken)
	_assert_derived(world, "after a death")
	# Arrival: unit 1 reaches its goal and nobody points at any slot.
	while world.order[0] != IDLE and tick < 900:
		Sim.step(world, [])
		tick += 1
		_assert_derived(world, "tick %d" % tick)
	assert_array([world.pos_x[0], world.pos_y[0]]).is_equal([goals[0].x, goals[0].y])
	assert_int(world.field.count(-1)).is_equal(3)
	for slot: int in 3:
		assert_int(world.flow.refs(slot)).is_equal(0)


## A death releases the slot of the unit that held it. Two tanks follow fields of their own (goals
## 10000 apart, a cache of 2 slots); the first dies: the rows compact, the second keeps its slot in
## row 0, the dead unit's slot has no references after the next recount, and a third tank's new key
## takes that slot, not the one still in use.
func test_a_death_releases_the_slot_of_the_unit_that_held_it() -> void:
	var rock: Array[Vector2i] = []
	for row: int in 10:
		rock.append(Vector2i(8, row))
	var world: World = GridWorld.from_rows(GridWorld.grass(20, 12, rock))
	world.flow.configure(world.map_cols, world.map_rows, World.MoveClass.size(), 2)
	world.add_unit(1, 0, 3500, 1500)
	world.add_unit(1, 0, 3500, 5500)
	world.add_unit(1, 0, 3500, 3500)
	var goals: Array[Vector2i] = [Vector2i(14500, 1500), Vector2i(14500, 11500)]
	for row: int in 2:
		world.order[row] = MOVE
		world.goal_x[row] = goals[row].x
		world.goal_y[row] = goals[row].y
	Movement.reset_nav(world, PackedInt32Array([0, 1]), DIRECT)
	for _tick: int in 30:
		Sim.step(world, [])
	var doomed: int = world.field[0]
	var kept: int = world.field[1]
	assert_bool(doomed >= 0 and kept >= 0 and doomed != kept).is_true()
	assert_array([world.nav_mode[0], world.nav_mode[1]]).is_equal([FIELD, FIELD])
	_assert_derived(world, "before the death")
	assert_array([world.flow.refs(doomed), world.flow.refs(kept)]).is_equal([1, 1])
	world.hp[0] = 0
	Sim.step(world, [])
	assert_int(world.unit_count()).is_equal(2)
	assert_array(world.field.slice(0, 2)).is_equal([kept, -1])
	_assert_derived(world, "after the death")
	assert_array([world.flow.refs(doomed), world.flow.refs(kept)]).is_equal([0, 1])
	# The third tank (now row 1) asks for a field of its own: the slot nobody holds is the one taken.
	world.order[1] = MOVE
	world.goal_x[1] = 14500
	world.goal_y[1] = 6500
	Movement.reset_nav(world, PackedInt32Array([1]), DIRECT)
	for _tick: int in 10:
		Sim.step(world, [])
	assert_array([world.field[0], world.field[1]]).is_equal([kept, doomed])
	assert_int(world.flow.key_goal[doomed]).is_equal(world.cell_of(14500, 6500))


## An ATTACK unit's field is keyed on the tile its target stands in, and stays while the target
## moves 4000 or less from the centre of that tile; beyond that the unit takes the field of the
## target's new tile at its next event (a tile entered, or its line-check turn), and the old slot
## is released. The map is 20 x 12 with a wall in column 8 and a gap in rows 10 and 11.
func test_an_attack_field_is_keyed_on_the_targets_tile_and_rekeys_beyond_the_distance() -> void:
	var world: World = _attack_world()
	var old_slot: int = _attack_until_field(world)
	assert_int(old_slot).is_greater(-1)
	assert_array([world.order[0], world.nav_mode[0]]).is_equal([ATTACK, FIELD])
	assert_int(world.flow.key_goal[old_slot]).is_equal(world.cell_of(14500, 2500))
	assert_array([world.goal_x[0], world.goal_y[0]]).is_equal([14500, 2500])
	# The target walks 2500 away: the same field, for 30 ticks.
	world.pos_x[1] = 17000
	for _tick: int in 30:
		Sim.step(world, [])
		assert_int(world.field[0]).is_equal(old_slot)
	assert_int(world.flow.key_goal[old_slot]).is_equal(world.cell_of(14500, 2500))
	# It walks on, 5000 from the old key's centre: the unit asks for the field of the new tile.
	world.pos_x[1] = 19500
	for _tick: int in 12:
		Sim.step(world, [])
	var new_slot: int = world.field[0]
	assert_int(new_slot).is_not_equal(old_slot)
	assert_int(world.flow.key_goal[new_slot]).is_equal(world.cell_of(19500, 2500))
	FlowCache.run(world, 0)
	assert_array([world.flow.refs(old_slot), world.flow.refs(new_slot)]).is_equal([0, 1])
	assert_int(world.order[0]).is_equal(ATTACK)


## The distance is "more than" `attack_rekey_milli` from the centre of the keyed tile: a target 4000
## away keeps the field, one milli further re-keys.
func test_the_rekey_distance_is_more_than_attack_rekey_milli() -> void:
	for far: int in [3999, 4000, 4001]:
		var world: World = _attack_world()
		var slot: int = _attack_until_field(world)
		world.pos_x[1] = 14500 + far
		for _tick: int in 12:
			Sim.step(world, [])
		var label: String = "%d away" % far
		var kept: bool = world.field[0] == slot
		assert_bool(kept).override_failure_message(label).is_equal(far <= 4000)


## The re-key distance is the World's `attack_rekey_milli`: with 2000, a target 2500 from the keyed
## tile's centre (which the default 4000 keeps) gets a field of its own tile.
func test_the_rekey_distance_is_the_worlds_rule() -> void:
	var world: World = _attack_world()
	world.attack_rekey_milli = 2000
	var slot: int = _attack_until_field(world)
	world.pos_x[1] = 14500 + 2500
	for _tick: int in 12:
		Sim.step(world, [])
	assert_bool(world.field[0] != slot).is_true()
	assert_int(world.flow.key_goal[world.field[0]]).is_equal(world.cell_of(17000, 2500))


## The re-key is decided by the distance alone, not by sight: the target steps 3000, 4000 or 4001
## south of the keyed tile's centre, with a rock tile (14, 4) between the target and that centre, so
## the key is out of the target's sight. 3000 and exactly 4000 keep the field (the limit is
## inclusive), 4001 takes the field of the target's tile.
func test_the_rekey_keeps_a_key_within_the_distance_though_the_target_cannot_see_it() -> void:
	for far: int in [3000, 4000, 4001]:
		var world: World = _attack_world([Vector2i(14, 4)])
		var slot: int = _attack_until_field(world)
		assert_int(slot).is_greater(-1)
		world.pos_y[1] = 2500 + far
		for _tick: int in 12:
			Sim.step(world, [])
		var label: String = "%d away" % far
		assert_bool(world.field[0] == slot).override_failure_message(label).is_equal(far <= 4000)
		if far > 4000:
			var rekeyed: int = world.flow.key_goal[world.field[0]]
			assert_int(rekeyed).is_equal(world.cell_of(14500, 2500 + far))


## An ATTACK unit takes the field of its target's tile, not one it could share: a tank (row 0) has
## the field of (14, 2); the attacker (row 1) checks on the same tick (period 1), its target stands
## 2000 from that key's centre in clear sight, and still the attacker gets a field of its own,
## keyed on the target's tile (14, 4).
func test_an_attack_takes_the_field_of_its_targets_tile_though_another_unit_holds_one_to_share(
) -> void:
	var rock: Array[Vector2i] = []
	for row: int in 10:
		rock.append(Vector2i(8, row))
	var world: World = GridWorld.from_rows(GridWorld.grass(20, 12, rock))
	world.player_count = 2
	world.type_weapon[0] = 0
	world.line_check_period_ticks = 1
	world.add_unit(1, 0, 3500, 1500)
	world.add_unit(1, 0, 3500, 2500)
	world.add_unit(2, 0, 14500, 4500)
	world.order[0] = MOVE
	world.goal_x[0] = 14500
	world.goal_y[0] = 2500
	Movement.reset_nav(world, PackedInt32Array([0]), DIRECT)
	Sim.step(world, [_stamped(Command.attack(1, PackedInt32Array([2]), 3), 0)])
	assert_array([world.nav_mode[0], world.nav_mode[1]]).is_equal([FIELD, FIELD])
	assert_array(world.field.slice(0, 2)).is_equal([0, 1])
	assert_array(world.flow.key_goal.slice(0, 2)).is_equal(
		[world.cell_of(14500, 2500), world.cell_of(14500, 4500)]
	)


## A pending field is not re-keyed under the unit: with a flow budget of 0 the attacker's field
## never completes, the target walks 5000 away, and for 30 ticks (line-check turns and tile
## entries) the unit keeps its slot. When the budget comes back the field completes, and at that
## event the unit takes the field of its target's tile. (A target that keeps walking cannot starve
## the unit of a finished field: it follows the old one while the new one integrates.)
func test_an_attack_unit_keeps_a_pending_field_until_it_completes_then_rekeys() -> void:
	var world: World = _attack_world()
	world.flow_cells_per_tick = 0
	var slot: int = _attack_until_field(world)
	assert_int(slot).is_greater(-1)
	assert_bool(world.flow.field(slot).complete).is_false()
	world.pos_x[1] = 19500
	for _tick: int in 30:
		Sim.step(world, [])
		assert_int(world.field[0]).is_equal(slot)
	world.flow_cells_per_tick = 512
	for _tick: int in 30:
		Sim.step(world, [])
	assert_int(world.field[0]).is_not_equal(slot)
	assert_int(world.flow.key_goal[world.field[0]]).is_equal(world.cell_of(19500, 2500))


## An ATTACK unit asks `best_neighbour` at event cadence like any FIELD unit (FieldCadence holds the
## rule): on the tick its field completes, on a tile entered, and on its line-check turn; on every
## other tick not at all, and `nav_next` keeps its value. The target stands still, so the field is
## never re-keyed; refreshing an ATTACK unit's `nav_next` on every tick would fail the count.
func test_an_attack_unit_asks_best_neighbour_at_event_cadence_only() -> void:
	var world: World = _attack_world()
	var order: Command = Command.attack(1, PackedInt32Array([1]), 2)
	var found: Dictionary = FieldCadence.run(world, order, 300)
	assert_array(found["violations"]).is_empty()
	assert_array([found["entry"] > 3, found["turn"] > 3, found["completion"]]).is_equal(
		[true, true, 1]
	)
	assert_int(found["lookups"]).is_less(found["followed"] / 2)
	assert_int(world.order[0]).is_equal(ATTACK)


## An ATTACK on a target in the open needs no field at all: a clear line stays DIRECT.
func test_an_attack_with_a_clear_line_needs_no_field() -> void:
	var world: World = _attack_world()
	world.pos_x[1] = 6500
	for tick: int in 20:
		var commands: Array[Command] = []
		if tick == 0:
			commands.append(_stamped(Command.attack(1, PackedInt32Array([1]), 2), 0))
		Sim.step(world, commands)
	assert_array([world.nav_mode[0], world.field[0]]).is_equal([DIRECT, -1])


## A 20 x 12 map with a wall in column 8 (gap in rows 10 and 11) and the `extra` rock tiles, a tank
## of player 1 at (3500, 2500) and an unarmed unit of player 2 at (14500, 2500).
func _attack_world(extra: Array[Vector2i] = []) -> World:
	var rock: Array[Vector2i] = extra.duplicate()
	for row: int in 10:
		rock.append(Vector2i(8, row))
	var world: World = GridWorld.from_rows(GridWorld.grass(20, 12, rock))
	world.player_count = 2
	world.type_weapon[0] = 0
	world.add_unit(1, 0, 3500, 2500)
	world.add_unit(2, 0, 14500, 2500)
	return world


## Orders unit 1 to attack unit 2 and steps until the attacker follows a field; returns its slot.
func _attack_until_field(world: World) -> int:
	for tick: int in 30:
		var commands: Array[Command] = []
		if tick == 0:
			commands.append(_stamped(Command.attack(1, PackedInt32Array([1]), 2), 0))
		Sim.step(world, commands)
		if world.field[0] >= 0:
			return world.field[0]
	return -1


## Recounts the cache and checks that every slot's count equals the number of rows that point at
## it, and that no row points at a number that is no slot.
func _assert_derived(world: World, label: String) -> void:
	FlowCache.run(world, 0)
	for slot: int in world.flow.status.size():
		var pointing: int = world.field.count(slot)
		(
			assert_int(world.flow.refs(slot))
			. override_failure_message("%s: slot %d" % [label, slot])
			. is_equal(pointing)
		)
	for slot: int in world.field:
		assert_bool(slot == -1 or slot < world.flow.status.size()).is_true()


func _stamped(command: Command, tick: int) -> Command:
	command.tick = tick
	return command
