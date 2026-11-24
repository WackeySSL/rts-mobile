extends GdUnitTestSuite
## The radar rule (plan row P574, ADR 0047 section 3): `Radar.dark` and `Radar.dark_until` over the
## rows, and the per-player flags `MatchSnapshot.capture` derives from them. The rig is
## `strike_worlds.gd`'s array and headquarters with a radar type of its own (2 x 2, power -30,
## `radar` set): player 1 owns the array (id 1) and a headquarters (id 2); player 2 owns a
## headquarters (id 3), a radar A (id 4, at tile (14, 9), inside the array's radius of `POINT`) and
## a radar B (id 5, at tile (26, 2), out of it). Every expected tick is read from the World's
## tables or from `offline_until`.

const Strikes: GDScript = preload("res://tests/sim/support/strike_worlds.gd")
const TargetingRig: GDScript = preload("res://tests/sim/support/targeting_rig.gd")
const ARRAY: int = 1
const HQ_2: int = 3
const RADAR_A: int = 4
const RADAR_B: int = 5
const STAMP: int = 100


## The rig's world; `radars` is how many of the two radars player 2 owns, and `radar` the flag the
## radar type carries (the frozen arena's copies carry none).
func _world(radars: int = 2, radar: bool = true) -> World:
	var hq: BuildingDef = Strikes._building("hq", 3, 1000)
	hq.produces = World.Tab.STRUCTURES
	var mast: BuildingDef = Strikes._building("mast", 2, 800)
	mast.power = -30
	mast.cost = 500  # A sale needs a price.
	mast.radar = radar
	var units: Array[UnitDef] = [Strikes._array(), hq, mast, Strikes._building("shed", 1, 2000)]
	var world: World = TargetingRig.world_of(units, Strikes.COLS, Strikes.ROWS, true, 2)
	world.fog.explored.fill(1)
	assert_int(world.add_building(1, Strikes.type_of(world, "array"), 10, 2)).is_equal(ARRAY)
	world.add_building(1, Strikes.type_of(world, "hq"), 2, 8)
	world.add_building(2, Strikes.type_of(world, "hq"), 24, 14)
	if radars >= 1:
		world.add_building(2, Strikes.type_of(world, "mast"), 14, 9)
	if radars >= 2:
		world.add_building(2, Strikes.type_of(world, "mast"), 26, 2)
	return world


func _off(world: World, id: int, until: int) -> void:
	world.offline_until[world.index_of(id)] = until


func test_a_radar_is_dark_only_while_it_is_offline_and_no_other_complete_one_is_online() -> void:
	var world: World = _world(1)
	assert_bool(Radar.dark(world, 2, STAMP)).is_false()
	assert_int(Radar.dark_until(world, 2, STAMP)).is_equal(0)
	_off(world, RADAR_A, STAMP + 40)
	assert_bool(Radar.dark(world, 2, STAMP)).is_true()
	assert_int(Radar.dark_until(world, 2, STAMP)).is_equal(STAMP + 40)
	# The last dark stamp is one before `offline_until`; at it the building is online again.
	assert_bool(Radar.dark(world, 2, STAMP + 39)).is_true()
	assert_bool(Radar.dark(world, 2, STAMP + 40)).is_false()
	assert_int(Radar.dark_until(world, 2, STAMP + 40)).is_equal(0)
	# The flag is the player's: player 1 and the neutral player have no radar.
	assert_bool(Radar.dark(world, 1, STAMP)).is_false()
	assert_bool(Radar.dark(world, 0, STAMP)).is_false()


func test_no_radar_building_means_never_dark_and_a_non_radar_offline_building_does_not_count(
) -> void:
	var world: World = _world(0)
	_off(world, HQ_2, STAMP + 40)
	assert_bool(Radar.dark(world, 2, STAMP)).is_false()
	assert_int(Radar.dark_until(world, 2, STAMP)).is_equal(0)
	# An offline building that is no radar beside an online radar changes nothing either.
	var with_radar: World = _world(1)
	_off(with_radar, HQ_2, STAMP + 40)
	assert_bool(Radar.dark(with_radar, 2, STAMP)).is_false()


func test_low_power_does_not_darken_and_a_blackout_during_low_power_does() -> void:
	var world: World = _world(1)
	Power.run(world)
	assert_int(world.power_used[2]).is_greater(world.power_made[2])  # The mast uses 30, no plant.
	assert_bool(Radar.dark(world, 2, STAMP)).is_false()
	_off(world, RADAR_A, STAMP + 40)
	assert_bool(Radar.dark(world, 2, STAMP)).is_true()


func test_a_site_counts_neither_way() -> void:
	# A radar that is a site never darkens the scope, offline or not.
	var site_only: World = _world(1)
	site_only.build_left[site_only.index_of(RADAR_A)] = 5
	_off(site_only, RADAR_A, STAMP + 40)
	assert_bool(Radar.dark(site_only, 2, STAMP)).is_false()
	assert_int(Radar.dark_until(site_only, 2, STAMP)).is_equal(0)
	# An online site does not clear a dark complete radar.
	var world: World = _world(2)
	world.build_left[world.index_of(RADAR_B)] = 5
	_off(world, RADAR_A, STAMP + 40)
	assert_bool(Radar.dark(world, 2, STAMP)).is_true()
	# A site that finishes during the blackout does clear it (the next case's rule).
	world.build_left[world.index_of(RADAR_B)] = 0
	assert_bool(Radar.dark(world, 2, STAMP)).is_false()


func test_a_second_online_radar_keeps_the_scope_on_and_a_second_offline_one_ends_it_last() -> void:
	var world: World = _world(2)
	_off(world, RADAR_A, STAMP + 40)
	assert_bool(Radar.dark(world, 2, STAMP)).is_false()
	assert_int(Radar.dark_until(world, 2, STAMP)).is_equal(0)
	# Both offline: dark until the lowest `offline_until`, then B alone is offline and A is online.
	_off(world, RADAR_B, STAMP + 25)
	assert_bool(Radar.dark(world, 2, STAMP)).is_true()
	assert_int(Radar.dark_until(world, 2, STAMP)).is_equal(STAMP + 25)
	assert_bool(Radar.dark(world, 2, STAMP + 24)).is_true()
	assert_bool(Radar.dark(world, 2, STAMP + 25)).is_false()
	# The order of the rows does not matter: swap the two lengths.
	_off(world, RADAR_A, STAMP + 25)
	_off(world, RADAR_B, STAMP + 40)
	assert_int(Radar.dark_until(world, 2, STAMP)).is_equal(STAMP + 25)


func test_selling_or_losing_the_dark_radar_clears_the_scope() -> void:
	var sold: World = _world(1)
	_off(sold, RADAR_A, STAMP + 40)
	assert_bool(Radar.dark(sold, 2, STAMP)).is_true()
	Strikes.step(sold, [Command.sell(2, RADAR_A)])
	assert_int(sold.index_of(RADAR_A)).is_equal(-1)  # REMOVE takes the sold row in the same tick.
	assert_bool(Radar.dark(sold, 2, sold.tick)).is_false()
	assert_int(Radar.dark_until(sold, 2, sold.tick)).is_equal(0)
	var lost: World = _world(1)
	_off(lost, RADAR_A, STAMP + 40)
	lost.hp[lost.index_of(RADAR_A)] = 0
	lost.remove_dead()
	assert_bool(Radar.dark(lost, 2, STAMP)).is_false()
	assert_int(Radar.dark_until(lost, 2, STAMP)).is_equal(0)
	# Losing the online one instead leaves the dark one: dark.
	var other: World = _world(2)
	_off(other, RADAR_A, STAMP + 40)
	other.hp[other.index_of(RADAR_B)] = 0
	other.remove_dead()
	assert_bool(Radar.dark(other, 2, STAMP)).is_true()


## The frozen arena's radar copies carry no flag, so they are never dark, and the shipped ones do.
func test_the_frozen_arenas_radar_is_never_dark_and_the_shipped_ones_are_radars() -> void:
	for id: String in ["fossil_radar", "renew_radar"]:
		var shipped: BuildingDef = load("res://data/units/%s.tres" % id) as BuildingDef
		var frozen: BuildingDef = load("res://data/dev/arena/units/%s.tres" % id) as BuildingDef
		assert_bool(shipped.radar).is_true()
		assert_bool(frozen.radar).is_false()
	for other: String in ["headquarters", "power_plant", "renew_hq", "fossil_strike"]:
		assert_bool((load("res://data/units/%s.tres" % other) as BuildingDef).radar).is_false()
	var world: World = _world(1, false)
	_off(world, RADAR_A, STAMP + 40)
	assert_array(world.type_radar).is_equal([0, 0, 0, 0])
	assert_bool(Radar.dark(world, 2, STAMP)).is_false()


func test_the_type_table_carries_the_flag() -> void:
	var world: World = _world(1)
	assert_array(world.type_radar).is_equal([0, 0, 1, 0])
	assert_int(world.type_radar.size()).is_equal(world.type_ids.size())
	# Both shipped radars set it in a World built from the shipped data.
	var scenario: ScenarioDef = load("res://data/scenarios/perf_arena.tres") as ScenarioDef
	assert_int(World.from_scenario(scenario).type_radar.size()).is_greater(0)


func _capture(world: World) -> MatchSnapshot:
	var snap: MatchSnapshot = MatchSnapshot.new()
	snap.match_serial = 1
	snap.capture(world, null)
	return snap


## A real Dusk Array: the flag flips on the firing step's snapshot, stays through the blackout and
## clears on the snapshot where `offline_until <= snap.tick`, the one where the glyph ends.
func test_the_snapshot_flag_flips_on_the_firing_step_and_clears_with_the_glyph() -> void:
	var world: World = _world(1)
	Strikes.run_to(world, Strikes.fire_tick(world, ARRAY))
	var before: MatchSnapshot = _capture(world)
	assert_array(before.radar_dark).is_equal([0, 0, 0])
	assert_array(before.radar_dark_until).is_equal([0, 0, 0])
	Strikes.step(world, [Strikes.fire(ARRAY)])
	var until: int = world.offline_until[world.index_of(RADAR_A)]
	assert_int(until).is_equal(
		world.tick + world.type_strike_ticks[Strikes.type_of(world, "array")]
	)
	var fired: MatchSnapshot = _capture(world)
	assert_array(fired.radar_dark).is_equal([0, 0, 1])
	assert_array(fired.radar_dark_until).is_equal([0, 0, until])
	assert_array(fired.type_radar).is_equal(world.type_radar)
	Strikes.run_to(world, until - 1)
	var last: MatchSnapshot = _capture(world)
	assert_int(last.radar_dark[2]).is_equal(1)
	Strikes.step(world)
	var cleared: MatchSnapshot = _capture(world)
	assert_int(cleared.tick).is_equal(until)
	assert_int(cleared.offline_until[cleared.index_of(RADAR_A)]).is_equal(until)
	assert_array(cleared.radar_dark).is_equal([0, 0, 0])
	assert_array(cleared.radar_dark_until).is_equal([0, 0, 0])
	# A published snapshot never changes with the World after it.
	assert_array(fired.radar_dark).is_equal([0, 0, 1])


func test_the_snapshot_flag_stays_off_for_a_second_radar_and_for_the_frozen_radar() -> void:
	var two: World = _world(2)
	Strikes.run_to(two, Strikes.fire_tick(two, ARRAY))
	Strikes.step(two, [Strikes.fire(ARRAY)])
	assert_bool(two.offline_until[two.index_of(RADAR_A)] > two.tick).is_true()
	assert_array(_capture(two).radar_dark).is_equal([0, 0, 0])
	var frozen: World = _world(1, false)
	Strikes.run_to(frozen, Strikes.fire_tick(frozen, ARRAY))
	Strikes.step(frozen, [Strikes.fire(ARRAY)])
	assert_bool(frozen.offline_until[frozen.index_of(RADAR_A)] > frozen.tick).is_true()
	assert_array(_capture(frozen).radar_dark).is_equal([0, 0, 0])


## The two arrays are sized once per capture for the players and written in place, and a later
## capture of the same snapshot object keeps them (no allocation after the first).
func test_a_capture_sizes_the_arrays_once_and_writes_in_place() -> void:
	var world: World = _world(1)
	var snap: MatchSnapshot = _capture(world)
	assert_int(snap.radar_dark.size()).is_equal(world.player_count + 1)
	assert_int(snap.radar_dark_until.size()).is_equal(world.player_count + 1)
	var first: PackedInt32Array = snap.radar_dark
	_off(world, RADAR_A, snap.tick + 10)
	snap.capture(world, null)
	assert_array(snap.radar_dark).is_equal([0, 0, 1])
	assert_array(first).is_equal([0, 0, 1])  # Same buffer: written in place.
