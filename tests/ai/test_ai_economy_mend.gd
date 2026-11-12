extends GdUnitTestSuite
## Building repair of the opponent's economy manager (plan row P274, ADR 0037 section 4): `MEND` on
## for a complete own building under `mend_below_percent` percent of its hp while the credits left
## after the think's spending (`credits - reserve_credits - production's spend`) are strictly above
## `mend_floor`; a building of price 0 goes on whatever they are; the AI never switches off. The
## Commands come after production's, from the budget it left. The tests play their own level values
## (`PERCENT`, `FLOOR`), not the shipped ones, so a retune cannot move a boundary under them.

const Rig: GDScript = preload("res://tests/ai/support/opponent_rig.gd")
const AiRig: GDScript = preload("res://tests/ai/support/ai_rig.gd")
const FactionRig: GDScript = preload("res://tests/ai/support/faction_rig.gd")

const RICH: int = 100000
const PERCENT: int = 40
const FLOOR: int = 300


func test_a_damaged_building_is_mended() -> void:
	var world: World = _world_with_plant(RICH)
	var plant: int = _plant(world)
	world.hp[plant] = _below(world, plant)
	var mends: Array[Command] = _mends(_think(world, _level(PERCENT, FLOOR)).out)
	assert_int(mends.size()).is_equal(1)
	assert_int(mends[0].target_id).is_equal(world.unit_id[plant])
	assert_array(mends[0].payload).is_equal(PackedInt32Array([1]))
	assert_int(mends[0].player_id).is_equal(1)


func test_the_threshold_is_exclusive() -> void:
	var world: World = _world_with_plant(RICH)
	var plant: int = _plant(world)
	var top: int = world.type_max_hp[world.type_index[plant]]
	assert_int(top * PERCENT % 100).is_equal(0)
	world.hp[plant] = top * PERCENT / 100
	assert_int(_mends(_think(world, _level(PERCENT, FLOOR)).out).size()).is_equal(0)
	world.hp[plant] = top * PERCENT / 100 - 1
	assert_int(_mends(_think(world, _level(PERCENT, FLOOR)).out).size()).is_equal(1)


func test_a_hundred_percent_mends_any_damage_but_not_a_full_building() -> void:
	var world: World = _world_with_plant(RICH)
	var plant: int = _plant(world)
	var top: int = world.type_max_hp[world.type_index[plant]]
	world.hp[plant] = top
	assert_int(_mends(_think(world, _level(100, FLOOR)).out).size()).is_equal(0)
	world.hp[plant] = top - 1
	assert_int(_mends(_think(world, _level(100, FLOOR)).out).size()).is_equal(1)


func test_a_level_of_percent_0_never_mends_even_at_1_hp() -> void:
	var world: World = _world_with_plant(RICH)
	world.hp[_plant(world)] = 1
	assert_int(_mends(_think(world, _level(0, 0)).out).size()).is_equal(0)
	assert_int(_mends(_think(world, Rig.level_of("easy")).out).size()).is_equal(0)


func test_the_floor_is_strict_and_what_was_queued_counts_against_it() -> void:
	var def: OpponentDef = _def_with_steps(["power_plant", "power_plant"])
	var level: AiDifficultyDef = _bare_level(PERCENT, FLOOR)
	var world: World = _world_with_plant(0)
	var plant: int = _plant(world)
	world.hp[plant] = _below(world, plant)
	var price: int = world.type_cost[AiRig.type_of(world, "power_plant")]
	assert_int(price).is_greater(0)
	# After the QUEUE of the second plant the credits left are `credits - price`: at the floor itself
	# nothing is above it, one more and the building goes on.
	world.credits[1] = FLOOR + price
	var held: Dictionary = _think(world, level, def)
	assert_int(_of_type(held.out, Command.Type.QUEUE).size()).is_equal(1)
	assert_int(_mends(held.out).size()).is_equal(0)
	world.credits[1] = FLOOR + price + 1
	var free: Dictionary = _think(world, level, def)
	assert_int(_of_type(free.out, Command.Type.QUEUE).size()).is_equal(1)
	assert_int(_mends(free.out).size()).is_equal(1)


func test_the_credits_production_spent_count_against_the_floor() -> void:
	var world: World = _world_with_plant(FLOOR + 50)
	var plant: int = _plant(world)
	world.hp[plant] = _below(world, plant)
	var level: AiDifficultyDef = _bare_level(PERCENT, FLOOR)
	var def: OpponentDef = _def_with_steps(["power_plant"])
	assert_int(_mends(_think(world, level, def, 99, 49).out).size()).is_equal(1)
	assert_int(_mends(_think(world, level, def, 99, 50).out).size()).is_equal(0)


func test_the_headquarters_mends_free_whatever_the_credits() -> void:
	var world: World = _world_with_plant(0)
	var hq: int = AiRig.row_of(world, 1, "headquarters")
	assert_int(world.type_cost[world.type_index[hq]]).is_equal(0)
	world.hp[hq] = _below(world, hq)
	var plant: int = _plant(world)
	world.hp[plant] = _below(world, plant)
	var mends: Array[Command] = _mends(_think(world, _level(PERCENT, FLOOR)).out)
	assert_int(mends.size()).is_equal(1)
	assert_int(mends[0].target_id).is_equal(world.unit_id[hq])


func test_an_applied_switch_is_not_sent_again_and_the_ai_never_switches_off() -> void:
	var world: World = _world_with_plant(0)
	var plant: int = _plant(world)
	world.hp[plant] = _below(world, plant)
	world.cargo[plant] = 1
	for credits: int in [0, FLOOR / 2, FLOOR, RICH]:
		world.credits[1] = credits
		assert_int(_mends(_think(world, _level(PERCENT, FLOOR)).out).size()).is_equal(0)


func test_a_building_site_is_not_mended() -> void:
	var world: World = _world_with_plant(RICH)
	var plant: int = _plant(world)
	world.hp[plant] = _below(world, plant)
	world.build_left[plant] = 500
	assert_int(_mends(_think(world, _level(PERCENT, FLOOR)).out).size()).is_equal(0)


func test_a_budget_of_one_sends_one_mend_for_the_lower_id() -> void:
	var world: World = _world_with_plant(RICH)
	var second: int = world.index_of(AiRig.give(world, 1, "power_plant", 4, 24))
	for row: int in [_plant(world), second]:
		world.hp[row] = _below(world, row)
	var think: Dictionary = _think(
		world, _bare_level(PERCENT, FLOOR), _def_with_steps(["power_plant"]), 1, 0
	)
	var mends: Array[Command] = _mends(think.out)
	assert_int(mends.size()).is_equal(1)
	assert_int(think.memory.commands_left).is_equal(0)
	var ids: Array[int] = [world.unit_id[_plant(world)], world.unit_id[second]]
	ids.sort()
	assert_int(mends[0].target_id).is_equal(ids[0])


func test_the_enemys_switch_and_health_are_never_read() -> void:
	var world: World = _world_with_plant(RICH)
	var loop: MatchLoop = AiRig.loop_of(world)
	var near: int = world.index_of(AiRig.give(world, 2, "power_plant", 10, 6))
	AiRig.settle(world, loop)
	var view: PlayerView = PlayerView.of(world, 1)
	assert_int(view.row_of(world.unit_id[near])).is_greater_equal(0)
	world.credits[1] = RICH
	var counts: Array[int] = []
	for switch: int in 2:
		world.hp[near] = 1
		world.cargo[near] = switch
		var out: Array[Command] = _think(world, _level(PERCENT, FLOOR)).out
		for command: Command in out:
			assert_int(command.target_id).is_not_equal(world.unit_id[near])
		counts.append(out.size())
	assert_int(counts[1]).is_equal(counts[0])


func test_mends_use_only_the_budget_production_left() -> void:
	var level: AiDifficultyDef = _level(PERCENT, FLOOR)
	var clean: Dictionary = _opponent_think(_world_of_five(false), level)
	var others: int = clean.out.size()
	assert_int(others).is_greater(0)
	# The barracks gives production something to queue, so the order of the calls is pinned.
	assert_int(clean.ai.production.queued).is_greater(0)
	assert_int(_mends(clean.out).size()).is_equal(0)
	# Room for two more Commands: production's QUEUEs are the clean run's, the mends are the two.
	level.commands_per_think_max = others + 2
	var hurt: Dictionary = _opponent_think(_world_of_five(true), level)
	assert_int(_mends(hurt.out).size()).is_equal(2)
	assert_array(_queue_types(hurt.out)).is_equal(_queue_types(clean.out))
	assert_int(hurt.out.size()).is_equal(others + 2)
	assert_int(hurt.ai.commands_cut).is_equal(0)
	# With the full budget of Normal the five buildings may take what production left, no more.
	level.commands_per_think_max = 8
	var wide: Dictionary = _opponent_think(_world_of_five(true), level)
	assert_array(_queue_types(wide.out)).is_equal(_queue_types(clean.out))
	assert_int(wide.ai.commands_cut).is_equal(0)


func test_a_base_with_no_producer_left_still_mends() -> void:
	var world: World = _world_with_plant(RICH)
	var plant: int = _plant(world)
	var loop: MatchLoop = AiRig.loop_of(world)
	AiRig.kill(world, loop, AiRig.row_of(world, 1, "headquarters"))
	assert_int(AiRig.row_of(world, 1, "headquarters")).is_equal(-1)
	var plant_row: int = AiRig.row_of(world, 1, "power_plant")
	assert_int(plant_row).is_greater_equal(0)
	world.hp[plant_row] = _below(world, plant_row)
	var out: Array[Command] = _opponent_think(world, _level(PERCENT, FLOOR)).out
	assert_int(_mends(out).size()).is_equal(1)


func test_the_sim_applies_the_command_and_the_building_mends_when_the_rules_allow() -> void:
	var world: World = _world_with_plant(RICH)
	world.mend_hp = 10
	world.mend_period_ticks = 15
	world.mend_cost_percent = 30
	var plant: int = _plant(world)
	var start: int = _below(world, plant)
	world.hp[plant] = start
	var credits: int = world.credits[1]
	var loop: MatchLoop = AiRig.loop_of(world)
	var sent: Array[Command] = _mends(_think(world, _level(PERCENT, FLOOR)).out)
	assert_int(sent.size()).is_equal(1)
	# The id of the plant, found again: the loop may reorder nothing, but the row is not assumed.
	var id: int = sent[0].target_id
	for _tick: int in 30:
		AiRig.step(world, loop, sent)
		sent = []
	var row: int = world.index_of(id)
	assert_int(world.cargo[row]).is_equal(1)
	# Two periods in 30 ticks: staggered by id, so one or two steps of mend_hp.
	var gained: int = world.hp[row] - start
	assert_bool(gained == 10 or gained == 20).override_failure_message(str(gained)).is_true()
	assert_int(world.credits[1]).is_less(credits)


func test_a_think_without_damage_sends_no_mend_and_the_same_commands() -> void:
	var world: World = _world_with_plant(RICH)
	var off: Dictionary = _think(world, _level(0, 0))
	var on: Dictionary = _think(world, _level(100, FLOOR))
	assert_int(_mends(on.out).size()).is_equal(0)
	assert_int(on.out.size()).is_equal(off.out.size())


func test_the_level_files_hold_usable_mend_values() -> void:
	for level: String in Rig.LEVELS:
		var def: AiDifficultyDef = Rig.level_of(level)
		(
			assert_bool(_in_range(def.mend_below_percent, def.mend_floor))
			. override_failure_message(
				(
					"%s: mend_below_percent %d, mend_floor %d"
					% [level, def.mend_below_percent, def.mend_floor]
				)
			)
			. is_true()
		)
	assert_int(Rig.level_of("easy").mend_below_percent).is_equal(0)
	assert_int(Rig.level_of("normal").mend_below_percent).is_greater(0)
	assert_int(Rig.level_of("hard").mend_below_percent).is_greater(0)


## The range rule itself, on edge values of both sides.
func test_the_range_rule_accepts_the_edges_and_rejects_beyond() -> void:
	for ok: Array in [[0, 0], [100, 0], [1, 1], [50, 100000]]:
		assert_bool(_in_range(ok[0], ok[1])).is_true()
	for bad: Array in [[-1, 0], [101, 0], [50, -1]]:
		assert_bool(_in_range(bad[0], bad[1])).is_false()


func _in_range(percent: int, floor_credits: int) -> bool:
	return percent >= 0 and percent <= 100 and floor_credits >= 0


## A start where player 1 owns a finished power plant, with `credits`; the fog explored.
func _world_with_plant(credits: int) -> World:
	var world: World = FactionRig.start("fossil", "renew")
	AiRig.explore_all(world)
	world.credits[1] = credits
	AiRig.give(world, 1, "power_plant", 10, 2)
	Power.run(world)
	return world


## Five damaged buildings of player 1 (or the same five whole), rich, for the OpponentAi tests.
func _world_of_five(hurt: bool) -> World:
	var world: World = _world_with_plant(RICH)
	for at: int in 4:
		AiRig.give(world, 1, "power_plant", 4 + at * 4, 24)
	AiRig.give(world, 1, "barracks", 20, 10)
	for row: int in world.unit_count():
		if world.owner[row] == 1 and world.type_foot_w[world.type_index[row]] > 0:
			if hurt and world.type_cost[world.type_index[row]] > 0:
				world.hp[row] = _below(world, row)
	Power.run(world)
	return world


## A hit point count under the test's threshold for the row.
func _below(world: World, row: int) -> int:
	return world.type_max_hp[world.type_index[row]] * PERCENT / 100 - 1


func _plant(world: World) -> int:
	return AiRig.row_of(world, 1, "power_plant")


## Normal's file with the test's own mend values.
func _level(percent: int, floor_credits: int) -> AiDifficultyDef:
	var level: AiDifficultyDef = Rig.level_of("normal").duplicate() as AiDifficultyDef
	level.mend_below_percent = percent
	level.mend_floor = floor_credits
	return level


## A level that queues nothing by itself: no tankers, no loop; the def's steps alone decide.
func _bare_level(percent: int, floor_credits: int) -> AiDifficultyDef:
	var level: AiDifficultyDef = _level(percent, floor_credits)
	level.harvesters_per_refinery = 0
	level.refineries_max = 0
	level.factories_max = 0
	level.defences_max = 0
	return level


func _def_with_steps(steps: Array) -> OpponentDef:
	var def: OpponentDef = Rig.def_of("fossil").duplicate() as OpponentDef
	var order: AiBuildOrderDef = AiBuildOrderDef.new()
	for id: String in steps:
		order.steps.append(StringName(id))
	var orders: Array[AiBuildOrderDef] = [order, order, order]
	def.build_orders = orders
	return def


## One economy run and the mend call on one view of `world` for player 1 (`limit` Commands; the
## memory is returned in `memory`). `production_spent` is what production would have queued.
func _think(
	world: World,
	level: AiDifficultyDef,
	def: OpponentDef = null,
	limit: int = 99,
	production_spent: int = 0,
) -> Dictionary:
	var used: OpponentDef = def if def != null else Rig.def_of("fossil")
	var economy: AiEconomy = AiEconomy.create(used, level, 1)
	var memory: AiMemory = AiMemory.create(used)
	memory.commands_left = limit
	var view: PlayerView = PlayerView.of(world, 1)
	var out: Array[Command] = []
	economy.run(view, memory, DetRandom.create(1, DetRandom.STREAM_AI_BASE + 1), out)
	economy.mend(view, memory, out, production_spent)
	return {"out": out, "memory": memory}


## One ECONOMY-slot think of a real `OpponentAi` (economy, production, then mend).
func _opponent_think(world: World, level: AiDifficultyDef) -> Dictionary:
	var stream: DetRandom = DetRandom.create(1, DetRandom.STREAM_AI_BASE + 1)
	var ai: OpponentAi = OpponentAi.create(Rig.def_of("fossil"), level, 1, stream)
	var view: PlayerView = PlayerView.of(world, 1)
	view.tick = 0
	while ai.slot_of(view.tick) != OpponentAi.Slot.ECONOMY:
		view.tick += 1
	var out: Array[Command] = []
	ai.think(view, out)
	return {"out": out, "ai": ai}


func _queue_types(sent: Array[Command]) -> Array[int]:
	var found: Array[int] = []
	for command: Command in sent:
		if command.type == Command.Type.QUEUE:
			found.append(command.payload[0])
	return found


func _mends(sent: Array[Command]) -> Array[Command]:
	return _of_type(sent, Command.Type.MEND)


func _of_type(sent: Array[Command], type: int) -> Array[Command]:
	var found: Array[Command] = []
	for command: Command in sent:
		if command.type == type:
			found.append(command)
	return found
