extends RefCounted
## Worlds and helpers for the strike suites (plan rows P110 and P111, ADR 0023 section 10). Not a
## test suite. The data is the rig's own (the shipped strike buildings arrive with P107 and P108),
## so the suites read every expected number from the World's tables, never from a literal here.
##
## `world()` is 30 x 20 open tiles with the shipped rules, two players and the explored map, the
## types of `TYPES` (a test asks `type_of`) and these rows, in this order (ids from 1), all placed
## at tick 0: player 1's two rupture buildings `BORE_A` and `BORE_B` (3x3 at tiles (2, 2) and
## (6, 2)), its blackout building `ARRAY` (3x3 at (10, 2)) and its headquarters `HQ_1` (3x3 at
## (2, 8)); player 2's headquarters `HQ_2` (3x3 at (24, 14)). Nothing is armed and nothing moves.
## The bore's charge is 40 ticks, its warning 12, its radius 3000 and its weapon does 600 with
## 100, 80, 50 and 25 percent against infantry, light, heavy and building armour (so no two classes
## agree); the array charges for 30. The units have a radius of 0, so that no two of them push
## each other apart while a strike is in the air. `POINT` is the centre of tile (15, 10).

const TargetingRig: GDScript = preload("res://tests/sim/support/targeting_rig.gd")
const TargetingWorlds: GDScript = preload("res://tests/sim/support/targeting_worlds.gd")
const COLS: int = 30
const ROWS: int = 20
const BORE_A: int = 1
const BORE_B: int = 2
const ARRAY: int = 3
const HQ_1: int = 4
const HQ_2: int = 5
const POINT: Vector2i = Vector2i(15500, 10500)
const TYPES: Array[String] = ["bore", "array", "hq", "plant", "rifle", "jeep", "tank", "shed"]


## The rig's world with `players` players (player 3 owns nothing); without `revealed` the fog is
## real and every row is stamped.
static func world(revealed: bool = true, players: int = 2) -> World:
	var headquarters: BuildingDef = _building("hq", 3, 1000)
	headquarters.produces = World.Tab.STRUCTURES
	var plant: BuildingDef = _building("plant", 3, 1000)
	plant.power = 100
	var units: Array[UnitDef] = [
		_bore(),
		_array(),
		headquarters,
		plant,
		_unit("rifle", World.Armour.INFANTRY),
		_unit("jeep", World.Armour.LIGHT),
		_unit("tank", World.Armour.HEAVY),
		_building("shed", 1, 2000),
	]
	var made: World = TargetingRig.world_of(units, COLS, ROWS, revealed, players)
	made.fog.explored.fill(1)
	made.add_building(1, type_of(made, "bore"), 2, 2)
	made.add_building(1, type_of(made, "bore"), 6, 2)
	made.add_building(1, type_of(made, "array"), 10, 2)
	made.add_building(1, type_of(made, "hq"), 2, 8)
	made.add_building(2, type_of(made, "hq"), 24, 14)
	if not revealed:
		stamp(made)
	return made


static func type_of(world: World, id: String) -> int:
	return world.type_ids.find(StringName(id))


## Stamps the sight of every row added since (a row added to a prepared World is blind until then).
static func stamp(world: World) -> void:
	TargetingWorlds.stamp_fog(world)


## The hit points of unit `id`, or -1000000 when it has no row.
static func hp_of(world: World, id: int) -> int:
	var row: int = world.index_of(id)
	return world.hp[row] if row >= 0 else -1000000


## The charge, the warning and the radius of the type `id`, from the World's tables.
static func charge_of(world: World, id: String) -> int:
	return world.type_charge_ticks[type_of(world, id)]


static func delay_of(world: World, id: String) -> int:
	return world.type_strike_delay[type_of(world, id)]


static func radius_of(world: World, id: String) -> int:
	return world.type_strike_radius[type_of(world, id)]


## A SUPERWEAPON of `player` with building `id` at `at` (the point of the rig by default).
static func fire(id: int, player: int = 1, at: Vector2i = POINT) -> Command:
	return Command.superweapon(player, id, at.x, at.y)


## One tick: `commands` (a plain Array: a caller reaches this through a preloaded script) are
## stamped with the World's tick and `Sim.step` runs, with `probe` when there is one.
static func step(world: World, commands: Array = [], probe: SimProbe = null) -> void:
	var stamped: Array[Command] = []
	stamped.assign(commands)
	for command: Command in stamped:
		command.tick = world.tick
	Sim.step(world, stamped, probe)


## Steps with no commands until `world.tick` is `tick`.
static func run_to(world: World, tick: int) -> void:
	while world.tick < tick:
		step(world)


## The first tick a SUPERWEAPON of building `id` is accepted: the stamp (tick + 1) reaches its
## `ready_tick`.
static func fire_tick(world: World, id: int) -> int:
	return world.ready_tick[world.index_of(id)] - 1


## Adds a unit of `player` and the type `id` at (x, y) and returns its id.
static func add(world: World, player: int, id: String, x: int, y: int) -> int:
	return world.add_unit(player, type_of(world, id), x, y)


## What the rupture takes from the row `row` of `world`, from the tables: the weapon's damage times
## the percent against the row's armour, at least 1, 0 when the percent is 0 (Combat.fire's rule).
@warning_ignore("integer_division")
static func damage_on(world: World, row: int) -> int:
	var weapon: int = world.type_strike_weapon[type_of(world, "bore")]
	var armour: int = world.type_armour[world.type_index[row]]
	var percent: int = world.weapon_vs_armour[weapon * World.Armour.size() + armour]
	return 0 if percent == 0 else maxi(1, world.weapon_damage[weapon] * percent / 100)


## The names of the hash sections where `a` and `b` differ.
static func differing(a: World, b: World) -> Array[String]:
	var names: PackedStringArray = World.hash_section_names()
	var left: PackedInt64Array = a.hash_parts()
	var right: PackedInt64Array = b.hash_parts()
	var found: Array[String] = []
	for index: int in names.size():
		if left[index] != right[index]:
			found.append(names[index])
	return found


static func _bore() -> BuildingDef:
	var def: BuildingDef = _building("bore", 3, 1500)
	def.cost = 500
	def.build_ticks = 5
	def.tab = World.Tab.STRUCTURES
	def.strike_kind = 1
	def.charge_ticks = 40
	def.strike_radius = 3000
	def.strike_delay = 12
	var weapon: WeaponDef = WeaponDef.new()
	weapon.id = &"bore_rupture"
	weapon.damage = 600
	weapon.vs_armour = PackedInt32Array([100, 80, 50, 25])
	def.strike_weapon = weapon
	return def


static func _array() -> BuildingDef:
	var def: BuildingDef = _building("array", 3, 1500)
	def.strike_kind = 2
	def.charge_ticks = 30
	def.strike_radius = 4000
	def.strike_ticks = 90
	return def


static func _building(id: String, size: int, hit_points: int) -> BuildingDef:
	var def: BuildingDef = BuildingDef.new()
	def.type_id = StringName(id)
	def.max_hp = hit_points
	def.armour = World.Armour.BUILDING
	def.footprint = Vector2i(size, size)
	def.sight_range = 4000
	return def


static func _unit(id: String, armour: int) -> UnitDef:
	var def: UnitDef = UnitDef.new()
	def.type_id = StringName(id)
	def.speed = 67
	def.radius = 0
	def.max_hp = 2000
	def.armour = armour
	def.sight_range = 3000
	return def
