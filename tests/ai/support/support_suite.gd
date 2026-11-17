extends GdUnitTestSuite
## The base of the ground support suites (P283): fixtures and helpers, not a test suite. The rig's
## types are its own (the shipped support types are in no roster before P279 and P280):
## `AiProduction`'s medics, `AiRepair`'s repairs and medic orders run on them.
## Fixture: a headquarters, a barracks and a factory, a shed (the repair building), a squad (armed
## infantry), a medic (unarmed infantry), a tank and a tanker (both on the vehicle tab).

const Rig: GDScript = preload("res://tests/sim/support/targeting_rig.gd")
const AiRig: GDScript = preload("res://tests/ai/support/ai_rig.gd")
const Worlds: GDScript = preload("res://tests/sim/support/air_worlds.gd")
const NONE: int = -1
const HOME: int = 0
const WAVE: int = 1


func _building(id: String, produces: int, size: Vector2i, cost: int) -> BuildingDef:
	var def: BuildingDef = BuildingDef.new()
	def.type_id = StringName(id)
	def.max_hp = 1000
	def.armour = World.Armour.BUILDING
	def.footprint = size
	def.sight_range = 4000
	def.produces = produces
	def.cost = cost
	def.tab = World.Tab.STRUCTURES
	return def


func _unit(id: String, tab: int, armed: bool, cost: int) -> UnitDef:
	var def: UnitDef = Rig.unit(
		StringName(id), 6000, 5000, 4000 if armed else 0, 0, [100, 100, 100, 100]
	)
	if not armed:
		def.weapon = null
	def.tab = tab
	def.cost = cost
	def.build_ticks = 30
	if tab == World.Tab.VEHICLES:
		def.move_class = World.MoveClass.TRACKED
	return def


## A World of 24 x 16 tiles: player 1 owns a headquarters (1, 1), a barracks (6, 1), a factory
## (10, 1) and, with `shed`, a shed at (3, 8); player 2 a headquarters. 100000 credits.
func _world(
	shed: bool = true, medic: bool = true, place: bool = true, decoys: bool = false
) -> World:
	var units: Array[UnitDef] = [
		_building("hq", World.Tab.STRUCTURES, Vector2i(3, 3), 0),
		_building("barracks", World.Tab.INFANTRY, Vector2i(2, 2), 300),
		_building("factory", World.Tab.VEHICLES, Vector2i(3, 3), 800),
		_unit("squad", World.Tab.INFANTRY, true, 100),
		_unit("tank", World.Tab.VEHICLES, true, 200),
		_unit("tanker", World.Tab.VEHICLES, false, 100),
	]
	if decoys:
		# An armed unit that heals the foot class and a building of slots 0 come first: neither is
		# a medic or a repair building.
		var healer: UnitDef = _unit("armed_healer", World.Tab.INFANTRY, true, 100)
		healer.repair_classes = 1
		healer.repair_slots = 1
		units.append(healer)
		var dud: BuildingDef = _building("dud", NONE, Vector2i(2, 2), 800)
		dud.repair_classes = 6
		dud.repair_slots = 0
		units.append(dud)
	if shed:
		var building: BuildingDef = _building("shed", NONE, Vector2i(2, 2), 800)
		building.repair_classes = 6
		building.repair_slots = 2
		building.repair_hp = 30
		building.repair_cost_percent = 25
		building.repair_reach_milli = 2700
		units.append(building)
	if medic:
		var squad: UnitDef = _unit("medic", World.Tab.INFANTRY, false, 300)
		squad.repair_classes = 1
		squad.repair_slots = 1
		squad.repair_hp = 6
		squad.repair_reach_milli = 1500
		squad.repair_seek_milli = 4000
		units.append(squad)
	var made: World = Rig.world_of(units, 24, 16, true, 2)
	made.add_building(1, Worlds.type_of(made, "hq"), 1, 1)
	made.add_building(1, Worlds.type_of(made, "barracks"), 6, 1)
	made.add_building(1, Worlds.type_of(made, "factory"), 10, 1)
	if shed and place:
		made.add_building(1, Worlds.type_of(made, "shed"), 3, 8)
	made.add_building(2, Worlds.type_of(made, "hq"), 20, 12)
	made.credits[1] = 100000
	return made


func _def() -> OpponentDef:
	var def: OpponentDef = OpponentDef.new()
	def.hq_type = &"hq"
	def.anti_infantry_type = &"squad"
	def.anti_vehicle_types = [] as Array[StringName]
	def.tank_type = &"tank"
	def.artillery_type = &"nothing"
	def.role_weights = PackedInt32Array([1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0])
	return def


func _level(retreat: int, medic_per: int, wave_retreat: int = 0) -> AiDifficultyDef:
	var level: AiDifficultyDef = AiDifficultyDef.new()
	level.repair_wave_retreat = wave_retreat
	level.repair_retreat_percent = retreat
	level.medic_per_squads = medic_per
	level.counter_percent = 0
	return level


func _memory() -> AiMemory:
	var memory: AiMemory = AiMemory.create(_def())
	memory.commands_left = 99
	memory.staging_x = 8
	memory.staging_y = 8
	return memory


func _add(world: World, id: String, x: int, y: int, hp: int = 100) -> int:
	var row: int = Worlds.add(world, 1, id, x, y)
	world.hp[row] = hp
	return world.unit_id[row]


## The memory's lists as `AiIntel` leaves them for the rows of player 1 of `world`: own buildings,
## own combat units but the scouts (the squads and the tanks), the mobile rows and the members, all
## in the home squad.
func _fill(world: World, memory: AiMemory) -> void:
	var view: PlayerView = PlayerView.of(world, 1)
	memory.site_id.clear()
	memory.unit_id.clear()
	memory.own_mobile_id.clear()
	for row: int in view.own_rows:
		var id: int = view.row_id(row)
		var type: int = view.row_type(row)
		if view.type_foot_w[type] > 0:
			memory.site_id.append(id)
			memory.site_x.append(view.row_pos(row).x)
			memory.site_y.append(view.row_pos(row).y)
			continue
		memory.own_mobile_id.append(id)
		if view.type_weapon[type] >= 0:
			memory.unit_id.append(id)
	memory.member_id = memory.unit_id.duplicate()
	memory.member_squad.resize(memory.unit_id.size())
	memory.member_squad.fill(HOME)
	memory.squad_role[HOME] = 0
	memory.squad_state[HOME] = AiMemory.SquadState.HOME


func _repair(world: World, memory: AiMemory, repair: AiRepair) -> Array[Command]:
	memory.commands_left = 99
	_fill(world, memory)
	var out: Array[Command] = []
	repair.run(PlayerView.of(world, 1), memory, out)
	return out


func _launch_wave(memory: AiMemory, ids: PackedInt32Array, goal: Vector2i) -> void:
	for id: int in ids:
		memory.member_squad[memory.member_id.bsearch(id)] = WAVE
	memory.squad_role[WAVE] = 1
	memory.squad_state[WAVE] = AiMemory.SquadState.WAVE
	memory.squad_goal_x[WAVE] = goal.x
	memory.squad_goal_y[WAVE] = goal.y


func _production(medic_per: int) -> AiProduction:
	return AiProduction.create(_def(), _level(0, medic_per), 1)


func _queued(sent: Array[Command], world: World, id: String) -> int:
	var count: int = 0
	for command: Command in sent:
		if command.type == Command.Type.QUEUE and command.payload[0] == Worlds.type_of(world, id):
			count += 1
	return count


func _produce(production: AiProduction, world: World, memory: AiMemory) -> Array[Command]:
	memory.commands_left = 99
	var out: Array[Command] = []
	production.run(
		PlayerView.of(world, 1), memory, DetRandom.create(1, DetRandom.STREAM_AI_BASE + 1), out
	)
	return out


func _shed_id(world: World) -> int:
	var view: PlayerView = PlayerView.of(world, 1)
	for row: int in view.own_rows:
		if view.row_type(row) == Worlds.type_of(world, "shed"):
			return view.row_id(row)
	return NONE


func _economy_queues(world: World, retreat: int) -> Array[String]:
	var def: OpponentDef = _def()
	var order: AiBuildOrderDef = AiBuildOrderDef.new()
	order.steps = [&"factory"] as Array[StringName]
	def.build_orders = [order, order, order] as Array[AiBuildOrderDef]
	var economy: AiEconomy = AiEconomy.create(def, _level(retreat, 0), 1)
	var memory: AiMemory = _memory()
	var out: Array[Command] = []
	economy.run(PlayerView.of(world, 1), memory, DetRandom.create(1, 1), out)
	var found: Array[String] = []
	for command: Command in out:
		if command.type == Command.Type.QUEUE:
			found.append(String(world.type_ids[command.payload[0]]))
	return found


func _order_of(world: World, steps: Array[StringName]) -> Array[StringName]:
	var def: OpponentDef = _def()
	var order: AiBuildOrderDef = AiBuildOrderDef.new()
	order.steps = steps
	def.build_orders = [order, order, order] as Array[AiBuildOrderDef]
	var economy: AiEconomy = AiEconomy.create(def, _level(40, 0), 1)
	var view: PlayerView = PlayerView.of(world, 1)
	economy.run(view, _memory(), DetRandom.create(1, 1), [] as Array[Command])
	var ids: Array[StringName] = []
	for type: int in economy._order:
		ids.append(world.type_ids[type])
	return ids
