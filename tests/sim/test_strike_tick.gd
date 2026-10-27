extends GdUnitTestSuite
## What a rupture does to the rest of its tick (plan row P110, ADR 0023 section 10): it lands in the
## FIRE mark, so the damage lowers hit points there and the rows that died leave at the REMOVE mark
## of the same tick (a DIED record each, none left in the World when the tick ends), a dying row's
## fog unstamp lands in its owner's dirty list of that tick, the power totals of that tick's ECONOMY
## leave it out, a rupture that kills a player's last producer defeats the player on that tick, and
## a replay of the match reproduces all of it. The rig is `strike_worlds.gd`; the numbers are read
## from the World's tables.

const Strikes: GDScript = preload("res://tests/sim/support/strike_worlds.gd")
const StrikeProbe: GDScript = preload("res://tests/sim/support/strike_probe.gd")
const GONE: int = -1000000  # What the probe writes for a row that has none.


## Runs a rig world to the first tick bore A may fire and returns that tick.
func _at_fire_tick(world: World) -> int:
	var tick: int = Strikes.fire_tick(world, Strikes.BORE_A)
	Strikes.run_to(world, tick)
	return tick


## The ids of the DIED records in `world.events`, in order.
func _died(world: World) -> Array[int]:
	var found: Array[int] = []
	for at: int in range(0, world.events.size(), World.EVENT_STRIDE):
		if world.events[at] == World.Event.DIED:
			found.append(world.events[at + 1])
	return found


## The probe shows the order inside the landing step: before FIRE the victim is untouched and the
## strike pending, at the FIRE mark the hit points are lowered, the strike is cleared and the row is
## still in the World, and at the REMOVE mark the row that died is gone (a DIED record, the row
## count down by one, `rows_version` moved) while the one that survived keeps 1 hit point and the
## one outside the radius is untouched. No row of hit points 0 or less is left when the tick ends.
func test_the_damage_lands_in_fire_and_the_dead_leave_at_remove_of_the_same_tick() -> void:
	var world: World = Strikes.world()
	var radius: int = Strikes.radius_of(world, "bore")
	var tick: int = _at_fire_tick(world)
	var at: Vector2i = Strikes.POINT
	var dying: int = Strikes.add(world, 2, "rifle", at.x, at.y)
	var lost: int = Strikes.damage_on(world, world.index_of(dying))
	var surviving: int = Strikes.add(world, 2, "rifle", at.x + 500, at.y)
	var far: int = Strikes.add(world, 2, "rifle", at.x + radius + 1, at.y)
	world.hp[world.index_of(dying)] = lost
	world.hp[world.index_of(surviving)] = lost + 1
	world.hp[world.index_of(far)] = lost
	Strikes.step(world, [Strikes.fire(Strikes.BORE_A)])
	Strikes.run_to(world, tick + Strikes.delay_of(world, "bore"))  # The next step lands.
	var landing: int = world.strike_tick[1]
	var rows: int = world.unit_count()
	var version: int = world.rows_version
	var probe: SimProbe = StrikeProbe.new(world, dying)
	Strikes.step(world, [], probe)
	var phases: Array[int] = probe.phases
	var fire: int = phases.find(SimProbe.Phase.FIRE)
	var remove: int = phases.find(SimProbe.Phase.REMOVE)
	assert_int(fire).is_greater(0)
	assert_int(remove).is_equal(fire + 1)
	assert_array([probe.hit_points[fire - 1], probe.pending[fire - 1]]).is_equal([lost, landing])
	assert_array([probe.hit_points[fire], probe.pending[fire], probe.rows[fire]]).is_equal(
		[0, 0, rows]
	)
	assert_array([probe.hit_points[remove], probe.rows[remove]]).is_equal([GONE, rows - 1])
	assert_int(world.rows_version).is_greater(version)
	assert_array(_died(world)).is_equal([dying])
	assert_array([Strikes.hp_of(world, surviving), Strikes.hp_of(world, far)]).is_equal([1, lost])
	for hit_points: int in world.hp:
		assert_int(hit_points).is_greater(0)


## A row that dies to the rupture leaves its owner's vision in that tick: its disc is unstamped
## before the owner's FOG turn, so the cells that flip are in the owner's dirty list of the landing
## tick, the same list as for a row that a shot killed. The landing tick is player 2's fog turn.
func test_the_fog_unstamp_of_a_ruptured_row_is_in_its_owners_dirty_list_of_that_tick() -> void:
	var world: World = Strikes.world(false)
	var control: World = Strikes.world(false)
	var delay: int = Strikes.delay_of(world, "bore")
	var tick: int = Strikes.fire_tick(world, Strikes.BORE_A)
	while (tick + delay - 1) % world.fog_period_ticks != 0:
		tick += 1  # Player 2 updates when (tick - 2 + 1) divides by the period.
	var both: Array[World] = [world, control]
	var ids: Array[int] = []
	for each: World in both:
		Strikes.run_to(each, tick)
		ids.append(Strikes.add(each, 2, "rifle", Strikes.POINT.x, Strikes.POINT.y))
		Strikes.stamp(each)
	var cell: int = world.cell_of(Strikes.POINT.x, Strikes.POINT.y)
	assert_int(world.fog.visible[world.fog.cells + cell]).is_equal(1)  # Player 2 sees its cell.
	Strikes.step(world, [Strikes.fire(Strikes.BORE_A)])
	Strikes.step(control)
	Strikes.run_to(world, tick + delay)
	Strikes.run_to(control, tick + delay)
	world.hp[world.index_of(ids[0])] = Strikes.damage_on(world, world.index_of(ids[0]))
	control.hp[control.index_of(ids[1])] = 0  # Killed by something else in that step.
	Strikes.step(world)
	Strikes.step(control)
	assert_int(Strikes.hp_of(world, ids[0])).is_equal(GONE)
	assert_int(Strikes.hp_of(control, ids[1])).is_equal(GONE)
	assert_array(world.fog.dirty_cells(2)).contains([cell])
	assert_array(world.fog.dirty_cells(2)).is_equal(control.fog.dirty_cells(2))
	assert_int(world.fog.visible[world.fog.cells + cell]).is_equal(0)


## The totals of the landing tick's ECONOMY leave a ruptured building out: two plants of player 2,
## one in the radius (it dies) and one outside, make the sum of both until the landing step and the
## sum of the survivor after it.
func test_the_power_of_the_landing_tick_leaves_a_ruptured_building_out() -> void:
	var world: World = Strikes.world()
	var plant: int = Strikes.type_of(world, "plant")
	var inside: int = world.add_building(2, plant, 14, 9)  # Centred on the point.
	world.add_building(2, plant, 22, 4)
	var power: int = world.type_power[plant]
	assert_int(power).is_greater(0)
	var tick: int = _at_fire_tick(world)
	world.hp[world.index_of(inside)] = Strikes.damage_on(world, world.index_of(inside))
	Strikes.step(world, [Strikes.fire(Strikes.BORE_A)])
	Strikes.run_to(world, tick + Strikes.delay_of(world, "bore"))
	assert_int(world.power_made[2]).is_equal(2 * power)
	Strikes.step(world)
	assert_int(world.index_of(inside)).is_equal(-1)
	assert_int(world.power_made[2]).is_equal(power)


## A rupture that kills a player's last producer defeats the player in that same step, and the match
## ends with the other player the winner: the headquarters are the only producers of the rig, and
## the rupture takes player 1's own as readily as player 2's. A headquarters with one hit point
## more survives, and nobody is defeated.
func test_a_rupture_that_kills_the_last_producer_defeats_its_player_on_that_tick() -> void:
	var cases: Array[Array] = [
		[Strikes.HQ_2, Vector2i(25500, 15500), 2, 1], [Strikes.HQ_1, Vector2i(3500, 9500), 1, 2]
	]
	for scenario: Array in cases:
		var world: World = Strikes.world()
		var survivor: World = Strikes.world()
		var loser: int = scenario[2]
		var both: Array[World] = [world, survivor]
		for each: World in both:
			var tick: int = _at_fire_tick(each)
			var row: int = each.index_of(scenario[0])
			var lost: int = Strikes.damage_on(each, row)
			each.hp[row] = lost + (1 if each == survivor else 0)
			Strikes.step(each, [Strikes.fire(Strikes.BORE_A, 1, scenario[1])])
			Strikes.run_to(each, tick + Strikes.delay_of(each, "bore"))
			assert_array([each.defeated_tick[loser], each.match_end_tick]).is_equal([0, 0])
			Strikes.step(each)
		(
			assert_array(
				[world.defeated_tick[loser], world.match_end_tick, world.winner, world.tick]
			)
			. is_equal([world.tick, world.tick, scenario[3], world.tick])
		)
		(
			assert_array([survivor.defeated_tick[loser], survivor.match_end_tick, survivor.winner])
			. is_equal([0, 0, 0])
		)
		assert_int(Strikes.hp_of(survivor, scenario[0])).is_equal(1)
		assert_int(Strikes.hp_of(world, scenario[0])).is_equal(GONE)


## A replay reproduces the strike: a match recorded through the MatchLoop with the command in its
## log plays back on a fresh world to the same checkpoints and the same final hash, also through
## the bytes a saved replay would be, and the victim has lost what the rupture takes.
func test_a_replay_reproduces_the_rupture() -> void:
	var recorded: World = _scene()
	var victim: int = recorded.unit_id[recorded.unit_count() - 1]
	var start: int = Strikes.hp_of(recorded, victim)
	var loop: MatchLoop = MatchLoop.create(null, "", 7, recorded)
	var fire_at: int = Strikes.fire_tick(recorded, Strikes.BORE_A)
	var ticks: int = fire_at + Strikes.delay_of(recorded, "bore") + 40
	while recorded.tick < ticks:
		var queued: Array[Command] = []
		if recorded.tick == fire_at:
			queued.append(Strikes.fire(Strikes.BORE_A))
		loop.step(recorded, queued)
	loop.replay.finish(recorded)
	var replay: Replay = loop.replay
	assert_int(replay.checkpoint_ticks.size()).is_greater(3)
	assert_int(Strikes.hp_of(recorded, victim)).is_equal(
		start - Strikes.damage_on(recorded, recorded.index_of(victim))
	)
	var fresh: World = _scene()
	assert_int(Replay.play(replay, fresh, ticks)).is_equal(Replay.PLAY_MATCHED)
	assert_int(fresh.state_hash()).is_equal(replay.final_hash)
	assert_int(Strikes.hp_of(fresh, victim)).is_equal(Strikes.hp_of(recorded, victim))
	var loaded: Replay = Replay.from_bytes(replay.to_bytes())
	var again: World = _scene()
	assert_int(Replay.play(loaded, again, ticks)).is_equal(Replay.PLAY_MATCHED)
	assert_int(again.state_hash()).is_equal(replay.final_hash)


## The rig's world with one rifle of player 2 on the point (id 6), the start of a replay.
func _scene() -> World:
	var world: World = Strikes.world()
	Strikes.add(world, 2, "rifle", Strikes.POINT.x, Strikes.POINT.y)
	return world
