extends GdUnitTestSuite
## The FOG kernel against its GDScript twin on seeded random states (ADR 0013 section 4, plan
## P46n2), each compared after every phase like test_fog_lockstep.gd, with the FogTallyProbe holding
## the twin to the rule: Worlds.random() (fog_worlds.gd) builds a map of 1 to 40 x 1 to 30 tiles for
## 1 to 4 players, 1 to 4 types of sight (0 to 91000 milli) and 0 to 119 units at random points on
## the map and off it, some stacked, with a cadence from -3 to 2^40, a tick from -20 to 2^61, rows
## moved to other stamped cells, rows not stamped, rows of the neutral player and of a player past
## player_count, and a few dead rows.
## - One phase at a time (`once()`: FogUpdate.begin, the removal, FogUpdate.run, like Sim.step does
##   it), 160 states, a type past the sight table among them (the pad mask): three rounds at the
##   state's own cadence and tick, then four rounds at the cadence of 1 (every player's turn on
##   every tick), the rows walking, dying and joining between the rounds.
## - Whole ticks (Sim.step through the MatchLoop, 100 states without a type past the tables), 12
##   ticks each, from a small tick if the state's is out of the range of a run.
## The floors are measured on main at 5984880 and set at about two thirds of the figures measured;
## the figures are beside each one.

const Rig: GDScript = preload("res://tests/sim/support/fog_lockstep_rig.gd")
const Orders: GDScript = preload("res://tests/sim/support/fog_orders.gd")
const Worlds: GDScript = preload("res://tests/sim/support/fog_worlds.gd")
const PHASE_STATES: int = 160
const TICK_STATES: int = 100
## The 160 states, one phase at a time, measured: 32,900 turns, 14,892 stays, 16,252 restamps,
## 16,252 unstamps, 1,448,621 covered, 717,106 overlap_stamps, 645,390 overlap_unstamps, 43,420
## flips_on, 37,458 flips_off, 17,467 explored_new, 50,684 listed, 13,871 relisted, 12,621
## version_flips, 21,639 quiet_stamps, 1,987 deaths, 1,122 deaths_stamped, 791 death_on_turn,
## 14,413 clipped, 8,469 clip_w, 8,559 clip_e, 8,776 clip_n, 8,790 clip_s, 9,958 clip_corner,
## 16,323 overflows, 284 full_blocks, 1,756 first_stamps, 3,687 off_map, 4,906 high_players,
## 4,857 pad_moves, 28,583 no_player.
const PHASE_FLOORS: Dictionary[StringName, int] = {
	&"turns": 21000,
	&"stays": 9900,
	&"restamps": 10000,
	&"unstamps": 10000,
	&"covered": 960000,
	&"overlap_stamps": 470000,
	&"overlap_unstamps": 430000,
	&"flips_on": 28000,
	&"flips_off": 24000,
	&"explored_new": 11000,
	&"listed": 33000,
	&"relisted": 9200,
	&"version_flips": 8400,
	&"quiet_stamps": 14000,
	&"deaths": 1300,
	&"deaths_stamped": 740,
	&"death_on_turn": 520,
	&"clipped": 9600,
	&"clip_w": 5600,
	&"clip_e": 5700,
	&"clip_n": 5800,
	&"clip_s": 5800,
	&"clip_corner": 6600,
	&"overflows": 10000,
	&"full_blocks": 180,
	&"first_stamps": 1100,
	&"off_map": 2400,
	&"high_players": 3200,
	&"pad_moves": 3200,
	&"no_player": 19000
}
## The 100 states over whole ticks, measured: 20,903 turns, 7,680 stays, 11,870 restamps, 11,870
## unstamps, 1,694,864 covered, 846,110 overlap_stamps, 782,973 overlap_unstamps, 29,802
## flips_on, 28,073 flips_off, 11,595 explored_new, 35,812 listed, 12,110 relisted, 9,799
## version_flips, 15,294 quiet_stamps, 1,697 deaths, 912 deaths_stamped, 415 death_on_turn,
## 15,470 clipped, 9,747 clip_w, 9,371 clip_e, 8,245 clip_n, 7,996 clip_s, 10,113 clip_corner,
## 9,953 overflows, 202 full_blocks, 1,353 first_stamps, 3,199 off_map, 2,803 high_players,
## 30,871 no_player.
const TICK_FLOORS: Dictionary[StringName, int] = {
	&"turns": 13000,
	&"stays": 5100,
	&"restamps": 7900,
	&"unstamps": 7900,
	&"covered": 1100000,
	&"overlap_stamps": 560000,
	&"overlap_unstamps": 520000,
	&"flips_on": 19000,
	&"flips_off": 18000,
	&"explored_new": 7700,
	&"listed": 23000,
	&"relisted": 8000,
	&"version_flips": 6500,
	&"quiet_stamps": 10000,
	&"deaths": 1100,
	&"deaths_stamped": 600,
	&"death_on_turn": 270,
	&"clipped": 10000,
	&"clip_w": 6400,
	&"clip_e": 6200,
	&"clip_n": 5400,
	&"clip_s": 5300,
	&"clip_corner": 6700,
	&"overflows": 6600,
	&"full_blocks": 130,
	&"first_stamps": 900,
	&"off_map": 2100,
	&"high_players": 1800,
	&"no_player": 20000
}


func test_random_states_match_one_phase_at_a_time() -> void:
	var total: Dictionary[StringName, int] = Rig.empty_tally()
	for salt: int in PHASE_STATES:
		var rig: RefCounted = Rig.new().setup(Worlds.random.bind(salt))
		assert_array(rig.problems).is_empty()
		for round: int in 7:
			if round == 3:
				for world: World in rig.worlds:
					world.fog_period_ticks = 1
					world.tick = world.tick % 100
			var found: String = rig.once()
			(
				assert_str(found)
				. override_failure_message("state %d, round %d" % [salt, round])
				. is_empty()
			)
			for world: World in rig.worlds:
				Orders.walkers(world, round, salt, 20, 20)
				world.tick += 1
		assert_int(rig.tally()[&"rows"] + rig.tally()[&"deaths"]).is_equal(rig.rows_stepped)
		Rig.add_to(total, rig.tally())
	_assert_reached(total, PHASE_FLOORS, "phases")


func test_random_states_match_over_whole_ticks() -> void:
	var total: Dictionary[StringName, int] = Rig.empty_tally()
	for salt: int in TICK_STATES:
		var build: Callable = Worlds.random.bind(1000 + salt, false)
		var rig: RefCounted = Rig.new().setup(build, Rig.ALL if salt % 2 == 0 else Rig.ONLY)
		assert_array(rig.problems).is_empty()
		for world: World in rig.worlds:
			if world.tick < 0 or world.tick > 1000:
				world.tick = 7 + salt % 5
		var found: String = rig.run(12, Orders.walkers.bind(salt, 15, 15))
		assert_str(found).override_failure_message("state %d" % salt).is_empty()
		assert_int(rig.tally()[&"rows"] + rig.tally()[&"deaths"]).is_equal(rig.rows_stepped)
		Rig.add_to(total, rig.tally())
	_assert_reached(total, TICK_FLOORS, "random ticks")


## Asserts that a run reached each count at least as often as `least` (by tally name) says.
func _assert_reached(
	tally: Dictionary[StringName, int], least: Dictionary[StringName, int], label: String
) -> void:
	for name: StringName in least:
		var message: String = "%s: reached %s" % [label, name]
		assert_int(tally[name]).override_failure_message(message).is_greater(least[name] - 1)
