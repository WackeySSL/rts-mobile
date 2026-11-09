extends GdUnitTestSuite
## Seat probes of the sim (plan row P195, the diagnosis of the top seat's 98% in the first balance
## run): is anything in the sim itself a reason for player 1 to win? The map, the spawns, a duel of
## mirrored groups and a march are symmetric (these cases pass and pin it); the refinery's dock is
## not (the last case pins the measured asymmetry, so a fix that mirrors the dock moves it).

const SmokeRun: GDScript = preload("res://tests/smoke/smoke_run.gd")

const MAP_PATH: String = "res://data/maps/kestrel_flats.tres"
const SIDE: int = 64
const SIDE_MILLI: int = 63999


func test_the_map_is_its_own_half_turn() -> void:
	var map: MapDef = load(MAP_PATH) as MapDef
	assert_int(map.rows.size()).is_equal(SIDE)
	for line: int in SIDE:
		var turned: String = ""
		for column: int in SIDE:
			turned += map.rows[SIDE - 1 - line][SIDE - 1 - column]
		assert_str(map.rows[line]).is_equal(turned)


func test_the_fossil_mirror_spawns_are_half_turns_of_each_other() -> void:
	var world: World = SmokeRun.world_of(1, SmokeRun.FOSSIL_MIRROR)
	var first: Array[Vector2i] = _centres(world, 1)
	var second: Array[Vector2i] = _centres(world, 2)
	assert_int(first.size()).is_equal(second.size())
	var turned: Array[Vector2i] = []
	for centre: Vector2i in first:
		turned.append(Vector2i(SIDE * 1000 - centre.x, SIDE * 1000 - centre.y))
	for centre: Vector2i in turned:
		assert_bool(second.has(centre)).is_true()


## Twelve of one type each, mirrored, attack-moving at each other on open ground: the survivors
## differ by at most 2 whichever player's rows come first. (Measured: rifle 4-4, heavy tank 6-6 and
## 6-5; the rocket squad's duel flips with the row order, 3-6 against 6-3, so it is no case here.)
func test_a_duel_of_mirrored_groups_is_not_decided_by_the_seat() -> void:
	for type_id: String in ["rifle_squad", "heavy_tank"]:
		for second_first: bool in [false, true]:
			var left: Vector2i = _duel(type_id, second_first)
			assert_int(absi(left.x - left.y)).is_less_equal(2)


## One group of eight marches the same way from either corner: the arrival ticks differ by at most
## 6 (measured: rifle 726 and 729, heavy tank 675 and 671).
func test_a_march_takes_as_long_from_either_corner() -> void:
	for type_id: String in ["rifle_squad", "heavy_tank"]:
		var first: int = _march(1, type_id)
		var second: int = _march(2, type_id)
		assert_int(first).is_greater(0)
		assert_int(second).is_greater(0)
		assert_int(absi(first - second)).is_less_equal(6)


## A refinery and its two tankers at mirrored footprints earn the same in 3000 ticks when the dock
## faces the ore on both sides, and not when it does not: the dock is at (1, 3), south of the
## footprint, for both players, so the half turn of a refinery has its dock on the wrong side.
## Measured credits harvested with two tankers each: footprint at (11, 3) and its half turn within
## 5% of each other; at (3, 11) and its half turn 10000 and 7500 (with one tanker each, 8000
## and 4000).
func test_a_refinerys_dock_is_not_mirrored_so_the_same_site_earns_less_for_player_2() -> void:
	var near: Vector2i = _harvest(Vector2i(11, 3))
	assert_int(absi(near.x - near.y)).is_less_equal(near.x / 5)
	var far: Vector2i = _harvest(Vector2i(3, 11))
	assert_int(far.x).is_greater(far.y * 5 / 4)


## The centres of player `player`'s rows at the start, in milli-tiles, sorted.
func _centres(world: World, player: int) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	for row: int in world.unit_count():
		if world.owner[row] == player:
			found.append(Vector2i(world.pos_x[row], world.pos_y[row]))
	found.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y)
	)
	return found


## The survivors (player 1, player 2) after 900 ticks of two mirrored groups of 12 around the map's
## centre. With `second_first` player 2's rows get the lower ids in the odd places.
func _duel(type_id: String, second_first: bool) -> Vector2i:
	var world: World = SmokeRun.world_of(1, SmokeRun.FOSSIL_MIRROR)
	var type: int = PlayerView.of(world, 1).type_index_of(StringName(type_id))
	var ids_1: PackedInt32Array = PackedInt32Array()
	var ids_2: PackedInt32Array = PackedInt32Array()
	for at: int in 12:
		var x: int = 32000 - 4000 - (at % 4) * 1500
		var y: int = 32000 - 4000 - at / 4 * 1500
		if second_first and at % 2 == 1:
			ids_2.append(world.add_unit(2, type, SIDE_MILLI - x, SIDE_MILLI - y))
			ids_1.append(world.add_unit(1, type, x, y))
		else:
			ids_1.append(world.add_unit(1, type, x, y))
			ids_2.append(world.add_unit(2, type, SIDE_MILLI - x, SIDE_MILLI - y))
	var orders: Array[Command] = [
		Command.attack_move(1, ids_1, 60000, 60000), Command.attack_move(2, ids_2, 3000, 3000)
	]
	var loop: MatchLoop = MatchLoop.create(null, "", 1, world)
	for _tick: int in 900:
		loop.step(world, orders)
		orders.clear()
	var left: Vector2i = Vector2i.ZERO
	for row: int in world.unit_count():
		if world.type_index[row] == type:
			left += Vector2i(1 if world.owner[row] == 1 else 0, 1 if world.owner[row] == 2 else 0)
	return left


## The tick at which all eight units of `player` stand within 4 tiles of the far base's corner.
func _march(player: int, type_id: String) -> int:
	var world: World = SmokeRun.world_of(1, SmokeRun.FOSSIL_MIRROR)
	var type: int = PlayerView.of(world, 1).type_index_of(StringName(type_id))
	var ids: PackedInt32Array = PackedInt32Array()
	for at: int in 8:
		var x: int = 14500 + at % 4 * 1200
		var y: int = 14500 + at / 4 * 1200
		ids.append(
			world.add_unit(
				player,
				type,
				x if player == 1 else SIDE_MILLI - x,
				y if player == 1 else SIDE_MILLI - y
			)
		)
	var goal: int = 50500 if player == 1 else SIDE_MILLI - 50500
	var orders: Array[Command] = [Command.move(player, ids, goal, goal)]
	var loop: MatchLoop = MatchLoop.create(null, "", 1, world)
	for tick: int in 3000:
		loop.step(world, orders)
		orders.clear()
		var near: int = 0
		for id: int in ids:
			var row: int = world.index_of(id)
			var dx: int = world.pos_x[row] - goal
			var dy: int = world.pos_y[row] - goal
			near += 1 if dx * dx + dy * dy < 4000 * 4000 else 0
		if near == ids.size():
			return tick
	return -1


## The credits harvested after 3000 ticks by (player 1, player 2) with a finished refinery and its
## free tanker twice: player 1's at `origin`, player 2's on the half turn of that footprint.
func _harvest(origin: Vector2i) -> Vector2i:
	var world: World = SmokeRun.world_of(1, SmokeRun.FOSSIL_MIRROR)
	var type: int = PlayerView.of(world, 1).type_index_of(&"refinery")
	var turned: Vector2i = Vector2i(SIDE - origin.x - 3, SIDE - origin.y - 3)
	var first: int = world.index_of(world.add_building(1, type, origin.x, origin.y))
	var second: int = world.index_of(world.add_building(2, type, turned.x, turned.y))
	for row: int in [first, first, second, second]:
		assert_bool(ProductionSpawn.spawn_free(world, row)).is_true()
	var none: Array[Command] = []
	for _tick: int in 3000:
		Sim.step(world, none)
	return Vector2i(world.stat_harvested[1], world.stat_harvested[2])
