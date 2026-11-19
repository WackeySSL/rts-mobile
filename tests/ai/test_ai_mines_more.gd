extends "res://tests/ai/support/mine_rig.gd"
## The mine manager (plan row P295, ADR 0037 section 8), part 2: keys, production, the walk back.


func test_no_mine_is_laid_past_the_own_half_whatever_the_target() -> void:
	var fixture: Array = _fixture()
	var world: World = fixture[0]
	var memory: AiMemory = fixture[1]
	world.mine_cap = 12
	var miner: AiMines = AiMines.create(_mine_def(), _mine_level(12, 1, 0))
	_add(world, "layer", 5500, 3500)
	_play(world, AiRig.loop_of(world), memory, miner, 40)
	# 34 tiles of route, 4 apart, its own half 17: four cells, not eight.
	assert_int(world.mine_count).is_equal(4)
	for at: int in world.mine_count:
		assert_bool(world.mine_cell[at] % COLS - HOME_TILE.x <= 17).is_true()


func test_two_layers_count_each_others_pending_lays() -> void:
	var fixture: Array = _fixture()
	var world: World = fixture[0]
	var memory: AiMemory = fixture[1]
	var miner: AiMines = AiMines.create(_mine_def(), _mine_level(2, 2, 0))
	var first: int = _add(world, "layer", 5500, 3500)
	var second: int = _add(world, "layer", 6500, 3500)
	var loop: MatchLoop = AiRig.loop_of(world)
	var one: Array[Command] = _think(world, memory, miner)
	AiRig.step(world, loop, one)
	var two: Array[Command] = _think(world, memory, miner)
	AiRig.step(world, loop, two)
	assert_int(one.size() + two.size()).is_equal(2)
	assert_array(one[0].unit_ids).is_equal(PackedInt32Array([first]))
	assert_array(two[0].unit_ids).is_equal(PackedInt32Array([second]))
	assert_int(one[0].target_x).is_not_equal(two[0].target_x)
	# Both lays are on their way: nothing more is due, and each moving layer holds a key.
	assert_array(_think(world, memory, miner)).is_empty()
	assert_int(memory.goal_keys_of(AiMemory.Owner.MINE)).is_equal(2)


func test_the_scout_waits_while_a_wave_is_in_the_field() -> void:
	var fixture: Array = _fixture()
	var world: World = fixture[0]
	var memory: AiMemory = fixture[1]
	var miner: AiMines = AiMines.create(_mine_def(), _mine_level(1, 1, 1))
	_add(world, "layer", 5500, 3500)
	_put(world, 1, Vector2i(7, 4))
	memory.squad_role[WAVE] = 1
	memory.squad_state[WAVE] = AiMemory.SquadState.WAVE
	assert_array(_think(world, memory, miner)).is_empty()
	memory.squad_state[WAVE] = AiMemory.SquadState.HOME
	assert_int(_think(world, memory, miner).size()).is_equal(1)


func test_the_mine_key_is_the_last_to_yield_and_the_army_holds_a_wheeled_goal() -> void:
	var memory: AiMemory = _memory()
	memory.goal_keys_max = 3
	memory.add_goal_key(1, 1, AiMemory.TRACKED, AiMemory.Owner.MINE)
	memory.add_goal_key(2, 2, AiMemory.TRACKED, AiMemory.Owner.REPAIR)
	memory.add_goal_key(3, 3, AiMemory.TRACKED, AiMemory.Owner.SCOUT)
	memory.yield_keys()
	assert_int(memory.goal_keys_of(AiMemory.Owner.SCOUT)).is_equal(0)
	assert_int(memory.goal_keys_of(AiMemory.Owner.MINE)).is_equal(1)
	assert_int(memory.goal_keys_of(AiMemory.Owner.REPAIR)).is_equal(1)
	var army: AiArmy = AiArmy.create(_def(), AiDifficultyDef.new(), 1)
	var held: AiMemory = _memory()
	(
		assert_bool(army._hold(held, AiMemory.Owner.ARMY, Vector2i(9, 9), 1 << AiMemory.WHEELED))
		. is_true()
	)
	assert_int(held.goal_class[0]).is_equal(AiMemory.WHEELED)


func test_a_type_that_is_no_layer_does_nothing_and_a_zero_cap_turns_it_off() -> void:
	# A mobile unarmed type with no mine weapon, a building with one, and a type the roster lacks.
	for id: String in ["hauler", "depot", "no_such_type"]:
		var fixture: Array = _fixture()
		var def: OpponentDef = _mine_def()
		def.mine_layer_type = StringName(id)
		_add(fixture[0], "layer", 5500, 3500)
		var miner: AiMines = AiMines.create(def, _mine_level(2, 1, 1))
		assert_array(_think(fixture[0], fixture[1], miner)).is_empty()
	var capped: Array = _fixture()
	capped[0].mine_cap = 0
	_add(capped[0], "layer", 5500, 3500)
	(
		assert_array(
			_think(capped[0], capped[1], AiMines.create(_mine_def(), _mine_level(2, 1, 1)))
		)
		. is_empty()
	)
	# An armed layer type is no layer: `AiArmy` would order it too.
	var armed: Array = _fixture()
	armed[0].type_weapon[Worlds.type_of(armed[0], "layer")] = 0
	_add(armed[0], "layer", 5500, 3500)
	(
		assert_array(_think(armed[0], armed[1], AiMines.create(_mine_def(), _mine_level(2, 1, 1))))
		. is_empty()
	)


func test_production_queues_the_layer_like_the_medic() -> void:
	var fixture: Array = _fixture()
	var world: World = fixture[0]
	var memory: AiMemory = fixture[1]
	var production: AiProduction = _layer_production(_mine_def())
	var sent: Array[Command] = _produce(production, world, memory)
	assert_int(_queued(sent, world, "layer")).is_equal(1)
	assert_int(production.layers_queued).is_equal(1)
	# Queued already: not a second one, nor while alive.
	AiRig.step(world, AiRig.loop_of(world), sent)
	assert_int(_queued(_produce(production, world, memory), world, "layer")).is_equal(0)
	# Credits the economy reserved are not spent on it.
	var reserved: Array = _fixture()
	reserved[1].reserve_credits = 100000
	(
		assert_int(
			_queued(
				_produce(_layer_production(_mine_def()), reserved[0], reserved[1]),
				reserved[0],
				"layer"
			)
		)
		. is_equal(0)
	)
	# No radar (the requirement): none. No room in the queue: none.
	var bare: Array = _fixture(false)
	(
		assert_int(
			_queued(_produce(_layer_production(_mine_def()), bare[0], bare[1]), bare[0], "layer")
		)
		. is_equal(0)
	)
	var full: Array = _fixture()
	var def: OpponentDef = _mine_def()
	def.queue_target = 0
	(
		assert_int(_queued(_produce(_layer_production(def), full[0], full[1]), full[0], "layer"))
		. is_equal(0)
	)


func test_the_unit_cap_counts_the_queued_units_for_the_layer() -> void:
	var fixture: Array = _fixture()
	var world: World = fixture[0]
	world.unit_cap = 1
	# Two layers wanted, so only the unit cap can stop the second: the first waits in the queue.
	var production: AiProduction = _layer_production(_mine_def(), 2)
	var first: Array[Command] = _produce(production, world, fixture[1])
	assert_int(_queued(first, world, "layer")).is_equal(1)
	AiRig.step(world, AiRig.loop_of(world), first)
	assert_int(_queued(_produce(production, world, fixture[1]), world, "layer")).is_equal(0)
	world.unit_cap = 5
	assert_int(_queued(_produce(production, world, fixture[1]), world, "layer")).is_equal(1)


func test_a_zero_mine_cap_queues_no_layer() -> void:
	var fixture: Array = _fixture()
	fixture[0].mine_cap = 0
	var sent: Array[Command] = _produce(_layer_production(_mine_def()), fixture[0], fixture[1])
	assert_int(_queued(sent, fixture[0], "layer")).is_equal(0)


func test_a_blocked_midpoint_gets_one_way_back_a_lull_not_one_every_other_think() -> void:
	var fixture: Array = _fixture()
	var world: World = fixture[0]
	var memory: AiMemory = fixture[1]
	var miner: AiMines = AiMines.create(_mine_def(), _mine_level(1, 1, 1))
	_add(world, "layer", 5500, 3500)
	_put(world, 1, Vector2i(7, 4))
	# A building on the edge of the own half (20, 12): the layer cannot stand on it.
	world.add_building(2, Worlds.type_of(world, "radar"), 20, 12)
	var moves: int = 0
	for command: Command in _play(world, AiRig.loop_of(world), memory, miner, 90):
		moves += 1 if command.type == Command.Type.MOVE else 0
	assert_int(moves).is_less_equal(2)


func test_the_legs_start_again_after_a_wave_even_while_the_layer_is_free() -> void:
	var fixture: Array = _fixture()
	var world: World = fixture[0]
	var memory: AiMemory = fixture[1]
	var miner: AiMines = AiMines.create(_mine_def(), _mine_level(1, 1, 1))
	var layer: int = _add(world, "layer", 5500, 3500)
	_put(world, 1, Vector2i(7, 4))
	var first: Array[Command] = _think(world, memory, miner)
	assert_int(first[0].target_x).is_equal(28500)
	AiRig.step(world, AiRig.loop_of(world), first)
	world.order[world.index_of(layer)] = World.Order.IDLE
	world.pos_x[world.index_of(layer)] = 28500
	world.pos_y[world.index_of(layer)] = 16500
	memory.squad_role[WAVE] = 1
	memory.squad_state[WAVE] = AiMemory.SquadState.WAVE
	assert_array(_think(world, memory, miner)).is_empty()
	memory.squad_state[WAVE] = AiMemory.SquadState.HOME
	var again: Array[Command] = _think(world, memory, miner)
	assert_int(again.size()).is_equal(1)
	assert_int(again[0].target_x).is_equal(28500)


func test_a_lay_refused_for_credits_does_not_block_its_cell() -> void:
	var fixture: Array = _fixture()
	var world: World = fixture[0]
	var memory: AiMemory = fixture[1]
	var loop: MatchLoop = AiRig.loop_of(world)
	var miner: AiMines = AiMines.create(_mine_def(), _mine_level(1, 1, 0))
	_add(world, "layer", 5500, 3500)
	var order: Array[Command] = _think(world, memory, miner)
	assert_int(order.size()).is_equal(1)
	AiRig.step(world, loop, order)
	world.credits[1] = 0
	_play(world, loop, memory, miner, 12)
	assert_int(world.mine_count).is_equal(0)
	assert_int(miner._blocked.size()).is_equal(0)


func test_the_blocked_cells_are_forgotten_when_the_route_moves() -> void:
	var fixture: Array = _fixture()
	var world: World = fixture[0]
	var memory: AiMemory = fixture[1]
	var miner: AiMines = AiMines.create(_mine_def(), _mine_level(1, 1, 0))
	_add(world, "layer", 5500, 3500)
	_put(world, 1, Vector2i(7, 5))  # The target is met: nothing is ordered.
	_think(world, memory, miner)
	miner._blocked = PackedInt32Array([207])
	_think(world, memory, miner)
	assert_int(miner._blocked.size()).is_equal(1)
	memory.base_x -= 2
	_think(world, memory, miner)
	assert_int(miner._blocked.size()).is_equal(0)
