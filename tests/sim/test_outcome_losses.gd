extends GdUnitTestSuite
## The loss stats (plan row P76, ADR 0018 section 7, lead decision of 2026-10-26): each row that
## dies in `World.remove_dead` adds one to its owner's `stat_lost_buildings` (a type with a
## footprint) or `stat_lost_units` (any other row), for an owner whose `had_producer` is 1. A player
## that never owned a producer counts nothing (the perf arena and a World of units only never set
## it, so their hashes stay), and neither does a neutral row. Each death counts once, in the tick
## the row leaves. The world is `production_worlds.gd`'s base world: player 1 owns a power plant
## (id 1), a barracks (id 2), a refinery (id 3) and a vehicle factory (id 4), player 2 a barracks
## (id 5), so both have a producer and neither is defeated by losing the plant, the refinery or a
## unit.

const Rig: GDScript = preload("res://tests/sim/support/production_worlds.gd")
const Worlds: GDScript = preload("res://tests/sim/support/building_worlds.gd")


## A rifle squad of `player` at (`x`, `y`) milli-tiles, clear of every building of the base world;
## returns its id.
func _squad(world: World, player: int, x: int, y: int) -> int:
	return world.add_unit(player, Worlds.type_of(world, "rifle_squad"), x, y)


## Makes row `id` die in the next step: REMOVE takes it.
func _kill(world: World, id: int) -> void:
	world.hp[world.index_of(id)] = 0


## [stat_lost_units, stat_lost_buildings] of `player`.
func _lost(world: World, player: int) -> Array[int]:
	return [world.stat_lost_units[player], world.stat_lost_buildings[player]]


## A building and two units of a player with a producer die in one tick: the stats read 2 units and
## 1 building for that player, and nothing for the other one.
func test_a_building_and_two_units_dying_in_one_tick_count_as_one_building_and_two_units() -> void:
	var world: World = Rig.base()
	var first: int = _squad(world, 1, 500, 500)
	var second: int = _squad(world, 1, 1500, 500)
	Rig.run(world, 3)
	assert_array(_lost(world, 1)).is_equal([0, 0])
	for id: int in [Rig.PLANT, first, second]:
		_kill(world, id)
	Rig.step(world)
	assert_array(_lost(world, 1)).is_equal([2, 1])
	assert_array(_lost(world, 2)).is_equal([0, 0])
	assert_int(world.index_of(Rig.PLANT)).is_less(0)


## Deaths across ticks add up, one count per death in the tick the row leaves: the plant in the
## first step, a unit in the third, the second unit and the refinery in the sixth, and the ticks
## between and after change nothing.
func test_deaths_across_ticks_count_once_each_in_the_tick_they_happen() -> void:
	var world: World = Rig.base()
	var first: int = _squad(world, 1, 500, 500)
	var second: int = _squad(world, 1, 1500, 500)
	_kill(world, Rig.PLANT)
	Rig.step(world)
	assert_array(_lost(world, 1)).is_equal([0, 1])
	Rig.run(world, 1)
	assert_array(_lost(world, 1)).is_equal([0, 1])
	_kill(world, first)
	Rig.step(world)
	assert_array(_lost(world, 1)).is_equal([1, 1])
	Rig.run(world, 2)
	assert_array(_lost(world, 1)).is_equal([1, 1])
	_kill(world, second)
	_kill(world, Rig.REFINERY)
	Rig.step(world)
	assert_array(_lost(world, 1)).is_equal([2, 2])
	Rig.run(world, 10)
	assert_array(_lost(world, 1)).is_equal([2, 2])
	assert_array(_lost(world, 2)).is_equal([0, 0])


## The count is per owner: player 2's unit and the barracks it owns count for player 2 only.
func test_each_loss_counts_for_the_owner_of_the_row() -> void:
	var world: World = Rig.base()
	var scout: int = _squad(world, 2, 20500, 2500)
	var mine: int = _squad(world, 1, 500, 500)
	_kill(world, scout)
	_kill(world, mine)
	_kill(world, Rig.REFINERY)
	Rig.step(world)
	assert_array(_lost(world, 1)).is_equal([1, 1])
	assert_array(_lost(world, 2)).is_equal([1, 0])
	_kill(world, Rig.ENEMY_BARRACKS)
	Rig.step(world)
	assert_array(_lost(world, 1)).is_equal([1, 1])
	assert_array(_lost(world, 2)).is_equal([1, 1])


## A player whose `had_producer` is 0 counts nothing, whatever dies: player 1 here has a power plant
## and two units and no producer, and loses all three, while player 2 (a barracks, `had_producer`
## 1) loses a unit and counts it.
func test_a_player_that_never_owned_a_producer_counts_nothing() -> void:
	var world: World = Worlds.open(24, 16, Rig.IDS)
	var plant: int = world.add_building(1, Worlds.type_of(world, "power_plant"), 2, 1)
	var first: int = _squad(world, 1, 500, 500)
	var second: int = _squad(world, 1, 1500, 500)
	world.add_building(2, Worlds.type_of(world, "barracks"), 8, 12)
	var enemy: int = _squad(world, 2, 20500, 2500)
	assert_array([world.had_producer[1], world.had_producer[2]]).is_equal([0, 1])
	for id: int in [plant, first, second, enemy]:
		_kill(world, id)
	Rig.step(world)
	assert_array(_lost(world, 1)).is_equal([0, 0])
	assert_array(_lost(world, 2)).is_equal([1, 0])
	assert_int(world.unit_count()).is_equal(1)
	assert_array([world.defeated_tick[1], world.match_end_tick]).is_equal([0, 0])


## A neutral row counts for nobody, a building and a unit of owner 0 alike, even when the neutral
## slot of `had_producer` were 1 (set by hand here: no rule ever writes it).
func test_a_neutral_row_counts_nothing() -> void:
	var world: World = Rig.base()
	var rock: int = world.add_building(0, Worlds.type_of(world, "power_plant"), 20, 8)
	var stray: int = world.add_unit(0, Worlds.type_of(world, "rifle_squad"), 20500, 2500)
	assert_int(world.owner[world.index_of(rock)]).is_equal(0)
	world.had_producer[0] = 1
	_kill(world, rock)
	_kill(world, stray)
	Rig.step(world)
	assert_int(world.index_of(rock)).is_less(0)
	assert_int(world.index_of(stray)).is_less(0)
	assert_array(world.stat_lost_units).is_equal([0, 0, 0])
	assert_array(world.stat_lost_buildings).is_equal([0, 0, 0])


## The stats are hashed state: the same deaths in a second world give the same hash, one more unit
## lost does not.
func test_the_stats_are_part_of_the_state_hash() -> void:
	var one: World = Rig.base()
	var two: World = Rig.base()
	var third: World = Rig.base()
	for made: World in [one, two, third]:
		var first: int = _squad(made, 1, 500, 500)
		var second: int = _squad(made, 1, 1500, 500)
		_kill(made, first)
		if made == third:
			_kill(made, second)
	for made: World in [one, two, third]:
		Rig.run(made, 5)
	assert_array(_lost(one, 1)).is_equal([1, 0])
	assert_array(_lost(third, 1)).is_equal([2, 0])
	assert_str(World.hash_hex(one.state_hash())).is_equal(World.hash_hex(two.state_hash()))
	assert_str(World.hash_hex(one.state_hash())).is_not_equal(World.hash_hex(third.state_hash()))
