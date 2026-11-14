extends GdUnitTestSuite
## The rig of the mine suites (test_mines, test_mines_run): the types, the World, the steps and
## the checks. Not a suite of its own: it holds no test.

const Strikes: GDScript = preload("res://tests/sim/support/strike_worlds.gd")
const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const COLS: int = 16
const LAYER: int = 0
const TANK: int = 1
const SQUAD: int = 2
const AWARE: int = 3
const JET: int = 4
const GUNNER: int = 5
const CARRIER: int = 6
const HQ: int = 7
const SHED: int = 8
const CELL: Vector2i = Vector2i(5, 5)


func _unit(id: String, armour: int, move_class: int = 0, hp: int = 200) -> UnitDef:
	var def: UnitDef = UnitDef.new()
	def.type_id = StringName(id)
	def.speed = 67
	def.radius = 300
	def.max_hp = hp
	def.sight_range = 6000
	def.acquire_range = 5000
	def.armour = armour
	def.move_class = move_class
	return def


func _mine_weapon() -> WeaponDef:
	var weapon: WeaponDef = WeaponDef.new()
	weapon.id = &"test_mine"
	weapon.damage = 60
	weapon.vs_armour = PackedInt32Array([100, 50, 25, 0])
	weapon.blast_milli = 1500
	return weapon


func _world(cap: int = 2) -> World:
	var layer: UnitDef = _unit("layer", 0)
	layer.mine_weapon = _mine_weapon()
	layer.mine_cost = 40
	var aware: UnitDef = _unit("aware", 0)
	aware.mine_aware = true
	var gunner: UnitDef = _unit("gunner", 0)
	gunner.mine_weapon = layer.mine_weapon
	gunner.mine_cost = 40
	var gun: WeaponDef = WeaponDef.new()
	gun.id = &"test_gun"
	gun.range = 5000
	gun.damage = 1
	gun.vs_armour = PackedInt32Array([100, 100, 100, 100])
	gunner.weapon = gun
	var carrier: UnitDef = _unit("carrier", 1, World.MoveClass.WHEELED)
	carrier.carry_slots = 2
	carrier.carry_classes = 1
	var hq: BuildingDef = BuildingDef.new()
	hq.type_id = &"hq"
	hq.max_hp = 500
	hq.armour = World.Armour.BUILDING
	hq.footprint = Vector2i(2, 2)
	hq.sight_range = 4000
	var shed: BuildingDef = BuildingDef.new()
	shed.type_id = &"shed"
	shed.max_hp = 500
	shed.armour = World.Armour.BUILDING
	shed.footprint = Vector2i(2, 2)
	shed.sight_range = 4000
	shed.repair_classes = 1
	shed.repair_hp = 30
	shed.repair_period_ticks = 15
	shed.repair_reach_milli = 2700
	shed.repair_slots = 2
	var units: Array[UnitDef] = [
		layer,
		_unit("tank", 1, World.MoveClass.TRACKED),
		_unit("squad", 0),
		aware,
		_unit("jet", 1, World.MoveClass.AIR),
		gunner,
		carrier,
		hq,
		shed,
	]
	var rules: RulesDef = (load("res://data/dev/arena/rules.tres") as RulesDef).duplicate()
	rules.mine_cap = cap
	rules.mine_lay_ticks = 4
	rules.mine_arm_ticks = 3
	rules.passenger_cap = 4
	rules.load_reach_milli = 2000
	rules.unload_reach_tiles = 2
	var scenario: ScenarioDef = ScenarioDef.new()
	scenario.map_size_tiles = Vector2i(COLS, 12)
	scenario.player_count = 2
	scenario.rules = rules
	scenario.roster.assign(units)
	var world: World = World.from_scenario(scenario)
	world.prepare()
	world.fog.visible.fill(1)
	world.credits[1] = 100
	world.credits[2] = 100
	return world


func _add(world: World, player: int, type: int, col: int, line: int) -> int:
	var id: int = world.add_unit(player, type, col * 1000 + 500, line * 1000 + 500)
	assert_int(id).is_greater(0)
	return world.index_of(id)


func _step(world: World, commands: Array[Command] = []) -> void:
	for command: Command in commands:
		command.tick = world.tick
	Sim.step(world, commands)


## Steps `ticks` times and returns the refusals counted over them (the stat resets every tick).
func _refusals(world: World, ticks: int) -> int:
	var total: int = 0
	for _tick: int in ticks:
		_step(world)
		total += world.stats[World.Stat.MINES_REFUSED]
	return total


func _steps(world: World, ticks: int) -> void:
	for _tick: int in ticks:
		_step(world)


func _lay(ids: Array, col: int = CELL.x, line: int = CELL.y) -> Command:
	return Command.lay_mine(1, PackedInt32Array(ids), col * 1000 + 500, line * 1000 + 500)


## Steps until a pending lay of `row` shows its `ready_tick`; returns it (0 if none in 20 ticks).
func _until_started(world: World, row: int) -> int:
	for _tick: int in 20:
		if world.ready_tick[row] != 0:
			return world.ready_tick[row]
		_step(world)
	return 0


## Applies a LAY_MINE for one layer and steps until the mine joins the table.
func _lay_one(world: World, row: int) -> void:
	_step(world, [_lay([world.unit_id[row]])])
	for _tick: int in 20:
		if world.mine_count > 0:
			return
		_step(world)


func _blasts(world: World) -> Array[PackedInt32Array]:
	var found: Array[PackedInt32Array] = []
	for at: int in range(0, world.events.size(), World.EVENT_STRIDE):
		if world.events[at] == World.Event.MINE_BLAST:
			found.append(world.events.slice(at, at + World.EVENT_STRIDE))
	return found


## A mine put straight into the table (a hand-built state), armed from tick 0.
func _put(world: World, owner: int, col: int, line: int) -> void:
	for column_name: StringName in World.MINE_ARRAYS:
		var column: PackedInt32Array = world.get(column_name)
		column.resize(maxi(column.size(), world.mine_count + 1))
	var at: int = world.mine_count
	world.mine_id[at] = world.next_mine_id
	world.mine_owner[at] = owner
	world.mine_cell[at] = line * COLS + col
	world.mine_weapon[at] = world.type_mine_weapon[LAYER]
	world.mine_armed_tick[at] = 1
	world.mine_at[line * COLS + col] = at + 1
	world.next_mine_id += 1
	world.mine_count += 1


## What `mine_at` is when rebuilt from the table: zeros, then `index + 1` at each live mine's cell.
func _rebuilt(world: World) -> PackedInt32Array:
	var grid: PackedInt32Array = PackedInt32Array()
	grid.resize(world.mine_at.size())
	for index: int in world.mine_count:
		grid[world.mine_cell[index]] = index + 1
	return grid


## The rows the mark pass looks up: living mobile ground rows of a player, not mine-aware.
func _eligible(world: World) -> int:
	var total: int = 0
	for row: int in world.unit_id.size():
		var type: int = world.type_index[row]
		total += int(
			(
				world.owner[row] != 0
				and world.hp[row] > 0
				and world.type_speed[type] > 0
				and (world.type_layer_bit[type] & World.Layer.GROUND) != 0
				and world.type_mine_aware[type] == 0
			)
		)
	return total


## One step that asserts the row's invariants: `mine_at` equals a rebuild, and `MINE_CHECKS` is the
## eligible rows while a mine is armed at the stamp (so at most the rows) and 0 otherwise.
func _checked(world: World, commands: Array[Command] = []) -> void:
	var armed: bool = false
	for index: int in world.mine_count:
		armed = armed or world.mine_armed_tick[index] <= world.tick + 1
	var expected: int = _eligible(world) if armed else 0
	var rows: int = world.unit_id.size()
	_step(world, commands)
	assert_int(world.stats[World.Stat.MINE_CHECKS]).is_equal(expected)
	assert_int(world.stats[World.Stat.MINE_CHECKS]).is_less_equal(rows)
	assert_array(world.mine_at).is_equal(_rebuilt(world))


## Lays, a two-mine blast, a third lay and a refusal in one run, checked after every step.
func _scenario(world: World, hashes: PackedInt64Array = PackedInt64Array()) -> void:
	var one: int = _add(world, 1, LAYER, 5, 5)
	var two: int = _add(world, 1, LAYER, 9, 5)
	var three: int = _add(world, 1, LAYER, 3, 8)
	var ids: Array = [world.unit_id[one], world.unit_id[two], world.unit_id[three]]
	var points: Array[Command] = [
		Command.lay_mine(1, PackedInt32Array([ids[0]]), 5500, 5500),
		Command.lay_mine(1, PackedInt32Array([ids[1]]), 9500, 5500),
		Command.lay_mine(1, PackedInt32Array([ids[2]]), 3500, 8500),
	]
	_checked(world, points)
	for _tick: int in 12:
		_checked(world)
		hashes.append(world.state_hash())
	assert_int(world.mine_count).is_equal(2)  # The cap is 2: the third was refused.
	_add(world, 2, TANK, 5, 5)
	_add(world, 2, SQUAD, 9, 5)
	for _tick: int in 4:
		_checked(world)
		hashes.append(world.state_hash())
	assert_int(world.mine_count).is_equal(0)
