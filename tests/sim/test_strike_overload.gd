extends GdUnitTestSuite
## The Dusk Array's overload (plan row P572, ADR 0047 section 1): in the blackout's own pass, every
## building the blackout reaches (not the firing player's, neutral ones included, the radius edge
## inside) also loses `Strike.hit_damage` of the strike weapon, 200 against building armour. A row
## whose hp is 0 or less is skipped. A row that falls to 0 dies at that tick's REMOVE as a real
## loss. No weapon (-1) is the blackout of P111, bit for bit. The rig is `strike_worlds.gd` with
## `overload` on: the array (id 3, player 1) has a radius of 4000 and a weapon of 200 / 100 percent
## against buildings, 0 against the other classes; its victims are sheds (2000 hp) and the
## headquarters of player 2 (id 5, 1000 hp, its only producer).

const Strikes: GDScript = preload("res://tests/sim/support/strike_worlds.gd")
const BUILDING: int = World.Armour.BUILDING


func _world() -> World:
	var world: World = Strikes.world(true, 2, true)
	Strikes.run_to(world, Strikes.fire_tick(world, Strikes.ARRAY))
	return world


func _weapon(world: World) -> int:
	return world.type_strike_weapon[Strikes.type_of(world, "array")]


## A 1 x 1 shed of `owner` on tile (col, line); returns its id.
func _shed(world: World, owner: int, col: int, line: int) -> int:
	return world.add_building(owner, Strikes.type_of(world, "shed"), col, line)


func _set_hp(world: World, id: int, hit_points: int) -> void:
	world.hp[world.index_of(id)] = hit_points


## A shed in the radius of the rig's point (a few tiles from it).
func _near(world: World, owner: int, hit_points: int = 2000) -> int:
	var id: int = _shed(world, owner, 14 + world.unit_id.size() % 3, 9 + world.unit_id.size() % 2)
	_set_hp(world, id, hit_points)
	return id


func _fire(world: World, extra: Array = []) -> void:
	var commands: Array = [Strikes.fire(Strikes.ARRAY)]
	commands.append_array(extra)
	Strikes.step(world, commands)


func _died(world: World) -> Array[PackedInt32Array]:
	var found: Array[PackedInt32Array] = []
	for at: int in range(0, world.events.size(), World.EVENT_STRIDE):
		if world.events[at] == World.Event.DIED:
			found.append(world.events.slice(at, at + World.EVENT_STRIDE))
	return found


## The shipped file: 200 damage, 100 percent against building armour and 0 against the rest, ground
## only, and the Dusk Array holds it.
func test_the_shipped_overload_weapon_is_200_against_buildings_only() -> void:
	var weapon: WeaponDef = (
		(load("res://data/units/renew_strike.tres") as BuildingDef).strike_weapon
	)
	assert_str(weapon.resource_path).is_equal("res://data/weapons/renew_overload.tres")
	assert_str(String(weapon.id)).is_equal("renew_overload")
	assert_int(weapon.damage).is_equal(200)
	assert_array(Array(weapon.vs_armour)).is_equal([0, 0, 0, 100])
	assert_int(weapon.targets).is_equal(1)


## `hit_damage` is the rupture's formula: damage times percent against the row's armour, with the
## owner's Upgrades.taken, at least 1, and 0 when the percent is 0.
func test_hit_damage_applies_the_armour_percent_the_upgrade_and_the_floor_of_one() -> void:
	var world: World = _world()
	var weapon: int = _weapon(world)
	var shed: int = _near(world, 2)
	var row: int = world.index_of(shed)
	assert_int(Strike.hit_damage(world, row, weapon)).is_equal(200)
	var types: int = world.type_ids.size()
	var type: int = world.type_index[row]
	world.mod_taken.resize(3 * types)
	world.mod_taken.fill(100)
	world.mod_taken[2 * types + type] = 60
	assert_int(Strike.hit_damage(world, row, weapon)).is_equal(Combat.damage(200, 100, 100, 60))
	assert_int(Strike.hit_damage(world, row, weapon)).is_equal(120)
	world.mod_taken[2 * types + type] = 0  # Zero taken: still at least 1 (percent above 0).
	assert_int(Strike.hit_damage(world, row, weapon)).is_equal(1)
	var jeep: int = Strikes.add(world, 2, "jeep", 15500, 10500)
	assert_int(Strike.hit_damage(world, world.index_of(jeep), weapon)).is_equal(0)


func test_the_overload_takes_the_upgrade_modified_hit_in_the_blackout() -> void:
	var world: World = _world()
	var shed: int = _near(world, 2)
	var types: int = world.type_ids.size()
	world.mod_taken.resize(3 * types)
	world.mod_taken.fill(100)
	world.mod_taken[2 * types + Strikes.type_of(world, "shed")] = 50
	_fire(world)
	assert_int(Strikes.hp_of(world, shed)).is_equal(2000 - 100)


func test_the_overload_hits_an_enemy_building_for_200_and_blacks_it_out_as_before() -> void:
	var world: World = _world()
	var shed: int = _near(world, 2)
	var stamp: int = world.tick + 1
	_fire(world)
	assert_int(Strikes.hp_of(world, shed)).is_equal(1800)
	var length: int = world.type_strike_ticks[Strikes.type_of(world, "array")]
	assert_int(world.offline_until[world.index_of(shed)]).is_equal(stamp + length)
	assert_int(world.dropped_commands).is_equal(0)


## 200 hp: the hit takes it to 0 and REMOVE takes the row out that tick, a real loss (flag 0),
## counted once; its owner's last producer is gone, so Outcome defeats it on the same tick.
func test_a_building_with_200_hp_dies_at_that_ticks_remove_and_outcome_sees_it() -> void:
	var world: World = _world()
	_set_hp(world, Strikes.HQ_2, 200)
	var before: int = world.stat_lost_buildings[2]
	var point: Vector2i = Vector2i(25500, 15500)
	var tick: int = world.tick
	Strikes.step(world, [Strikes.fire(Strikes.ARRAY, 1, point)])
	assert_int(world.index_of(Strikes.HQ_2)).is_equal(-1)
	var records: Array[PackedInt32Array] = _died(world)
	assert_int(records.size()).is_equal(1)
	assert_int(records[0][1]).is_equal(Strikes.HQ_2)
	assert_int(records[0][Removal.DIED_FLAG_AT]).is_equal(0)
	assert_int(world.stat_lost_buildings[2]).is_equal(before + 1)
	assert_int(world.defeated_tick[2]).is_equal(tick + 1)
	assert_int(world.match_end_tick).is_equal(tick + 1)
	assert_int(world.winner).is_equal(1)


func test_a_building_with_201_hp_lives_on_at_1() -> void:
	var world: World = _world()
	var shed: int = _near(world, 2, 201)
	var lost: int = world.stat_lost_buildings[2]
	_fire(world)
	assert_int(Strikes.hp_of(world, shed)).is_equal(1)
	assert_int(_died(world).size()).is_equal(0)
	assert_int(world.stat_lost_buildings[2]).is_equal(lost)


## Own rows, unit rows (any armour, an air layer one too) are untouched; a neutral row is hit.
func test_own_unit_and_air_rows_are_untouched_and_a_neutral_row_is_hit() -> void:
	var world: World = _world()
	var own: int = _near(world, 1)
	var neutral: int = _near(world, 0)
	var units: Array[int] = []
	for id: String in ["rifle", "jeep", "tank"]:
		units.append(Strikes.add(world, 2, id, 15500, 10500))
	var air: int = Strikes.add(world, 2, "jeep", 15600, 10500)
	world.type_layer_bit[world.type_index[world.index_of(air)]] = 2
	units.append(air)
	var hp_units: Array[int] = []
	for id: int in units:
		hp_units.append(Strikes.hp_of(world, id))
	var array_hp: int = Strikes.hp_of(world, Strikes.ARRAY)
	_fire(world)
	assert_int(Strikes.hp_of(world, own)).is_equal(2000)
	assert_int(Strikes.hp_of(world, Strikes.ARRAY)).is_equal(array_hp)
	assert_int(Strikes.hp_of(world, neutral)).is_equal(1800)
	for at: int in units.size():
		assert_int(Strikes.hp_of(world, units[at])).is_equal(hp_units[at])


## A building whose middle is exactly on the radius is hit, one milli beyond it is not.
func test_a_row_exactly_on_the_radius_is_hit_and_one_milli_beyond_is_not() -> void:
	var world: World = _world()
	var radius: int = Strikes.radius_of(world, "array")
	var edge: int = _shed(world, 2, 17, 13)  # Centre (17500, 13500).
	var beyond: int = _shed(world, 2, 17, 12)
	var point: Vector2i = Vector2i(17500 - radius * 3 / 5, 13500 - radius * 4 / 5)
	var row: int = world.index_of(edge)
	var dx: int = world.pos_x[row] - point.x
	var dy: int = world.pos_y[row] - point.y
	assert_int(dx * dx + dy * dy).is_equal(radius * radius)
	world.pos_y[world.index_of(beyond)] = world.pos_y[row] + 1  # Hand-placed: 1 milli too far.
	world.pos_x[world.index_of(beyond)] = world.pos_x[row]
	Strikes.step(world, [Strikes.fire(Strikes.ARRAY, 1, point)])
	assert_int(Strikes.hp_of(world, edge)).is_equal(1800)
	assert_int(Strikes.hp_of(world, beyond)).is_equal(2000)


## A row with 0 or less hp (a sold or cancelled one waiting for REMOVE, or one an earlier overload
## killed) is skipped: the apply leaves its hp as it is, so a death is never counted twice.
func test_a_row_with_no_hp_left_is_skipped() -> void:
	var world: World = _world()
	var gone: int = _near(world, 2, 0)
	var below: int = _near(world, 2, -50)
	var live: int = _near(world, 2)
	var command: Command = Strikes.fire(Strikes.ARRAY)
	command.tick = world.tick
	assert_bool(Strike.apply_superweapon(world, command)).is_true()
	assert_int(Strikes.hp_of(world, gone)).is_equal(0)
	assert_int(Strikes.hp_of(world, below)).is_equal(-50)
	assert_int(Strikes.hp_of(world, live)).is_equal(1800)
	var offline: PackedInt32Array = world.offline_until
	assert_int(offline[world.index_of(gone)]).is_greater(0)  # Still blacked out as before.


## Second array of player 2, so that the victim (player 1) sells before and after: commands apply
## by player, so a player-2 strike comes after player 1's SELL and before nothing. The victim
## here is player 1's shed; the SELL (player 1) is ordered before the strike (player 2).
func _two_player_world() -> World:
	var world: World = Strikes.world(true, 2, true)
	var second: int = world.add_building(2, Strikes.type_of(world, "array"), 20, 2)
	Strikes.stamp(world)
	Strikes.run_to(world, Strikes.fire_tick(world, second))
	world.type_cost[Strikes.type_of(world, "shed")] = 100
	world.sell_refund_percent = 50
	return world


func test_a_sell_ordered_before_the_overload_is_skipped_by_it() -> void:
	var world: World = _two_player_world()
	var second: int = world.unit_id[world.unit_id.size() - 1]
	var shed: int = _near(world, 1)
	var credits: int = world.credits[1]
	var expected: int = Production.sale_refund(100, 50, 2000, 2000)
	Strikes.step(world, [Command.sell(1, shed), Strikes.fire(second, 2)])
	assert_int(world.credits[1]).is_equal(credits + expected)
	var records: Array[PackedInt32Array] = _died(world)
	assert_int(records.size()).is_equal(1)
	assert_int(records[0][Removal.DIED_FLAG_AT]).is_equal(Removal.FLAG_SOLD)
	assert_int(world.stat_lost_buildings[1]).is_equal(0)


func test_a_sell_ordered_after_the_overload_pays_on_the_lower_hp() -> void:
	var world: World = _world()
	world.type_cost[Strikes.type_of(world, "shed")] = 100
	world.sell_refund_percent = 50
	var shed: int = _near(world, 2)
	var credits: int = world.credits[2]
	Strikes.step(world, [Strikes.fire(Strikes.ARRAY), Command.sell(2, shed)])
	assert_int(world.credits[2]).is_equal(credits + Production.sale_refund(100, 50, 1800, 2000))
	assert_int(world.credits[2] - credits).is_less(Production.sale_refund(100, 50, 2000, 2000))
	assert_int(_died(world)[0][Removal.DIED_FLAG_AT]).is_equal(Removal.FLAG_SOLD)


## A sale after a killing overload is refused (the row has 0 hp): no credits, one death.
func test_a_sell_after_a_killing_overload_is_refused() -> void:
	var world: World = _world()
	world.type_cost[Strikes.type_of(world, "shed")] = 100
	world.sell_refund_percent = 50
	var shed: int = _near(world, 2, 150)
	var credits: int = world.credits[2]
	Strikes.step(world, [Strikes.fire(Strikes.ARRAY), Command.sell(2, shed)])
	assert_int(world.credits[2]).is_equal(credits)
	assert_int(_died(world).size()).is_equal(1)
	assert_int(_died(world)[0][Removal.DIED_FLAG_AT]).is_equal(0)


## Two arrays hitting the same row in one tick stack: player 1's and player 2's (each is its own
## strike), on a neutral row both reach; offline_until keeps the longer one.
func test_two_arrays_in_one_tick_stack() -> void:
	var world: World = _two_player_world()
	var second: int = world.unit_id[world.unit_id.size() - 1]
	var neutral: int = _near(world, 0)
	Strikes.step(world, [Strikes.fire(Strikes.ARRAY, 1), Strikes.fire(second, 2)])
	assert_int(Strikes.hp_of(world, neutral)).is_equal(2000 - 2 * 200)
	assert_int(world.dropped_commands).is_equal(0)


## An array with no weapon (-1) is P111's blackout, bit for bit: the same world with the weapon
## taken off differs from a world that took a quiet tick only in `offline_until` and `ready_tick`.
func test_with_no_weapon_the_blackout_is_as_before() -> void:
	var world: World = Strikes.world(true, 2, true)
	var twin: World = Strikes.world(true, 2, false)
	var plain: World = Strikes.world(true, 2, false)
	for each: World in [world, twin, plain] as Array[World]:
		Strikes.run_to(each, Strikes.fire_tick(each, Strikes.ARRAY))
		_near(each, 2)
		_near(each, 0)
	world.type_strike_weapon[Strikes.type_of(world, "array")] = -1
	assert_int(twin.type_strike_weapon[Strikes.type_of(twin, "array")]).is_equal(-1)
	_fire(world)
	_fire(twin)
	Strikes.step(plain)
	assert_int(world.state_hash()).is_equal(twin.state_hash())
	assert_array(Strikes.differing(twin, plain)).is_equal(["ready_tick", "offline_until"])
	for id: int in [Strikes.HQ_2]:
		assert_int(Strikes.hp_of(world, id)).is_equal(1000)


## The frozen arena's Dusk Array has no weapon, so it does no overload.
func test_the_frozen_arena_does_no_overload() -> void:
	var array: BuildingDef = load("res://data/dev/arena/units/renew_strike.tres")
	assert_object(array.strike_weapon).is_null()


## The weapon index 0 is a weapon like any other (the rig's first one, the bore's rupture: 600
## damage, 25 percent against buildings), and a weapon index past the tables hits nothing and
## raises no error: the blackout stays as it was.
func test_weapon_index_zero_works_and_one_past_the_tables_is_no_overload() -> void:
	var world: World = _world()
	var array: int = Strikes.type_of(world, "array")
	var shed: int = _near(world, 2)
	world.type_strike_weapon[array] = 0
	var row: int = world.index_of(shed)
	var expected: int = Strike.hit_damage(world, row, 0)
	assert_int(expected).is_equal(150)
	var twin: World = _world()
	var other: int = _near(twin, 2)
	twin.type_strike_weapon[array] = twin.weapon_damage.size()
	_fire(world)
	_fire(twin)
	assert_int(Strikes.hp_of(world, shed)).is_equal(2000 - expected)
	assert_int(Strikes.hp_of(twin, other)).is_equal(2000)
	assert_int(twin.offline_until[twin.index_of(other)]).is_greater(0)
