extends RefCounted
## The world of the blackout suites that need armed buildings and queues (plan row P111, ADR 0023
## section 10): `test_blackout_defence` and `test_blackout_production`. Not a test suite. The data
## is the rig's own, so the suites read every expected tick and number from the World's tables.
##
## `world()` is 40 x 24 open tiles with the shipped rules, two players, a revealed map and these
## rows (ids from 1, all placed at tick 0): player 1's blackout array `ARRAY` (3x3 at tile (2, 2);
## it charges for 30 and blacks out buildings within 4000 for 90) and headquarters `HQ_1`; player
## 2's headquarters `HQ_2`, power plant `PLANT` (outside the blackout's reach), defence turrets
## `TURRET_IN` and `TURRET_OUT`, barracks `BARRACKS` (infantry) and vehicle factory `FACTORY`; and
## two of player 1's dummies, `TARGET_IN` and `TARGET_OUT`, each 3500 west of a turret. `POINT`
## (30000, 6000) is the point a test fires the array at: it reaches `TURRET_IN` (1000 away) and
## `BARRACKS` (2828), and neither `TURRET_OUT`, `FACTORY` nor `PLANT` (all 7000 or more away).
##
## Player 2's power is never low: the plant makes 100 against the 80 that its turrets and producers
## use, and the plant is outside the blackout's reach, so a blackout shows through `offline_until`
## alone. A turret has a range of 5500 and a cooldown of 20 ticks; a dummy has hit points to last
## any run, and nothing else is armed. A `gunner` (a queue item of the barracks, and a unit a test
## adds) shoots at 5500; a `jeep` (an item of the factory) is unarmed. Both take 100 ticks to
## build.

const TargetingRig: GDScript = preload("res://tests/sim/support/targeting_rig.gd")
const COLS: int = 40
const ROWS: int = 24
const ARRAY: int = 1
const HQ_1: int = 2
const HQ_2: int = 3
const PLANT: int = 4
const TURRET_IN: int = 5
const TURRET_OUT: int = 6
const BARRACKS: int = 7
const FACTORY: int = 8
const TARGET_IN: int = 9
const TARGET_OUT: int = 10
const POINT: Vector2i = Vector2i(30000, 6000)
const TYPES: Array[String] = [
	"array", "hq", "plant", "turret", "barracks", "factory", "gunner", "jeep", "dummy"
]


static func world() -> World:
	var units: Array[UnitDef] = [
		_array(),
		_building("hq", 3, 1000, 0, World.Tab.STRUCTURES),
		_building("plant", 2, 1000, 100, -1),
		_turret(),
		_building("barracks", 2, 1000, -20, World.Tab.INFANTRY),
		_building("factory", 2, 1000, -20, World.Tab.VEHICLES),
		_unit("gunner", true, World.Tab.INFANTRY),
		_unit("jeep", false, World.Tab.VEHICLES),
		_dummy(),
	]
	var made: World = TargetingRig.world_of(units, COLS, ROWS, true, 2)
	made.fog.explored.fill(1)
	made.add_building(1, type_of(made, "array"), 2, 2)
	made.add_building(1, type_of(made, "hq"), 2, 8)
	made.add_building(2, type_of(made, "hq"), 34, 19)
	made.add_building(2, type_of(made, "plant"), 36, 1)
	made.add_building(2, type_of(made, "turret"), 29, 4)  # Its centre is (30000, 5000).
	made.add_building(2, type_of(made, "turret"), 29, 16)  # (30000, 17000).
	made.add_building(2, type_of(made, "barracks"), 31, 7)  # (32000, 8000).
	made.add_building(2, type_of(made, "factory"), 36, 10)  # (37000, 11000).
	made.add_unit(1, type_of(made, "dummy"), 26500, 5000)
	made.add_unit(1, type_of(made, "dummy"), 26500, 17000)
	return made


static func type_of(world: World, id: String) -> int:
	return world.type_ids.find(StringName(id))


## One tick: `commands` (a plain Array) are stamped with the World's tick and `Sim.step` runs.
static func step(world: World, commands: Array = []) -> void:
	var stamped: Array[Command] = []
	stamped.assign(commands)
	for command: Command in stamped:
		command.tick = world.tick
	Sim.step(world, stamped)


## Steps with no commands until `world.tick` is `tick`.
static func run_to(world: World, tick: int) -> void:
	while world.tick < tick:
		step(world)


## A SUPERWEAPON of player 1's array at `at` (the rig's point by default).
static func fire(at: Vector2i = POINT) -> Command:
	return Command.superweapon(1, ARRAY, at.x, at.y)


## The first tick the array is accepted: the stamp (tick + 1) reaches its `ready_tick`.
static func fire_tick(world: World) -> int:
	return world.ready_tick[world.index_of(ARRAY)] - 1


## The blackout's length in ticks, from the World's table.
static func length_of(world: World) -> int:
	return world.type_strike_ticks[type_of(world, "array")]


## The ids of the SHOT records of the last step's events, by shooter, in order.
static func shooters(world: World) -> Array[int]:
	var found: Array[int] = []
	for at: int in range(0, world.events.size(), World.EVENT_STRIDE):
		if world.events[at] == World.Event.SHOT:
			found.append(world.events[at + 1])
	return found


## The number of rows of `owner` of the type `id`.
static func count_of(world: World, owner: int, id: String) -> int:
	var type: int = type_of(world, id)
	var found: int = 0
	for row: int in world.unit_count():
		if world.owner[row] == owner and world.type_index[row] == type:
			found += 1
	return found


static func _array() -> BuildingDef:
	var def: BuildingDef = _building("array", 3, 1500, 0, -1)
	def.strike_kind = 2
	def.charge_ticks = 30
	def.strike_radius = 4000
	def.strike_ticks = 90
	return def


static func _turret() -> BuildingDef:
	var def: BuildingDef = _building("turret", 2, 1000, -20, -1)
	def.sight_range = 7000
	def.acquire_range = 5500
	def.weapon = _weapon("turret_gun")
	return def


static func _building(
	id: String, size: int, hit_points: int, power: int, produces: int
) -> BuildingDef:
	var def: BuildingDef = BuildingDef.new()
	def.type_id = StringName(id)
	def.max_hp = hit_points
	def.armour = World.Armour.BUILDING
	def.footprint = Vector2i(size, size)
	def.sight_range = 4000
	def.power = power
	def.produces = produces
	def.exit = Vector2i(1, size)  # The tile below the footprint's second column.
	return def


## A unit with a radius of 0 (so that none pushes another), `tab` as the queue it comes from, and a
## gun that does `armed`.
static func _unit(id: String, armed: bool, tab: int) -> UnitDef:
	var def: UnitDef = UnitDef.new()
	def.type_id = StringName(id)
	def.speed = 67
	def.radius = 0
	def.max_hp = 2000
	def.armour = World.Armour.LIGHT
	def.sight_range = 7000
	def.acquire_range = 5500
	def.cost = 50
	def.build_ticks = 100
	def.tab = tab
	if armed:
		def.weapon = _weapon(id + "_gun")
	return def


static func _dummy() -> UnitDef:
	var def: UnitDef = _unit("dummy", false, -1)
	def.max_hp = 1000000
	def.cost = 0
	def.build_ticks = 0
	return def


static func _weapon(id: String) -> WeaponDef:
	var weapon: WeaponDef = WeaponDef.new()
	weapon.id = StringName(id)
	weapon.range = 5500
	weapon.damage = 10
	weapon.cooldown_ticks = 20
	return weapon
