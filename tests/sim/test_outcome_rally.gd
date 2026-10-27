extends GdUnitTestSuite
## RALLY (plan row P76, ADR 0017 section 4, ADR 0018 section 6): a building of the player's own
## that produces INFANTRY or VEHICLES sets that player's rally point of that tab, the point is
## clamped to the map (a stored value below 0 means "no rally point" to ProductionSpawn), a later
## RALLY replaces an earlier one in command order, and every other command is dropped and counted
## with the stored points as they were: a Headquarters (it produces STRUCTURES), a building that
## produces nothing, an enemy building, a unit, a missing id, a payload and a defeated player (the
## `_playing` gate of `Sim._apply`, which `Outcome.apply_rally` itself does not ask). The world is
## `production_worlds.gd`'s base world: player 1 owns a power plant (id 1), a barracks (id 2), a
## refinery (id 3) and a vehicle factory (id 4), player 2 a barracks (id 5).

const Rig: GDScript = preload("res://tests/sim/support/production_worlds.gd")
const Worlds: GDScript = preload("res://tests/sim/support/building_worlds.gd")
const NONE: Array[int] = [-1, -1, -1, -1, -1, -1]


## The rally points of `player` tab by tab, as x and y of STRUCTURES, of INFANTRY and of VEHICLES.
func _points(world: World, player: int) -> Array[int]:
	var found: Array[int] = []
	for tab: int in World.TABS:
		found.append(world.rally_x[Rig.queue_of(player, tab)])
		found.append(world.rally_y[Rig.queue_of(player, tab)])
	return found


func test_a_barracks_and_a_vehicle_factory_set_the_rally_point_of_their_own_tab() -> void:
	var world: World = Rig.base()
	assert_array(_points(world, 1)).is_equal(NONE)
	Rig.step(world, [Command.rally(1, Rig.BARRACKS, 15500, 9500)])
	assert_array(_points(world, 1)).is_equal([-1, -1, 15500, 9500, -1, -1])
	Rig.step(world, [Command.rally(1, Rig.FACTORY, 20500, 12500)])
	assert_array(_points(world, 1)).is_equal([-1, -1, 15500, 9500, 20500, 12500])
	assert_array(_points(world, 2)).is_equal(NONE)
	Rig.step(world, [Command.rally(2, Rig.ENEMY_BARRACKS, 5500, 6500)])
	assert_array(_points(world, 2)).is_equal([-1, -1, 5500, 6500, -1, -1])
	assert_array(_points(world, 1)).is_equal([-1, -1, 15500, 9500, 20500, 12500])
	assert_int(world.dropped_commands).is_equal(0)


## Two RALLYs of one tick apply in command order (tick, player, sequence), not in list order: the
## later one is the point that stays.
func test_a_later_rally_replaces_the_earlier_one_in_command_order() -> void:
	var world: World = Rig.base()
	var first: Command = Command.rally(1, Rig.BARRACKS, 15500, 9500)
	var second: Command = Command.rally(1, Rig.BARRACKS, 4500, 7500)
	second.sequence = 1
	Rig.step(world, [second, first])
	assert_array(_points(world, 1)).is_equal([-1, -1, 4500, 7500, -1, -1])
	Rig.step(world, [Command.rally(1, Rig.BARRACKS, 6500, 3500)])
	assert_array(_points(world, 1)).is_equal([-1, -1, 6500, 3500, -1, -1])
	assert_int(world.dropped_commands).is_equal(0)


## A point off the map lands on its edge, each axis alone, and a stored point is never below 0 or
## past the last milli-tile; a point on the map, corners included, stays as it is.
func test_the_point_is_clamped_to_the_map_and_never_stored_below_zero() -> void:
	var last: Vector2i = Vector2i(Rig.COLS * World.MILLI_PER_TILE - 1, Rig.ROWS * 1000 - 1)
	var cases: Array[Array] = [
		[Vector2i(-1, -1), Vector2i(0, 0)],
		[Vector2i(-70000, 5500), Vector2i(0, 5500)],
		[Vector2i(7500, -200), Vector2i(7500, 0)],
		[Vector2i(0, 0), Vector2i(0, 0)],
		[last, last],
		[Vector2i(last.x + 1, last.y + 1), last],
		[Vector2i(900000, 5500), Vector2i(last.x, 5500)],
		[Vector2i(7500, 900000), Vector2i(7500, last.y)],
	]
	for case: Array in cases:
		var world: World = Rig.base()
		var asked: Vector2i = case[0]
		Rig.step(world, [Command.rally(1, Rig.BARRACKS, asked.x, asked.y)])
		var label: String = str(asked)
		assert_int(world.dropped_commands).override_failure_message(label).is_equal(0)
		var stored: Array[int] = _points(world, 1)
		var expected: Vector2i = case[1]
		assert_array(stored).override_failure_message(label).is_equal(
			[-1, -1, expected.x, expected.y, -1, -1]
		)


## Every command that is not a barracks or a vehicle factory of the player is dropped and counted,
## and no stored point moves: the Headquarters produces STRUCTURES, the plant and the refinery
## produce nothing, player 2's barracks is not player 1's, a unit is no building, ids 0, -1 and
## 999 name nothing, and a payload or a player past the match is no RALLY.
func test_every_other_command_is_dropped_and_counted_with_the_points_unchanged() -> void:
	var world: World = Rig.base()
	var headquarters: int = Rig.add_headquarters(world)
	var rifle: int = world.add_unit(1, Worlds.type_of(world, "rifle_squad"), 5500, 9500)
	var payload: Command = Command.rally(1, Rig.BARRACKS, 15500, 9500)
	payload.payload = PackedInt32Array([1])
	var cases: Dictionary[String, Command] = {
		"headquarters": Command.rally(1, headquarters, 15500, 9500),
		"power plant": Command.rally(1, Rig.PLANT, 15500, 9500),
		"refinery": Command.rally(1, Rig.REFINERY, 15500, 9500),
		"enemy barracks": Command.rally(1, Rig.ENEMY_BARRACKS, 15500, 9500),
		"unit": Command.rally(1, rifle, 15500, 9500),
		"id 0": Command.rally(1, 0, 15500, 9500),
		"id -1": Command.rally(1, -1, 15500, 9500),
		"unknown id": Command.rally(1, 999, 15500, 9500),
		"payload": payload,
		"player past the match": Command.rally(3, Rig.BARRACKS, 15500, 9500),
	}
	var dropped: int = 0
	for label: String in cases:
		Rig.step(world, [cases[label]])
		dropped += 1
		assert_int(world.dropped_commands).override_failure_message(label).is_equal(dropped)
		assert_array(_points(world, 1)).override_failure_message(label).is_equal(NONE)
		assert_array(_points(world, 2)).override_failure_message(label).is_equal(NONE)


## The `_playing` gate: a defeated player's RALLY is dropped and counted although `apply_rally`
## would take it (called on its own it sets the point, so the gate is what stops the command).
func test_a_defeated_players_rally_is_dropped_by_the_gate() -> void:
	var direct: World = Rig.base()
	direct.defeated_tick[1] = 3
	var command: Command = Command.rally(1, Rig.BARRACKS, 15500, 9500)
	assert_bool(Outcome.apply_rally(direct, command)).is_true()
	assert_array(_points(direct, 1)).is_equal([-1, -1, 15500, 9500, -1, -1])
	var world: World = Rig.base()
	world.defeated_tick[1] = 3
	Rig.step(world, [Command.rally(1, Rig.BARRACKS, 15500, 9500)])
	assert_int(world.dropped_commands).is_equal(1)
	assert_array(_points(world, 1)).is_equal(NONE)
	assert_int(world.defeated_tick[1]).is_equal(3)


## The point reaches a unit: the next unit of the tab leaves its exit by a MOVE, and the open point
## is its goal. A point at the corner (0, 0) is a rally point too, not "none" (-1 is).
func test_the_stored_point_sends_the_next_unit_of_the_tab_away() -> void:
	for point: Vector2i in [Vector2i(15500, 9500), Vector2i(0, 0)]:
		var world: World = Rig.base()
		var ticks: int = world.type_build_ticks[Worlds.type_of(world, "rifle_squad")]
		var queued: Command = Rig.queue(world, 1, "rifle_squad", 1)
		Rig.step(world, [Command.rally(1, Rig.BARRACKS, point.x, point.y), queued])
		Rig.run(world, ticks - 1)
		var rows: Array[int] = Rig.rows_of(world, 1, "rifle_squad")
		var label: String = str(point)
		assert_array(rows).override_failure_message(label).has_size(1)
		assert_int(world.order[rows[0]]).override_failure_message(label).is_equal(World.Order.MOVE)
		if point.x > 0:
			var goal: Vector2i = Vector2i(world.goal_x[rows[0]], world.goal_y[rows[0]])
			assert_vector(goal).override_failure_message(label).is_equal(point)
