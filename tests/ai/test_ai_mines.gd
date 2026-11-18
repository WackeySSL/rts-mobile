extends "res://tests/ai/support/support_suite.gd"
## The mine manager (plan row P295, ADR 0037 section 8): it lays on the own half of the route,
## sweeps a known mine before a wave, sends a scout layer ahead on Hard, builds its layer, and does
## nothing on Easy, on a def with no layer type or on the frozen copies. The rig's World is its own:
## a 40 x 24 map, the Headquarters of player 1 at (2, 2) and of player 2 at (36, 20) (the route is
## 34 tiles, so its own half ends 17 tiles out), a vehicle factory and a radar (the layer's
## requirement) of player 1 and one layer.

const Smoke: GDScript = preload("res://tests/smoke/smoke_run.gd")
const MATCH_TICKS: int = 6000
const COLS: int = 40
const LINES: int = 24
const HOME_TILE: Vector2i = Vector2i(3, 3)
const BASE_TILE: Vector2i = Vector2i(37, 21)


func test_a_layer_lays_target_mines_on_the_own_half_of_the_route_spaced_apart() -> void:
	var fixture: Array = _fixture()
	var world: World = fixture[0]
	var memory: AiMemory = fixture[1]
	var loop: MatchLoop = AiRig.loop_of(world)
	var miner: AiMines = AiMines.create(_mine_def(), _mine_level(3, 1, 0))
	_add(world, "layer", 5500, 3500)
	var sent: Array[Command] = _play(world, loop, memory, miner, 30)
	assert_int(world.mine_count).is_equal(3)
	assert_int(miner.lays).is_equal(3)
	var cells: Array[Vector2i] = []
	for at: int in world.mine_count:
		assert_int(world.mine_owner[at]).is_equal(1)
		cells.append(Vector2i(world.mine_cell[at] % COLS, world.mine_cell[at] / COLS))
	for cell: Vector2i in cells:
		# On the line from the Headquarters to the base, no further than half way.
		assert_bool(absi(cell.x - HOME_TILE.x) <= (BASE_TILE.x - HOME_TILE.x) / 2).is_true()
		assert_int(absi((cell.y - HOME_TILE.y) * 34 - (cell.x - HOME_TILE.x) * 18)).is_less(40)
	assert_int(cells[1].x - cells[0].x).is_equal(4)
	assert_int(cells[2].x - cells[1].x).is_equal(4)
	var lay_commands: int = 0
	for command: Command in sent:
		lay_commands += 1 if command.type == Command.Type.LAY_MINE else 0
		assert_bool(command.type in [Command.Type.LAY_MINE, Command.Type.QUEUE]).is_true()
	assert_int(lay_commands).is_equal(3)
	# At the target it lays no more, and the price of three mines was paid.
	assert_array(_play(world, loop, memory, miner, 6)).is_empty()
	assert_int(world.credits[1]).is_equal(100000 - 3 * 60)


func test_a_cell_that_left_no_mine_is_not_tried_again() -> void:
	var fixture: Array = _fixture()
	var world: World = fixture[0]
	var memory: AiMemory = fixture[1]
	var loop: MatchLoop = AiRig.loop_of(world)
	var miner: AiMines = AiMines.create(_mine_def(), _mine_level(2, 1, 0))
	_add(world, "layer", 5500, 3500)
	# A mine of the enemy on the first cell of the route: the sim refuses a second one there (and the
	# layer, which finds it, clears it), so the cell stays empty and is not asked for again.
	_put(world, 2, Vector2i(7, 5))
	_play(world, loop, memory, miner, 30)
	assert_int(miner.lays).is_equal(3)
	assert_int(world.mine_count).is_equal(2)
	for at: int in world.mine_count:
		assert_int(world.mine_owner[at]).is_equal(1)
		assert_int(world.mine_cell[at]).is_not_equal(5 * COLS + 7)


func test_a_known_enemy_mine_on_the_route_is_swept_before_a_wave_leaves() -> void:
	var fixture: Array = _fixture()
	var world: World = fixture[0]
	var memory: AiMemory = fixture[1]
	var loop: MatchLoop = AiRig.loop_of(world)
	var miner: AiMines = AiMines.create(_mine_def(), _mine_level(1, 1, 0))
	var layer: int = _add(world, "layer", 5500, 3500)
	_put(world, 2, Vector2i(11, 6))
	_record(world, 1, 2, Vector2i(11, 6))
	# Another one, far from the route: not swept.
	_put(world, 2, Vector2i(30, 3))
	_record(world, 1, 2, Vector2i(30, 3))
	var out: Array[Command] = _think(world, memory, miner)
	assert_int(out.size()).is_equal(1)
	assert_int(out[0].type).is_equal(Command.Type.MOVE)
	assert_array(out[0].unit_ids).is_equal(PackedInt32Array([layer]))
	assert_int(out[0].target_x).is_equal(11500)
	assert_int(out[0].target_y).is_equal(6500)
	assert_int(miner.sweeps).is_equal(1)
	AiRig.step(world, loop, out)
	# The sim clears it: the layer walks there, stands, and the mine leaves the table.
	_play(world, loop, memory, miner, 30)
	assert_int(world.mine_count).is_equal(2)  # The far one stays, and the own mine is laid.
	for at: int in world.mine_count:
		assert_bool(world.mine_cell[at] == 6 * COLS + 11).is_false()
	assert_int(miner.sweeps).is_equal(1)


func test_no_sweep_while_a_wave_is_in_the_field() -> void:
	var fixture: Array = _fixture()
	var world: World = fixture[0]
	var memory: AiMemory = fixture[1]
	var miner: AiMines = AiMines.create(_mine_def(), _mine_level(1, 1, 0))
	var layer: int = _add(world, "layer", 5500, 3500)
	_put(world, 2, Vector2i(11, 6))
	_record(world, 1, 2, Vector2i(11, 6))
	memory.squad_role[WAVE] = 1
	memory.squad_state[WAVE] = AiMemory.SquadState.WAVE
	var out: Array[Command] = _think(world, memory, miner)
	assert_int(out.size()).is_equal(1)
	assert_int(out[0].type).is_equal(Command.Type.LAY_MINE)
	assert_array(out[0].unit_ids).is_equal(PackedInt32Array([layer]))
	assert_int(miner.sweeps).is_equal(0)


func test_hard_sends_the_layer_ahead_past_the_own_half_and_normal_does_not() -> void:
	for scout: int in [0, 1]:
		var fixture: Array = _fixture()
		var world: World = fixture[0]
		var memory: AiMemory = fixture[1]
		var miner: AiMines = AiMines.create(_mine_def(), _mine_level(1, 1, scout))
		var layer: int = _add(world, "layer", 5500, 3500)
		_put(world, 1, Vector2i(7, 4))  # The target is met: no lay is due.
		var out: Array[Command] = _think(world, memory, miner)
		if scout == 0:
			assert_array(out).is_empty()
			continue
		assert_int(out.size()).is_equal(1)
		assert_int(out[0].type).is_equal(Command.Type.MOVE)
		assert_array(out[0].unit_ids).is_equal(PackedInt32Array([layer]))
		# Half of 34 and a leg of 8 along: 25 tiles out, at (3 + 25, 3 + 25 * 18 / 34).
		assert_int(out[0].target_x).is_equal(28500)
		assert_int(out[0].target_y).is_equal(16500)
		assert_int(miner.legs).is_equal(1)
		# The leg went as far as three quarters of this short route: no second one, not while the
		# layer moves and not when it stands there.
		var loop: MatchLoop = AiRig.loop_of(world)
		AiRig.step(world, loop, out)
		assert_array(_think(world, memory, miner)).is_empty()
		world.order[world.index_of(layer)] = World.Order.IDLE
		assert_array(_think(world, memory, miner)).is_empty()
		assert_int(miner.legs).is_equal(1)


func test_easy_a_def_without_a_layer_and_the_frozen_copies_do_nothing() -> void:
	var cases: Array = [
		[_mine_def(), load("res://data/ai/difficulty/easy.tres")],
		[_def(), _mine_level(4, 1, 1)],
		[_mine_def(), _mine_level(0, 1, 1)],
		[_mine_def(), _mine_level(4, 0, 1)],
	]
	for level: String in ["easy", "normal", "hard"]:
		var frozen: OpponentDef = load("res://data/dev/arena/ai_4b/opponent_fossil.tres")
		cases.append([frozen, load("res://data/dev/arena/ai_4b/difficulty/%s.tres" % level)])
	for case: Array in cases:
		var fixture: Array = _fixture()
		var world: World = fixture[0]
		var memory: AiMemory = fixture[1]
		_add(world, "layer", 5500, 3500)
		var miner: AiMines = AiMines.create(case[0], case[1])
		assert_array(_think(world, memory, miner)).is_empty()
		assert_int(miner.lays + miner.sweeps + miner.legs + miner.queued).is_equal(0)


func test_the_shipped_levels_and_factions_turn_it_on_for_normal_and_hard_only() -> void:
	var expected: Dictionary[String, Array] = {
		"easy": [0, 0, 0], "normal": [4, 1, 0], "hard": [8, 2, 1]
	}
	for level: String in expected:
		var shipped: AiDifficultyDef = load("res://data/ai/difficulty/%s.tres" % level)
		assert_array([shipped.mine_target, shipped.mine_layers, shipped.mine_scout_ahead]).is_equal(
			expected[level]
		)
		var frozen: AiDifficultyDef = load("res://data/dev/arena/ai_4b/difficulty/%s.tres" % level)
		assert_array([frozen.mine_target, frozen.mine_layers, frozen.mine_scout_ahead]).is_equal(
			[0, 0, 0]
		)
	(
		assert_str(
			String((load("res://data/ai/opponent_fossil.tres") as OpponentDef).mine_layer_type)
		)
		. is_equal("fossil_shot_truck")
	)
	(
		assert_str(
			String((load("res://data/ai/opponent_renew.tres") as OpponentDef).mine_layer_type)
		)
		. is_equal("renew_seeder")
	)
	var ai: OpponentAi = OpponentAi.create(
		_mine_def(), _mine_level(1, 1, 0), 1, DetRandom.create(1, DetRandom.STREAM_AI_BASE + 1)
	)
	assert_object(ai.miner).is_not_null()


func test_a_layer_is_queued_when_the_factory_and_radar_stand_and_not_otherwise() -> void:
	var fixture: Array = _fixture()
	var world: World = fixture[0]
	var memory: AiMemory = fixture[1]
	var miner: AiMines = AiMines.create(_mine_def(), _mine_level(2, 1, 0))
	var out: Array[Command] = _think(world, memory, miner)
	assert_int(out.size()).is_equal(1)
	assert_int(out[0].type).is_equal(Command.Type.QUEUE)
	assert_int(out[0].payload[0]).is_equal(Worlds.type_of(world, "layer"))
	assert_int(miner.queued).is_equal(1)
	# Queued already: not a second one. A layer alive: none either.
	AiRig.step(world, AiRig.loop_of(world), out)
	assert_array(_think(world, memory, miner)).is_empty()
	# No radar: nothing queues.
	var bare: Array = _fixture(false)
	(
		assert_array(_think(bare[0], bare[1], AiMines.create(_mine_def(), _mine_level(2, 1, 0))))
		. is_empty()
	)
	# Too poor for the layer and a mine.
	var poor: Array = _fixture()
	poor[0].credits[1] = 200
	(
		assert_array(_think(poor[0], poor[1], AiMines.create(_mine_def(), _mine_level(2, 1, 0))))
		. is_empty()
	)


func test_a_think_without_commands_left_sends_nothing_and_keeps_the_layer_free() -> void:
	var fixture: Array = _fixture()
	var world: World = fixture[0]
	var memory: AiMemory = fixture[1]
	var miner: AiMines = AiMines.create(_mine_def(), _mine_level(1, 1, 0))
	_add(world, "layer", 5500, 3500)
	_fill(world, memory)
	memory.commands_left = 0
	var out: Array[Command] = []
	miner.run(PlayerView.of(world, 1), memory, out)
	assert_array(out).is_empty()
	assert_int(_think(world, memory, miner).size()).is_equal(1)


func test_the_layer_goal_key_is_held_only_while_the_layer_moves() -> void:
	var fixture: Array = _fixture()
	var world: World = fixture[0]
	var memory: AiMemory = fixture[1]
	var loop: MatchLoop = AiRig.loop_of(world)
	var miner: AiMines = AiMines.create(_mine_def(), _mine_level(1, 1, 0))
	_add(world, "layer", 5500, 3500)
	AiRig.step(world, loop, _think(world, memory, miner))
	assert_int(memory.goal_keys_of(AiMemory.Owner.MINE)).is_equal(1)
	assert_int(memory.goal_class[0]).is_equal(AiMemory.WHEELED)
	_play(world, loop, memory, miner, 6)
	assert_int(memory.goal_keys_of(AiMemory.Owner.MINE)).is_equal(0)
	# A full cache that the army holds gives the layer no key, and it sends nothing.
	var full: Array = _fixture()
	var crowded: AiMemory = full[1]
	for at: int in crowded.goal_keys_max:
		crowded.add_goal_key(30 + at, 20, AiMemory.TRACKED, AiMemory.Owner.ARMY)
	_add(full[0], "layer", 5500, 3500)
	(
		assert_array(_think(full[0], crowded, AiMines.create(_mine_def(), _mine_level(1, 1, 0))))
		. is_empty()
	)


func test_the_same_matches_twice_lay_the_same_mines_on_the_thread_snapshot_path() -> void:
	var first: Dictionary = _match()
	var second: Dictionary = _match()
	assert_int(first["laid"]).is_greater(0)
	assert_dict(second).is_equal(first)


## An AI-vs-AI Normal match from one seed on the lagged pipeline (`AiDriver.lagged_tick`, the one
## the worker runs: the views are built before the step and the Commands land a tick later): the
## mines laid over the match and the state hash.
func _match() -> Dictionary:
	var levels: Array[String] = ["normal", "normal"]
	var setup: Dictionary = Smoke.start(1, "cross", levels)
	var world: World = setup["world"]
	Smoke.run(world, setup["loop"], setup["controllers"], MATCH_TICKS)
	return {"laid": world.next_mine_id, "hash": WorldHash.state_hash(world)}


func _fixture(radar: bool = true) -> Array:
	var world: World = _mine_world(radar)
	var memory: AiMemory = _memory()
	memory.home_x = HOME_TILE.x
	memory.home_y = HOME_TILE.y
	memory.base_x = BASE_TILE.x
	memory.base_y = BASE_TILE.y
	return [world, memory]


func _mine_world(radar: bool) -> World:
	var weapon: WeaponDef = WeaponDef.new()
	weapon.id = &"test_mine"
	weapon.damage = 60
	weapon.vs_armour = PackedInt32Array([100, 50, 25, 0])
	weapon.blast_milli = 1500
	var radar_def: BuildingDef = _building("radar", NONE, Vector2i(2, 2), 500)
	var layer: UnitDef = _unit("layer", World.Tab.VEHICLES, false, 200)
	layer.move_class = World.MoveClass.WHEELED
	layer.mine_weapon = weapon
	layer.mine_cost = 60
	layer.mine_aware = true
	layer.detect_milli = 3000
	layer.requires = radar_def
	var units: Array[UnitDef] = [
		_building("hq", World.Tab.STRUCTURES, Vector2i(3, 3), 0),
		_building("factory", World.Tab.VEHICLES, Vector2i(3, 3), 800),
		radar_def,
		layer,
	]
	var made: World = Rig.world_of(units, COLS, LINES, true, 2, "res://data/rules.tres")
	made.add_building(1, Worlds.type_of(made, "hq"), 2, 2)
	made.add_building(1, Worlds.type_of(made, "factory"), 8, 1)
	if radar:
		made.add_building(1, Worlds.type_of(made, "radar"), 12, 1)
	made.add_building(2, Worlds.type_of(made, "hq"), 36, 20)
	made.credits[1] = 100000
	return made


func _mine_def() -> OpponentDef:
	var def: OpponentDef = _def()
	def.mine_layer_type = &"layer"
	return def


func _mine_level(target: int, layers: int, scout: int) -> AiDifficultyDef:
	var level: AiDifficultyDef = AiDifficultyDef.new()
	level.mine_target = target
	level.mine_layers = layers
	level.mine_scout_ahead = scout
	return level


func _think(world: World, memory: AiMemory, miner: AiMines) -> Array[Command]:
	memory.commands_left = 99
	_fill(world, memory)
	var out: Array[Command] = []
	miner.run(PlayerView.of(world, 1), memory, out)
	return out


## `thinks` thinks one second apart, each followed by the fifteen ticks the sim runs; returns every
## Command sent.
func _play(
	world: World, loop: MatchLoop, memory: AiMemory, miner: AiMines, thinks: int
) -> Array[Command]:
	var all: Array[Command] = []
	for _think_at: int in thinks:
		var sent: Array[Command] = _think(world, memory, miner)
		all.append_array(sent)
		AiRig.step(world, loop, sent)
		for _tick: int in 14:
			AiRig.step(world, loop)
	return all


## A mine of `owner` on `cell` in the table.
func _put(world: World, owner: int, cell: Vector2i) -> void:
	for column_name: StringName in World.MINE_ARRAYS:
		var column: PackedInt32Array = world.get(column_name)
		column.resize(maxi(column.size(), world.mine_count + 1))
	var at: int = world.mine_count
	world.mine_id[at] = world.next_mine_id
	world.mine_owner[at] = owner
	world.mine_cell[at] = cell.y * COLS + cell.x
	world.mine_weapon[at] = world.type_mine_weapon[Worlds.type_of(world, "layer")]
	world.mine_armed_tick[at] = 1
	world.mine_at[cell.y * COLS + cell.x] = at + 1
	world.next_mine_id += 1
	world.mine_count += 1


## A record of the mine of `owner` on `cell` in player `player`'s block, as `MineMemory` writes it.
func _record(world: World, player: int, owner: int, cell: Vector2i) -> void:
	var at: int = player * world.mine_known_cap + world.mine_seen_count[player]
	world.mine_seen_id[at] = world.mine_id[world.mine_at[cell.y * COLS + cell.x] - 1]
	world.mine_seen_owner[at] = owner
	world.mine_seen_cell[at] = cell.y * COLS + cell.x
	world.mine_seen_count[player] += 1
