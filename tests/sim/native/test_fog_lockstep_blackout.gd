extends GdUnitTestSuite
## The FOG kernel against its GDScript twin while buildings are blacked out and the vision cut is on
## (plan row P573, ADR 0047 section 2). A row whose `offline_until` is above the stamp `tick + 1`
## wants no cell while `blackout_sight_cut` is 1: the twin (`FogUpdate.run`) and the kernel
## (core/fog.cpp, which reads `offline_until` and the rule through world_access.h) must take its
## disc away on its owner's turn and give it back on the first turn at or after the step it is back,
## and agree on every count, dirty list, version and `fog_cell` after every tick. The FogTallyProbe
## works the rule out again from its definition (cuts), and the rig rebuilds `visible` from the rows
## (fog_derivation.gd), which holds the cut rows to no disc.
## - A script, at the cadence of 1 and of 3 and with FOG alone native and with every phase the
##   library has: blackouts written the way a strike writes them (`offline_until` = stamp + length),
##   one written again while the first stands, a row that dies while cut, a blackout that outlasts
##   the run, a row added already blacked out (never stamped), and the rule switched off and on
##   again in the middle, over walkers that move, die and are born.
## - Seeded random blackouts on every row over walkers, 24 states.
## The floors are measured and set at about two thirds of the figures beside each one.

const Rig: GDScript = preload("res://tests/sim/support/fog_lockstep_rig.gd")
const Orders: GDScript = preload("res://tests/sim/support/fog_orders.gd")
const Worlds: GDScript = preload("res://tests/sim/support/fog_worlds.gd")
const SIGHTS: Array[int] = [6000, 3000, 4500]
const TICKS: int = 60
const STATES: int = 24
## The script, in ticks: a blackout of id 1 (14 steps), of id 3 (20), of id 5 (30, still on at the
## end), id 1's again while it stands (and again once it is over), the death of id 3 while cut, a
## row added already blacked out, and the rule off and on.
const BLACK_1: int = 3
const BLACK_3: int = 8
const BLACK_5: int = 12
const BLACK_1_AGAIN: int = 10
const BLACK_1_LATER: int = 24
const KILL_3: int = 16
const ADD_CUT: int = 20
const RULE_OFF: int = 34
const RULE_ON: int = 42
## The scripted run of both cadences and both masks together, measured: 14 cuts.
const SCRIPT_CUTS_FLOOR: int = 9
## The 24 random states, measured: 198 cuts.
const RANDOM_CUTS_FLOOR: int = 130


func _units() -> Array:
	return [
		[1, 0, Worlds.centre(10), Worlds.centre(10)],
		[1, 1, Worlds.centre(11), Worlds.centre(10)],
		[2, 0, Worlds.centre(20), Worlds.centre(12)],
		[2, 2, Worlds.centre(22), Worlds.centre(5)],
		[3, 1, Worlds.centre(5), Worlds.centre(15)],
		[1, 2, Worlds.centre(14), Worlds.centre(10)]
	]


func _build(period: int, rule: int) -> World:
	return Worlds.field(
		30, 20, 3, SIGHTS, _units(), {&"fog_period_ticks": period, &"blackout_sight_cut": rule}
	)


## What a strike writes: the stamp of the tick plus the length, kept if it is longer already.
func _black_out(world: World, id: int, tick: int, length: int) -> void:
	var row: int = world.index_of(id)
	if row >= 0:
		world.offline_until[row] = maxi(world.offline_until[row], tick + 1 + length)


func _script(world: World, tick: int, salt: int) -> Array[Command]:
	if tick == BLACK_1:
		_black_out(world, 1, tick, 14)
	elif tick == BLACK_3:
		_black_out(world, 3, tick, 20)
	elif tick == BLACK_5:
		_black_out(world, 5, tick, 30)
	elif tick == BLACK_1_AGAIN:
		_black_out(world, 1, tick, 14)
	elif tick == BLACK_1_LATER:
		_black_out(world, 1, tick, 6)
	elif tick == KILL_3:
		var row: int = world.index_of(3)
		if row >= 0:
			world.hp[row] = 0
	elif tick == ADD_CUT:
		var added: int = world.add_unit(2, 0, Worlds.centre(3), Worlds.centre(3))
		_black_out(world, added, tick, 25)
	elif tick == RULE_OFF:
		world.blackout_sight_cut = 0
	elif tick == RULE_ON:
		world.blackout_sight_cut = 1
	return Orders.walkers(world, tick, salt, 3, 3)


## Seeded blackouts: about one row in 25 each tick is blacked out for 1 to 40 steps.
func _random_orders(world: World, tick: int, salt: int) -> Array[Command]:
	var rng: DetRandom = DetRandom.create(salt, 700 + tick)
	for row: int in world.unit_count():
		if rng.next_int(25) == 0:
			world.offline_until[row] = maxi(world.offline_until[row], tick + 2 + rng.next_int(40))
	return Orders.walkers(world, tick, salt, 6, 6)


func test_a_scripted_blackout_matches_the_twin_at_both_cadences_and_masks() -> void:
	var cuts: int = 0
	for period: int in [1, 3]:
		for mask: int in [Rig.ONLY, Rig.ALL]:
			var rig: RefCounted = Rig.new().setup(_build.bind(period, 1), mask)
			assert_array(rig.problems).is_empty()
			rig.derive_every = 1
			var orders: Callable = _script.bind(5 + period)
			var label: String = "period %d, mask %d" % [period, mask]
			for _tick: int in TICKS:
				assert_str(rig.step(orders)).override_failure_message(label).is_empty()
			cuts += rig.tally()[&"cuts"]
	assert_int(cuts).is_greater_equal(SCRIPT_CUTS_FLOOR)


func test_seeded_random_blackouts_match_the_twin() -> void:
	var cuts: int = 0
	for salt: int in STATES:
		var period: int = [1, 3, 3, 2][salt % 4]
		var rig: RefCounted = Rig.new().setup(_build.bind(period, 1), Rig.ONLY)
		assert_array(rig.problems).is_empty()
		rig.derive_every = 1
		var orders: Callable = _random_orders.bind(salt)
		var label: String = "state %d, period %d" % [salt, period]
		for _tick: int in TICKS:
			assert_str(rig.step(orders)).override_failure_message(label).is_empty()
		cuts += rig.tally()[&"cuts"]
	assert_int(cuts).is_greater_equal(RANDOM_CUTS_FLOOR)


## With the rule at 0 no row is ever cut, whatever `offline_until` says, in both implementations.
func test_the_rule_at_zero_cuts_nothing_in_either_implementation() -> void:
	var rig: RefCounted = Rig.new().setup(_build.bind(1, 0), Rig.ONLY)
	assert_array(rig.problems).is_empty()
	var orders: Callable = _random_orders.bind(3)
	for _tick: int in 40:
		assert_str(rig.step(orders)).is_empty()
	assert_int(rig.tally()[&"cuts"]).is_equal(0)


func test_the_rig_names_a_cut_that_the_other_side_did_not_make() -> void:
	var rig: RefCounted = Rig.new().setup(_build.bind(1, 1), Rig.ONLY)
	rig.derive_every = 1
	assert_str(rig.run(BLACK_1 + 1, _script.bind(5))).is_empty()
	# The kernel's side wants no cut: one row keeps a cell that the twin took away.
	var row: int = rig.worlds[1].index_of(1)
	rig.worlds[1].offline_until[row] = 0
	rig.worlds[1].fog_cell[row] = 10 * 30 + 10
	assert_str(rig.step(_script.bind(5))).is_not_empty()
