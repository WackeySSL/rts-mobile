extends RefCounted
## Worlds for the target-layer tests (plan row P238, ADR 0036 section 5). Not a test suite.
##
## The roster has every mask of the ADR once, aircraft among the targets and among the shooters:
## 0 gun (mask 1), 1 rocket (7), 2 rifle (5), 3 flak (6), 4 jet (AIR, mask 2), 5 bomber (AIR,
## mask 1), 6 drone (low AIR, mask 1), 7 scout (no weapon). `field` scatters random rows of them
## with random orders, locks and held targets for the lockstep, `duel` is the two-row world of the
## rule tests.

const Rig: GDScript = preload("res://tests/sim/support/targeting_rig.gd")
const Worlds: GDScript = preload("res://tests/sim/support/targeting_worlds.gd")
const GUN: int = 0
const ROCKET: int = 1
const RIFLE: int = 2
const FLAK: int = 3
const JET: int = 4
const BOMBER: int = 5
const DRONE: int = 6
const SCOUT: int = 7
const TYPES: int = 8
const GROUND: int = World.Layer.GROUND
const AIR: int = World.Layer.AIR
const LOW_AIR: int = World.Layer.LOW_AIR


## The eight types. Every weapon reaches 4000 and the types acquire at 5000 and see 6000, so that
## a pair within 4000 is in reach of both the idle and the attack-moving rule. The percents differ
## per weapon (flak has 0 against infantry), so that the percent test and the layer test are told
## apart.
static func roster() -> Array[UnitDef]:
	var units: Array[UnitDef] = [
		_armed(&"gun", 1, [100, 60, 40, 100], World.Armour.HEAVY),
		_armed(&"rocket", 7, [20, 100, 100, 80], World.Armour.INFANTRY),
		_armed(&"rifle", 5, [100, 10, 5, 5], World.Armour.INFANTRY),
		_armed(&"flak", 6, [0, 100, 100, 100], World.Armour.LIGHT),
		_armed(&"jet", 2, [100, 100, 80, 100], World.Armour.LIGHT),
		_armed(&"bomber", 1, [100, 100, 100, 100], World.Armour.HEAVY),
		_armed(&"drone", 1, [100, 50, 50, 50], World.Armour.INFANTRY),
		Rig.unit(&"scout", 6000, 5000, 0, 0, []),
	]
	units[JET].move_class = World.MoveClass.AIR
	units[BOMBER].move_class = World.MoveClass.AIR
	units[DRONE].move_class = World.MoveClass.AIR
	units[DRONE].low_flying = true
	return units


## A revealed 20 x 12 World of the roster with `players` players: nothing on it yet.
static func empty(revealed: bool = true) -> World:
	return Rig.world_of(roster(), 20, 12, revealed)


## A revealed World with a shooter of type `shooter` (owner 1, id 1) at (4000, 6000) and a mark of
## type `mark` (owner 2, id 2) `gap` milli east of it, both idle.
static func duel(shooter: int, mark: int, gap: int = 2000) -> World:
	var world: World = empty()
	world.add_unit(1, shooter, 4000, 6000)
	world.add_unit(2, mark, 4000 + gap, 6000)
	return world


## `count` rows of random types and owners (a few neutral) at random points of a 24 x 16 tile map,
## with random orders (IDLE, ATTACK_MOVE, MOVE, and ATTACK at a random row), random held targets and
## a fog stamped for a share of the rows only, so that sight refuses some. The tick and the
## cadences are the shipped ones.
static func field(salt: int, count: int = 60) -> World:
	var rng: DetRandom = DetRandom.create(salt, 41)
	var world: World = Rig.world_of(roster(), 24, 16, false)
	for _row: int in count:
		var owner: int = 0 if rng.next_int(10) == 0 else 1 + rng.next_int(2)
		var type: int = rng.next_int(TYPES)
		world.add_unit(owner, type, rng.next_int(24000), rng.next_int(16000))
	for row: int in count:
		world.order[row] = rng.next_int(4)
		world.goal_x[row] = rng.next_int(24000)
		world.goal_y[row] = rng.next_int(16000)
		world.target[row] = world.unit_id[rng.next_int(count)] if rng.next_int(3) == 0 else 0
		if world.order[row] == World.Order.ATTACK:
			world.order_target[row] = world.unit_id[rng.next_int(count)]
	world.tick = rng.next_int(50)
	var sight: DetRandom = DetRandom.create(salt, 42)
	Worlds.stamp_fog(world, 100 if sight.next_int(3) == 0 else 25 * (1 + sight.next_int(3)), sight)
	return world


static func _armed(id: StringName, mask: int, vs: Array, armour: int) -> UnitDef:
	var def: UnitDef = Rig.unit(id, 6000, 5000, 4000, 0, vs)
	def.weapon.targets = mask
	def.armour = armour
	return def
