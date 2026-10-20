extends GdUnitTestSuite
## Engagement across rock (P41b; ADR 0009 section 3): a unit chases its target only while the
## straight line to it is clear, so units use the gaps in the rock instead of pressing into it. The
## map is 30 x 12 tiles with a band of rock four tiles thick (columns 13 to 16, x 13000 to 17000)
## over rows 0 to 9, and a gap in rows 10 and 11. Two rifle squads (range 4000, acquire 5000, sight
## 6000, speed 67) stand on opposite sides of it, 5000 apart at x 12500 and 17500 (each in the tile
## beside the band, so each is within acquire range of the other and out of weapon range, as in
## the plan review's deadlock). The line between them is blocked, and so is the line to each one's
## goal on the other side. The cases of test_engagement.gd cover the open ground. Acquisition,
## the line check and the cadence are the rules' own: `retarget_period_ticks` and
## `line_check_period_ticks` are 5, so a unit checks on the ticks where `(tick + id) % 5 == 0`.

const Rig: GDScript = preload("res://tests/sim/support/targeting_rig.gd")
const GridWorld: GDScript = preload("res://tests/sim/support/grid_world.gd")
const RIFLE: int = 0
const TANK: int = 2
const FOOT: int = World.MoveClass.FOOT
const COLUMNS: int = 30
const ROCK: int = 2
const NONE: int = World.NavMode.NONE
const DIRECT: int = World.NavMode.DIRECT
const FIELD: int = World.NavMode.FIELD
const HOLD: int = World.NavMode.HOLD
const CHASE: int = World.NavMode.CHASE
const ATTACK_MOVE: int = World.Order.ATTACK_MOVE
const ATTACK: int = World.Order.ATTACK
## The most ticks in a row a unit may stay in CHASE with a blocked line (observed after the tick):
## the line is checked on the unit's turn, once in `line_check_period_ticks` (5) ticks.
const MOST_BLOCKED_CHASE_TICKS: int = 5


## The deadlock of the plan review, two squads at the ridge: at their first scan each one holds the
## other as its target (5000 away, inside acquire range, out of weapon range) and the line to it is
## blocked, so neither chases. Id 2 scans first (tick 3, with its line-check turn): its target is
## id 1, its mode is not CHASE and it takes a flow field on that tick (the line to its goal is
## blocked too). Id 1 does the same at tick 4.
func test_a_blocked_line_at_the_first_scan_keeps_the_path() -> void:
	var world: World = _band_world()
	world.add_unit(1, RIFLE, 12500, 5500)
	world.add_unit(2, RIFLE, 17500, 5500)
	var orders: Array[Command] = [
		_stamped(Command.attack_move(1, _ids([1]), 22500, 5500), world),
		_stamped(Command.attack_move(2, _ids([2]), 7500, 5500), world),
	]
	while world.tick < 4:
		Sim.step(world, orders)
		orders.clear()
	assert_int(world.target[1]).is_equal(1)
	assert_int(world.nav_mode[1]).is_not_equal(CHASE)
	assert_bool(world.field[1] >= 0).is_true()
	Sim.step(world, [])
	assert_int(world.target[0]).is_equal(2)
	assert_int(world.nav_mode[0]).is_equal(FIELD)
	assert_bool(world.field[0] >= 0).is_true()
	assert_array(Rig.outside_sight(world)).is_empty()


## The two squads keep following their path round the band's end, never press into the band (no
## unit stays in CHASE for more than the check period with a blocked line, and no unit is ever on
## rock), and reach weapon range of each other in the gap: both `HOLD`, no more than 4000 apart,
## with no flow field held (the cache's references are derived from the `field` column, so a holding
## unit pins no slot) and their orders and goals as given. They used a field on the way, and chased
## once the line was clear.
func test_squads_on_opposite_sides_of_a_four_tile_band_use_the_gap_and_reach_weapon_range() -> void:
	var world: World = _band_world()
	world.add_unit(1, RIFLE, 12500, 5500)
	world.add_unit(2, RIFLE, 17500, 5500)
	var orders: Array[Command] = [
		_stamped(Command.attack_move(1, _ids([1]), 22500, 5500), world),
		_stamped(Command.attack_move(2, _ids([2]), 7500, 5500), world),
	]
	var seen: Dictionary[int, int] = {}
	var blocked_run: PackedInt32Array = PackedInt32Array([0, 0])
	var longest: int = 0
	for tick: int in 600:
		Sim.step(world, orders)
		orders.clear()
		for row: int in 2:
			seen[world.nav_mode[row]] = tick
			var cell: int = world.cell_of(world.pos_x[row], world.pos_y[row])
			assert_bool(world.is_passable(cell, FOOT)).is_true()
			if world.nav_mode[row] == CHASE and not _line_clear(world, row, 1 - row):
				blocked_run[row] += 1
			else:
				blocked_run[row] = 0
			longest = maxi(longest, blocked_run[row])
		if world.nav_mode[0] == HOLD and world.nav_mode[1] == HOLD:
			break
	assert_int(longest).is_less_equal(MOST_BLOCKED_CHASE_TICKS)
	assert_bool(seen.has(FIELD)).is_true()
	assert_bool(seen.has(CHASE)).is_true()
	assert_array([world.nav_mode[0], world.nav_mode[1]]).is_equal([HOLD, HOLD])
	assert_array([world.order[0], world.order[1]]).is_equal([ATTACK_MOVE, ATTACK_MOVE])
	assert_array([world.field[0], world.field[1]]).is_equal([-1, -1])
	assert_array([world.goal_x[0], world.goal_x[1]]).is_equal([22500, 7500])
	var dx: int = world.pos_x[1] - world.pos_x[0]
	var dy: int = world.pos_y[1] - world.pos_y[0]
	assert_int(dx * dx + dy * dy).is_less_equal(4000 * 4000)
	assert_int(world.pos_y[0]).is_greater(9999)
	assert_int(world.pos_y[1]).is_greater(9999)
	assert_array(Rig.outside_sight(world)).is_empty()


## The chase follows the line, checked on the unit's turn. A squad (range 1500, so that it never
## holds in this case) attack-moves east with an idle enemy 4900 away behind a wall of rock
## (tile column 8, rows 0 to 10): its line is blocked at its first scan (tick 4), so it is not
## chasing but following a field round the wall's end. The wall is removed before tick 8, a tick
## that is not its turn, and it is not chasing then; at its turn, tick 9, it chases. The wall is put
## back before tick 10: it keeps chasing on the ticks that are not its turn (10 to 13) and leaves
## CHASE at tick 14, its next turn, for the field.
func test_the_chase_starts_and_ends_on_the_units_turn_when_the_line_clears_or_blocks() -> void:
	var gun: UnitDef = Rig.unit(&"gun", 6000, 5000, 1500, 0, [100, 100, 100, 100])
	var world: World = Rig.world_of([gun], COLUMNS, 12)
	world.terrain_cost = PackedByteArray(GridWorld.GROUND_COST)
	_set_wall(world, ROCK)
	world.add_unit(1, 0, 5000, 5500)
	world.add_unit(2, 0, 9900, 5500)
	Sim.step(world, [_stamped(Command.attack_move(1, _ids([1]), 25000, 5500), world)])
	while world.tick < 8:
		Sim.step(world, [])
		assert_int(world.nav_mode[0]).override_failure_message("tick %d" % world.tick).is_not_equal(
			CHASE
		)
	assert_int(world.target[0]).is_equal(2)
	assert_int(world.nav_mode[0]).is_equal(FIELD)
	_set_wall(world, 0)
	Sim.step(world, [])
	assert_int(world.nav_mode[0]).is_not_equal(CHASE)
	Sim.step(world, [])
	assert_int(world.tick).is_equal(10)
	assert_int(world.nav_mode[0]).is_equal(CHASE)
	assert_int(world.field[0]).is_equal(-1)
	_set_wall(world, ROCK)
	while world.tick < 14:
		Sim.step(world, [])
		assert_int(world.nav_mode[0]).override_failure_message("tick %d" % world.tick).is_equal(
			CHASE
		)
	Sim.step(world, [])
	assert_int(world.nav_mode[0]).is_equal(FIELD)
	assert_bool(world.field[0] >= 0).is_true()
	assert_int(world.target[0]).is_equal(2)


## An `ATTACK` order across the band: the tank drives at the idle tank on the far side by the
## navigation of its order (a field keyed on the target's tile, since the line is blocked), never
## `CHASE`, through the gap, and holds at 4500 or less from it. The target is not moved.
func test_an_attack_across_the_band_follows_its_field_and_holds_at_range() -> void:
	var world: World = _band_world()
	world.add_unit(1, TANK, 11500, 5500)
	world.add_unit(2, TANK, 17500, 5500)
	Sim.step(world, [_stamped(Command.attack(1, _ids([1]), 2), world)])
	var field_ticks: int = 0
	var chased: bool = false
	for _tick: int in 400:
		Sim.step(world, [])
		field_ticks += 1 if world.nav_mode[0] == FIELD else 0
		chased = chased or world.nav_mode[0] == CHASE
		if world.nav_mode[0] == HOLD:
			break
	assert_bool(chased).is_false()
	assert_int(field_ticks).is_greater(20)
	assert_int(world.nav_mode[0]).is_equal(HOLD)
	assert_array([world.order[0], world.field[0]]).is_equal([ATTACK, -1])
	var dx: int = world.pos_x[1] - world.pos_x[0]
	var dy: int = world.pos_y[1] - world.pos_y[0]
	assert_int(dx * dx + dy * dy).is_less_equal(4500 * 4500)
	assert_array([world.pos_x[1], world.pos_y[1]]).is_equal([17500, 5500])
	assert_array(Rig.outside_sight(world)).is_empty()


## An `ATTACK` target that walks from the gap row to behind the band: the line to it is clear when
## the tank first tests it, so the tank steers `DIRECT`, and its goal walks away with the target.
## The line is tested again on the tank's turns (a clear line stays clear only while the goal stays
## put), the first test that finds it blocked sends the tank to a field keyed on the target's tile
## through the gap in the same tick, and it holds at 4500 or less from the target. The tank never
## steers into the band for more than one line-check period: no tick's intent ends on a tile its
## class cannot enter (the first version of P41b pressed into the band for 329 ticks).
func test_an_attack_target_that_walks_behind_the_band_is_followed_through_the_gap() -> void:
	var world: World = _band_world()
	world.type_sight[TANK] = 30000
	world.add_unit(1, TANK, 8000, 11000)
	world.add_unit(2, TANK, 19500, 11000)
	var orders: Array[Command] = [
		_stamped(Command.attack(1, _ids([1]), 2), world),
		_stamped(Command.move(2, _ids([2]), 19500, 2000), world),
	]
	var cells: int = world.map_cols * world.map_rows
	var pressing: int = 0
	var longest: int = 0
	var seen: Dictionary[int, int] = {}
	for _tick: int in 400:
		Sim.step(world, orders)
		orders.clear()
		seen[world.nav_mode[0]] = world.tick
		var next_x: int = world.pos_x[0] + world.intent_x[0]
		var next_y: int = world.pos_y[0] + world.intent_y[0]
		var into_rock: bool = (
			world.move_cost[2 * cells + next_y / 1000 * COLUMNS + next_x / 1000] == 0
		)
		pressing = pressing + 1 if into_rock else 0
		longest = maxi(longest, pressing)
		if world.nav_mode[0] == HOLD:
			break
	assert_int(longest).is_less_equal(MOST_BLOCKED_CHASE_TICKS)
	assert_bool(seen.has(DIRECT) and seen.has(FIELD)).is_true()
	assert_bool(seen.has(CHASE)).is_false()
	assert_array([world.nav_mode[0], world.order[0], world.field[0]]).is_equal([HOLD, ATTACK, -1])
	assert_array([world.pos_x[1], world.pos_y[1]]).is_equal([19500, 2000])
	var dx: int = world.pos_x[1] - world.pos_x[0]
	var dy: int = world.pos_y[1] - world.pos_y[0]
	assert_int(dx * dx + dy * dy).is_less_equal(4500 * 4500)
	assert_array(Rig.outside_sight(world)).is_empty()


## A unit that follows a field and has a target in weapon range holds without the field: the tank
## stands in `FIELD` on a slot with its line to the goal blocked, and its target comes into range
## (4230 away, the cannon's is 4500, on the far side of the band, which the line to it crosses), so
## the next tick it is `HOLD` with no field, no next tile and an unchecked line, and no intent.
func test_a_unit_on_a_field_holds_with_no_field() -> void:
	var world: World = _band_world()
	world.add_unit(1, TANK, 12900, 5500)
	world.add_unit(2, RIFLE, 17100, 5000)
	world.order[0] = ATTACK_MOVE
	world.goal_x[0] = 22500
	world.goal_y[0] = 5500
	var slot: int = world.flow.acquire(world.cell_of(22500, 5500), 2, world.map_version, 0)
	world.field[0] = slot
	world.nav_mode[0] = FIELD
	world.nav_next[0] = 12 * COLUMNS + 12
	world.target[0] = 2
	Sim.step(world, [])
	assert_array([world.nav_mode[0], world.field[0], world.nav_next[0]]).is_equal([HOLD, -1, -1])
	assert_array([world.nav_cell[0], world.intent_x[0], world.intent_y[0]]).is_equal([-1, 0, 0])


## The line to the target is checked for the unit's own move class: a band of scrub (columns 8 and
## 9, every row), which foot units cross and tracked ones do not, lies between an enemy rifle squad
## and two attack-moving units 4800 to 4900 from it, a rifle squad (id 1) and a tank (id 2). At
## their first scans (ticks 4 and 3) the squad chases, the tank does not (it takes a field, and
## holds from tick 5, in range of its cannon).
func test_the_chase_line_is_checked_for_the_units_own_move_class() -> void:
	var world: World = Rig.data_world(COLUMNS, 12)
	world.terrain_cost = PackedByteArray(GridWorld.GROUND_COST)
	for column: int in [8, 9]:
		for line: int in 12:
			world.set_terrain(line * COLUMNS + column, 1)
	world.add_unit(1, RIFLE, 6000, 6000)
	world.add_unit(1, TANK, 6000, 8000)
	world.add_unit(2, RIFLE, 10800, 7000)
	var orders: Array[Command] = [
		_stamped(Command.attack_move(1, _ids([1, 2]), 25000, 7000), world),
	]
	var chased: Array[bool] = [false, false]
	for _tick: int in 6:
		Sim.step(world, orders)
		orders.clear()
		for row: int in 2:
			chased[row] = chased[row] or world.nav_mode[row] == CHASE
	assert_array([world.target[0], world.target[1]]).is_equal([3, 3])
	assert_array(chased).is_equal([true, false])
	assert_array(Rig.outside_sight(world)).is_empty()


## Two runs of the band fight give the same state hash at every checkpoint, and not the hashes of a
## run where nobody scans.
func test_two_runs_give_the_same_hashes() -> void:
	var first: PackedInt64Array = _band_hashes(0)
	var second: PackedInt64Array = _band_hashes(0)
	assert_int(first.size()).is_equal(10)
	assert_array(second).is_equal(first)
	assert_int(_band_hashes(1000000)[-1]).is_not_equal(first[-1])


## The state hash after each 15th tick of the first 150 ticks of the band deadlock; with `period`
## of 1 or more, `retarget_period_ticks` is set to it first.
func _band_hashes(period: int) -> PackedInt64Array:
	var world: World = _band_world()
	if period > 0:
		world.retarget_period_ticks = period
	world.add_unit(1, RIFLE, 12500, 5500)
	world.add_unit(2, RIFLE, 17500, 5500)
	var orders: Array[Command] = [
		_stamped(Command.attack_move(1, _ids([1]), 22500, 5500), world),
		_stamped(Command.attack_move(2, _ids([2]), 7500, 5500), world),
	]
	var hashes: PackedInt64Array = PackedInt64Array()
	for _tick: int in 150:
		Sim.step(world, orders)
		orders.clear()
		if world.tick % Replay.CHECKPOINT_PERIOD == 0:
			hashes.append(world.state_hash())
	return hashes


## Whether the straight line from unit `from` to unit `to` is clear for the class of `from`.
func _line_clear(world: World, from: int, to: int) -> bool:
	var move_class: int = world.type_move_class[world.type_index[from]]
	return FixedMath.line_clear(
		world, world.pos_x[from], world.pos_y[from], world.pos_x[to], world.pos_y[to], move_class
	)


## The open 30 x 12 tile map with the rock band in columns 13 to 16, rows 0 to 9.
func _band_world() -> World:
	var world: World = Rig.data_world(COLUMNS, 12)
	world.terrain_cost = PackedByteArray(GridWorld.GROUND_COST)
	for column: int in range(13, 17):
		for line: int in 10:
			world.set_terrain(line * COLUMNS + column, ROCK)
	return world


## Sets the wall in tile column 8, rows 0 to 10, to `terrain` (2 is rock, 0 grass).
func _set_wall(world: World, terrain: int) -> void:
	for line: int in 11:
		world.set_terrain(line * COLUMNS + 8, terrain)


func _ids(ids: Array) -> PackedInt32Array:
	return PackedInt32Array(ids)


func _stamped(command: Command, world: World) -> Command:
	command.tick = world.tick
	return command
