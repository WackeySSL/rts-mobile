extends RefCounted
## Worlds with buildings for the P71 suites (plan row P71, ADR 0017 sections 1 and 2): a map from
## one string per tile row (GridWorld's characters), the shipped units and buildings, and helpers
## to find a type by id. Not a test suite.
##
## The roster has the three shipped Phase 2 units, then the buildings and units of Phase 3 that the
## suites use. The type indexes depend on what `requires` pulls in after a type, so a test asks
## `type_of(world, id)`.

const Rig: GDScript = preload("res://tests/sim/support/targeting_rig.gd")
const GridWorld: GDScript = preload("res://tests/sim/support/grid_world.gd")
const TargetingWorlds: GDScript = preload("res://tests/sim/support/targeting_worlds.gd")
const UNIT_DIR: String = "res://data/units/"
const ROSTER: Array[String] = [
	"rifle_squad",
	"rocket_squad",
	"light_tank",
	"headquarters",
	"power_plant",
	"defence_turret",
	"harvester",
	"artillery"
]
## Which terrains of GridWorld.GROUND a building may stand on: grass, 'w', 't', '2' and '4'; not
## scrub ('^') and not rock ('#').
const BUILDABLE: Array[int] = [1, 0, 0, 1, 1, 1, 1]

## A prepared World of the map `rows` (GridWorld's characters), with the roster and 2 players, and
## the terrains' buildable flags. With `revealed` (the default) every cell is visible and explored
## for both players; without, the fog is real and a row is blind until its player's first FOG turn
## (TargetingWorlds.stamp_fog gives it sight at once).
@warning_ignore("integer_division")
static func world(
	rows: PackedStringArray, ids: Array[String] = ROSTER, revealed: bool = true
) -> World:
	var units: Array[UnitDef] = []
	for id: String in ids:
		units.append(load(UNIT_DIR + id + ".tres") as UnitDef)
	var cols: int = len(rows[0])
	var made: World = Rig.world_of(units, cols, rows.size(), revealed)
	made.terrain_cost = PackedByteArray(GridWorld.GROUND_COST)
	for cell: int in cols * rows.size():
		made.set_terrain(cell, GridWorld.GROUND.find(rows[cell / cols][cell % cols]))
	made.terrain_buildable = PackedByteArray(BUILDABLE)
	if revealed:
		made.fog.explored.fill(1)
	return made


## An open map of `cols` x `rows` tiles (see world()).
static func open(cols: int, rows: int, ids: Array[String] = ROSTER) -> World:
	return world(GridWorld.grass(cols, rows), ids)


## The type index of `id` in `world`, or -1.
static func type_of(world: World, id: String) -> int:
	return world.type_ids.find(StringName(id))


## The cost of `cell` for each move class, as an array.
static func costs_at(world: World, cell: int) -> Array[int]:
	var cells: int = world.map_cols * world.map_rows
	var found: Array[int] = []
	for move_class: int in World.MoveClass.size():
		found.append(world.move_cost[move_class * cells + cell])
	return found


## Two small bases on 28 x 16 tiles for the lockstep runs: a wall of rock on column 13 with a gap in
## its southern rows, player 1's Headquarters, power plant and turret west of it and player 2's
## Headquarters, turret and power plant east of it (the turrets and the plants have a few hit
## points, so that buildings die within a few hundred ticks), six light tanks and six rifle squads
## of player 1 at x 8..11, six rocket squads and four light tanks of player 2 at x 18..20, and the
## fog real, every row seeing from tick 0.
@warning_ignore("integer_division")
static func fight() -> World:
	var rock: Array[Vector2i] = []
	for line: int in 10:
		rock.append(Vector2i(13, line))
	var made: World = world(GridWorld.grass(28, 16, rock), ROSTER, false)
	var hq: int = type_of(made, "headquarters")
	var plant: int = type_of(made, "power_plant")
	var turret: int = type_of(made, "defence_turret")
	made.add_building(1, hq, 2, 6)
	_weaken(made, made.add_building(1, plant, 6, 2), 150)
	_weaken(made, made.add_building(1, turret, 9, 10), 120)
	made.add_building(2, hq, 23, 6)
	_weaken(made, made.add_building(2, turret, 17, 5), 120)
	_weaken(made, made.add_building(2, plant, 20, 11), 150)
	for unit: int in 12:
		var type: int = type_of(made, "light_tank" if unit % 2 == 0 else "rifle_squad")
		made.add_unit(1, type, 8500 + unit % 4 * 1000, 4500 + unit / 4 * 1500)
	for unit: int in 10:
		var type: int = type_of(made, "rocket_squad" if unit < 6 else "light_tank")
		made.add_unit(2, type, 18500 + unit % 3 * 1000, 4000 + unit / 3 * 1500)
	TargetingWorlds.stamp_fog(made)
	return made


## Gives the building `id` `hit_points`.
static func _weaken(made: World, id: int, hit_points: int) -> void:
	made.hp[made.index_of(id)] = hit_points
