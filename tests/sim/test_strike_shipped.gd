extends GdUnitTestSuite
## The strikes on the shipped data (plan row P110d, ADR 0023 section 10): a match of the two shipped
## factions (data/factions, their units and the strike files of P110d), not the rig of the P110 and
## P111 suites (`strike_worlds.gd` data, `blackout_worlds.gd` data). A Deep Bore placed at tick 0
## charges for its `charge_ticks` and is accepted on the first tick that reaches them and not a tick
## before; its rupture lands on exactly `strike_tick` and takes the weapon's damage times the armour
## percent from every row within the radius, own rows included, and from none outside; a Blackout
## Array takes the enemy buildings within its radius offline for exactly `strike_ticks`, which the
## power totals show; and `Strike.rupture_type` finds the Deep Bore when both rosters are loaded.
## Every expected tick, radius and damage is read from the World's tables (the numbers themselves
## are test_defs_strike_data's), so a retune of the data moves no case. The rules of the rig (each
## invalid command, the fog, the defeat of a landing step, a blacked-out defence and producer) stay
## the P110 and P111 suites'.
##
## The world is 40 x 30 open tiles with the shipped rules. Player 1 plays the Derrick League and
## owns its Headquarters (`HQ_1`, id 1) and Deep Bore (`BORE`, 2) at the north-west corner; player 2
## plays the Lumen Accord and owns its Grid Hub (`HQ_2`, 3) and Blackout Array (`ARRAY`, 4) at the
## south-east corner. The types of both rosters are registered, the spawned ones first. The
## weapons are taken from every type (`type_weapon` -1), so that no shot lands while a strike is in
## the air: only the strike changes a hit point or a flag. The cases step from tick 0 to the tick of
## the first possible firing: a few thousand steps of a near-empty World.
## `POINT` is the tile centre (20, 15) in the middle of the map.

const Strikes: GDScript = preload("res://tests/sim/support/strike_worlds.gd")
const RULES_PATH: String = "res://data/rules.tres"
const UNITS_DIR: String = "res://data/units/"
const FACTIONS: Array[String] = [
	"res://data/factions/fossil.tres", "res://data/factions/renew.tres"
]
const COLS: int = 40
const ROWS: int = 30
const HQ_1: int = 1
const BORE: int = 2
const HQ_2: int = 3
const ARRAY: int = 4
const POINT: Vector2i = Vector2i(20500, 15500)
const MILLI: int = World.MILLI_PER_TILE


## The Deep Bore charges from its placement (tick 0, so the first stamp is 1) and a SUPERWEAPON on
## the stamp one short of `ready_tick` is dropped and counted, with the building and the player left
## as they were; on the next tick it is accepted. The Headquarters makes less than the bore uses, so
## player 1 is on low power throughout and the charge does not wait for it (ADR 0023 section 10).
## The Blackout Array of the other roster charges the same way, by its own charge.
func test_a_placed_deep_bore_charges_for_its_charge_ticks_and_fires_on_the_first_tick_it_may(
) -> void:
	var world: World = _world()
	var bore: int = Strikes.type_of(world, "fossil_strike")
	var array: int = Strikes.type_of(world, "renew_strike")
	var charge: int = world.type_charge_ticks[bore]
	assert_int(charge).is_greater(0)
	assert_int(world.ready_tick[world.index_of(BORE)]).is_equal(1 + charge)
	assert_int(world.ready_tick[world.index_of(ARRAY)]).is_equal(1 + world.type_charge_ticks[array])
	assert_int(world.ready_tick[world.index_of(HQ_1)]).is_equal(0)
	assert_int(world.ready_tick[world.index_of(HQ_2)]).is_equal(0)
	var headquarters: int = Strikes.type_of(world, "headquarters")
	assert_int(world.type_power[headquarters] + world.type_power[bore]).is_less(0)
	var first: int = Strikes.fire_tick(world, BORE)
	assert_int(first).is_equal(charge)
	Strikes.run_to(world, first - 1)
	assert_bool(Power.is_low(world, 1)).is_true()
	assert_int(world.ready_tick[world.index_of(BORE)]).is_equal(1 + charge)
	Strikes.step(world, [Strikes.fire(BORE, 1, POINT)])  # The stamp is one short of ready_tick.
	assert_int(world.dropped_commands).is_equal(1)
	assert_int(world.strike_tick[1]).is_equal(0)
	assert_int(world.ready_tick[world.index_of(BORE)]).is_equal(1 + charge)
	Strikes.step(world, [Strikes.fire(BORE, 1, POINT)])  # The stamp reaches it.
	assert_int(world.dropped_commands).is_equal(1)
	assert_int(world.strike_tick[1]).is_equal(first + 1 + world.type_strike_delay[bore])
	assert_int(world.ready_tick[world.index_of(BORE)]).is_equal(first + 1 + charge)
	assert_bool(Power.is_low(world, 1)).is_true()


## The rupture lands on exactly `strike_tick` (the stamp of the firing step plus the delay), after a
## warning in which nothing changes. A row within the radius by squared distance (one on the radius
## included, one a milli beyond it not) loses the weapon's damage times its armour percent, whoever
## owns it; a row that cannot take that is gone at that tick's REMOVE; the rest are as they were,
## and nobody is defeated. The rows are every armour class: units of both factions and buildings of
## both. The expected loss is the weapon table's, class by class.
func test_the_rupture_takes_the_weapons_damage_from_every_row_within_its_radius_at_strike_tick(
) -> void:
	var world: World = _world()
	var bore: int = Strikes.type_of(world, "fossil_strike")
	var radius: int = world.type_strike_radius[bore]
	var ids: Array[int] = _populate_rupture(world, radius)
	Strikes.run_to(world, Strikes.fire_tick(world, BORE))
	var rows: Array[Dictionary] = _rows_of(world, ids)
	var count: int = world.unit_count()
	Strikes.step(world, [Strikes.fire(BORE, 1, POINT)])
	var landing: int = world.strike_tick[1]
	assert_int(landing).is_equal(world.tick + world.type_strike_delay[bore])
	assert_array([world.strike_x[1], world.strike_y[1]]).is_equal([POINT.x, POINT.y])
	while world.tick < landing - 1:
		Strikes.step(world)
		assert_array(_hp_of(world, ids)).is_equal(_hp_in(rows))
		assert_int(world.strike_tick[1]).is_equal(landing)
	assert_int(world.dropped_commands).is_equal(0)
	Strikes.step(world)  # The landing: its stamp is strike_tick.
	assert_int(world.tick).is_equal(landing)
	assert_int(world.strike_tick[1]).is_equal(0)
	var killed: int = 0
	var hurt: int = 0
	var spared: int = 0
	var owners: Array[int] = []
	for at: int in ids.size():
		var was: Dictionary = rows[at]
		var inside: bool = _distance_squared(was["at"], POINT) <= radius * radius
		var lost: int = _loss(world, was["type"]) if inside else 0
		var row: int = world.index_of(ids[at])
		var label: String = "%s of player %d" % [world.type_ids[was["type"]], was["owner"]]
		if inside and was["hp"] <= lost:
			assert_int(row).override_failure_message(label).is_equal(-1)
			killed += 1
		else:
			assert_int(world.hp[row]).override_failure_message(label).is_equal(was["hp"] - lost)
			assert_int(world.pos_x[row]).override_failure_message(label).is_equal(was["at"].x)
			hurt += 1 if inside else 0
			spared += 0 if inside else 1
		if inside and not owners.has(was["owner"]):
			owners.append(was["owner"])
	assert_int(killed).is_greater(0)
	assert_int(hurt).is_greater(0)
	assert_int(spared).is_greater(1)
	assert_array(owners).contains_exactly_in_any_order([1, 2])
	assert_int(world.unit_count()).is_equal(count - killed)
	for id: int in [HQ_1, BORE, HQ_2, ARRAY]:
		var type: int = world.type_index[world.index_of(id)]
		assert_int(Strikes.hp_of(world, id)).is_equal(world.type_max_hp[type])
	assert_array(world.defeated_tick).is_equal([0, 0, 0])
	assert_int(world.match_end_tick).is_equal(0)


## The same match twice gives one state hash (the replay-grade check on the shipped data), and the
## rupture is in it: the match with no SUPERWEAPON ends in another.
func test_the_shipped_rupture_scenario_runs_twice_to_one_state_hash() -> void:
	var first: World = _ruptured(true)
	var second: World = _ruptured(true)
	assert_int(first.state_hash()).is_equal(second.state_hash())
	assert_int(first.state_hash()).is_not_equal(_ruptured(false).state_hash())


## The blackout takes the buildings of the other player within the radius (the one on the radius
## included) offline until the firing stamp plus `strike_ticks`, and no other: not the firing
## player's own building in the radius, not the buildings outside it, not the Deep Bore and its
## Headquarters far away. The power totals of the blacked-out player fall in the firing step, stay
## down for exactly `strike_ticks` steps and are whole again on the stamp that reaches
## `offline_until`; the firing player's totals never move. The totals are sums of the types' power.
func test_the_blackout_takes_enemy_buildings_in_its_radius_offline_for_exactly_its_length() -> void:
	var world: World = _world()
	var array: int = Strikes.type_of(world, "renew_strike")
	var radius: int = world.type_strike_radius[array]
	var length: int = world.type_strike_ticks[array]
	assert_int(length).is_greater(0)
	var ids: Array[int] = _populate_blackout(world, radius)
	Strikes.run_to(world, Strikes.fire_tick(world, ARRAY))
	var whole: Array[int] = _totals(world, 1)
	var own: Array[int] = _totals(world, 2)
	assert_array(whole).is_equal(_power_of(world, 1, []))
	Strikes.step(world, [Strikes.fire(ARRAY, 2, POINT)])
	assert_int(world.dropped_commands).is_equal(0)
	var until: int = world.tick + length  # The firing stamp is the tick the step left behind.
	var hit: Array[int] = []
	for id: int in ids:
		var row: int = world.index_of(id)
		var centre: Vector2i = Vector2i(world.pos_x[row], world.pos_y[row])
		var inside: bool = _distance_squared(centre, POINT) <= radius * radius
		var wanted: int = until if inside and world.owner[row] == 1 else 0
		assert_int(world.offline_until[row]).override_failure_message(str(id)).is_equal(wanted)
		if wanted > 0:
			hit.append(id)
	assert_int(hit.size()).is_greater(2)
	for id: int in [HQ_1, BORE, HQ_2, ARRAY]:
		assert_int(world.offline_until[world.index_of(id)]).is_equal(0)
	var down: Array[int] = _power_of(world, 1, hit)
	assert_array(down).is_not_equal(whole)
	assert_array(_totals(world, 1)).is_equal(down)
	for _step: int in length - 1:
		Strikes.step(world)
		assert_array(_totals(world, 1)).is_equal(down)
		assert_array(_totals(world, 2)).is_equal(own)
	assert_int(world.tick + 1).is_equal(until)
	Strikes.step(world)  # The stamp reaches offline_until: back.
	assert_array(_totals(world, 1)).is_equal(whole)
	assert_array(_totals(world, 2)).is_equal(own)


## `Strike.rupture_type` is the first type of kind RUPTURE. With both rosters loaded, that is the
## Deep Bore whichever player plays which faction: with the Derrick League first its type index is
## the lower one, and with the Lumen Accord first (its spawns come first, so its Blackout Array is
## the first strike type of the World) the Blackout Array has the lower index and the rupture type
## is still the Deep Bore. The Blackout Array is of kind BLACKOUT and the only other strike type.
## The landing reads the radius and the weapon from it, and the weapon is the shipped file's.
func test_the_rupture_type_is_the_deep_bore_when_both_rosters_are_loaded_in_either_order() -> void:
	var reversed: Array[String] = [FACTIONS[1], FACTIONS[0]]
	for flipped: bool in [false, true]:
		var paths: Array[String] = reversed if flipped else FACTIONS
		var world: World = _world(paths)
		var bore: int = Strikes.type_of(world, "fossil_strike")
		var array: int = Strikes.type_of(world, "renew_strike")
		assert_int(bore).is_greater_equal(0)
		assert_int(array).is_greater_equal(0)
		# The order really is the one the case names, so that the Blackout Array comes first in the
		# second pass and the lowest strike type is not the Deep Bore.
		if flipped:
			assert_int(array).override_failure_message(str(paths)).is_less(bore)
		else:
			assert_int(bore).override_failure_message(str(paths)).is_less(array)
		assert_int(Strike.rupture_type(world)).override_failure_message(str(paths)).is_equal(bore)
		assert_int(world.type_strike_kind.count(Strike.Kind.RUPTURE)).is_equal(1)
		assert_int(world.type_strike_kind.count(Strike.Kind.BLACKOUT)).is_equal(1)
		assert_int(world.type_strike_kind[bore]).is_equal(Strike.Kind.RUPTURE)
		assert_int(world.type_strike_kind[array]).is_equal(Strike.Kind.BLACKOUT)
		var weapon: int = world.type_strike_weapon[bore]
		assert_str(String(world.weapon_ids[weapon])).is_equal("fossil_rupture")
		assert_int(world.weapon_damage[weapon]).is_greater(0)
		assert_int(world.type_strike_weapon[array]).is_equal(-1)


## A World of the shipped rosters of `paths` (the factions of players 1 and 2, in that order) with
## each player's Headquarters and strike building, and no weapon fired by anyone. The spawns follow
## the players, so the types of the first player's faction are registered first (the rosters come
## last, ADR 0023 section 6): `paths` reversed puts the Blackout Array before the Deep Bore.
func _world(paths: Array[String] = FACTIONS) -> World:
	var scenario: ScenarioDef = ScenarioDef.new()
	scenario.map_size_tiles = Vector2i(COLS, ROWS)
	scenario.rules = load(RULES_PATH)
	scenario.player_count = 2
	scenario.factions.append(null)
	for path: String in paths:
		scenario.factions.append(load(path))
	# The Headquarters and the strike building of each of FACTIONS, with their tiles.
	var homes: Array[Array] = [
		["headquarters", Vector2i(2, 2), "fossil_strike", Vector2i(8, 2)],
		["renew_hq", Vector2i(34, 24), "renew_strike", Vector2i(30, 24)],
	]
	for index: int in paths.size():
		var home: Array = homes[FACTIONS.find(paths[index])]
		scenario.spawns.append(_spawn(index + 1, home[0], home[1]))
		scenario.spawns.append(_spawn(index + 1, home[2], home[3]))
	var world: World = World.from_scenario(scenario)
	world.type_weapon.fill(-1)
	return world


func _spawn(player: int, id: String, tile: Vector2i) -> SpawnDef:
	var spawn: SpawnDef = SpawnDef.new()
	spawn.owner = player
	spawn.unit = load(UNITS_DIR + id + ".tres")
	spawn.count = 1
	spawn.origin_tile = tile
	return spawn


## Places the rows of the rupture case around POINT and returns their ids in order: units of both
## players of each armour class (infantry, light, heavy; one of each on the radius and one a milli
## beyond it) and two 2x2 buildings inside the radius (one of each player) and one outside.
## Distances are one tile or more apart, so that no unit pushes another and nothing moves.
func _populate_rupture(world: World, radius: int) -> Array[int]:
	var units: Array[Array] = [
		[2, "renew_rifle", Vector2i(-1000, 0)],
		[1, "light_tank", Vector2i(0, -1400)],
		[2, "renew_scout", Vector2i(radius, 0)],
		[2, "renew_tank", Vector2i(0, 1500)],
		[1, "heavy_tank", Vector2i(-2000, 1000)],
		[2, "renew_tanker", Vector2i(1500, 1500)],
		[2, "renew_rifle", Vector2i(-(radius + 1), 0)],
		[1, "light_tank", Vector2i(0, radius + 1)],
	]
	var ids: Array[int] = []
	for row: Array in units:
		var at: Vector2i = POINT + (row[2] as Vector2i)
		ids.append(Strikes.add(world, row[0], row[1], at.x, at.y))
	ids.append(_build(world, 2, "renew_power", Vector2i(22, 13)))
	ids.append(_build(world, 1, "power_plant", Vector2i(17, 13)))
	ids.append(_build(world, 2, "renew_power", Vector2i(20, 20)))
	return ids


## Places the buildings of the blackout case around POINT and returns their ids: player 1's plant,
## refinery and two defences inside the radius (one on it), its barracks and a defence outside it,
## and player 2's own plant inside it. All are 1x1 to 3x3 footprints that do not overlap.
func _populate_blackout(world: World, radius: int) -> Array[int]:
	var edge: Vector2i = Vector2i((POINT.x + radius - MILLI / 2) / MILLI, 15)
	var ids: Array[int] = []
	ids.append(_build(world, 1, "power_plant", Vector2i(19, 14)))
	ids.append(_build(world, 1, "refinery", Vector2i(21, 11)))
	ids.append(_build(world, 1, "defence_turret", Vector2i(20, 18)))
	ids.append(_build(world, 1, "defence_turret", edge))
	ids.append(_build(world, 1, "barracks", Vector2i(20, 21)))
	ids.append(_build(world, 1, "defence_turret", edge + Vector2i(1, 0)))
	ids.append(_build(world, 2, "renew_power", Vector2i(18, 16)))
	return ids


func _build(world: World, player: int, id: String, tile: Vector2i) -> int:
	var made: int = world.add_building(player, Strikes.type_of(world, id), tile.x, tile.y)
	assert_int(made).override_failure_message(id).is_greater(0)
	return made


## One record per id: its owner, type, position and hit points now.
func _rows_of(world: World, ids: Array[int]) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for id: int in ids:
		var row: int = world.index_of(id)
		(
			found
			. append(
				{
					"owner": world.owner[row],
					"type": world.type_index[row],
					"at": Vector2i(world.pos_x[row], world.pos_y[row]),
					"hp": world.hp[row],
				}
			)
		)
	return found


func _hp_of(world: World, ids: Array[int]) -> Array[int]:
	var found: Array[int] = []
	for id: int in ids:
		found.append(Strikes.hp_of(world, id))
	return found


func _hp_in(rows: Array[Dictionary]) -> Array[int]:
	var found: Array[int] = []
	for row: Dictionary in rows:
		found.append(row["hp"])
	return found


@warning_ignore("integer_division")
func _loss(world: World, type: int) -> int:
	var weapon: int = world.type_strike_weapon[Strikes.type_of(world, "fossil_strike")]
	var percent: int = world.weapon_vs_armour[
		weapon * World.Armour.size() + world.type_armour[type]
	]
	return 0 if percent == 0 else maxi(1, world.weapon_damage[weapon] * percent / 100)


func _distance_squared(a: Vector2i, b: Vector2i) -> int:
	return (a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)


## The totals of `player` as the last ECONOMY built them: [made, used].
func _totals(world: World, player: int) -> Array[int]:
	return [world.power_made[player], world.power_used[player]]


## What the power of `player`'s buildings sums to in the types' table, [made, used], leaving out the
## rows whose ids are in `left_out`.
func _power_of(world: World, player: int, left_out: Array[int]) -> Array[int]:
	var made: int = 0
	var used: int = 0
	for row: int in world.unit_count():
		var type: int = world.type_index[row]
		if world.owner[row] != player or world.type_foot_w[type] == 0:
			continue
		if left_out.has(world.unit_id[row]):
			continue
		if world.type_power[type] > 0:
			made += world.type_power[type]
		else:
			used -= world.type_power[type]
	return [made, used]


## The rupture case played to three steps after the landing, with the SUPERWEAPON or without.
func _ruptured(fire: bool) -> World:
	var world: World = _world()
	var radius: int = world.type_strike_radius[Strikes.type_of(world, "fossil_strike")]
	_populate_rupture(world, radius)
	Strikes.run_to(world, Strikes.fire_tick(world, BORE))
	var commands: Array = [Strikes.fire(BORE, 1, POINT)] if fire else []
	Strikes.step(world, commands)
	Strikes.run_to(
		world, world.tick + world.type_strike_delay[Strikes.type_of(world, "fossil_strike")] + 3
	)
	return world
