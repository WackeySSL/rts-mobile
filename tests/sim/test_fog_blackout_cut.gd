extends GdUnitTestSuite
## The vision cut of the Dusk Array (plan row P573, ADR 0047 section 2 and 4), in the GDScript twin
## (the kernel's lockstep is native/test_fog_lockstep_blackout.gd). While `blackout_sight_cut` is 1
## a row whose `offline_until` is above the stamp `tick + 1` has no disc: FogUpdate leaves it
## unstamped (`fog_cell` -1) and the disc returns on the owner's first fog turn at or after the step
## the building is back. Units never have an `offline_until`, so they keep their sight. At rule 0
## nothing changes. The exact ticks are literals worked out by hand from the turn rule `(tick -
## player + 1) % period == 0` and the comparison `offline_until > tick + 1`.

const Worlds: GDScript = preload("res://tests/sim/support/fog_worlds.gd")
const Derivation: GDScript = preload("res://tests/sim/support/fog_derivation.gd")
const Strikes: GDScript = preload("res://tests/sim/support/strike_worlds.gd")
const SIGHTS: Array[int] = [3000]
const TILE: int = World.MILLI_PER_TILE


## Player 1's row (id 1) on tile (10, 10) and player 2's (id 2) on tile (20, 10), one type of sight
## 3000, a 30 x 20 map.
func _field(period: int, rule: int = 1) -> World:
	var units: Array = [
		[1, 0, Worlds.centre(10), Worlds.centre(10)], [2, 0, Worlds.centre(20), Worlds.centre(10)]
	]
	return Worlds.field(
		30, 20, 2, SIGHTS, units, {&"fog_period_ticks": period, &"blackout_sight_cut": rule}
	)


## One FOG phase of the tick as Sim.step runs it, then the tick counts.
func _phase(world: World) -> void:
	FogUpdate.begin(world)
	FogUpdate.run(world)
	world.tick += 1


## Blacks the row of `id` out until `until` at tick 0, steps 30 ticks and returns the first tick
## after whose phase the row has no cell, and the first tick after that where it has one again
## (-1 for never).
func _cut_and_back(world: World, id: int, until: int) -> Vector2i:
	var row: int = world.index_of(id)
	world.offline_until[row] = until
	var cut: int = -1
	var back: int = -1
	for _step: int in 30:
		var tick: int = world.tick
		_phase(world)
		if cut < 0 and world.fog_cell[row] == -1:
			cut = tick
		elif cut >= 0 and back < 0 and world.fog_cell[row] >= 0:
			back = tick
	return Vector2i(cut, back)


func test_the_cut_and_the_return_land_on_the_exact_fog_turns() -> void:
	# [period, id, offline_until, first cut tick, first tick back]. Player 1's turns at period 3 are
	# ticks 0, 3, 6, 9, 12, 15 (stamp tick + 1); player 2's are 1, 4, 7, 10, 13, 16.
	var table: Array = [
		[3, 1, 10, 0, 9],  # tick 9 has stamp 10: offline_until == stamp is back (not above).
		[3, 1, 11, 0, 12],  # tick 9: 11 > 10, still cut.
		[3, 1, 13, 0, 12],  # tick 12: stamp 13, 13 > 13 is false, back.
		[3, 1, 14, 0, 15],
		[3, 2, 10, 1, 10],  # tick 7 (stamp 8) cut; tick 10 (stamp 11) back.
		[3, 2, 11, 1, 10],  # tick 10: stamp 11 == 11, back.
		[3, 2, 12, 1, 13],  # tick 10: 12 > 11 cut; tick 13 back.
		[1, 1, 10, 0, 9],
		[1, 2, 10, 0, 9],
		[1, 1, 2, 0, 1],  # at tick 0 stamp 1: 2 > 1 cut; tick 1 stamp 2 back.
	]
	for entry: Array in table:
		var world: World = _field(entry[0])
		var found: Vector2i = _cut_and_back(world, entry[1], entry[2])
		var label: String = "period %d id %d until %d" % [entry[0], entry[1], entry[2]]
		assert_array([found.x, found.y]).override_failure_message(label).is_equal(
			[entry[3], entry[4]]
		)
	# One step short of being above the stamp is never cut: offline_until 1 at tick 0 (stamp 1).
	var never: World = _field(1)
	assert_int(_cut_and_back(never, 1, 1).x).is_equal(-1)


func test_a_cut_row_gives_no_sight_and_the_dirty_list_holds_the_flipped_cells() -> void:
	var world: World = _field(1)
	var fog: FogGrid = world.fog
	var cells: int = fog.cells
	var before: PackedInt32Array = fog.visible.duplicate()
	var disc: int = 0
	for at: int in cells:
		disc += int(before[at] > 0)
	assert_int(disc).is_greater(0)
	world.offline_until[0] = 50
	_phase(world)
	assert_int(world.fog_cell[0]).is_equal(-1)
	var flipped: Array[int] = []
	for at: int in cells:
		assert_int(fog.visible[at]).is_equal(0)  # Player 1's block: its only row is cut.
		if before[at] > 0:
			flipped.append(at)
	var listed: Array[int] = []
	for entry: int in fog.dirty_count[0]:
		listed.append(fog.dirty[entry])
	listed.sort()
	assert_array(listed).is_equal(flipped)
	# Player 2's block is untouched, and `explored` stays.
	for at: int in cells:
		assert_int(fog.visible[cells + at]).is_equal(before[cells + at])
		assert_int(fog.explored[at]).is_equal(1 if before[at] > 0 else 0)
	assert_str(Derivation.mismatch(world)).is_empty()


func test_the_disc_comes_back_when_the_blackout_ends() -> void:
	var world: World = _field(1)
	var before: PackedInt32Array = world.fog.visible.duplicate()
	var until: int = 12
	world.offline_until[0] = until
	for _step: int in until - 1:  # Ticks 0..10 (stamps 1..11): cut.
		_phase(world)
		assert_int(world.fog_cell[0]).is_equal(-1)
	_phase(world)  # Tick 11, stamp 12 == offline_until: back.
	assert_bool(world.fog_cell[0] >= 0).is_true()
	assert_array(Array(world.fog.visible)).is_equal(Array(before))


func test_another_building_or_a_unit_still_covers_the_cells_a_cut_row_shared() -> void:
	var world: World = _field(1)
	var unit: int = world.add_unit(1, 0, Worlds.centre(12), Worlds.centre(10))
	_phase(world)  # Stamps the added unit.
	var shared: int = 11 * 30 + 10 - 30  # Tile (10, 9) lies in both discs.
	assert_int(world.fog.visible[shared]).is_equal(2)
	world.offline_until[0] = 50
	_phase(world)
	assert_int(world.fog.visible[shared]).is_equal(1)
	assert_bool(world.fog_cell[world.index_of(unit)] >= 0).is_true()
	assert_bool(world.fog.dirty.slice(0, world.fog.dirty_count[0]).has(shared)).is_false()
	assert_str(Derivation.mismatch(world)).is_empty()


func test_a_rule_of_zero_changes_nothing() -> void:
	var cut: World = _field(3, 0)
	var plain: World = _field(3, 0)
	cut.offline_until[0] = 1000
	cut.offline_until[1] = 20
	for _step: int in 30:
		_phase(cut)
		_phase(plain)
		assert_array(Array(cut.fog.visible)).is_equal(Array(plain.fog.visible))
		assert_array(Array(cut.fog_cell)).is_equal(Array(plain.fog_cell))
		assert_array(Array(cut.fog.explored)).is_equal(Array(plain.fog.explored))
		assert_array(Array(cut.fog.dirty_count)).is_equal(Array(plain.fog.dirty_count))
	assert_bool(cut.fog_cell[0] >= 0 and cut.fog_cell[1] >= 0).is_true()


func test_a_row_that_dies_while_cut_takes_nothing_away_twice() -> void:
	var world: World = _field(1)
	world.offline_until[0] = 500
	_phase(world)
	var after_cut: PackedInt32Array = world.fog.visible.duplicate()
	world.hp[0] = 0
	var dying_tick_loop: Array[Command] = []
	Sim.step(world, dying_tick_loop)
	assert_int(world.index_of(1)).is_equal(-1)
	assert_array(Array(world.fog.visible)).is_equal(Array(after_cut))
	for count: int in world.fog.visible:
		assert_int(count).is_greater_equal(0)
	assert_str(Derivation.mismatch(world)).is_empty()


func test_prepare_leaves_a_row_that_is_offline_unstamped() -> void:
	for case: Array in [[1, 5, 3, -1], [1, 3, 3, 0], [0, 5, 3, 0], [1, 4, 3, -1]]:
		# [rule, offline_until, tick, expected fog_cell: -1 unstamped, 0 stamped]
		var world: World = World.new()
		world.map_w = 30 * TILE
		world.map_h = 20 * TILE
		world.player_count = 2
		world.type_ids.append(&"sight_0")
		world.type_sight.append(3000)
		world.blackout_sight_cut = case[0]
		world.tick = case[2]
		world.add_unit(1, 0, Worlds.centre(10), Worlds.centre(10))
		world.offline_until[0] = case[1]
		world.prepare()
		var label: String = "rule %d until %d tick %d" % [case[0], case[1], case[2]]
		if case[3] == -1:
			assert_int(world.fog_cell[0]).override_failure_message(label).is_equal(-1)
			assert_int(world.fog.visible[10 * 30 + 10]).override_failure_message(label).is_equal(0)
		else:
			assert_bool(world.fog_cell[0] >= 0).override_failure_message(label).is_true()
		assert_str(Derivation.mismatch(world)).override_failure_message(label).is_empty()


# ---- The strike, the fairness of the view and the units ----


## The rig world with real fog and the rule on, a Dusk Array of player 1 ready to fire, a shed of
## player 2 on the strike's point, and a tank of player 1 two tiles from the shed, which only the
## shed sees of player 2's rows (the shipped HQ stands far away).
func _rig() -> Dictionary:
	var world: World = Strikes.world(false)
	world.blackout_sight_cut = 1
	Strikes.run_to(world, Strikes.fire_tick(world, Strikes.ARRAY))
	var shed: int = world.add_building(2, Strikes.type_of(world, "shed"), 15, 10)
	var tank: int = Strikes.add(world, 1, "tank", 17500, 10500)
	var rifle: int = Strikes.add(world, 2, "rifle", 16500, 12500)
	Strikes.stamp(world)
	return {"world": world, "shed": shed, "tank": tank, "rifle": rifle}


func _turn(world: World, player: int, tick: int) -> bool:
	return (tick - player + 1) % world.fog_period_ticks == 0


func test_a_blacked_out_shed_blinds_its_owner_and_the_sight_returns() -> void:
	var rig: Dictionary = _rig()
	var world: World = rig.world
	var shed_row: int = world.index_of(rig.shed)
	var fire_tick: int = world.tick
	var length: int = world.type_strike_ticks[Strikes.type_of(world, "array")]
	var until: int = fire_tick + 1 + length
	# Remove the shed's neighbours from the picture: player 2's rifle is the only other sight, so
	# stand it somewhere far to keep the tank seen by the shed alone.
	var rifle_row: int = world.index_of(rig.rifle)
	world.pos_x[rifle_row] = 2500
	world.pos_y[rifle_row] = 17500
	for _step: int in 6:
		Strikes.step(world)  # Let player 2's fog turn move the rifle's disc.
	fire_tick = world.tick
	until = fire_tick + 1 + length
	assert_bool(Targeting.sees(world, 2, 17500, 10500)).is_true()
	var cut_tick: int = fire_tick
	while not _turn(world, 2, cut_tick):
		cut_tick += 1
	var back_tick: int = until - 1
	while not _turn(world, 2, back_tick):
		back_tick += 1
	var fired: bool = false
	while world.tick <= back_tick:
		var tick: int = world.tick
		var commands: Array = [] if fired else [Strikes.fire(Strikes.ARRAY)]
		fired = true
		Strikes.step(world, commands)
		var cut: bool = world.fog_cell[shed_row] == -1
		assert_bool(cut).override_failure_message("tick %d" % tick).is_equal(
			tick >= cut_tick and tick < back_tick
		)
		(
			assert_bool(Targeting.sees(world, 2, 17500, 10500))
			. override_failure_message("tick %d" % tick)
			. is_equal(not cut)
		)
		assert_str(Derivation.mismatch(world)).override_failure_message("tick %d" % tick).is_empty()
	assert_int(world.offline_until[shed_row]).is_equal(until)


## ADR 0047 section 4: the fog a victim loses is the fog every reader of it loses, so the view of
## player 2 (what its AI reads) says exactly what its fog block says, with the cut and without it.
func test_the_victims_view_equals_its_fog_block_with_and_without_the_cut() -> void:
	for rule: int in [1, 0]:
		var rig: Dictionary = _rig()
		var world: World = rig.world
		world.blackout_sight_cut = rule
		var rifle_row: int = world.index_of(rig.rifle)
		world.pos_x[rifle_row] = 2500
		world.pos_y[rifle_row] = 17500
		Strikes.step(world, [Strikes.fire(Strikes.ARRAY)])
		for _step: int in 6:
			Strikes.step(world)
		var view: PlayerView = PlayerView.of(world, 2)
		var tank_seen: bool = view.row_of(rig.tank) != PlayerView.MISSING
		assert_bool(tank_seen).override_failure_message("rule %d" % rule).is_equal(rule == 0)
		for row: int in world.unit_count():
			var seen: bool = view.row_of(world.unit_id[row]) != PlayerView.MISSING
			var want: bool = (
				world.owner[row] == 2
				or Targeting.sees(world, 2, world.pos_x[row], world.pos_y[row])
			)
			assert_bool(seen).override_failure_message("rule %d row %d" % [rule, row]).is_equal(
				want
			)


func test_units_keep_their_sight_and_no_unit_row_gets_an_offline_until() -> void:
	var rig: Dictionary = _rig()
	var world: World = rig.world
	var rifle_row: int = world.index_of(rig.rifle)  # Player 2's unit, inside the ring.
	Strikes.step(world, [Strikes.fire(Strikes.ARRAY)])
	for _step: int in 12:
		Strikes.step(world)
	Buildings.rebuild_lists(world)
	var buildings: Dictionary[int, bool] = {}
	for row: int in world.building_rows:
		buildings[row] = true
	var cut_buildings: int = 0
	for row: int in world.unit_count():
		if buildings.has(row):
			cut_buildings += int(world.offline_until[row] > 0)
		else:
			assert_int(world.offline_until[row]).override_failure_message("row %d" % row).is_equal(
				0
			)
	assert_int(cut_buildings).is_greater(0)
	assert_bool(world.fog_cell[rifle_row] >= 0).is_true()
	assert_bool(world.fog_cell[world.index_of(rig.shed)] == -1).is_true()
	assert_bool(Targeting.sees(world, 2, 16500, 12500)).is_true()  # The rifle's own sight.


# ---- LastSeen and the sweep ----


## The ids of the buildings player `player` remembers.
func _remembered(world: World, player: int) -> Array[int]:
	var found: Array[int] = []
	var first: int = player * world.ghost_cap
	for record: int in world.ghost_count[player]:
		found.append(world.ghost_id[first + record])
	return found


## Player 2's shed on the strike's point sees player 1's building A (id of `plant`, 3 tiles off);
## the array fires at the 7th tick and `later` is a building that player 1 raises in the shed's disc
## after the cut. Returns [world, plant id, later id]; the World has stepped 14 ticks past the fire.
func _memory_match(rule: int) -> Array:
	var world: World = Strikes.world(false)
	world.blackout_sight_cut = rule
	world.add_building(2, Strikes.type_of(world, "shed"), 15, 10)
	var plant: int = world.add_building(1, Strikes.type_of(world, "plant"), 17, 9)
	Strikes.stamp(world)
	Strikes.run_to(world, Strikes.fire_tick(world, Strikes.ARRAY))
	assert_array(_remembered(world, 2)).is_equal([plant])  # Seen before the strike.
	Strikes.step(world, [Strikes.fire(Strikes.ARRAY)])
	for _step: int in 6:
		Strikes.step(world)
	var later: int = world.add_building(1, Strikes.type_of(world, "shed"), 16, 12)
	Strikes.stamp(world)
	for _step: int in 7:
		Strikes.step(world)
	return [world, plant, later]


func test_last_seen_keeps_its_record_and_makes_none_where_nothing_sees() -> void:
	var cut: Array = _memory_match(1)
	var world: World = cut[0]
	var shed_row: int = world.index_of(6)
	assert_int(world.fog_cell[shed_row]).is_equal(-1)  # The shed is cut.
	# The record of the building seen before the cut stays, and the one raised in the dark has none.
	assert_array(_remembered(world, 2)).is_equal([cut[1]])
	assert_bool(Targeting.sees(world, 2, 16500, 12500)).is_false()
	# Without the cut the shed still sees the new building and remembers it.
	var open: Array = _memory_match(0)
	assert_array(_remembered(open[0], 2)).is_equal([open[1], open[2]])


func test_a_sweep_that_is_on_still_shows_the_whole_map_during_a_cut() -> void:
	var world: World = Strikes.world(false)
	world.blackout_sight_cut = 1
	var shed: int = world.add_building(2, Strikes.type_of(world, "shed"), 15, 10)
	Strikes.stamp(world)
	# Player 2's headquarters (id 5, outside the ring) stands in for its space centre.
	world.reveal_site[2] = Strikes.HQ_2
	world.reveal[2] = Reveal.State.ON
	Strikes.run_to(world, Strikes.fire_tick(world, Strikes.ARRAY))
	Strikes.step(world, [Strikes.fire(Strikes.ARRAY)])
	for _step: int in 8:
		Strikes.step(world)
	assert_int(world.fog_cell[world.index_of(shed)]).is_equal(-1)
	assert_int(world.reveal[2]).is_equal(Reveal.State.ON)
	var fog: FogGrid = world.fog
	for at: int in fog.cells:
		assert_int(fog.visible[fog.cells + at]).override_failure_message("cell %d" % at).is_greater(
			0
		)
	assert_bool(Targeting.sees(world, 2, 28500, 1500)).is_true()
	assert_str(Derivation.mismatch(world)).is_empty()
