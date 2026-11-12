extends RefCounted
## The Worlds of the map reveal suites (plan row P233, ADR 0036 section 11). Not a test suite. The
## data is the rig's own (the shipped space centre arrives with P234), so a suite reads every
## number from the World's tables.
##
## `world()` is 30 x 20 open tiles with the shipped rules, two players, a real fog (every row
## stamped, nothing explored beyond the discs) and these rows, ids from 1, all at tick 0:
## player 1's space centres `SPACE_A` and `SPACE_B` (kind REVEAL, charge 40, 3x3 at tiles (2, 2) and
## (6, 2)), its rupture building `BORE` (charge 40, at (10, 2)), its headquarters `HQ_1` at (2, 8),
## its power plant `PLANT` (100 made) at (6, 8) and its blackout building `ARRAY_1` (charge 30) at
## (14, 8); player 2's headquarters `HQ_2` at (24, 14) and its blackout building `ARRAY_2` (charge
## 30, radius 4000, 90 ticks) at (24, 2). `drain()` adds a building of player 1 that uses 200
## power, which puts it on low power from the end of the step that follows.

const TargetingRig: GDScript = preload("res://tests/sim/support/targeting_rig.gd")
const Strikes: GDScript = preload("res://tests/sim/support/strike_worlds.gd")
const COLS: int = 30
const ROWS: int = 20
const SPACE_A: int = 1
const SPACE_B: int = 2
const BORE: int = 3
const HQ_1: int = 4
const PLANT: int = 5
const ARRAY_1: int = 6
const HQ_2: int = 7
const ARRAY_2: int = 8
## A point 2 tiles from the centre of SPACE_A and 6 from SPACE_B: ARRAY_2's blackout there takes
## SPACE_A offline and leaves SPACE_B.
const OVER_A: Vector2i = Vector2i(1500, 3500)


static func world() -> World:
	var units: Array = [
		_building("space", 3, 40, 3),
		_building("bore", 3, 40, 1),
		_building("hq", 3, 0, 0),
		_building("plant", 3, 0, 0),
		_building("array", 3, 30, 2),
		_building("drain", 1, 0, 0)
	]
	units[2].produces = World.Tab.STRUCTURES
	units[3].power = 100
	units[1].strike_radius = 3000
	units[1].strike_delay = 12
	units[4].strike_radius = 4000
	units[4].strike_ticks = 90
	units[5].power = -200
	var made: World = TargetingRig.world_of(units, COLS, ROWS, false, 2)
	made.add_building(1, type_of(made, "space"), 2, 2)
	made.add_building(1, type_of(made, "space"), 6, 2)
	made.add_building(1, type_of(made, "bore"), 10, 2)
	made.add_building(1, type_of(made, "hq"), 2, 8)
	made.add_building(1, type_of(made, "plant"), 6, 8)
	made.add_building(1, type_of(made, "array"), 14, 8)
	made.add_building(2, type_of(made, "hq"), 24, 14)
	made.add_building(2, type_of(made, "array"), 24, 2)
	Strikes.stamp(made)
	return made


static func type_of(world: World, id: String) -> int:
	return world.type_ids.find(StringName(id))


## Adds the power drain of player 1 at tile (x, y), stamped, and returns its id.
static func drain(world: World, x: int, y: int) -> int:
	var id: int = world.add_building(1, type_of(world, "drain"), x, y)
	Strikes.stamp(world)
	return id


## One tick with `commands` (see Strikes.step).
static func step(world: World, commands: Array = []) -> void:
	Strikes.step(world, commands)


## The first tick a SUPERWEAPON of building `id` is accepted.
static func fire_tick(world: World, id: int) -> int:
	return Strikes.fire_tick(world, id)


static func fire(id: int, player: int = 1, at: Vector2i = Strikes.POINT) -> Command:
	return Command.superweapon(player, id, at.x, at.y)


static func _building(id: String, size: int, charge: int, kind: int) -> BuildingDef:
	var def: BuildingDef = BuildingDef.new()
	def.type_id = StringName(id)
	def.max_hp = 2000
	def.armour = World.Armour.BUILDING
	def.footprint = Vector2i(size, size)
	def.sight_range = 4000
	def.charge_ticks = charge
	def.strike_kind = kind
	if kind == 1:
		var weapon: WeaponDef = WeaponDef.new()
		weapon.id = &"rig_rupture"
		weapon.damage = 10
		weapon.vs_armour = PackedInt32Array([100, 100, 100, 100])
		def.strike_weapon = weapon
	return def
