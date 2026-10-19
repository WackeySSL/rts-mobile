extends RefCounted
## Worlds and helpers for the targeting tests (P41). Not a test suite.
##
## `data_world` builds a World from the three shipped unit types (rifle squad, rocket squad, light
## tank: types 0, 1 and 2, weapons 0, 1 and 2), so the ranges and armour percents are the ones of
## data/: rifle range 4000 and acquire 5000 with 100/10 percent against infantry/light, rocket 5000
## and 5500 with 20/100, tank 4500 and 5500 with 70/60; sight is 6000 or 7000. Targets within
## 6000 of their unit are inside its sight, which is the authoring rule of the fog PR (P46b). Units
## are the test's to add, owner 1 and 2 (`player_count` is 2).

const RULES_PATH: String = "res://data/rules.tres"
const RIFLE_PATH: String = "res://data/units/rifle_squad.tres"
const ROCKET_PATH: String = "res://data/units/rocket_squad.tres"
const TANK_PATH: String = "res://data/units/light_tank.tres"
const RIFLE: int = 0
const ROCKET: int = 1
const TANK: int = 2


## A World of `cols` x `rows` open tiles with the shipped rules and the three shipped types.
static func data_world(cols: int = 20, rows: int = 12) -> World:
	var units: Array[UnitDef] = [
		load(RIFLE_PATH) as UnitDef, load(ROCKET_PATH) as UnitDef, load(TANK_PATH) as UnitDef
	]
	return world_of(units, cols, rows)


## A World of `cols` x `rows` open tiles with the shipped rules, one type per entry of `units`
## (type 0 is `units[0]`) and two players.
static func world_of(units: Array, cols: int = 20, rows: int = 12) -> World:
	var scenario: ScenarioDef = ScenarioDef.new()
	scenario.map_size_tiles = Vector2i(cols, rows)
	scenario.player_count = 2
	scenario.rules = load(RULES_PATH) as RulesDef
	scenario.roster.assign(units)
	return World.from_scenario(scenario)


## A unit type for a test: a 300 radius, `sight` and `acquire` as given, and a weapon of `range`,
## `min_range` and `vs` (percents against infantry, light, heavy and building), or no weapon when
## `vs` is empty.
static func unit(
	id: StringName, sight: int, acquire: int, range_milli: int, min_range: int, vs: Array
) -> UnitDef:
	var def: UnitDef = UnitDef.new()
	def.type_id = id
	def.speed = 67
	def.radius = 300
	def.max_hp = 100
	def.sight_range = sight
	def.acquire_range = acquire
	if not vs.is_empty():
		var weapon: WeaponDef = WeaponDef.new()
		weapon.id = StringName(String(id) + "_gun")
		weapon.range = range_milli
		weapon.min_range = min_range
		weapon.damage = 10
		weapon.vs_armour = PackedInt32Array(vs)
		def.weapon = weapon
	return def


## The GRIDS and TARGETING phases as `Sim.step` runs them: the grid from the positions as they
## stand, then `Targeting.run` at the World's tick.
static func acquire(world: World) -> void:
	world.prepare()
	world.target_grid.rebuild(world.pos_x, world.pos_y, world.unit_count())
	Targeting.run(world)


## Sets the World's tick so that unit `id` is due (`(tick + id) % period == 0`), at or after the
## current tick.
static func due_tick_for(world: World, id: int) -> int:
	var period: int = world.retarget_period_ticks
	return world.tick + (period - (world.tick + id) % period) % period


## Makes unit `id` due, runs `acquire` and returns that unit's target id (0 = none).
static func target_of(world: World, id: int) -> int:
	world.tick = due_tick_for(world, id)
	acquire(world)
	return world.target[world.index_of(id)]


## `target_of` one tick later: the unit's next due tick after the one it just had.
static func retarget(world: World, id: int) -> int:
	world.tick += 1
	return target_of(world, id)


## Whether the unit in `row` scans at the World's tick: `(tick + id) % period == 0`.
static func is_due(world: World, row: int) -> bool:
	return (world.tick + world.unit_id[row]) % maxi(world.retarget_period_ticks, 1) == 0


## The ids of the units that hold a target farther away than their own sight, in ascending order
## (with `due_only`, only the units that scan at the World's tick). Empty is what the fog PR's
## vision check needs to leave a case green (row P46b, the authoring rule): a test asserts it, so
## a failure names the units.
static func outside_sight(world: World, due_only: bool = false) -> Array[int]:
	var found: Array[int] = []
	for row: int in world.unit_count():
		var id: int = world.target[row]
		if id == 0 or (due_only and not is_due(world, row)):
			continue
		var other: int = world.index_of(id)
		if other < 0:
			found.append(world.unit_id[row])
			continue
		var dx: int = world.pos_x[other] - world.pos_x[row]
		var dy: int = world.pos_y[other] - world.pos_y[row]
		var sight: int = world.type_sight[world.type_index[row]]
		if dx * dx + dy * dy > sight * sight:
			found.append(world.unit_id[row])
	return found


## The state hash after each 15th tick of `ticks` ticks of `Sim.step` on `world`, no commands.
static func hashes(world: World, ticks: int) -> PackedInt64Array:
	var found: PackedInt64Array = PackedInt64Array()
	for _tick: int in ticks:
		Sim.step(world, [])
		if world.tick % Replay.CHECKPOINT_PERIOD == 0:
			found.append(world.state_hash())
	return found
