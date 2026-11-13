extends RefCounted
## Worlds for the airfield suites (plan row P241, ADR 0036 section 6). Not a test suite. The data is
## the rig's own (the shipped airfield arrives with P242), so a suite reads every number from the
## World's tables.
##
## `world()` is 24 x 16 open tiles with the shipped rules, two players and every cell visible, and
## these rows (ids from 1, all at tick 0): player 1's airfield `FIELD` (3x3 at tile (2, 2), two pads
## at the offsets (0, 0) and (2, 0), reach 1500, repair 10 hp per 15 ticks, producer of FLIGHT) and
## player 2's headquarters `HQ_2` (3x3 at (20, 12)), so that neither player is defeated. The types
## are the airfield, the headquarters, `jet` (AIR, ammo 3, reloads in 30 ticks, a gun of range 4000
## with mask 1, built in 6 ticks for 100 credits on the FLIGHT tab), `fighter` (AIR, no ammo limit),
## `drone` (low AIR) and `dummy` (a ground target of 100000 hit points).
## `second_field` adds player 1's second airfield `FIELD_2` (id 3, at (8, 2)).

const Rig: GDScript = preload("res://tests/sim/support/targeting_rig.gd")
const COLS: int = 24
const ROWS: int = 16
const FIELD: int = 1
const HQ_2: int = 2
const FIELD_2: int = 3
const AMMO: int = 3
const REARM: int = 30
const BUILD: int = 6
const REACH: int = 1500


static func world(second_field: bool = false) -> World:
	var field: BuildingDef = _field()
	var hq: BuildingDef = _building("hq", World.Tab.STRUCTURES)
	var units: Array[UnitDef] = [field, hq, _jet(), _fighter(), _drone(), _dummy()]
	var made: World = Rig.world_of(units, COLS, ROWS, true, 2)
	made.add_building(1, type_of(made, "field"), 2, 2)
	made.add_building(2, type_of(made, "hq"), 20, 12)
	if second_field:
		made.add_building(1, type_of(made, "field"), 8, 2)
	return made


static func type_of(world: World, id: String) -> int:
	return world.type_ids.find(StringName(id))


## Adds a unit of `player` and the type `id` at (x, y) milli and returns its row. A new row has
## `ammo` of its type, no home and no order.
static func add(world: World, player: int, id: String, x: int, y: int) -> int:
	world.add_unit(player, type_of(world, id), x, y)
	return world.unit_id.size() - 1


## Adds an aircraft of type `id` homed at the airfield `field` (an id), over pad `pad` of it, and
## returns its row.
static func add_homed(world: World, id: String, field: int, pad: int = 0) -> int:
	var at: Vector2i = Air.pad_point(world, world.index_of(field), pad)
	var row: int = add(world, 1, id, at.x, at.y)
	world.home[row] = field
	return row


static func queue(world: World, id: String, player: int = 1) -> Command:
	return Command.queue(player, type_of(world, id))


## One tick: `commands` (a plain Array) are stamped with the World's tick and `Sim.step` runs.
static func step(world: World, commands: Array = []) -> void:
	var stamped: Array[Command] = []
	stamped.assign(commands)
	for command: Command in stamped:
		command.tick = world.tick
	Sim.step(world, stamped)


static func run(world: World, ticks: int) -> void:
	for _tick: int in ticks:
		step(world)


static func _field() -> BuildingDef:
	var def: BuildingDef = _building("field", World.Tab.FLIGHT)
	def.pads = 2
	def.pad_offsets = [Vector2i(0, 0), Vector2i(2, 0)] as Array[Vector2i]
	def.repair_classes = 8
	def.repair_hp = 10
	def.repair_period_ticks = 15
	def.repair_cost_percent = 40
	def.repair_reach_milli = REACH
	def.repair_slots = 0
	return def


static func _building(id: String, produces: int) -> BuildingDef:
	var def: BuildingDef = BuildingDef.new()
	def.type_id = StringName(id)
	def.max_hp = 2000
	def.armour = World.Armour.BUILDING
	def.footprint = Vector2i(3, 3)
	def.sight_range = 4000
	def.produces = produces
	return def


static func _jet() -> UnitDef:
	var def: UnitDef = Rig.unit(&"jet", 6000, 5000, 4000, 0, [100, 100, 100, 100])
	def.move_class = World.MoveClass.AIR
	def.ammo = AMMO
	def.rearm_ticks = REARM
	def.tab = World.Tab.FLIGHT
	def.cost = 100
	def.build_ticks = BUILD
	def.formation_spacing = 1200
	def.weapon.cooldown_ticks = 3
	return def


static func _fighter() -> UnitDef:
	var def: UnitDef = _jet()
	def.type_id = &"fighter"
	def.weapon.id = &"fighter_gun"
	def.ammo = 0
	def.rearm_ticks = 0
	return def


static func _drone() -> UnitDef:
	var def: UnitDef = Rig.unit(&"drone", 6000, 5000, 0, 0, [])
	def.move_class = World.MoveClass.AIR
	def.low_flying = true
	return def


static func _dummy() -> UnitDef:
	var def: UnitDef = Rig.unit(&"dummy", 1000, 0, 0, 0, [])
	def.max_hp = 100000
	def.speed = 0
	return def
