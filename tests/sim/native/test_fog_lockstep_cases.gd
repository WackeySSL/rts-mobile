extends GdUnitTestSuite
## The FOG kernel against its GDScript twin on the cases that the arena does not reach (ADR 0013
## section 4, plan P46n2), each compared after every tick like test_fog_lockstep.gd, with hand-built
## Worlds of any size and any number of players (fog_worlds.gd) driven by a script of
## moves, deaths and births (fog_orders.gd), and the FogTallyProbe holding the twin to the rule
## as it goes:
## - discs clipped at every edge and corner: units that tour the corners, the middles of the
##   edges, the tiles one in from the corners and the exact milli positions at the edges and past
##   them, with sights from under a tile to far more than the map, on maps of 24 x 17, 9 x 31, 5
##   x 5 and 31 x 3 tiles, at the cadence of 1 and of 3;
## - overlapping stamps: 27 units of 3 players stacked on one tile each and then stepping on
##   offsets, so the counts of a cell reach 9 and an unstamp leaves it visible;
## - a stamp and its removal in one tick: deaths on the owner's own update tick (the list that
##   FogUpdate.begin has just emptied takes the unstamp), on another player's tick, of a row
##   moved after its stamp, of a unit added in the same tick, and a mover that stamps the cells
##   that a death had just unstamped (a cell flips twice and is listed once);
## - full blocks: a block that overflows on an 8 x 8 map (capacity 16), a block that is exactly
##   full (4 flips on a capacity of 4) and one flip more, and maps whose capacity is 0 or 1;
## - the pad mask: types with no sight entry take the last mask (sight 0), also when a mask was
##   added after prepare() (a mask id is not a type index);
## - the cadence at -3, 0, 1, 2, 3, 4, 7 and 2^40 with 4 players (players 1 and 4 share their
##   ticks), and at negative and huge ticks;
## - a grid whose sides do not make its cells (the twin's guard): the seven grids of
##   test_fog_kernel.gd under a run of walkers, which stamp, list and count nothing;
## - 2 to 4 players on maps that are not square (40 x 20, 20 x 40, 7 x 3, 3 x 7, 1 x 9, 9 x 1, 33
##   x 5, 5 x 33) under walkers;
## - rows added after prepare() (stamped for the first time at their player's turn, none for a
##   player past player_count, one that dies the tick it is added) and a World with no unit at
##   the start;
## - the cells covered, added to a count the tick already holds;
## - the rig and the probe name a difference in every array the phase writes, so that a case that
##   passes is not one whose check looks at nothing;
## - fog.visible is not in the state hash (P65, ADR 0016), so after every tick of these cases (the
##   grid that is not whole excepted: it has no fog) the rig rebuilds the counts from the rows
##   (owner, type_index, fog_cell and the sight of the type) and holds both Worlds to them.
## The floors are the figures that the cases reach, measured on main at 5984880 and set at about
## two thirds of them, beside each one. That each case is on a World with a fog at all, and that
## the phase runs in the implementation asked for, is asserted by the rig.

const Rig: GDScript = preload("res://tests/sim/support/fog_lockstep_rig.gd")
const Orders: GDScript = preload("res://tests/sim/support/fog_orders.gd")
const Worlds: GDScript = preload("res://tests/sim/support/fog_worlds.gd")
## The sights of the five types of the edge cases: 6 tiles, 6.5, 2, more than any map there, and
## below one tile.
const SIGHTS: Array[int] = [6000, 6500, 2000, 91000, 999]
const MAPS: Array[Vector2i] = [Vector2i(24, 17), Vector2i(9, 31), Vector2i(5, 5), Vector2i(31, 3)]
## The sizes and player counts of the walkers' maps.
const SHAPES: Array[Vector3i] = [
	Vector3i(40, 20, 2),
	Vector3i(20, 40, 3),
	Vector3i(7, 3, 4),
	Vector3i(3, 7, 2),
	Vector3i(1, 9, 2),
	Vector3i(9, 1, 3),
	Vector3i(33, 5, 4),
	Vector3i(5, 33, 3)
]
const PERIODS: Array[int] = [-3, 0, 1, 2, 3, 4, 7, 1 << 40]
const BENDS: Array[String] = [
	"one column less",
	"one row more",
	"no columns",
	"no rows",
	"sides of minus the columns and rows",
	"no rows, no cells",
	"cells that the columns do not divide"
]
## The 8 runs of the edge cases together, measured: 2,592 turns, 204 stays, 2,388 restamps, 2,388
## unstamps, 202,191 covered, 76,577 overlap_stamps, 77,586 overlap_unstamps, 23,883 flips_on,
## 24,145 flips_off, 1,712 explored_new, 26,592 listed, 1,348 relisted, 2,103 version_flips,
## 2,673 quiet_stamps, 3,692 clipped, 2,453 clip_w, 2,110 clip_e, 2,710 clip_n, 2,376 clip_s,
## 3,072 clip_corner, 20,088 overflows, 354 full_blocks, 420 off_map, 280 high_players.
const EDGE_FLOORS: Dictionary[StringName, int] = {
	&"turns": 1700,
	&"stays": 130,
	&"restamps": 1500,
	&"unstamps": 1500,
	&"covered": 130000,
	&"overlap_stamps": 51000,
	&"overlap_unstamps": 51000,
	&"flips_on": 15000,
	&"flips_off": 16000,
	&"explored_new": 1100,
	&"listed": 17000,
	&"relisted": 890,
	&"version_flips": 1400,
	&"quiet_stamps": 1700,
	&"clipped": 2400,
	&"clip_w": 1600,
	&"clip_e": 1400,
	&"clip_n": 1800,
	&"clip_s": 1500,
	&"clip_corner": 2000,
	&"overflows": 13000,
	&"full_blocks": 230,
	&"off_map": 280,
	&"high_players": 180
}
## The overlapping stamps, measured: 540 restamps, 47,374 covered, 22,740 overlap_stamps, 23,043
## overlap_unstamps, 872 flips_on, 719 flips_off, 1,461 listed, 265 version_flips, 815
## quiet_stamps, 180 high_players, 536 clipped.
const OVERLAP_FLOORS: Dictionary[StringName, int] = {
	&"restamps": 360,
	&"covered": 31000,
	&"overlap_stamps": 15000,
	&"overlap_unstamps": 15000,
	&"flips_on": 580,
	&"flips_off": 470,
	&"listed": 970,
	&"version_flips": 170,
	&"quiet_stamps": 540,
	&"high_players": 120,
	&"clipped": 350
}
## The two removal runs together, measured: 18 deaths, 16 deaths_stamped, 13 death_on_turn, 2
## first_stamps, 12 restamps, 48 relisted, 125 flips_on, 233 flips_off, 310 listed, 837
## overlap_stamps, 703 overlap_unstamps, 20 version_flips, 2 high_players.
const REMOVAL_FLOORS: Dictionary[StringName, int] = {
	&"deaths": 12,
	&"deaths_stamped": 10,
	&"death_on_turn": 8,
	&"first_stamps": 1,
	&"restamps": 8,
	&"relisted": 32,
	&"flips_on": 83,
	&"flips_off": 150,
	&"listed": 200,
	&"overlap_stamps": 550,
	&"overlap_unstamps": 460,
	&"version_flips": 13,
	&"high_players": 1
}
## The full-block run on the 8 x 8 map, measured: 192 listed, 124 relisted, 364 overflows, 12
## full_blocks, 352 flips_on, 328 flips_off, 139 version_flips.
const FULL_FLOORS: Dictionary[StringName, int] = {
	&"listed": 120,
	&"relisted": 82,
	&"overflows": 240,
	&"full_blocks": 8,
	&"flips_on": 230,
	&"flips_off": 210,
	&"version_flips": 92
}
## The eight runs on the maps of capacity 0 and 1 together, measured: 990 first_stamps, 1,462
## restamps, 703 off_map, 7,630 covered, 190 deaths, 164 death_on_turn, 4,547 overlap_stamps,
## 2,908 overlap_unstamps, 112 flips_on, 63 flips_off, 52 listed, 115 overflows, 56 full_blocks,
## 3,767 quiet_stamps, 147 version_flips, 1,904 clipped.
const TINY_FLOORS: Dictionary[StringName, int] = {
	&"first_stamps": 660,
	&"restamps": 970,
	&"off_map": 460,
	&"covered": 5000,
	&"deaths": 120,
	&"death_on_turn": 100,
	&"overlap_stamps": 3000,
	&"overlap_unstamps": 1900,
	&"flips_on": 74,
	&"flips_off": 42,
	&"listed": 34,
	&"overflows": 76,
	&"full_blocks": 37,
	&"quiet_stamps": 2500,
	&"version_flips": 98,
	&"clipped": 1200
}
## The pad-mask run, measured: 32 pad_moves, 63 restamps, 3,458 covered, 761 flips_on, 705
## flips_off, 1,371 listed, 95 overflows, 995 overlap_stamps, 997 overlap_unstamps.
const PAD_FLOORS: Dictionary[StringName, int] = {
	&"pad_moves": 21,
	&"restamps": 42,
	&"covered": 2300,
	&"flips_on": 500,
	&"flips_off": 470,
	&"listed": 910,
	&"overflows": 63,
	&"overlap_stamps": 660,
	&"overlap_unstamps": 660
}
## The eight cadences together, measured: 1,633 turns, 844 stays, 782 restamps, 782 unstamps,
## 28,008 covered, 7,864 overlap_stamps, 8,056 overlap_unstamps, 6,037 flips_on, 6,051 flips_off,
## 1,850 explored_new, 8,523 listed, 132 relisted, 1,286 version_flips, 285 quiet_stamps, 9
## deaths, 9 deaths_stamped, 5 death_on_turn, 1,172 clipped, 531 clip_w, 373 clip_e, 638 clip_n,
## 350 clip_s, 720 clip_corner, 3,433 overflows, 163 full_blocks, 7 first_stamps, 188 off_map,
## 387 high_players.
const PERIOD_FLOORS: Dictionary[StringName, int] = {
	&"turns": 1000,
	&"stays": 560,
	&"restamps": 520,
	&"unstamps": 520,
	&"covered": 18000,
	&"overlap_stamps": 5200,
	&"overlap_unstamps": 5300,
	&"flips_on": 4000,
	&"flips_off": 4000,
	&"explored_new": 1200,
	&"listed": 5600,
	&"relisted": 88,
	&"version_flips": 850,
	&"quiet_stamps": 190,
	&"deaths": 6,
	&"deaths_stamped": 6,
	&"death_on_turn": 3,
	&"clipped": 780,
	&"clip_w": 350,
	&"clip_e": 240,
	&"clip_n": 420,
	&"clip_s": 230,
	&"clip_corner": 480,
	&"overflows": 2200,
	&"full_blocks": 100,
	&"first_stamps": 4,
	&"off_map": 120,
	&"high_players": 250
}
## The two runs at negative and huge ticks together, measured: 140 turns, 35 stays, 105 restamps,
## 4,370 covered, 937 flips_on, 1,006 flips_off, 1,215 listed, 48 high_players, 1,199
## overlap_stamps, 1,228 overlap_unstamps, 707 overflows, 166 version_flips.
const TICK_FLOORS: Dictionary[StringName, int] = {
	&"turns": 93,
	&"stays": 23,
	&"restamps": 70,
	&"covered": 2900,
	&"flips_on": 620,
	&"flips_off": 670,
	&"listed": 810,
	&"high_players": 32,
	&"overlap_stamps": 790,
	&"overlap_unstamps": 810,
	&"overflows": 470,
	&"version_flips": 110
}
## The eight shapes together, measured: 1,716 turns, 535 stays, 1,173 restamps, 1,173 unstamps,
## 39,712 covered, 10,373 overlap_stamps, 10,418 overlap_unstamps, 9,618 flips_on, 9,303
## flips_off, 3,697 explored_new, 15,768 listed, 224 relisted, 1,384 version_flips, 970
## quiet_stamps, 28 deaths, 28 deaths_stamped, 10 death_on_turn, 1,478 clipped, 811 clip_w, 729
## clip_e, 955 clip_n, 828 clip_s, 965 clip_corner, 2,929 overflows, 93 full_blocks, 8
## first_stamps, 413 off_map, 333 high_players.
const SHAPE_FLOORS: Dictionary[StringName, int] = {
	&"turns": 1100,
	&"stays": 350,
	&"restamps": 780,
	&"unstamps": 780,
	&"covered": 26000,
	&"overlap_stamps": 6900,
	&"overlap_unstamps": 6900,
	&"flips_on": 6400,
	&"flips_off": 6200,
	&"explored_new": 2400,
	&"listed": 10000,
	&"relisted": 140,
	&"version_flips": 920,
	&"quiet_stamps": 640,
	&"deaths": 18,
	&"deaths_stamped": 18,
	&"death_on_turn": 6,
	&"clipped": 980,
	&"clip_w": 540,
	&"clip_e": 480,
	&"clip_n": 630,
	&"clip_s": 550,
	&"clip_corner": 640,
	&"overflows": 1900,
	&"full_blocks": 62,
	&"first_stamps": 5,
	&"off_map": 270,
	&"high_players": 220
}
## The run with rows added after prepare(), measured: 11 first_stamps, 2 restamps, 187 covered,
## 137 flips_on, 105 listed, 43 overflows, 5 full_blocks, 7 high_players, 5 off_map, 11 clipped.
const BORN_FLOORS: Dictionary[StringName, int] = {
	&"first_stamps": 7,
	&"restamps": 1,
	&"covered": 120,
	&"flips_on": 91,
	&"listed": 70,
	&"overflows": 28,
	&"full_blocks": 3,
	&"high_players": 4,
	&"off_map": 3,
	&"clipped": 7
}

## Players 1 and 2 have a unit of each of the four sights that can be cut (6000, 6500, 2000 and 999
## milli), so that the cells flip at the edges; player 3 has the one that covers any map (91000),
## whose disc is clipped on all four sides at every place it goes.
@warning_ignore("integer_division")
func test_discs_clipped_at_every_edge_and_corner_match() -> void:
	var total: Dictionary[StringName, int] = Rig.empty_tally()
	for size: Vector2i in MAPS:
		for period: int in [1, 3]:
			var units: Array = []
			for type: int in SIGHTS.size():
				for player: int in [1, 2] if type != 3 else [3]:
					var at: Vector2i = Vector2i(size.x / 2, size.y / 2)
					units.append([player, type, Worlds.centre(at.x), Worlds.centre(at.y)])
			var members: Dictionary = {&"fog_period_ticks": period}
			var build: Callable = Worlds.field.bind(size.x, size.y, 3, SIGHTS, units, members)
			var rig: RefCounted = _rig(build)
			var label: String = "%s, period %d" % [size, period]
			var found: String = rig.run(54, Orders.scripted.bind(_tour(size, units.size())))
			assert_str(found).override_failure_message(label).is_empty()
			_assert_whole(rig, label)
			Rig.add_to(total, rig.tally())
	_assert_reached(total, EDGE_FLOORS, "edges")


@warning_ignore("integer_division")
func test_overlapping_stamps_of_several_units_and_players_match() -> void:
	var units: Array = []
	for player: int in [1, 2, 3]:
		for unit: int in 9:
			units.append([player, unit % 3, Worlds.centre(4 + player), Worlds.centre(5)])
	var members: Dictionary = {&"fog_period_ticks": 1}
	var rig: RefCounted = _rig(Worlds.field.bind(20, 12, 3, [6000, 3000, 2000], units, members))
	# Nine discs on one tile: a cell near the middle is seen nine times by the player.
	assert_int(_most_seen(rig.worlds[0])).is_equal(9)
	var script: Dictionary = {}
	for tick: int in 40:
		var entries: Array = []
		for index: int in units.size():
			var group: int = index % 4
			var x: int = (tick / 2 + group * 2 + index / 9 * 5) % 20
			entries.append(Orders.move(index + 1, Worlds.centre(x), Worlds.centre(3 + group)))
		script[tick] = entries
	var found: String = rig.run(40, Orders.scripted.bind(script))
	assert_str(found).is_empty()
	_assert_whole(rig, "overlap")
	_assert_reached(rig.tally(), OVERLAP_FLOORS, "overlap")


func test_a_stamp_and_its_removal_in_one_tick_match() -> void:
	var total: Dictionary[StringName, int] = Rig.empty_tally()
	for period: int in [1, 3]:
		var units: Array = [
			[1, 0, Worlds.centre(10), Worlds.centre(10)],
			[1, 0, Worlds.centre(12), Worlds.centre(10)],
			[1, 1, Worlds.centre(11), Worlds.centre(12)],
			[2, 0, Worlds.centre(10), Worlds.centre(10)],
			[2, 0, Worlds.centre(14), Worlds.centre(14)],
			[3, 2, Worlds.centre(20), Worlds.centre(20)],
			[3, 2, Worlds.centre(21), Worlds.centre(20)],
			[1, 2, Worlds.centre(25), Worlds.centre(25)]
		]
		var members: Dictionary = {&"fog_period_ticks": period}
		var rig: RefCounted = _rig(Worlds.field.bind(30, 30, 3, [6000, 2000, 4500], units, members))
		# Unit 2 dies on tick 0 (player 1's turn at either cadence) while units 1 and 8 step onto
		# the cells that its death unstamped; a unit of player 2 is added on tick 1 (its turn) and
		# killed in the same tick, one of player 2 dies on its turn; on tick 2 (player 3's turn)
		# unit 6 dies and unit 7 steps onto its tile; unit 3 steps on tick 3 and unit 5 on tick 4,
		# and each dies on the tick after its step (a row that moved after its stamp, then died).
		var script: Dictionary = {
			0:
			[
				Orders.kill(2),
				Orders.move(1, Worlds.centre(11), Worlds.centre(10)),
				Orders.move(8, Worlds.centre(13), Worlds.centre(10))
			],
			1: [Orders.add(2, 0, Worlds.centre(14), Worlds.centre(14)), Orders.kill(9)],
			2: [Orders.kill(6), Orders.move(7, Worlds.centre(20), Worlds.centre(20))],
			3: [Orders.move(3, Worlds.centre(11), Worlds.centre(13))],
			4:
			[
				Orders.kill(3),
				Orders.kill(4),
				Orders.move(5, Worlds.centre(15), Worlds.centre(15)),
				Orders.move(1, Worlds.centre(12), Worlds.centre(11))
			],
			5: [Orders.kill(5), Orders.move(8, Worlds.centre(12), Worlds.centre(10))],
			6: [Orders.kill(1), Orders.kill(7), Orders.kill(8)],
			7: [Orders.add(1, 1, Worlds.centre(3), Worlds.centre(3))]
		}
		var found: String = rig.run(12, Orders.scripted.bind(script))
		assert_str(found).override_failure_message("period %d" % period).is_empty()
		_assert_whole(rig, "removal")
		Rig.add_to(total, rig.tally())
	_assert_reached(total, REMOVAL_FLOORS, "removal")


## A block of 16 on an 8 x 8 map: six units of player 1 jump across the map at every update (period
## 1) and overflow it each time: the flag is set, the block is full, and the next update empties
## and fills it again. Player 2 does not move, so its block stays empty. The exactly full block is
## on a 4 x 4 map (capacity 4) with units that see only their own tile (the pad sight): two steps
## list 4 cells, which fill the block and set no flag, three steps list 4 and find it full, and
## the update after that empties it and lists 2.
func test_full_blocks_match() -> void:
	var units: Array = []
	for unit: int in 6:
		units.append([1, 0, Worlds.centre(unit), Worlds.centre(2)])
		units.append([2, 0, Worlds.centre(unit), Worlds.centre(5)])
	var members: Dictionary = {&"fog_period_ticks": 1}
	var rig: RefCounted = _rig(Worlds.field.bind(8, 8, 2, [1500], units, members))
	var script: Dictionary = {}
	for tick: int in 12:
		var entries: Array = []
		for unit: int in 6:
			var x: int = (unit * 5 + tick * 3 + 1) % 8
			entries.append(Orders.move(1 + 2 * unit, Worlds.centre(x), Worlds.centre(unit)))
		script[tick] = entries
	assert_int(rig.worlds[0].fog.dirty_capacity).is_equal(16)
	for tick: int in 12:
		var found: String = rig.step(Orders.scripted.bind(script))
		assert_str(found).override_failure_message("tick %d" % tick).is_empty()
		var fog: FogGrid = rig.worlds[0].fog
		var seen: Array = [fog.dirty_count[0], fog.dirty_full[0], fog.dirty_count[1]]
		assert_array(seen).override_failure_message("tick %d" % tick).is_equal([16, 1, 0])
	assert_int(rig.tally()[&"full_blocks"]).is_equal(12)
	_assert_whole(rig, "full")
	_assert_reached(rig.tally(), FULL_FLOORS, "full")
	_exactly_full_block(members)


## Maps whose block holds 0 or 1 cells (a quarter of 1, 2, 3, 4 or 7 cells), where every flip
## overflows, with units that join and leave under walkers.
func test_blocks_of_capacity_0_and_1_match() -> void:
	var total: Dictionary[StringName, int] = Rig.empty_tally()
	var index: int = 0
	for size: Vector2i in [Vector2i(1, 1), Vector2i(2, 2), Vector2i(3, 1), Vector2i(1, 7)]:
		for period: int in [1, 3]:
			var units: Array = [[1, 1, 500, 500], [2, 0, 500, 500], [1, 0, 1500, 500]]
			var members: Dictionary = {&"fog_period_ticks": period}
			var build: Callable = Worlds.field.bind(size.x, size.y, 2, [0, 1500], units, members)
			var rig: RefCounted = _rig(build)
			var label: String = "%s, period %d" % [size, period]
			var found: String = rig.run(40, Orders.walkers.bind(60 + index, 20, 120))
			assert_str(found).override_failure_message(label).is_empty()
			assert_int(rig.worlds[0].fog.dirty_capacity).is_less_equal(1)
			Rig.add_to(total, rig.tally())
			index += 1
	_assert_reached(total, TINY_FLOORS, "tiny")


## A type past the tables of the World is not one that Sim.step can run (the other phases index the
## tables by the type), so the FOG phase is run by itself here, with `once()`, a tick at a time.
func test_a_type_with_no_sight_entry_takes_the_pad_mask_match() -> void:
	var rig: RefCounted = _rig(_padded)
	# The pad mask is the one after the two masks of the types, and the mask added after it is not.
	assert_array(rig.worlds[0].fog.mask_radius).is_equal([6, 2, 0, 4])
	assert_int(rig.worlds[0].type_sight.size()).is_equal(2)
	var script: Dictionary = {}
	for tick: int in 24:
		var entries: Array = []
		for unit: int in 8:
			var x: int = (3 * unit + tick) % 30
			entries.append(Orders.move(unit + 1, Worlds.centre(x), Worlds.centre(4 + 2 * unit)))
		script[tick] = entries
	for tick: int in 24:
		for world: World in rig.worlds:
			Orders.scripted(world, tick, script)
			world.tick = tick
		var found: String = rig.once()
		assert_str(found).override_failure_message("tick %d" % tick).is_empty()
	_assert_whole(rig, "pad")
	_assert_reached(rig.tally(), PAD_FLOORS, "pad")


func test_every_cadence_matches_with_four_players() -> void:
	var total: Dictionary[StringName, int] = Rig.empty_tally()
	for index: int in PERIODS.size():
		var units: Array = []
		for player: int in [1, 2, 3, 4]:
			for type: int in 2:
				units.append([player, type, Worlds.centre(2 + 2 * type), Worlds.centre(player)])
		var members: Dictionary = {&"fog_period_ticks": PERIODS[index]}
		var rig: RefCounted = _rig(Worlds.field.bind(12, 9, 4, [4000, 1500], units, members))
		var label: String = "period %d" % PERIODS[index]
		var found: String = rig.run(48, Orders.walkers.bind(21 + index, 4, 2))
		assert_str(found).override_failure_message(label).is_empty()
		Rig.add_to(total, rig.tally())
	_assert_reached(total, PERIOD_FLOORS, "periods")


## The cadence in the ends of the range: a tick below 0 (a remainder that is negative or 0), and
## ticks near 2^40 and 2^61, with a period of 3 and of 1 << 40 + 3, and the rows stepping a tile
## between the calls.
func test_the_cadence_at_negative_and_huge_ticks_matches() -> void:
	var units: Array = []
	for player: int in [1, 2, 3, 4]:
		for type: int in 2:
			units.append([player, type, Worlds.centre(3 * type + player), Worlds.centre(player)])
	var ticks: Array[int] = []
	for tick: int in range(-10, 11):
		ticks.append(tick)
	for base: int in [1 << 40, (1 << 40) + 3, (1 << 61) - 4]:
		for tick: int in range(base, base + 8):
			ticks.append(tick)
	var total: Dictionary[StringName, int] = Rig.empty_tally()
	for period: int in [3, (1 << 40) + 3]:
		var members: Dictionary = {&"fog_period_ticks": period}
		var rig: RefCounted = _rig(Worlds.field.bind(12, 9, 4, [4000, 1500], units, members))
		for tick: int in ticks:
			for world: World in rig.worlds:
				world.tick = tick
				Orders.walkers(world, tick, 5, 0, 0)
			var found: String = rig.once()
			assert_str(found).override_failure_message("tick %d" % tick).is_empty()
		Rig.add_to(total, rig.tally())
	_assert_reached(total, TICK_FLOORS, "ticks")


func test_a_grid_whose_sides_do_not_make_its_cells_stamps_nothing_in_either_version() -> void:
	for how: String in BENDS:
		var build: Callable = _bent.bind(how)
		var rig: RefCounted = _rig(build)
		rig.derive_every = 0  # No fog to rebuild: the phase does nothing on this grid.
		var first: World = rig.worlds[0]
		var cells: PackedInt32Array = first.fog_cell.duplicate()
		var xs: PackedInt32Array = first.pos_x.duplicate()
		var ys: PackedInt32Array = first.pos_y.duplicate()
		var found: String = rig.run(24, Orders.walkers.bind(33, 0, 0))
		assert_str(found).override_failure_message(how).is_empty()
		var tally: Dictionary[StringName, int] = rig.tally()
		assert_int(tally[&"ticks"]).is_equal(24)
		assert_array([tally[&"turns"], tally[&"covered"], tally[&"listed"]]).is_equal([0, 0, 0])
		# The rows moved (walkers neither kills nor adds a row here, so the copies line up), onto
		# cells other than the ones they were stamped on, which a whole grid would have restamped at
		# the owners' turns; but no row's cell moved, in either version.
		assert_int(first.unit_count()).override_failure_message(how).is_equal(cells.size())
		var moved: int = 0
		var due: int = 0
		for row: int in cells.size():
			moved += int(first.pos_x[row] != xs[row] or first.pos_y[row] != ys[row])
			due += int(first.cell_of(first.pos_x[row], first.pos_y[row]) != first.fog_cell[row])
		assert_int(moved).override_failure_message(how).is_greater(0)
		assert_int(due).override_failure_message(how).is_greater(0)
		for world: World in rig.worlds:
			assert_array(world.fog_cell).override_failure_message(how).is_equal(cells)


func test_two_to_four_players_on_maps_that_are_not_square_match() -> void:
	var total: Dictionary[StringName, int] = Rig.empty_tally()
	for index: int in SHAPES.size():
		var shape: Vector3i = SHAPES[index]
		var units: Array = []
		for player: int in range(1, shape.z + 1):
			for type: int in 3:
				units.append(
					[
						player,
						type,
						Worlds.centre(player * 3 % shape.x),
						Worlds.centre(type * 2 % shape.y)
					]
				)
		var sights: Array = [6000, 2500, 999]
		var rig: RefCounted = _rig(Worlds.field.bind(shape.x, shape.y, shape.z, sights, units))
		var label: String = "%d x %d tiles, %d players" % [shape.x, shape.y, shape.z]
		var found: String = rig.run(90, Orders.walkers.bind(40 + index, 6, 3))
		assert_str(found).override_failure_message(label).is_empty()
		Rig.add_to(total, rig.tally())
	_assert_reached(total, SHAPE_FLOORS, "shapes")


## A World that starts with no unit, and rows added later (fog_cell -1) for each player, one for a
## player past player_count (refused, counted in spawn_refused) and one killed in the tick it is
## added: each is stamped for the first time at its player's turn.
func test_rows_added_after_prepare_are_stamped_at_their_players_turn() -> void:
	var members: Dictionary = {&"fog_period_ticks": 3}
	var rig: RefCounted = _rig(Worlds.field.bind(10, 6, 4, [3000, 1000], [], members))
	var script: Dictionary = {}
	for tick: int in 14:
		var owner: int = 1 + tick % 5
		script[tick] = [Orders.add(owner, tick % 2, Worlds.centre(tick % 12 - 1), Worlds.centre(2))]
	script[1].append(Orders.kill(2))
	script[6].append(Orders.move(1, -2500, 200))
	script[9].append(Orders.move(4, 12345678, 87654321))
	assert_int(rig.worlds[0].unit_count()).is_equal(0)
	assert_str(rig.run(16, Orders.scripted.bind(script))).is_empty()
	assert_int(rig.worlds[0].spawn_refused).is_greater(0)
	_assert_whole(rig, "born")
	_assert_reached(rig.tally(), BORN_FLOORS, "born")


## The cells the phase covers are added to what the tick has counted so far, also when the
## tick counted some already.
func test_the_cells_covered_are_added_to_a_count_the_tick_already_holds() -> void:
	var units: Array = [[1, 0, 1500, 1500], [2, 1, 4500, 4500], [1, 0, 7500, 2500]]
	var rig: RefCounted = _rig(Worlds.field.bind(12, 9, 2, [3000, 6000], units))
	for round: int in 6:
		for world: World in rig.worlds:
			world.stats[World.Stat.FOG_CELLS] = 1000 * (round + 1)
			world.tick = round
			Orders.walkers(world, round, 8, 0, 0)
		assert_str(rig.once(true)).override_failure_message("round %d" % round).is_empty()
		assert_int(rig.worlds[1].stats[World.Stat.FOG_CELLS]).is_greater_equal(1000 * (round + 1))
	assert_int(rig.tally()[&"covered"]).is_greater(0)


## The rig names a difference in every array the phase writes (bent in the kernels' World alone,
## after a tick that moved a unit), and so does the probe (bent in both Worlds alike between the
## phase and the probe's count, so that only the rule can tell): a case that passes is not one whose
## check looks at nothing.
func test_the_rig_and_the_probe_name_a_difference_in_every_array_the_phase_writes() -> void:
	var fog_arrays: Array[String] = [
		"visible", "explored", "listed", "dirty", "dirty_count", "dirty_full", "version"
	]
	for name: String in fog_arrays + ["fog_cell", "stats"]:
		var in_fog: bool = name in fog_arrays
		var label: String = "fog.%s" % name if in_fog else name
		var rig: RefCounted = _rig(_two_units)
		assert_str(rig.run(1, Orders.scripted.bind(_one_step()))).is_empty()
		_bend_array(rig.worlds[1].fog if in_fog else rig.worlds[1], name)
		assert_str(rig.compare("tick")).override_failure_message(label).contains(label)
		var probed: RefCounted = _rig(_two_units)
		probed.probe.dying()
		for world: World in probed.worlds:
			Orders.scripted(world, 0, _one_step())
			FogUpdate.begin(world)
			world.remove_dead()
		probed.probe.before()
		for world: World in probed.worlds:
			FogUpdate.run(world)
			_bend_array(world.fog if in_fog else world, name)
		assert_str(probed.compare("tick")).is_empty()
		probed.probe.count()
		assert_int(probed.probe.last_mismatches).override_failure_message(label).is_equal(1)
		assert_str(probed.probe.first_mismatch).override_failure_message(label).starts_with(name)


## fog.visible is out of the state hash (P65), so the rebuild from the rows is the one check that
## sees a count the rows do not say. Both Worlds get the same wrong count (the lockstep compare and
## the probe, which works from the counts it finds, let it pass), and the next step names it; a rig
## with derive_every 0 lets it pass.
func test_the_rig_names_a_count_that_the_rows_do_not_say() -> void:
	var quiet: RefCounted = _rig(_two_units)
	quiet.derive_every = 0
	var loud: RefCounted = _rig(_two_units)
	for rig: RefCounted in [quiet, loud]:
		assert_str(rig.run(2)).is_empty()
		for world: World in rig.worlds:
			world.fog.visible[world.fog.visible.size() - 1] += 1
	assert_str(quiet.run(1)).is_empty()
	var found: String = loud.run(1)
	assert_str(found).contains("fog.visible of the twin's World is not what its rows say")
	assert_str(found).contains("player 2, tile 107")


## The 4 x 4 map of test_full_blocks_match(): the block of player 1 is exactly full after two
## steps (4 flips of 4), overflows after three and is empty at the update after that.
func _exactly_full_block(members: Dictionary) -> void:
	var units: Array = [[1, 0, 500, 500], [1, 0, 1500, 500], [1, 0, 2500, 500], [2, 0, 500, 3500]]
	var rig: RefCounted = _rig(Worlds.field.bind(4, 4, 2, [0], units, members))
	assert_int(rig.worlds[0].fog.dirty_capacity).is_equal(4)
	var steps: Dictionary = {
		0: [Orders.move(1, 500, 1500), Orders.move(2, 1500, 1500)],
		1: [Orders.move(1, 500, 2500), Orders.move(2, 1500, 2500), Orders.move(3, 2500, 2500)],
		2: [Orders.move(3, 2500, 3500), Orders.move(4, 1500, 3500)]
	}
	var seen: Array = []
	for tick: int in 3:
		assert_str(rig.step(Orders.scripted.bind(steps))).is_empty()
		var fog: FogGrid = rig.worlds[0].fog
		seen.append([fog.dirty_count[0], fog.dirty_full[0]])
	assert_array(seen).is_equal([[4, 0], [4, 1], [2, 0]])


## Two units, one of each player, on a 12 x 9 map; the first steps right at tick 0.
func _two_units() -> World:
	return Worlds.field(12, 9, 2, [3000], [[1, 0, 1500, 1500], [2, 0, 9500, 5500]])


func _one_step() -> Dictionary:
	return {0: [Orders.move(1, 2500, 1500)]}


## Adds 1 to the first entry of the array `name` of `holder` (the entry of FOG_CELLS for stats).
func _bend_array(holder: Object, name: String) -> void:
	var array: Variant = holder.get(name)
	var at: int = World.Stat.FOG_CELLS if name == "stats" else 0
	array[at] = array[at] + 1
	holder.set(name, array)


## A World of 30 x 22 tiles with two sight types (6000 and 2000) and eight units of types 0, 1 and
## beyond the table (2, 5 and 9), which sees only its own tile, and a mask of 4000 added after
## prepare(), so that the pad mask is no longer the last one.
func _padded() -> World:
	var types: Array[int] = [0, 1, 2, 5, 9, 2, 0, 1]
	var units: Array = []
	for index: int in types.size():
		units.append([1 + index % 2, types[index], Worlds.centre(3 * index), Worlds.centre(4)])
	var world: World = Worlds.field(30, 22, 2, [6000, 2000], units)
	world.fog.add_mask(4000)
	return world


## A World of 7 x 5 tiles with 3 players and 6 units whose grid says `how` (see Worlds.bend()).
func _bent(how: String) -> World:
	var units: Array = []
	for index: int in 6:
		units.append([1 + index % 3, index % 2, Worlds.centre(index), Worlds.centre(index % 5)])
	var world: World = Worlds.field(7, 5, 3, [3000, 1000], units)
	Worlds.bend(world, how)
	return world


## The tour of the units of the map `size`: unit `count`'s share of the anchors, each unit one
## anchor behind the one before it, so that every tick sends the units to different places.
func _tour(size: Vector2i, count: int) -> Dictionary:
	var anchors: Array[Vector2i] = _anchors(size)
	var script: Dictionary = {}
	for tick: int in 54:
		var entries: Array = []
		for index: int in count:
			var at: Vector2i = anchors[(tick + 3 * index) % anchors.size()]
			entries.append(Orders.move(index + 1, at.x, at.y))
		script[tick] = entries
	return script


## Where the units of the edge cases go (milli-tiles): the centres of the four corner tiles, of the
## middles of the four edges, of the four tiles one in from the corners, then the exact positions at
## the edges: the origin, one milli before the far end, the far end, one before the origin, and
## beyond them, on one axis and on both.
@warning_ignore("integer_division")
func _anchors(size: Vector2i) -> Array[Vector2i]:
	var wide: int = size.x * World.MILLI_PER_TILE
	var high: int = size.y * World.MILLI_PER_TILE
	var out: Array[Vector2i] = []
	for corner: Vector2i in [Vector2i(0, 0), Vector2i(size.x - 1, 0), Vector2i(0, size.y - 1)]:
		out.append(Vector2i(Worlds.centre(corner.x), Worlds.centre(corner.y)))
	out.append(Vector2i(Worlds.centre(size.x - 1), Worlds.centre(size.y - 1)))
	out.append(Vector2i(Worlds.centre(size.x / 2), Worlds.centre(0)))
	out.append(Vector2i(Worlds.centre(size.x / 2), Worlds.centre(size.y - 1)))
	out.append(Vector2i(Worlds.centre(0), Worlds.centre(size.y / 2)))
	out.append(Vector2i(Worlds.centre(size.x - 1), Worlds.centre(size.y / 2)))
	for inner: Vector2i in [Vector2i(1, 1), Vector2i(size.x - 2, 1), Vector2i(1, size.y - 2)]:
		out.append(Vector2i(Worlds.centre(inner.x), Worlds.centre(inner.y)))
	out.append(Vector2i(Worlds.centre(size.x - 2), Worlds.centre(size.y - 2)))
	out.append_array([Vector2i(0, 0), Vector2i(wide - 1, high - 1), Vector2i(wide, high)])
	out.append_array([Vector2i(-1, -1), Vector2i(-3000, high / 2), Vector2i(wide / 2, high + 2500)])
	out.append_array([Vector2i(999, 999), Vector2i(1000, 1000), Vector2i(wide, 0)])
	return out


## A rig over `build` with FOG alone in C++; nothing went wrong in attaching the kernels. It holds
## both Worlds to the rows after every tick (P65): fog.visible is out of the state hash, so the
## counts rebuilt from owner, type_index and fog_cell have to equal it in the twin and in the
## kernels' World. A case with a grid that is not whole switches that off.
func _rig(build: Callable, mask: int = Rig.ONLY) -> RefCounted:
	var rig: RefCounted = Rig.new().setup(build, mask)
	assert_array(rig.problems).is_empty()
	rig.derive_every = 1
	return rig


## After a run: every row of every tick was seen (the rows the FOG phase saw plus the ones the
## removal took first), and the twin's counts are never below 0.
func _assert_whole(rig: RefCounted, label: String) -> void:
	(
		assert_int(rig.tally()[&"rows"] + rig.tally()[&"deaths"])
		. override_failure_message(label)
		. is_equal(rig.rows_stepped)
	)
	for count: int in rig.worlds[0].fog.visible:
		assert_int(count).override_failure_message(label).is_greater_equal(0)


## How many discs see the most-seen cell of any player.
func _most_seen(world: World) -> int:
	var most: int = 0
	for count: int in world.fog.visible:
		most = maxi(most, count)
	return most


## Asserts that a run reached each count at least as often as `least` (by tally name) says.
func _assert_reached(
	tally: Dictionary[StringName, int], least: Dictionary[StringName, int], label: String
) -> void:
	for name: StringName in least:
		var message: String = "%s: reached %s" % [label, name]
		assert_int(tally[name]).override_failure_message(message).is_greater(least[name] - 1)
