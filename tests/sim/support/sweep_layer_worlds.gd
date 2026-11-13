extends RefCounted
## The world of the sweep and target-layer suite (plan row P241, ADR 0036 sections 5 and 11). Not a
## test suite. 30 x 20 open tiles, the shipped rules, a real fog (every row stamped), two players.
## Rows, ids from 1: player 1's space centre `SPACE` (a REVEAL building, charge 40, 200 hit points,
## 3x3 at tile (2, 2)), headquarters, power plant; player 2's headquarters and rupture building
## `BORE` (charge 40, delay 12, radius 3000, 10 damage, ground only, 3x3 at (14, 2)); then the
## units, with a sight of 2 tiles (the two targets stand still), so that an enemy outside the sight
## of every player 1 row is shown by the sweep only: player 1's `GUN` (mask 1) at (20.5,
## 9.5) and `FLAK` (mask 6) at (23.5, 6.5); player 2's `DUMMY` (ground) 4 tiles east of the gun
## and `JET` (AIR) 3 tiles north of it, nearer to the gun than the dummy. `drain()` adds a power
## drain of player 1 (200 power, low power pauses the sweep).

const Rig: GDScript = preload("res://tests/sim/support/targeting_rig.gd")
const Strikes: GDScript = preload("res://tests/sim/support/strike_worlds.gd")
const SPACE: int = 1
const BORE: int = 5
const GUN: int = 6
const FLAK: int = 7
const DUMMY: int = 8
const JET: int = 9
const SPACE_POINT: Vector2i = Vector2i(3500, 3500)


static func world() -> World:
	var units: Array[UnitDef] = [
		_building("space", 200, 3),
		_building("bore", 2000, 1),
		_building("hq", 2000, 0),
		_building("plant", 2000, 0),
		_building("drain", 2000, 0),
		_shooter("gun", 1),
		_shooter("flak", 6),
		_target("dummy", false),
		_target("jet", true),
	]
	units[2].produces = World.Tab.STRUCTURES
	units[3].power = 100
	units[4].power = -200
	var bore: BuildingDef = units[1]
	bore.strike_radius = 3000
	bore.strike_delay = 12
	var weapon: WeaponDef = WeaponDef.new()
	weapon.id = &"rig_rupture"
	weapon.damage = 10
	bore.strike_weapon = weapon
	var made: World = Rig.world_of(units, 30, 20, false, 2)
	made.add_building(1, type_of(made, "space"), 2, 2)
	made.add_building(1, type_of(made, "hq"), 2, 8)
	made.add_building(1, type_of(made, "plant"), 6, 8)
	made.add_building(2, type_of(made, "hq"), 24, 14)
	made.add_building(2, type_of(made, "bore"), 14, 2)
	made.add_unit(1, type_of(made, "gun"), 20500, 9500)
	made.add_unit(1, type_of(made, "flak"), 23500, 6500)
	made.add_unit(2, type_of(made, "dummy"), 24500, 9500)
	made.add_unit(2, type_of(made, "jet"), 20500, 6500)
	Strikes.stamp(made)
	return made


static func type_of(world: World, id: String) -> int:
	return world.type_ids.find(StringName(id))


static func drain(world: World) -> int:
	var id: int = world.add_building(1, type_of(world, "drain"), 20, 12)
	Strikes.stamp(world)
	return id


static func fire_tick(world: World, id: int) -> int:
	return Strikes.fire_tick(world, id)


static func step(world: World, commands: Array = []) -> void:
	Strikes.step(world, commands)


static func _building(id: String, hit_points: int, kind: int) -> BuildingDef:
	var def: BuildingDef = BuildingDef.new()
	def.type_id = StringName(id)
	def.max_hp = hit_points
	def.cost = 100
	def.armour = World.Armour.BUILDING
	def.footprint = Vector2i(3, 3)
	def.sight_range = 4000
	def.charge_ticks = 40 if kind != 0 else 0
	def.strike_kind = kind
	return def


static func _shooter(id: String, mask: int) -> UnitDef:
	var def: UnitDef = Rig.unit(StringName(id), 2000, 6000, 5000, 0, [100, 100, 100, 100])
	def.weapon.targets = mask
	def.max_hp = 100000
	return def


static func _target(id: String, air: bool) -> UnitDef:
	var def: UnitDef = Rig.unit(StringName(id), 2000, 0, 0, 0, [])
	def.speed = 0
	def.max_hp = 100000
	def.radius = 0
	if air:
		def.move_class = World.MoveClass.AIR
	return def
