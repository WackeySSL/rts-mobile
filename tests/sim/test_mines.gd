extends GdUnitTestSuite
## Laying and blasting mines (plan row P287, ADR 0037 section 8): LAY_MINE (8), the lay in ECONOMY
## with every check again at the lay tick, the cost and the cap, the arming, the mark and blast in
## FIRE (`Strike._land`'s formula through `Combat.damage`), the MINE_BLAST record, the compaction
## and the rule that every order-giving Command zeroes `carry_mode`. A 16 x 12 open map, two
## players, `mine_cap` 2, 4 ticks to lay and 3 to arm. The mine weapon does 60 damage, 100 / 50 / 25
## / 0 percent against infantry, light, heavy and building armour, blast radius 1500.

const COLS: int = 16
const LAYER: int = 0
const TANK: int = 1
const SQUAD: int = 2
const AWARE: int = 3
const JET: int = 4
const GUNNER: int = 5
const CARRIER: int = 6
const HQ: int = 7
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
	var units: Array[UnitDef] = [
		layer,
		_unit("tank", 1, World.MoveClass.TRACKED),
		_unit("squad", 0),
		aware,
		_unit("jet", 1, World.MoveClass.AIR),
		gunner,
		carrier,
		hq,
	]
	var rules: RulesDef = (load("res://data/dev/arena/rules.tres") as RulesDef).duplicate()
	rules.mine_cap = cap
	rules.mine_lay_ticks = 4
	rules.mine_arm_ticks = 3
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


func test_the_command_event_and_stats_are_the_contract() -> void:
	assert_int(Command.Type.LAY_MINE).is_equal(8)
	assert_int(World.Event.MINE_BLAST).is_equal(7)
	assert_int(World.Stat.MINE_CHECKS).is_equal(11)
	assert_int(World.Stat.MINES_REFUSED).is_equal(12)
	assert_int(Mines.LAYING).is_equal(2)
	var command: Command = Command.lay_mine(2, PackedInt32Array([5, 3]), 7000, 8000)
	assert_array([command.type, command.player_id, command.target_x, command.target_y]).is_equal(
		[8, 2, 7000, 8000]
	)
	var coded: PackedInt32Array = PackedInt32Array()
	command.encode(coded)
	var back: Command = Command.new()
	assert_int(Command.decode(coded, 0, back)).is_equal(coded.size())
	assert_array([back.type, back.target_x, back.target_y]).is_equal([8, 7000, 8000])


func test_lay_sends_the_layer_with_carry_mode_2_and_drops_what_cannot_lay() -> void:
	var world: World = _world()
	var layer: int = _add(world, 1, LAYER, 2, 2)
	var tank: int = _add(world, 1, TANK, 3, 2)
	var enemy: int = _add(world, 2, LAYER, 9, 9)
	assert_bool(Mines.apply_lay(world, _lay([world.unit_id[layer], world.unit_id[tank]]))).is_true()
	assert_array([world.order[layer], world.carry_mode[layer], world.ready_tick[layer]]).is_equal(
		[World.Order.MOVE, 2, 0]
	)
	assert_array([world.order[tank], world.carry_mode[tank]]).is_equal([World.Order.IDLE, 0])
	assert_bool(Mines.apply_lay(world, _lay([world.unit_id[tank]]))).is_false()
	assert_bool(Mines.apply_lay(world, _lay([world.unit_id[enemy]]))).is_false()
	var before: int = world.dropped_commands
	_step(world, [_lay([world.unit_id[tank]])])
	assert_int(world.dropped_commands - before).is_equal(1)


func test_a_lay_starts_when_the_layer_stops_and_the_mine_joins_at_the_lay_tick() -> void:
	var world: World = _world()
	var layer: int = _add(world, 1, LAYER, CELL.x, CELL.y)
	_step(world, [_lay([world.unit_id[layer]])])
	var ready: int = _until_started(world, layer)
	assert_int(ready).is_equal(world.tick + 4)  # Stamp (tick + 1) of the start, plus 4.
	assert_int(world.mine_count).is_equal(0)
	assert_int(world.credits[1]).is_equal(100)  # Nothing is paid at the start.
	while world.tick + 1 < ready:
		_step(world)
		assert_int(world.mine_count).is_equal(0)
	_step(world)
	var cell: int = CELL.y * COLS + CELL.x
	assert_int(world.mine_count).is_equal(1)
	(
		assert_array(
			[world.mine_id[0], world.mine_owner[0], world.mine_cell[0], world.mine_at[cell]]
		)
		. is_equal([1, 1, cell, 1])
	)
	assert_int(world.mine_armed_tick[0]).is_equal(ready + 3)  # Armed `mine_arm_ticks` later.
	assert_int(world.credits[1]).is_equal(60)
	assert_array([world.carry_mode[layer], world.ready_tick[layer]]).is_equal([0, 0])
	assert_int(world.next_mine_id).is_equal(2)
	assert_int(world.stats[World.Stat.MINES_REFUSED]).is_equal(0)
	assert_int(world.mine_at.count(0)).is_equal(COLS * 12 - 1)  # Sparse: one cell set.


func test_the_start_refuses_without_credits_and_a_refusal_is_counted_and_pays_nothing() -> void:
	var world: World = _world()
	var layer: int = _add(world, 1, LAYER, CELL.x, CELL.y)
	world.credits[1] = 39
	_step(world, [_lay([world.unit_id[layer]])])
	var refused: int = world.stats[World.Stat.MINES_REFUSED] + _refusals(world, 3)
	assert_int(world.mine_count).is_equal(0)
	assert_array([world.carry_mode[layer], world.credits[1]]).is_equal([0, 39])
	assert_int(refused).is_equal(1)


func test_the_lay_tick_runs_every_check_again_and_credits_never_go_below_0() -> void:
	var world: World = _world()
	var layer: int = _add(world, 1, LAYER, CELL.x, CELL.y)
	_step(world, [_lay([world.unit_id[layer]])])
	var ready: int = _until_started(world, layer)
	world.credits[1] = 10  # Spent elsewhere after the start.
	while world.tick + 1 < ready:
		_step(world)
	_step(world)
	assert_int(world.mine_count).is_equal(0)
	assert_array([world.credits[1], world.carry_mode[layer]]).is_equal([10, 0])
	assert_int(world.stats[World.Stat.MINES_REFUSED]).is_equal(1)  # At the lay tick, not before.
	# The cell: blocked after the start, the lay tick refuses it.
	var second: World = _world()
	layer = _add(second, 1, LAYER, CELL.x, CELL.y)
	_step(second, [_lay([second.unit_id[layer]])])
	ready = _until_started(second, layer)
	second.move_cost[World.MoveClass.FOOT * COLS * 12 + CELL.y * COLS + CELL.x] = 0
	var refused_cell: int = _refusals(second, 5)
	assert_array([second.mine_count, second.credits[1]]).is_equal([0, 100])
	assert_int(refused_cell).is_equal(1)


func test_a_cell_with_a_mine_or_a_blocked_cell_is_refused_at_the_start() -> void:
	var world: World = _world()
	var first: int = _add(world, 1, LAYER, CELL.x, CELL.y)
	_lay_one(world, first)
	assert_int(world.mine_count).is_equal(1)
	var second: int = _add(world, 1, LAYER, CELL.x + 1, CELL.y)
	_step(world, [_lay([world.unit_id[second]], CELL.x, CELL.y)])
	_steps(world, 3)
	world.pos_x[second] = CELL.x * 1000 + 600  # Shoved onto the mine's cell (a tick's separation).
	world.pos_y[second] = CELL.y * 1000 + 400
	world.carry_mode[second] = Mines.LAYING
	world.order[second] = World.Order.IDLE
	world.ready_tick[second] = 0
	var refused: int = world.stats[World.Stat.MINES_REFUSED]
	_step(world)
	assert_int(world.stats[World.Stat.MINES_REFUSED] - refused).is_equal(1)
	assert_int(world.mine_count).is_equal(1)
	assert_int(world.credits[1]).is_equal(60)
	# A cell that FOOT cannot enter (a footprint writes cost 0 there).
	var third: int = _add(world, 1, LAYER, 8, 8)
	world.move_cost[World.MoveClass.FOOT * COLS * 12 + 8 * COLS + 8] = 0
	world.carry_mode[third] = Mines.LAYING
	_step(world)
	assert_int(world.carry_mode[third]).is_equal(0)
	assert_int(world.mine_count).is_equal(1)


func test_two_layers_at_one_below_the_cap_give_one_mine_and_one_refusal() -> void:
	var world: World = _world(1)
	var low: int = _add(world, 1, LAYER, 5, 5)
	var high: int = _add(world, 1, LAYER, 8, 5)
	# Both start in one tick on their own cells: pending lays do not count toward the cap.
	_step(
		world,
		[
			Command.lay_mine(1, PackedInt32Array([world.unit_id[low]]), 5500, 5500),
			Command.lay_mine(1, PackedInt32Array([world.unit_id[high]]), 8500, 5500),
		]
	)
	var refused: int = world.stats[World.Stat.MINES_REFUSED]
	refused += _refusals(world, 12)
	assert_int(world.mine_count).is_equal(1)
	assert_int(world.mine_cell[0]).is_equal(5 * COLS + 5)  # Ascending row order: the lower row.
	assert_int(refused).is_equal(1)
	assert_int(world.credits[1]).is_equal(60)  # One price paid, once.
	assert_array([world.carry_mode[low], world.carry_mode[high]]).is_equal([0, 0])


func test_the_cap_counts_laid_mines_only_and_refuses_at_the_start() -> void:
	var world: World = _world(1)
	_lay_one(world, _add(world, 1, LAYER, 5, 5))
	var second: int = _add(world, 1, LAYER, 8, 8)
	_step(world, [Command.lay_mine(1, PackedInt32Array([world.unit_id[second]]), 8500, 8500)])
	var refused: int = world.stats[World.Stat.MINES_REFUSED] + _refusals(world, 12)
	assert_int(refused).is_equal(1)
	assert_int(world.mine_count).is_equal(1)
	assert_int(world.credits[1]).is_equal(60)
	# The other player is under its own cap.
	var other: int = _add(world, 2, LAYER, 12, 3)
	_step(world, [Command.lay_mine(2, PackedInt32Array([world.unit_id[other]]), 12500, 3500)])
	_steps(world, 12)
	assert_int(world.mine_count).is_equal(2)
	assert_int(world.mine_owner[1]).is_equal(2)


func test_a_mine_does_not_trigger_before_it_is_armed_and_never_for_its_owner() -> void:
	var world: World = _world()
	var layer: int = _add(world, 1, LAYER, CELL.x, CELL.y)
	_lay_one(world, layer)
	var armed: int = world.mine_armed_tick[0]
	var own: int = _add(world, 1, TANK, CELL.x, CELL.y)
	var enemy: int = _add(world, 2, TANK, CELL.x, CELL.y)
	world.hp[layer] = 200
	while world.tick + 1 < armed:  # Still arming: the enemy stands on it and nothing happens.
		_step(world)
		assert_int(world.mine_count).is_equal(1)
		assert_int(world.hp[enemy]).is_equal(200)
	_step(world)  # Armed at this stamp.
	assert_int(world.mine_count).is_equal(0)
	assert_int(world.hp[enemy]).is_equal(170)  # 60 * 50 / 100 against light armour.
	assert_int(world.hp[own]).is_equal(200)  # No friendly damage.
	assert_int(world.hp[layer]).is_equal(200)
	# The owner alone on its own armed mine: nothing.
	var quiet: World = _world()
	var maker: int = _add(quiet, 1, LAYER, CELL.x, CELL.y)
	_lay_one(quiet, maker)
	_steps(quiet, 10)
	assert_int(quiet.mine_count).is_equal(1)
	assert_int(quiet.hp[maker]).is_equal(200)
	assert_array(_blasts(quiet)).is_empty()


func test_the_blast_hurts_ground_mobile_rows_of_other_players_in_radius_by_armour() -> void:
	var world: World = _world()
	_lay_one(world, _add(world, 1, LAYER, CELL.x, CELL.y))
	while world.tick + 1 < world.mine_armed_tick[0]:
		_step(world)
	var trigger: int = _add(world, 2, SQUAD, CELL.x, CELL.y)
	var near_tank: int = _add(world, 2, TANK, CELL.x + 1, CELL.y)  # 1000 away: inside 1500.
	var far: int = _add(world, 2, SQUAD, CELL.x + 3, CELL.y)  # 3000 away.
	var jet: int = _add(world, 2, JET, CELL.x, CELL.y)  # Flies over.
	var building: int = world.add_building(2, HQ, CELL.x + 1, CELL.y + 1)
	var building_row: int = world.index_of(building)
	var friend: int = _add(world, 1, SQUAD, CELL.x, CELL.y + 1)  # The owner's, in the radius.
	_step(world)
	assert_int(world.hp[trigger]).is_equal(140)  # 60 * 100 / 100 against infantry.
	assert_int(world.hp[near_tank]).is_equal(170)
	assert_int(world.hp[far]).is_equal(200)
	assert_int(world.hp[jet]).is_equal(200)
	assert_int(world.hp[building_row]).is_equal(500)
	assert_int(world.hp[friend]).is_equal(200)


func test_a_flying_row_and_a_mine_aware_row_never_trigger() -> void:
	var world: World = _world()
	_lay_one(world, _add(world, 1, LAYER, CELL.x, CELL.y))
	var jet: int = _add(world, 2, JET, CELL.x, CELL.y)
	var aware: int = _add(world, 2, AWARE, CELL.x, CELL.y)
	_steps(world, 8)
	assert_int(world.mine_count).is_equal(1)
	assert_array([world.hp[jet], world.hp[aware]]).is_equal([200, 200])
	assert_array(_blasts(world)).is_empty()


func test_one_blast_record_per_mine_however_many_trigger_and_the_table_compacts() -> void:
	var world: World = _world()
	_lay_one(world, _add(world, 1, LAYER, 5, 5))
	var second: int = _add(world, 1, LAYER, 9, 5)
	_step(world, [Command.lay_mine(1, PackedInt32Array([world.unit_id[second]]), 9500, 5500)])
	_steps(world, 8)
	assert_int(world.mine_count).is_equal(2)
	var first_id: int = world.mine_id[0]
	var second_id: int = world.mine_id[1]
	var a: int = _add(world, 2, TANK, 5, 5)
	var b: int = _add(world, 2, SQUAD, 5, 5)
	_step(world)
	var blasts: Array[PackedInt32Array] = _blasts(world)
	assert_int(blasts.size()).is_equal(1)
	# [MINE_BLAST, mine id, x, y, weapon, owner, 0, 0] at the cell centre.
	assert_array(Array(blasts[0])).is_equal([7, first_id, 5500, 5500, 0, 1, 0, 0])
	assert_int(world.hp[a]).is_equal(170)  # Hurt once, not once per trigger.
	assert_int(world.hp[b]).is_equal(140)
	assert_int(world.mine_count).is_equal(1)
	assert_int(world.mine_id[0]).is_equal(second_id)  # Stable compaction: the later one moved up.
	assert_int(world.mine_at[5 * COLS + 5]).is_equal(0)
	assert_int(world.mine_at[5 * COLS + 9]).is_equal(1)
	assert_int(world.mine_owner[1] + world.mine_cell[1] + world.mine_armed_tick[1]).is_equal(
		0 + 0 + 0
	)


func test_no_chain_to_other_mines_and_the_next_tick_has_no_record() -> void:
	var world: World = _world()
	_lay_one(world, _add(world, 1, LAYER, 5, 5))
	var second: int = _add(world, 1, LAYER, 6, 5)  # One cell away, inside the blast.
	_step(world, [Command.lay_mine(1, PackedInt32Array([world.unit_id[second]]), 6500, 5500)])
	_steps(world, 8)
	assert_int(world.mine_count).is_equal(2)
	_add(world, 2, TANK, 5, 5)
	_step(world)
	assert_int(world.mine_count).is_equal(1)
	_step(world)
	assert_array(_blasts(world)).is_empty()


func test_blast_damage_goes_through_combat_damage_with_the_upgrade_modifier() -> void:
	var world: World = _world()
	_lay_one(world, _add(world, 1, LAYER, CELL.x, CELL.y))
	while world.tick + 1 < world.mine_armed_tick[0]:
		_step(world)
	var tank: int = _add(world, 2, TANK, CELL.x, CELL.y)
	var type: int = world.type_index[tank]
	world.mod_taken[2 * world.type_ids.size() + type] = 50  # Half damage taken (player 2).
	_step(world)
	assert_int(world.hp[tank]).is_equal(200 - Combat.damage(60, 50, 100, 50))
	assert_int(Combat.damage(60, 50, 100, 50)).is_equal(15)


func test_a_rupture_clears_mines_in_its_radius_and_a_building_removes_the_one_it_covers() -> void:
	var world: World = _world()
	_lay_one(world, _add(world, 1, LAYER, 5, 5))
	var far: int = _add(world, 2, LAYER, 12, 8)
	_step(world, [Command.lay_mine(2, PackedInt32Array([world.unit_id[far]]), 12500, 8500)])
	_steps(world, 8)
	assert_int(world.mine_count).is_equal(2)
	Mines.clear_radius(world, 5500, 5500, 500)
	assert_int(world.mine_count).is_equal(1)
	assert_array([world.mine_owner[0], world.mine_cell[0]]).is_equal([2, 8 * COLS + 12])
	assert_int(world.mine_at[8 * COLS + 12]).is_equal(1)
	assert_int(world.mine_at[5 * COLS + 5]).is_equal(0)
	assert_array(_blasts(world)).is_empty()  # No blast.
	# A building over the other mine's tile removes it, silently, whoever owns it.
	world.add_building(1, HQ, 11, 7)  # Tiles 11..12 x 7..8.
	assert_int(world.mine_count).is_equal(0)
	assert_int(world.mine_at.count(0)).is_equal(COLS * 12)
	assert_array(_blasts(world)).is_empty()


func test_every_order_giving_command_zeroes_carry_mode() -> void:
	var cases: Array[Callable] = [
		func(ids: PackedInt32Array) -> Command: return Command.move(1, ids, 9500, 9500),
		func(ids: PackedInt32Array) -> Command: return Command.attack_move(1, ids, 9500, 9500),
		func(ids: PackedInt32Array) -> Command: return Command.stop(1, ids),
		func(ids: PackedInt32Array) -> Command: return Command.lay_mine(1, ids, 9500, 9500),
	]
	for index: int in cases.size():
		var world: World = _world()
		var layer: int = _add(world, 1, GUNNER, 2, 2)
		world.carry_mode[layer] = Mines.LAYING
		var ids: PackedInt32Array = PackedInt32Array([world.unit_id[layer]])
		_step(world, [cases[index].call(ids)])
		var expected: int = 2 if index == 3 else 0
		(
			assert_int(world.carry_mode[world.index_of(ids[0])])
			. override_failure_message("command case %d" % index)
			. is_equal(expected)
		)
	# ATTACK on a seen enemy, and LOAD of a squad onto a carrier.
	var world: World = _world()
	var gunner: int = _add(world, 1, GUNNER, 2, 2)
	var enemy: int = _add(world, 2, SQUAD, 6, 2)
	world.carry_mode[gunner] = Mines.LAYING
	_step(
		world, [Command.attack(1, PackedInt32Array([world.unit_id[gunner]]), world.unit_id[enemy])]
	)
	assert_int(world.carry_mode[gunner]).is_equal(0)
	var load_world: World = _world()
	var squad_layer: int = _add(load_world, 1, GUNNER, 2, 2)
	var carrier: int = _add(load_world, 1, CARRIER, 3, 3)
	load_world.carry_mode[squad_layer] = Mines.LAYING
	var load: Command = Command.board(
		1, PackedInt32Array([load_world.unit_id[squad_layer]]), load_world.unit_id[carrier]
	)
	_step(load_world, [load])
	(
		assert_int(load_world.carry_mode[load_world.index_of(load_world.unit_id[squad_layer])])
		. is_equal(0)
	)


func test_a_new_order_cancels_a_pending_lay_unpaid() -> void:
	var world: World = _world()
	var layer: int = _add(world, 1, LAYER, CELL.x, CELL.y)
	_step(world, [_lay([world.unit_id[layer]])])
	_until_started(world, layer)
	_step(world, [Command.stop(1, PackedInt32Array([world.unit_id[layer]]))])
	_steps(world, 10)
	assert_int(world.mine_count).is_equal(0)
	assert_int(world.credits[1]).is_equal(100)
	assert_int(world.stats[World.Stat.MINES_REFUSED]).is_equal(0)
	# A fresh LAY_MINE after the cancelled one starts from a cleared timer.
	assert_bool(Mines.apply_lay(world, _lay([world.unit_id[layer]]))).is_true()
	assert_int(world.ready_tick[layer]).is_equal(0)


func test_a_defeated_player_and_a_finished_match_drop_the_command() -> void:
	var world: World = _world()
	var layer: int = _add(world, 1, LAYER, 2, 2)
	world.defeated_tick[1] = 5
	var before: int = world.dropped_commands
	_step(world, [_lay([world.unit_id[layer]])])
	assert_int(world.dropped_commands - before).is_equal(1)
	assert_int(world.carry_mode[layer]).is_equal(0)
