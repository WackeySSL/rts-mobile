extends GdUnitTestSuite
## Building repair of the opponent's economy manager (plan row P274, ADR 0037 section 4): `MEND`
## on for a complete own building under `mend_below_percent`, while the credits left after the
## think's queueing stay at the floor; off while they are under half the floor; nothing on Easy or
## for a site, a building at or above the threshold, or a building already mending; one Command per
## building, inside the think's budget, after the queueing; no enemy switch is read; every level
## file holds ranges the rule can use.

const Rig: GDScript = preload("res://tests/ai/support/opponent_rig.gd")
const AiRig: GDScript = preload("res://tests/ai/support/ai_rig.gd")
const FactionRig: GDScript = preload("res://tests/ai/support/faction_rig.gd")

const RICH: int = 100000


func test_a_damaged_building_is_mended_on_normal() -> void:
	var world: World = _world_with_damage(40)
	var sent: Array[Command] = _run(world, "normal")
	var mends: Array[Command] = _of_type(sent, Command.Type.MEND)
	assert_int(mends.size()).is_equal(1)
	assert_int(mends[0].target_id).is_equal(world.unit_id[_plant(world)])
	assert_array(mends[0].payload).is_equal(PackedInt32Array([1]))
	assert_int(mends[0].player_id).is_equal(1)


func test_hard_mends_what_normal_leaves() -> void:
	# 60 percent: above Normal's 50, under Hard's 70.
	var world: World = _world_with_damage(60)
	assert_int(_of_type(_run(world, "normal"), Command.Type.MEND).size()).is_equal(0)
	assert_int(_of_type(_run(world, "hard"), Command.Type.MEND).size()).is_equal(1)


func test_easy_never_mends() -> void:
	var world: World = _world_with_damage(1)
	assert_int(_of_type(_run(world, "easy"), Command.Type.MEND).size()).is_equal(0)


func test_the_threshold_is_exclusive_and_a_full_building_is_left_alone() -> void:
	var world: World = _world_with_damage(50)
	assert_int(_of_type(_run(world, "normal"), Command.Type.MEND).size()).is_equal(0)
	world = _world_with_damage(100)
	assert_int(_of_type(_run(world, "hard"), Command.Type.MEND).size()).is_equal(0)


func test_no_mend_below_the_floor_and_the_queueing_counts_against_it() -> void:
	var floor_credits: int = Rig.level_of("normal").mend_floor
	var world: World = _world_with_damage(40)
	world.credits[1] = floor_credits - 1
	assert_int(_of_type(_run(world, "normal"), Command.Type.MEND).size()).is_equal(0)
	# Exactly the floor, with nothing to queue (a build order of no steps): it mends.
	world.credits[1] = floor_credits
	var memory: AiMemory = AiMemory.create(Rig.def_of("fossil"))
	memory.commands_left = 99
	var def: OpponentDef = Rig.def_of("fossil").duplicate() as OpponentDef
	var empty: Array[AiBuildOrderDef] = [AiBuildOrderDef.new()]
	def.build_orders = empty
	var level: AiDifficultyDef = Rig.level_of("normal").duplicate() as AiDifficultyDef
	level.build_order_tier = 0
	level.harvesters_per_refinery = 0
	level.refineries_max = 0
	level.factories_max = 0
	level.defences_max = 0
	var out: Array[Command] = []
	AiEconomy.create(def, level, 1).run(
		PlayerView.of(world, 1), memory, DetRandom.create(1, DetRandom.STREAM_AI_BASE + 1), out
	)
	assert_int(_of_type(out, Command.Type.QUEUE).size()).is_equal(0)
	assert_int(_of_type(out, Command.Type.MEND).size()).is_equal(1)


func test_a_mending_building_is_switched_off_only_when_credits_are_under_half_the_floor() -> void:
	var floor_credits: int = Rig.level_of("normal").mend_floor
	var world: World = _world_with_damage(40)
	world.cargo[_plant(world)] = 1
	world.credits[1] = RICH
	assert_int(_of_type(_run(world, "normal"), Command.Type.MEND).size()).is_equal(0)
	# Between half the floor and the floor: no new switch on, and none off.
	world.credits[1] = floor_credits - 1
	assert_int(_of_type(_run(world, "normal"), Command.Type.MEND).size()).is_equal(0)
	world.credits[1] = floor_credits / 2 - 1
	var mends: Array[Command] = _of_type(_run(world, "normal"), Command.Type.MEND)
	assert_int(mends.size()).is_equal(1)
	assert_array(mends[0].payload).is_equal(PackedInt32Array([0]))


func test_a_building_site_is_not_mended() -> void:
	var world: World = _world_with_damage(40)
	world.build_left[_plant(world)] = 500
	assert_int(_of_type(_run(world, "normal"), Command.Type.MEND).size()).is_equal(0)


func test_mend_commands_use_the_think_budget_and_come_after_the_rest() -> void:
	var world: World = _world_with_damage(40)
	for at: int in 3:
		var row: int = world.index_of(AiRig.give(world, 1, "power_plant", 4 + at * 4, 24))
		world.hp[row] = world.type_max_hp[world.type_index[row]] / 4
	Power.run(world)
	var all: Array[Command] = _run(world, "normal")
	var mends: int = _of_type(all, Command.Type.MEND).size()
	assert_int(mends).is_equal(4)
	assert_int(all[all.size() - 1].type).is_equal(Command.Type.MEND)
	# A budget of one more than the other Commands leaves room for exactly one mend.
	var others: int = all.size() - mends
	var memory: AiMemory = AiMemory.create(Rig.def_of("fossil"))
	memory.commands_left = others + 1
	var out: Array[Command] = []
	AiEconomy.create(Rig.def_of("fossil"), Rig.level_of("normal"), 1).run(
		PlayerView.of(world, 1), memory, DetRandom.create(1, DetRandom.STREAM_AI_BASE + 1), out
	)
	assert_int(out.size()).is_equal(others + 1)
	assert_int(memory.commands_left).is_equal(0)


func test_the_enemys_switch_is_never_read() -> void:
	var world: World = _world_with_damage(100)
	var theirs: int = world.index_of(AiRig.give(world, 2, "power_plant", 60, 60))
	world.hp[theirs] = 1
	world.cargo[theirs] = 1
	assert_int(_of_type(_run(world, "hard"), Command.Type.MEND).size()).is_equal(0)


func test_the_sim_applies_the_command_and_the_building_mends_when_the_rules_allow() -> void:
	var world: World = _world_with_damage(40)
	world.mend_hp = 10
	world.mend_period_ticks = 15
	world.mend_cost_percent = 30
	var row: int = _plant(world)
	var before: int = world.hp[row]
	var loop: MatchLoop = AiRig.loop_of(world)
	var sent: Array[Command] = _of_type(_run(world, "normal"), Command.Type.MEND)
	for _tick: int in 30:
		AiRig.step(world, loop, sent)
		sent = []
	assert_int(world.cargo[row]).is_equal(1)
	assert_int(world.hp[row]).is_greater(before)


func test_the_level_files_hold_usable_mend_values() -> void:
	for level: String in Rig.LEVELS:
		var def: AiDifficultyDef = Rig.level_of(level)
		assert_int(def.mend_below_percent).is_between(0, 99)
		assert_int(def.mend_floor).is_between(0, 100000)
	assert_int(Rig.level_of("easy").mend_below_percent).is_equal(0)
	assert_int(Rig.level_of("normal").mend_below_percent).is_greater(0)
	assert_int(Rig.level_of("hard").mend_below_percent).is_greater_equal(
		Rig.level_of("normal").mend_below_percent
	)
	# The script defaults are off, so a def that names neither field (the frozen arena's) never mends.
	assert_int(AiDifficultyDef.new().mend_below_percent).is_equal(0)


func test_a_think_without_damage_costs_no_extra_pass() -> void:
	var world: World = _world_with_damage(100)
	var economy: AiEconomy = AiEconomy.create(Rig.def_of("fossil"), Rig.level_of("hard"), 1)
	var out: Array[Command] = []
	economy.run(
		PlayerView.of(world, 1),
		_open_memory(),
		DetRandom.create(1, DetRandom.STREAM_AI_BASE + 1),
		out
	)
	assert_int(economy.passes).is_equal(1)


## A start where player 1 owns a finished power plant at `percent` of its hit points.
func _world_with_damage(percent: int) -> World:
	var world: World = FactionRig.start("fossil", "renew")
	AiRig.explore_all(world)
	world.credits[1] = RICH
	var row: int = world.index_of(AiRig.give(world, 1, "power_plant", 10, 2))
	var top: int = world.type_max_hp[world.type_index[row]]
	world.hp[row] = top * percent / 100
	Power.run(world)
	return world


## The row of player 1's power plant.
func _plant(world: World) -> int:
	return AiRig.row_of(world, 1, "power_plant")


func _open_memory() -> AiMemory:
	var memory: AiMemory = AiMemory.create(Rig.def_of("fossil"))
	memory.commands_left = 99
	return memory


func _run(world: World, level: String) -> Array[Command]:
	var out: Array[Command] = []
	AiEconomy.create(Rig.def_of("fossil"), Rig.level_of(level), 1).run(
		PlayerView.of(world, 1),
		_open_memory(),
		DetRandom.create(1, DetRandom.STREAM_AI_BASE + 1),
		out
	)
	return out


func _of_type(sent: Array[Command], type: int) -> Array[Command]:
	var found: Array[Command] = []
	for command: Command in sent:
		if command.type == type:
			found.append(command)
	return found
