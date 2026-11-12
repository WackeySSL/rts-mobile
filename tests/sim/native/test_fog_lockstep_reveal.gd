extends GdUnitTestSuite
## The FOG kernel against its GDScript twin while a map sweep stands (plan row P233, ADR 0036
## section 11). `Reveal.run` adds a whole-map +1 to `fog.visible` in GDScript while the kernel
## stamps and unstamps discs on the same counts, so the cases run both versions through a sweep
## that starts, is paused by a blackout, resumes, ends with the death of its building, and the last
## player's (3) sweep that stands to the end, over walkers that move and are born, at the cadence
## of 1 and of 3, with FOG alone native and with every phase the library has. After every tick the
## rig compares the state hash and the full state (the fog, the `revealed` flags and the dirty
## lists included), and rebuilds `visible` from the rows and `reveal` (fog_derivation.gd).

const Rig: GDScript = preload("res://tests/sim/support/fog_lockstep_rig.gd")
const Orders: GDScript = preload("res://tests/sim/support/fog_orders.gd")
const Worlds: GDScript = preload("res://tests/sim/support/fog_worlds.gd")
const SIGHTS: Array[int] = [6000, 2000, 4500]
const TICKS: int = 48
## The script: what a SUPERWEAPON of the space centre and a blackout on it write, done by hand.
const SWEEP_1_ON: int = 3
const SWEEP_2_ON: int = 9
const PAUSE_AT: int = 15
const PAUSE_TICKS: int = 11
const SITE_1_DIES: int = 32


func _units() -> Array:
	return [
		[1, 0, Worlds.centre(10), Worlds.centre(10)],
		[1, 1, Worlds.centre(12), Worlds.centre(10)],
		[2, 0, Worlds.centre(20), Worlds.centre(12)],
		[2, 1, Worlds.centre(22), Worlds.centre(4)],
		[3, 2, Worlds.centre(5), Worlds.centre(15)]
	]


## The tick's hand-driven changes (the same on both Worlds) and the walkers of `salt`.
func _orders(world: World, tick: int, salt: int) -> Array[Command]:
	if tick == SWEEP_1_ON:
		world.reveal_site[1] = 1
		world.reveal[1] = 1
	elif tick == SWEEP_2_ON:
		world.reveal_site[3] = 5
		world.reveal[3] = 1
	elif tick == PAUSE_AT:
		world.offline_until[world.index_of(1)] = tick + 1 + PAUSE_TICKS
	elif tick == SITE_1_DIES:
		world.hp[world.index_of(1)] = 0
	return Orders.walkers(world, tick, salt, 0, 6)


func test_a_sweep_that_starts_pauses_resumes_and_ends_matches_the_twin() -> void:
	var seen: Dictionary[int, int] = {}
	for period: int in [1, 3]:
		for mask: int in [Rig.ONLY, Rig.ALL]:
			var members: Dictionary = {&"fog_period_ticks": period}
			var build: Callable = Worlds.field.bind(30, 20, 3, SIGHTS, _units(), members)
			var rig: RefCounted = Rig.new().setup(build, mask)
			assert_array(rig.problems).is_empty()
			rig.derive_every = 1
			var orders: Callable = _orders.bind(7 + period)
			var label: String = "period %d, mask %d" % [period, mask]
			for _tick: int in TICKS:
				var found: String = rig.step(orders)
				assert_str(found).override_failure_message(label).is_empty()
				var twin: World = rig.worlds[0]
				var state: int = twin.reveal[1] + 10 * twin.reveal[3]
				seen[state] = seen.get(state, 0) + 1
				var native: World = rig.worlds[1]
				assert_array(Array(native.fog.revealed)).is_equal(Array(twin.fog.revealed))
	# Reached (player 1's state + 10 * player 3's): none, player 1 on, both on, player 1 paused
	# under player 3's sweep, and player 1's ended with player 3's still on.
	for state: int in [0, 1, 11, 12, 10]:
		assert_int(seen.get(state, 0)).override_failure_message("state %d" % state).is_greater(0)


func test_the_rig_names_a_sweep_that_the_rows_and_reveal_do_not_say() -> void:
	var build: Callable = Worlds.field.bind(30, 20, 3, SIGHTS, _units(), {&"fog_period_ticks": 1})
	var rig: RefCounted = Rig.new().setup(build, Rig.ONLY)
	rig.derive_every = 1
	assert_str(rig.run(SWEEP_1_ON + 3, _orders.bind(7))).is_empty()
	# One side loses the stamp while `reveal` still says on: the comparison names it.
	rig.worlds[1].fog.revealed[0] = 0
	assert_str(rig.step(_orders.bind(7))).is_not_empty()
