extends GdUnitTestSuite
## The counter triangle (P42b, the judge of ADR 0009 section 1: rifle squads beat rocket squads,
## rocket squads beat light tanks, light tanks beat rifle squads), on the shipped data and an open
## 32 x 16 tile map. Each duel is two groups in a column 1000 apart, 14000 between the columns,
## each attack-moving to the other's start; the fight runs until one side has no unit left and no
## shell is in flight (a shell outlives its shooter and still hits, so a side that looks like the
## winner when the other's last unit dies may lose a unit to a shell already in the air; the
## survivors are read only when the last shell has landed). The duels of the plan:
## - 6 rifle squads against 1 light tank: the tank wins (the rifles do 1 hp a hit to light armour,
##   the tank kills a squad in 5 shells);
## - 2 rocket squads against 1 light tank: a squad wins (6 rockets kill the tank; the tank's last
##   shell still kills the second squad when the tank is dead, so one squad is left);
## - 6 rifle squads against 2 rocket squads: a rifle squad wins.
## Each is run in both orientations (the group named first as player 1, then as player 2, so that
## neither the lower owner nor the lower ids of a side decide it) and each run twice with the same
## final state hash. No balance value of data/ changed in P42b: the shipped numbers pass.
##
## The authoring rule of the fog PR (P46b) holds on every tick: no unit holds a target that still
## has a row and stands beyond its sight (`_beyond_sight`): the data units never acquire farther
## than they see, and nothing here issues an `ATTACK`.

const Rig: GDScript = preload("res://tests/sim/support/targeting_rig.gd")
## The columns of a duel stand this far apart in x (centred on the 32000 wide map).
const GAP: int = 14000
## Between two units of a column, in y.
const SPACING: int = 1000
## A duel that lasts this long has not ended: the longest of the three takes about 790.
const CAP: int = 1500


## 6 rifle squads against 1 light tank: the tank wins, whichever side it stands on, with no squad
## left; the fight lasts more than 600 ticks (the rifles chip the tank down while it kills the
## squads one after the other) and the tank ends with some of its 300 hp.
func test_six_rifle_squads_lose_to_one_light_tank() -> void:
	for swapped: bool in [false, true]:
		var label: String = "tank is player 1" if swapped else "tank is player 2"
		var duel: Dictionary = _twice(Rig.RIFLE, 6, Rig.TANK, 1, swapped)
		assert_array(duel["types"]).override_failure_message(label).is_equal([Rig.TANK])
		assert_int(duel["ticks"]).override_failure_message(label).is_between(600, CAP - 1)
		assert_int(duel["hp"][0]).override_failure_message(label).is_between(1, 300)


## 2 rocket squads against 1 light tank: at least one squad wins and the tank is dead; the fight is
## short (the rockets kill a tank in 6 hits, 3 shots each, while the tank needs 5 shells a squad).
## The tank's 5th shell is still in the air when the rockets kill it and lands after it: it kills
## the squad that was down to 6 hp, so one squad is left and not two (read after the last shell).
func test_two_rocket_squads_beat_one_light_tank() -> void:
	for swapped: bool in [false, true]:
		var label: String = "tank is player 1" if swapped else "tank is player 2"
		var duel: Dictionary = _twice(Rig.ROCKET, 2, Rig.TANK, 1, swapped)
		var survivors: Array = duel["types"]
		assert_bool(not survivors.is_empty()).override_failure_message(label).is_true()
		assert_int(survivors.count(Rig.ROCKET)).override_failure_message(label).is_equal(
			survivors.size()
		)
		assert_int(duel["ticks"]).override_failure_message(label).is_between(50, 400)


## 6 rifle squads against 2 rocket squads: the rockets are dead and a rifle squad is left (the
## rocket does 10 hp to infantry, the rifle 12), whichever side is which.
func test_six_rifle_squads_beat_two_rocket_squads() -> void:
	for swapped: bool in [false, true]:
		var label: String = "rifles are player 2" if swapped else "rifles are player 1"
		var duel: Dictionary = _twice(Rig.RIFLE, 6, Rig.ROCKET, 2, swapped)
		var survivors: Array = duel["types"]
		assert_bool(not survivors.is_empty()).override_failure_message(label).is_true()
		assert_int(survivors.count(Rig.RIFLE)).override_failure_message(label).is_equal(
			survivors.size()
		)
		assert_int(duel["ticks"]).override_failure_message(label).is_between(50, 400)


## The same duel twice gives the same final hash and the same survivors; the duels differ from one
## another (three different hashes), and the two orientations of a duel differ too (the hash holds
## owners and ids).
func test_each_duel_gives_the_same_final_hash_twice_and_the_duels_differ() -> void:
	var hashes: Array[int] = []
	for pair: Array in [
		[Rig.RIFLE, 6, Rig.TANK, 1], [Rig.ROCKET, 2, Rig.TANK, 1], [Rig.RIFLE, 6, Rig.ROCKET, 2]
	]:
		for swapped: bool in [false, true]:
			var first: Dictionary = _duel(pair[0], pair[1], pair[2], pair[3], swapped)
			var second: Dictionary = _duel(pair[0], pair[1], pair[2], pair[3], swapped)
			assert_int(second["hash"]).is_equal(first["hash"])
			assert_array(second["types"]).is_equal(first["types"])
			assert_int(second["ticks"]).is_equal(first["ticks"])
			hashes.append(first["hash"])
	var distinct: Dictionary[int, bool] = {}
	for value: int in hashes:
		distinct[value] = true
	assert_int(distinct.size()).is_equal(hashes.size())


## One duel run twice: the second result must equal the first (hash, survivors, hp, ticks), and
## the fight must have ended before the cap, with no shell left in flight. Returns the first.
func _twice(
	first_type: int, first_count: int, second_type: int, second_count: int, swapped: bool
) -> Dictionary:
	var first: Dictionary = _duel(first_type, first_count, second_type, second_count, swapped)
	var second: Dictionary = _duel(first_type, first_count, second_type, second_count, swapped)
	assert_int(second["hash"]).is_equal(first["hash"])
	assert_array(second["types"]).is_equal(first["types"])
	assert_array(second["hp"]).is_equal(first["hp"])
	assert_int(second["ticks"]).is_equal(first["ticks"])
	assert_int(first["ticks"]).is_less(CAP)
	assert_int(first["in_flight"]).is_equal(0)
	assert_array(first["beyond_sight"]).is_empty()
	return first


## One duel of `first_count` units of `first_type` against `second_count` of `second_type`. The
## first group is player 1 unless `swapped`. It runs until one side has no unit and no shell is in
## flight (`_decided`), or CAP ticks, and returns the ticks it took, the type index and hp of every
## unit left (row order), the state hash after the last tick, the number of shells still in flight
## (0 unless the cap came first) and the ids of the units that ever held a target beyond their
## sight.
@warning_ignore("integer_division")
func _duel(
	first_type: int, first_count: int, second_type: int, second_count: int, swapped: bool
) -> Dictionary:
	var world: World = Rig.data_world(32, 16)
	var left_x: int = 16000 - GAP / 2
	var right_x: int = 16000 + GAP / 2
	var first_owner: int = 2 if swapped else 1
	var first_ids: PackedInt32Array = _column(world, first_owner, first_type, first_count, left_x)
	var second_ids: PackedInt32Array = _column(
		world, 3 - first_owner, second_type, second_count, right_x
	)
	var orders: Array[Command] = [
		Command.attack_move(first_owner, first_ids, right_x, 8000),
		Command.attack_move(3 - first_owner, second_ids, left_x, 8000),
	]
	for order: Command in orders:
		order.tick = world.tick
	var beyond: Array[int] = []
	var ticks: int = 0
	while ticks < CAP:
		Sim.step(world, orders)
		orders.clear()
		ticks += 1
		for id: int in _beyond_sight(world):
			if not beyond.has(id):
				beyond.append(id)
		if _decided(world):
			break
	var types: Array[int] = []
	types.assign(world.type_index)
	var hp: Array[int] = []
	hp.assign(world.hp)
	return {
		"ticks": ticks,
		"types": types,
		"hp": hp,
		"hash": world.state_hash(),
		"in_flight": world.max_projectiles - world.proj_free_top,
		"beyond_sight": beyond,
	}


## True when one side has no unit left and every slot of the projectile pool is free again: a shell
## outlives its shooter, so until the last one has landed the units left are not the survivors.
func _decided(world: World) -> bool:
	var side_gone: bool = world.owner.count(1) == 0 or world.owner.count(2) == 0
	return side_gone and world.proj_free_top == world.max_projectiles


## `count` units of `type_index` of `owner_id` in a column at `x`, 1000 apart in y around 8000, and
## their ids.
@warning_ignore("integer_division")
func _column(world: World, owner_id: int, type_index: int, count: int, x: int) -> PackedInt32Array:
	var ids: PackedInt32Array = PackedInt32Array()
	for row: int in count:
		world.add_unit(owner_id, type_index, x, 8000 + (row - (count - 1) / 2) * SPACING)
		ids.append(world.unit_id[world.unit_count() - 1])
	return ids


## The ids of the units that hold a target that still has a row and stand beyond their sight.
func _beyond_sight(world: World) -> Array[int]:
	var found: Array[int] = []
	for id: int in Rig.outside_sight(world):
		if world.index_of(world.target[world.index_of(id)]) >= 0:
			found.append(id)
	return found
