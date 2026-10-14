extends GdUnitTestSuite
## What follows a field belongs to INTEGRATE (P37b; ADR 0013 section 1): `nav_next` with
## `best_neighbour`, the stall and the ATTACK re-key are `Movement.integrate`'s, so the INTEGRATE
## kernel (P37n) ports them; `Movement.run` keeps the steering and the line checks and only reads
## `nav_next`. The cases call the two phases on their own, with hand-set state, and show which phase
## does what. Further cases pin the rules that keep the work at event cadence: no lookup on ground
## the field does not reach, and a line check again for a unit the rock stops dead. Maps are built
## in code (GridWorld).

const GridWorld: GDScript = preload("res://tests/sim/support/grid_world.gd")
const CountingField: GDScript = preload("res://tests/sim/support/counting_field.gd")
const MOVE: int = World.Order.MOVE
const IDLE: int = World.Order.IDLE
const DIRECT: int = World.NavMode.DIRECT
const FIELD: int = World.NavMode.FIELD
const FOOT: int = World.MoveClass.FOOT


## A tank west of a wall (column 8, rows 0 to 8 of a 20 x 12 map) follows its complete field. With
## `nav_next` reset to -1, `Movement.run` asks `best_neighbour` never and leaves `nav_next` at -1
## (the unit steers at its goal); `Movement.integrate` asks once, for the unit's tile, and sets
## `nav_next` to the answer. The intents are zeroed first, so the unit stays in its tile.
func test_integrate_sets_nav_next_and_run_alone_asks_nothing() -> void:
	var world: World = _wall_world()
	world.add_unit(1, 0, 3500, 2500)
	var counting: CountingField = _count_slots(world)[0]
	var order: Command = Command.move(1, PackedInt32Array([1]), 14500, 2500)
	for tick: int in 80:
		Sim.step(world, _given(order, tick))
		if world.nav_mode[0] == FIELD and counting.complete and world.nav_next[0] >= 0:
			break
	assert_array([world.nav_mode[0], world.field[0], counting.complete]).is_equal([FIELD, 0, true])
	var cell: int = world.cell_of(world.pos_x[0], world.pos_y[0])
	counting.counted = false
	var named: int = counting.best_neighbour(cell)
	counting.counted = true
	assert_int(named).is_greater(-1)
	world.nav_next[0] = -1
	var asked: int = counting.lookups
	Movement.run(world)
	assert_array([counting.lookups - asked, world.nav_next[0]]).is_equal([0, -1])
	world.intent_x.fill(0)
	world.intent_y.fill(0)
	Movement.integrate(world)
	assert_array([counting.lookups - asked, world.nav_next[0]]).is_equal([1, named])
	assert_int(world.cell_of(world.pos_x[0], world.pos_y[0])).is_equal(cell)


## The stall is counted by `Movement.integrate`, also for a unit that does not move: a DIRECT unit
## with a checked line, 1000 from its goal, with `stall_ticks` 3 and no intent. The first call
## records the distance, the next three count, and the third count (call 4) ends the order where
## the unit stands. On that call the unit has an intent of 100 and a push of 30: the stall drops the
## intent, the push still moves the unit (the unit is IDLE, but not nailed down). `Movement.run`
## alone, ten times, changes none of it.
func test_integrate_counts_the_stall_and_run_alone_does_not() -> void:
	var world: World = _stall_world()
	var twin: World = _stall_world()
	for _call: int in 10:
		Movement.run(twin)
	assert_array([twin.stall[0], twin.best_dist[0], twin.order[0]]).is_equal(
		[0, FlowField.UNREACHED, MOVE]
	)
	var seen: Array[Array] = []
	for call: int in 4:
		if call == 3:
			world.intent_x[0] = 100
			world.push_x[0] = 30
		Movement.integrate(world)
		seen.append([world.best_dist[0], world.stall[0], world.order[0]])
	(
		assert_array(seen)
		. is_equal(
			[
				[1000, 0, MOVE],
				[1000, 1, MOVE],
				[1000, 2, MOVE],
				[FlowField.UNREACHED, 0, IDLE],
			]
		)
	)
	assert_array([world.goal_x[0], world.goal_y[0], world.nav_mode[0]]).is_equal(
		[5000, 2000, World.NavMode.NONE]
	)
	assert_array([world.intent_x[0], world.pos_x[0], world.pos_y[0]]).is_equal([0, 5030, 2000])


## The ATTACK re-key is `Movement.integrate`'s. An attacker follows the field keyed on its target's
## tile; the target's position (the goal) then moves 5000 away, and the unit's next lookup event
## (`nav_next` -1 on a complete field) takes the field of the new tile: `Movement.run` leaves the
## field alone, `Movement.integrate` re-keys it.
func test_integrate_rekeys_an_attack_field_and_run_alone_does_not() -> void:
	var world: World = _wall_world()
	world.player_count = 2
	world.type_weapon[0] = 0
	world.add_unit(1, 0, 3500, 2500)
	world.add_unit(2, 0, 14500, 2500)
	var order: Command = Command.attack(1, PackedInt32Array([1]), 2)
	for tick: int in 80:
		Sim.step(world, _given(order, tick))
		if world.field[0] >= 0 and world.flow.field(world.field[0]).complete:
			break
	var old: int = world.field[0]
	assert_int(old).is_greater(-1)
	assert_int(world.flow.key_goal[old]).is_equal(world.cell_of(14500, 2500))
	world.goal_x[0] = 19500
	world.nav_next[0] = -1
	Movement.run(world)
	assert_int(world.field[0]).is_equal(old)
	world.intent_x.fill(0)
	world.intent_y.fill(0)
	Movement.integrate(world)
	assert_int(world.field[0]).is_not_equal(old)
	assert_int(world.flow.key_goal[world.field[0]]).is_equal(world.cell_of(19500, 2500))
	assert_int(world.nav_next[0]).is_equal(-1)


## On ground the field does not reach, `best_neighbour` is asked once and then only at events. Six
## tanks stand west of a wall across the whole map (column 8) with their goals behind it, on their
## own rows: they press on the wall 6500 from their goals (out of the stall range), FIELD on a
## complete field that names no next tile (`nav_next` is the "looked up, none" mark). Over 100 ticks
## the asks are exactly their line-check turns, 20 for each unit: not one per unit and tick.
func test_ground_the_field_does_not_reach_is_asked_on_turns_only() -> void:
	var rock: Array[Vector2i] = []
	for row: int in 12:
		rock.append(Vector2i(8, row))
	var world: World = GridWorld.from_rows(GridWorld.grass(20, 12, rock))
	var rows: PackedInt32Array = PackedInt32Array()
	for k: int in 6:
		world.add_unit(1, 0, 3500, 1000 + k * 2000)
		rows.append(k)
		world.order[k] = MOVE
		world.goal_x[k] = 14500
		world.goal_y[k] = world.pos_y[k]
	Movement.reset_nav(world, rows, DIRECT)
	var counters: Array[CountingField] = _count_slots(world)
	var at_start: int = 0
	for tick: int in 200:
		Sim.step(world, [])
		if tick == 99:
			at_start = _lookups(counters)
	assert_int(_lookups(counters) - at_start).is_equal(120)
	assert_int(world.nav_mode.count(FIELD)).is_equal(6)
	assert_array(world.nav_next.slice(0, 6)).is_equal([-2, -2, -2, -2, -2, -2])
	assert_int(world.nav_next[0]).is_equal(Movement.NO_NEXT)
	assert_array(world.order.slice(0, 6)).is_equal([MOVE, MOVE, MOVE, MOVE, MOVE, MOVE])
	# A new order clears the mark with the rest.
	var again: Command = Command.move(1, PackedInt32Array([1]), 15500, 1000)
	again.tick = world.tick
	Sim.step(world, [again])
	assert_int(world.nav_next[0]).is_not_equal(Movement.NO_NEXT)


## A clear line stays clear, but the truncated steps do not follow it: a shallow line moves no whole
## milli across (the step's y part truncates to 0), so a unit can press on a rock tile the check
## never saw (the segment has moved into the next tile row, the unit has not). A 48 x 36 map with a
## wall in column 20 (rows 18 to 35) and one rock tile at (30, 17): a tank at (8500, 19500) takes a
## field round the wall's end, its line to (43114, 18075) is clear from (22848, 17965), and it runs
## along y 17965 into (30, 17) and stops there, DIRECT with a checked line. When the rock stops a
## DIRECT unit dead its line is marked unchecked, the next check finds the line blocked, and the
## field leads the unit round the tile: it arrives. Without that it stood there for good.
func test_a_unit_the_rock_stops_on_a_clear_line_gets_a_field_and_arrives() -> void:
	var rock: Array[Vector2i] = []
	for row: int in range(18, 36):
		rock.append(Vector2i(20, row))
	rock.append(Vector2i(30, 17))
	for speed: int in [80, 93, 120]:
		var world: World = GridWorld.from_rows(GridWorld.grass(48, 36, rock))
		world.type_speed[0] = speed
		world.add_unit(1, 0, 8500, 19500)
		var order: Command = Command.move(1, PackedInt32Array([1]), 43114, 18075)
		var fielded: bool = false
		for tick: int in 1500:
			Sim.step(world, _given(order, tick))
			fielded = fielded or world.nav_mode[0] == FIELD
			if world.order[0] == IDLE:
				break
		var label: String = "speed %d" % speed
		assert_array([world.goal_x[0], world.goal_y[0]]).is_equal([43114, 18075])
		(
			assert_array([world.pos_x[0], world.pos_y[0], world.order[0]])
			. override_failure_message(label)
			. is_equal([43114, 18075, IDLE])
		)
		assert_bool(fielded).override_failure_message(label).is_true()


## A DIRECT unit that has a field (a state P41's chase hand-off can leave, set by hand here) and a
## blocked line is FIELD in the column too, not only in the check's answer: the field is kept, the
## mode is written, the unit follows the slot. (Otherwise the row stays DIRECT with a slot, and the
## cache keeps counting a reference nothing follows.)
func test_a_blocked_line_keeps_the_field_of_a_direct_unit_and_makes_it_field() -> void:
	var world: World = _wall_world()
	world.add_unit(1, 0, 3500, 2500)
	world.order[0] = MOVE
	world.goal_x[0] = 14500
	world.goal_y[0] = 2500
	Movement.reset_nav(world, PackedInt32Array([0]), DIRECT)
	var slot: int = world.flow.acquire(
		world.cell_of(14500, 2500), World.MoveClass.TRACKED, world.map_version, 0
	)
	world.field[0] = slot
	world.tick = 4
	Movement.run(world)
	assert_array([world.nav_mode[0], world.field[0], world.stats[World.Stat.LINE_CHECKS]]).is_equal(
		[FIELD, slot, 1]
	)
	assert_int(world.nav_cell[0]).is_equal(world.cell_of(3500, 2500))


## A slot nobody holds (FREE) is no field to share, whatever key it was left with: a World that was
## never given a map version (0) has FREE slots keyed on cell 0, class FOOT, version 0. A foot
## soldier whose goal (1500, 500) lies within the distance of that key's tile centre, in sight of
## it, behind a short wall (column 2, rows 0 to 2) from the soldier, takes the field of its own
## goal tile (cell 1), not the stale slot 0 re-keyed on cell 0.
func test_a_free_slot_with_a_stale_key_is_not_a_field_to_share() -> void:
	var rock: Array[Vector2i] = []
	for row: int in 3:
		rock.append(Vector2i(2, row))
	var world: World = GridWorld.from_rows(GridWorld.grass(12, 10, rock), [FOOT])
	world.map_version = 0
	assert_array(world.flow.status.slice(0, 2)).is_equal(
		[FlowCache.Status.FREE, FlowCache.Status.FREE]
	)
	(
		assert_array([world.flow.key_goal[0], world.flow.key_class[0], world.flow.key_version[0]])
		. is_equal([0, FOOT, 0])
	)
	world.add_unit(1, 0, 4500, 500)
	world.order[0] = MOVE
	world.goal_x[0] = 1500
	world.goal_y[0] = 500
	Movement.reset_nav(world, PackedInt32Array([0]), DIRECT)
	world.tick = 4
	Movement.run(world)
	assert_array([world.nav_mode[0], world.stats[World.Stat.LINE_CHECKS]]).is_equal([FIELD, 1])
	assert_int(world.flow.key_goal[world.field[0]]).is_equal(1)


## A 20 x 12 map with a wall in column 8, rows 0 to 8 (a gap in rows 9 to 11).
func _wall_world() -> World:
	var rock: Array[Vector2i] = []
	for row: int in 9:
		rock.append(Vector2i(8, row))
	return GridWorld.from_rows(GridWorld.grass(20, 12, rock))


## An open 20 x 10 map and a tank 1000 from its goal, DIRECT with a checked line, stall after 3.
func _stall_world() -> World:
	var world: World = GridWorld.from_rows(GridWorld.grass(20, 10))
	world.add_unit(1, 0, 5000, 2000)
	world.order[0] = MOVE
	world.goal_x[0] = 6000
	world.goal_y[0] = 2000
	world.nav_mode[0] = DIRECT
	world.nav_cell[0] = world.cell_of(5000, 2000)
	world.stall_ticks = 3
	return world


## The commands of tick `tick`: `order` on tick 0, none after.
func _given(order: Command, tick: int) -> Array[Command]:
	var commands: Array[Command] = []
	if tick == 0:
		order.tick = 0
		commands.append(order)
	return commands


## Puts a counting slot in every slot of the cache; returns them in slot order.
func _count_slots(world: World) -> Array[CountingField]:
	var counters: Array[CountingField] = []
	for slot: int in world.flow.fields.size():
		var counting: CountingField = CountingField.new()
		counting.reserve(world.map_cols, world.map_rows)
		world.flow.fields[slot] = counting
		counters.append(counting)
	return counters


func _lookups(counters: Array[CountingField]) -> int:
	var total: int = 0
	for counting: CountingField in counters:
		total += counting.lookups
	return total
