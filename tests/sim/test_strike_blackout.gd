extends GdUnitTestSuite
## The Blackout Array's command (plan row P111, ADR 0023 section 10): a SUPERWEAPON of a blackout
## building takes effect at once, in COMMANDS: every building not owned by the firing player within
## `type_strike_radius` of the point (by squared distance, the edge included) gets `offline_until =
## stamp + type_strike_ticks`, and nothing else is written but the building's own restarted charge.
## What reads `offline_until` is test_power_blackout's (the totals), test_blackout_defence's (the
## shots) and test_blackout_production's (the queues). The rig is `strike_worlds.gd`: the array
## (id 3, player 1) has a radius of 4000, a length of 90 ticks and a charge of 30, and every
## expected tick, distance and length is read from the World's tables. The replay case uses
## `blackout_worlds.gd` instead, whose player 2 has the armed turrets and the queues that a recorded
## blackout has to silence and freeze.

const Strikes: GDScript = preload("res://tests/sim/support/strike_worlds.gd")
const BlackoutRig: GDScript = preload("res://tests/sim/support/blackout_worlds.gd")
const StrikeProbe: GDScript = preload("res://tests/sim/support/strike_probe.gd")


## The type index of the rig's blackout building.
func _array(world: World) -> int:
	return Strikes.type_of(world, "array")


## The length of the blackout in ticks, from the World's table.
func _length(world: World) -> int:
	return world.type_strike_ticks[_array(world)]


## `offline_until` of the row with `id`.
func _offline(world: World, id: int) -> int:
	return world.offline_until[world.index_of(id)]


## Adds a 1 x 1 building of `owner` on the tile (col, line) and returns its id.
func _shed(world: World, owner: int, col: int, line: int) -> int:
	return world.add_building(owner, Strikes.type_of(world, "shed"), col, line)


## A rig world at the first tick the array may fire, with that tick.
func _ready_world() -> World:
	var world: World = Strikes.world()
	Strikes.run_to(world, Strikes.fire_tick(world, Strikes.ARRAY))
	return world


## The blackout is written by the COMMANDS mark of the firing step itself (the probe sees it at the
## first mark, before any other phase), for the stamp of that step plus the length.
func test_the_blackout_is_written_in_the_commands_phase_of_the_firing_step() -> void:
	var world: World = _ready_world()
	var tick: int = world.tick
	var shed: int = _shed(world, 2, 15, 10)  # Its centre is the rig's point.
	var probe: SimProbe = StrikeProbe.new(world, shed)
	Strikes.step(world, [Strikes.fire(Strikes.ARRAY)], probe)
	assert_int(world.dropped_commands).is_equal(0)
	assert_int(probe.phases[0]).is_equal(SimProbe.Phase.COMMANDS)
	assert_int(probe.offline[0]).is_equal(tick + 1 + _length(world))
	assert_int(_offline(world, shed)).is_equal(tick + 1 + _length(world))


## The radius is a circle by squared distance and its edge is inside. Sheds stand at the exact
## radius (a 3-4-5 offset from the point), inside it near the point, and outside it at a corner of
## the square that the radius fits in; every one is judged by its own squared distance. With the
## radius one milli-tile shorter, the shed at the exact radius is outside.
@warning_ignore("integer_division")
func test_the_radius_is_a_circle_by_squared_distance_and_its_edge_is_inside() -> void:
	var world: World = _ready_world()
	var radius: int = world.type_strike_radius[_array(world)]
	assert_int(radius % 5).is_equal(0)  # So that 3-4-5 gives a whole offset.
	var edge: Vector2i = Vector2i(17500, 13500)  # The centre of the 1 x 1 on tile (17, 13).
	var point: Vector2i = edge - Vector2i(radius * 3 / 5, radius * 4 / 5)
	var tiles: Array[Vector2i] = [
		Vector2i(17, 13), Vector2i(18, 10), Vector2i(17, 14), Vector2i(18, 13), Vector2i(19, 10)
	]
	var ids: Array[int] = []
	for tile: Vector2i in tiles:
		ids.append(_shed(world, 2, tile.x, tile.y))
	var twin: World = Strikes.world()
	Strikes.run_to(twin, world.tick)
	for tile: Vector2i in tiles:
		_shed(twin, 2, tile.x, tile.y)
	twin.type_strike_radius[_array(twin)] = radius - 1
	var stamp: int = world.tick + 1
	Strikes.step(world, [Strikes.fire(Strikes.ARRAY, 1, point)])
	Strikes.step(twin, [Strikes.fire(Strikes.ARRAY, 1, point)])
	var inside: Array[int] = []
	var outside: Array[int] = []
	for at: int in tiles.size():
		var row: int = world.index_of(ids[at])
		var dx: int = world.pos_x[row] - point.x
		var dy: int = world.pos_y[row] - point.y
		var within: bool = dx * dx + dy * dy <= radius * radius
		(inside if within else outside).append(at)
		var until: int = stamp + _length(world) if within else 0
		(
			assert_int(_offline(world, ids[at]))
			. override_failure_message("shed on tile %s" % [tiles[at]])
			. is_equal(until)
		)
		# The shorter radius takes the same rows except the one at the exact radius.
		var shorter: bool = dx * dx + dy * dy <= (radius - 1) * (radius - 1)
		(
			assert_int(_offline(twin, ids[at]))
			. override_failure_message("shed on tile %s, radius - 1" % [tiles[at]])
			. is_equal(stamp + _length(twin) if shorter else 0)
		)
	assert_array(inside).is_equal([0, 1])  # The edge and the one near the point.
	assert_array(outside).is_equal([2, 3, 4])  # (18, 13) is inside the square, not the circle.
	var edge_row: int = world.index_of(ids[0])
	assert_int(world.pos_x[edge_row] - point.x).is_equal(radius * 3 / 5)
	assert_int(_offline(twin, ids[0])).is_equal(0)


## What a blackout leaves alone: the firing player's own buildings in the radius (its array and its
## headquarters included), every unit of either player in the radius, and the buildings outside it.
## The one other thing it writes is the array's restarted charge, so the only hash sections that
## differ from a twin that took a tick with no command are `ready_tick` and `offline_until`:
## nothing is pending, no point is stored and no cost or credit moves.
func test_a_blackout_spares_own_buildings_units_and_everything_outside_the_radius() -> void:
	var world: World = _ready_world()
	var twin: World = Strikes.world()
	Strikes.run_to(twin, world.tick)
	var tick: int = world.tick
	var enemy: Array[int] = []
	var spared: Array[int] = []
	for each: World in [world, twin] as Array[World]:
		var near: Vector2i = Strikes.POINT
		(
			spared
			. assign(
				[
					_shed(each, 1, 14, 10),  # Its own, in the radius.
					Strikes.add(each, 1, "rifle", near.x, near.y),
					Strikes.add(each, 2, "tank", near.x + 500, near.y),
					_shed(each, 2, 28, 1),  # Another player's, far outside.
				]
			)
		)
		enemy.assign([_shed(each, 2, 15, 10), _shed(each, 2, 16, 11)])
	Strikes.step(world, [Strikes.fire(Strikes.ARRAY)])
	Strikes.step(twin)
	for id: int in enemy:
		assert_int(_offline(world, id)).is_equal(tick + 1 + _length(world))
	for id: int in spared + [Strikes.ARRAY, Strikes.HQ_1, Strikes.BORE_A]:
		assert_int(_offline(world, id)).override_failure_message("row %d" % id).is_equal(0)
	assert_int(world.dropped_commands).is_equal(0)
	assert_array(Strikes.differing(world, twin)).is_equal(["ready_tick", "offline_until"])
	assert_array([world.strike_tick[1], world.strike_x[1], world.strike_y[1]]).is_equal([0, 0, 0])


## A neutral building (owner 0) in the radius goes offline too: the rule is "not owned by the firing
## player", as the rupture hits every row. A blackout it already has is never shortened: a longer
## one stays, a shorter one and an ended one (offline_until in the past) are replaced.
func test_a_neutral_building_goes_offline_and_a_longer_blackout_is_kept() -> void:
	var world: World = _ready_world()
	var stamp: int = world.tick + 1
	var until: int = stamp + _length(world)
	var neutral: int = _shed(world, 0, 15, 10)
	var longer: int = _shed(world, 2, 15, 11)
	var shorter: int = _shed(world, 2, 16, 10)
	var ended: int = _shed(world, 2, 16, 11)
	world.offline_until[world.index_of(longer)] = until + 50
	world.offline_until[world.index_of(shorter)] = stamp + 5
	world.offline_until[world.index_of(ended)] = stamp - 1
	Strikes.step(world, [Strikes.fire(Strikes.ARRAY)])
	assert_int(_offline(world, neutral)).is_equal(until)
	assert_int(_offline(world, longer)).is_equal(until + 50)
	assert_int(_offline(world, shorter)).is_equal(until)
	assert_int(_offline(world, ended)).is_equal(until)


## The point is clamped to the map as the rupture's is: a point far outside ends on the nearest edge
## or corner, so that a building near that corner is hit and the squared distances stay small
## (unclamped, 2^40 squared would overflow).
func test_the_point_is_clamped_to_the_map() -> void:
	var world: World = _ready_world()
	var corner: int = _shed(world, 2, 28, 18)  # Near the corner (map_w - 1, map_h - 1).
	var origin: int = _shed(world, 2, 1, 1)
	var middle: int = _shed(world, 2, 15, 10)
	Strikes.step(world, [Command.superweapon(1, Strikes.ARRAY, 1 << 40, 1 << 40)])
	var until: int = world.tick + _length(world)
	(
		assert_array([_offline(world, corner), _offline(world, origin), _offline(world, middle)])
		. is_equal([until, 0, 0])
	)
	Strikes.run_to(world, world.ready_tick[world.index_of(Strikes.ARRAY)] - 1)
	Strikes.step(world, [Command.superweapon(1, Strikes.ARRAY, -(1 << 40), -5000)])
	assert_int(world.dropped_commands).is_equal(0)
	assert_bool(_offline(world, origin) > 0).is_true()
	assert_int(_offline(world, middle)).is_equal(0)


## Firing restarts the array's charge from the firing step: refused until the stamp reaches the new
## ready_tick, accepted then. Nothing is pending after a blackout, so the player's bore may fire in
## the very next step (only a pending rupture holds the other strikes back).
func test_the_array_recharges_and_a_blackout_leaves_nothing_pending() -> void:
	var world: World = Strikes.world()
	var tick: int = Strikes.fire_tick(world, Strikes.BORE_A)  # Both strike buildings have charged.
	Strikes.run_to(world, tick)
	var charge: int = Strikes.charge_of(world, "array")
	Strikes.step(world, [Strikes.fire(Strikes.ARRAY)])
	assert_int(world.ready_tick[world.index_of(Strikes.ARRAY)]).is_equal(tick + 1 + charge)
	Strikes.step(world, [Strikes.fire(Strikes.BORE_A)])
	assert_array([world.dropped_commands, world.strike_tick[1] != 0]).is_equal([0, true])
	Strikes.run_to(world, world.strike_tick[1])  # The rupture lands; nothing is pending again.
	Strikes.run_to(world, tick + charge - 1)
	Strikes.step(world, [Strikes.fire(Strikes.ARRAY)])
	assert_int(world.dropped_commands).is_equal(1)
	var again: int = _shed(world, 2, 15, 10)
	Strikes.step(world, [Strikes.fire(Strikes.ARRAY)])
	assert_int(world.dropped_commands).is_equal(1)
	assert_int(_offline(world, again)).is_equal(tick + charge + 1 + _length(world))


## A strike building that is blacked out cannot fire until the stamp reaches its `offline_until`:
## player 2's charged array is taken offline by player 1's (the order of the two commands in one
## step is player 1 first, so the blackout is already written), its own SUPERWEAPON is dropped
## through the last offline stamp and accepted on the stamp that reaches `offline_until`.
func test_a_blacked_out_strike_building_fires_again_exactly_when_it_is_back() -> void:
	var world: World = Strikes.world()
	var enemy: int = world.add_building(2, _array(world), 20, 2)
	var tick: int = Strikes.fire_tick(world, Strikes.ARRAY)
	Strikes.run_to(world, tick)
	var until: int = tick + 1 + _length(world)
	var on_it: Vector2i = Vector2i(21500, 3500)  # The centre of player 2's array.
	var both: Array = [Strikes.fire(Strikes.ARRAY, 1, on_it), Strikes.fire(enemy, 2, on_it)]
	Strikes.step(world, both)
	assert_int(world.dropped_commands).is_equal(1)
	assert_int(_offline(world, enemy)).is_equal(until)
	Strikes.run_to(world, until - 2)
	Strikes.step(world, [Strikes.fire(enemy, 2, on_it)])  # The stamp is until - 1: still offline.
	assert_int(world.dropped_commands).is_equal(2)
	assert_int(world.ready_tick[world.index_of(enemy)]).is_less(until)  # Not restarted.
	Strikes.step(world, [Strikes.fire(enemy, 2, on_it)])  # The stamp is until: back.
	assert_int(world.dropped_commands).is_equal(2)
	assert_int(world.ready_tick[world.index_of(enemy)]).is_equal(
		until + Strikes.charge_of(world, "array")
	)


## A match recorded through the MatchLoop with a blackout in its log plays back to the same
## checkpoints and the same final hash, also through the bytes of a saved replay, and the same
## commands give the same hash twice. The blackout is real in the record: the rig's turret and
## barracks in the radius have `offline_until` for the length of the table and the ones outside it
## have none; checkpoints fall before it, inside it and after its end; and a twin match with no
## SUPERWEAPON agrees with it up to the firing step and differs from the first checkpoint after
## it, so that a replay of a command that did nothing could not pass for this one.
@warning_ignore("integer_division")
func test_a_replay_reproduces_the_blackout() -> void:
	var recorded: World = BlackoutRig.world()
	var fire_at: int = BlackoutRig.fire_tick(recorded)  # Before the firing restarts the charge.
	var replay: Replay = _record(recorded, true)
	var until: int = fire_at + 1 + BlackoutRig.length_of(recorded)
	var victims: Array[int] = [BlackoutRig.TURRET_IN, BlackoutRig.BARRACKS]
	var spared: Array[int] = [BlackoutRig.TURRET_OUT, BlackoutRig.FACTORY, BlackoutRig.PLANT]
	for id: int in victims:
		assert_int(recorded.offline_until[recorded.index_of(id)]).is_equal(until)
	for id: int in spared:
		assert_int(recorded.offline_until[recorded.index_of(id)]).is_equal(0)
	assert_int(recorded.dropped_commands).is_equal(0)
	var period: int = Replay.CHECKPOINT_PERIOD
	var before: int = 0
	var inside: int = 0
	var after: int = 0
	for tick: int in replay.checkpoint_ticks:
		if tick <= fire_at:
			before += 1
		elif tick < until:
			inside += 1
		else:
			after += 1
	assert_int(before).is_greater_equal(1)
	assert_int(inside).is_greater_equal(BlackoutRig.length_of(recorded) / period - 1)
	assert_int(after).is_greater_equal(2)
	var quiet_world: World = BlackoutRig.world()
	var quiet: Replay = _record(quiet_world, false)
	assert_array(quiet.checkpoint_ticks).is_equal(replay.checkpoint_ticks)
	for at: int in replay.checkpoint_ticks.size():
		var same: bool = replay.checkpoint_hashes[at] == quiet.checkpoint_hashes[at]
		(
			assert_bool(same)
			. override_failure_message("checkpoint at tick %d" % replay.checkpoint_ticks[at])
			. is_equal(replay.checkpoint_ticks[at] <= fire_at)
		)
	assert_int(replay.final_hash).is_not_equal(quiet.final_hash)
	var twice_world: World = BlackoutRig.world()
	var twice: Replay = _record(twice_world, true)
	assert_array(twice.commands).is_equal(replay.commands)
	assert_array(twice.checkpoint_hashes).is_equal(replay.checkpoint_hashes)
	assert_int(twice.final_hash).is_equal(replay.final_hash)
	var fresh: World = BlackoutRig.world()
	assert_int(Replay.play(replay, fresh, replay.final_tick)).is_equal(Replay.PLAY_MATCHED)
	assert_int(fresh.tick).is_equal(replay.final_tick)
	assert_int(fresh.state_hash()).is_equal(replay.final_hash)
	var loaded: Replay = Replay.from_bytes(replay.to_bytes())
	var again: World = BlackoutRig.world()
	assert_int(Replay.play(loaded, again, loaded.final_tick)).is_equal(Replay.PLAY_MATCHED)
	assert_int(again.state_hash()).is_equal(replay.final_hash)
	for each: World in [fresh, again]:
		for id: int in victims + spared:
			assert_int(each.offline_until[each.index_of(id)]).is_equal(
				recorded.offline_until[recorded.index_of(id)]
			)
		assert_int(each.queue_progress[2 * World.TABS + World.Tab.INFANTRY]).is_equal(
			recorded.queue_progress[2 * World.TABS + World.Tab.INFANTRY]
		)


## Records a match of `world` (a `blackout_worlds.gd` world at tick 0) through a MatchLoop and
## returns its finished replay: player 2 queues a gunner and a jeep in tick 0, player 1 fires the
## array on the first tick it may when `strike` is set, and the match runs 60 ticks past the end of
## the blackout (also with no strike, so that a twin has the same ticks and checkpoints).
func _record(world: World, strike: bool) -> Replay:
	var loop: MatchLoop = MatchLoop.create(null, "", 11, world)
	var fire_at: int = BlackoutRig.fire_tick(world)
	var ticks: int = fire_at + 1 + BlackoutRig.length_of(world) + 60
	while world.tick < ticks:
		var queued: Array[Command] = []
		if world.tick == 0:
			queued.append(Command.queue(2, BlackoutRig.type_of(world, "gunner")))
			queued.append(Command.queue(2, BlackoutRig.type_of(world, "jeep")))
		if strike and world.tick == fire_at:
			queued.append(BlackoutRig.fire())
		loop.step(world, queued)
	loop.replay.finish(world)
	return loop.replay


## Each invalid SUPERWEAPON of the array is dropped and counted with nothing else changed, as the
## bore's are (test_strike_command): not the player's own, not a strike building, still charging,
## offline, a defeated player, after the end of the match, a payload, and a rupture of the player's
## already pending.
func test_the_invalid_cases_of_the_array_are_dropped_and_counted() -> void:
	var offline: Callable = func(w: World) -> void:
		w.offline_until[w.index_of(Strikes.ARRAY)] = w.tick + 2
	var pending: Callable = func(w: World) -> void: w.strike_tick[1] = w.tick + 9
	var defeated: Callable = func(w: World) -> void: w.defeated_tick[1] = 3
	var ended: Callable = func(w: World) -> void: w.match_end_tick = 5
	var array: Callable = func() -> Command: return Strikes.fire(Strikes.ARRAY)
	_assert_dropped("player 2 fires player 1's array", func() -> Command: return Strikes.fire(3, 2))
	_assert_dropped("a headquarters", func() -> Command: return Strikes.fire(Strikes.HQ_1))
	_assert_dropped("still charging", array, Callable(), 1)
	_assert_dropped("offline", array, offline)
	_assert_dropped("a rupture pending", array, pending)
	_assert_dropped("defeated", array, defeated)
	_assert_dropped("after the end", array, ended)
	_assert_dropped(
		"a payload",
		func() -> Command:
			var command: Command = Strikes.fire(Strikes.ARRAY)
			command.payload = PackedInt32Array([1])
			return command
	)


## Runs `make`'s command in a rig world at the first tick the array may fire (`early` ticks before
## it), after `prepare` changed the World, with an enemy building in the radius, and checks that it
## is dropped and counted, that nothing else differs from a twin that took a tick with no command
## and that the enemy building stayed on. A third world, unprepared and on time, takes the plain
## SUPERWEAPON of the array and must black the building out, so the case's one fault is what drops
## the command.
func _assert_dropped(
	label: String, make: Callable, prepare: Callable = Callable(), early: int = 0
) -> void:
	var world: World = Strikes.world()
	var twin: World = Strikes.world()
	var tick: int = Strikes.fire_tick(world, Strikes.ARRAY) - early
	var both: Array[World] = [world, twin]
	for each: World in both:
		Strikes.run_to(each, tick)
		_shed(each, 2, 15, 10)
		if prepare.is_valid():
			prepare.call(each)
	Strikes.step(world, [make.call()])
	Strikes.step(twin)
	var shed: int = world.unit_id[world.unit_count() - 1]
	assert_int(world.dropped_commands).override_failure_message(label).is_equal(1)
	assert_int(_offline(world, shed)).override_failure_message(label).is_equal(0)
	assert_array(Strikes.differing(world, twin)).override_failure_message(label).is_equal(
		["header"]
	)
	var fine: World = _ready_world()
	var target: int = _shed(fine, 2, 15, 10)
	Strikes.step(fine, [Strikes.fire(Strikes.ARRAY)])
	assert_int(fine.dropped_commands).is_equal(0)
	assert_int(_offline(fine, target)).is_greater(0)
