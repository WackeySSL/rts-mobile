extends GdUnitTestSuite
## Seat symmetry of the AI's placement (plan row P195b with P195c-1 and P195c-3, ADR 0033 section 6;
## the P195 probes pinned the opposite). On Kestrel Flats' fossil mirror the two opponents' slots
## and refinery sites are exact half turns of each other, under the real start fog, because the
## spiral turns away from the enemy (P195b) and placement no longer reads the explored tiles
## (P195c-3). Docks and exits face the map centre (P195c-1), so the refineries earn alike.

const Rig: GDScript = preload("res://tests/ai/support/opponent_rig.gd")
const AiRig: GDScript = preload("res://tests/ai/support/ai_rig.gd")
const SmokeRun: GDScript = preload("res://tests/smoke/smoke_run.gd")
const EconomyOnly: GDScript = preload("res://tests/ai/support/economy_only.gd")

const SIDE: int = 64
const MATCH_TICKS: int = 3000


## Real think by real think, each Normal opponent's first plant (300 ticks, the full controllers,
## the real fog): player 2's is the half turn of player 1's. The probe's answer was (7, 3) and
## (54, 50), a mirror of nothing.
func test_the_first_plant_of_each_opponent_is_the_half_turn_of_the_others() -> void:
	var levels: Array[String] = ["normal", "normal"]
	var match_setup: Dictionary = SmokeRun.start(1, "fossil-mirror", levels)
	var world: World = match_setup["world"]
	SmokeRun.run(world, match_setup["loop"], match_setup["controllers"], 300)
	var plant: int = AiRig.type_of(world, "power_plant")
	var sites: Dictionary[int, Vector2i] = {}
	for row: int in world.unit_count():
		if world.type_index[row] == plant:
			sites[world.owner[row]] = world.footprint_origin(row)
	assert_bool(sites.has(1) and sites.has(2)).is_true()
	assert_object(sites[2]).is_equal(_turned(sites[1], world.type_foot_w[plant]))


## The refinery of each side: a half turn of the other's, the same squared distance (in half tiles)
## from the footprint's centre to the nearest ore cell (the probe: 26 against 49 tiles squared for
## the first spiral slot), and equal to what the other would have there.
func test_the_refineries_are_half_turns_and_equally_near_the_ore() -> void:
	var world: World = _economy_match(1500)
	var refinery: int = AiRig.type_of(world, "refinery")
	var wide: int = world.type_foot_w[refinery]
	var first: Array[Vector2i] = _sites(world, 1, refinery)
	var second: Array[Vector2i] = _sites(world, 2, refinery)
	assert_int(first.size()).is_greater(0)
	assert_int(second.size()).is_greater(0)
	assert_object(second[0]).is_equal(_turned(first[0], wide))
	assert_int(_ore_gap(world, first[0], wide)).is_equal(_ore_gap(world, second[0], wide))


## ADR 0033 section 6, the combined rows: a no-combat fossil-mirror match (both Normal, seed 1, the
## economy alone, 3000 ticks, the real fog) where every building of player 2 stands on the half turn
## of one of player 1's of the same type.
func test_every_building_of_player_2_is_the_half_turn_of_one_of_player_1s_in_3000_ticks() -> void:
	var world: World = _economy_match(MATCH_TICKS)
	var turned: Dictionary[Vector3i, bool] = {}
	var first: int = 0
	var second: int = 0
	for row: int in world.unit_count():
		var type: int = world.type_index[row]
		if world.type_foot_w[type] <= 0 or world.owner[row] != 1:
			continue
		first += 1
		var site: Vector2i = _turned(world.footprint_origin(row), world.type_foot_w[type])
		turned[Vector3i(site.x, site.y, type)] = true
	for row: int in world.unit_count():
		var type: int = world.type_index[row]
		if world.type_foot_w[type] <= 0 or world.owner[row] != 2:
			continue
		second += 1
		var at: Vector2i = world.footprint_origin(row)
		(
			assert_bool(turned.has(Vector3i(at.x, at.y, type)))
			. override_failure_message("%s at %s" % [world.type_ids[type], at])
			. is_true()
		)
	assert_int(first).is_greater(6)
	assert_int(second).is_greater(5)


# --- Helpers ---------------------------------------------------------------------------------


## The fossil mirror, both Normal opponents on the economy alone (no army, no production), played
## for `ticks` ticks; the World.
func _economy_match(ticks: int) -> World:
	var levels: Array[String] = ["normal", "normal"]
	var match_setup: Dictionary = SmokeRun.start(1, "fossil-mirror", levels)
	var world: World = match_setup["world"]
	var controllers: Array[AiController] = []
	for real: AiController in match_setup["controllers"]:
		var alone: Variant = EconomyOnly.new()
		alone.copy_from(real)
		controllers.append(alone)
	SmokeRun.run(world, match_setup["loop"], controllers, ticks)
	return world


## The half turn of the footprint at `site` (`wide` x `wide`) on the 64 x 64 map.
func _turned(site: Vector2i, wide: int) -> Vector2i:
	return Vector2i(SIDE - site.x - wide, SIDE - site.y - wide)


## The footprint origins of `player`'s buildings of `type`, in row order.
func _sites(world: World, player: int, type: int) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	for row: int in world.unit_count():
		if world.owner[row] == player and world.type_index[row] == type:
			found.append(world.footprint_origin(row))
	return found


## The squared distance, in half tiles, from the footprint's centre to the nearest ore cell's.
func _ore_gap(world: World, site: Vector2i, wide: int) -> int:
	var best: int = 1 << 40
	for cell: int in world.ore_cell:
		var dx: int = site.x * 2 + wide - (cell % world.map_cols * 2 + 1)
		var dy: int = site.y * 2 + wide - (cell / world.map_cols * 2 + 1)
		best = mini(best, dx * dx + dy * dy)
	return best
