extends "res://tests/ai/support/production_suite.gd"
## The opponent's production manager, the scout and the match (plan row P178, ADR 0030 section 6):
## the scout of `scout_wanted` (ahead of the draw, one a think, counted toward the queue, held for
## credits on its own tab, none once one waits or lives), the economy's QUEUEs of the same think,
## and one Normal match of two `OpponentAi`s for the scout and "no Command is dropped".

const NoArmy: GDScript = preload("res://tests/ai/support/no_army.gd")

## The first tick of a Normal match (seed 1, fossil against renew) at which player 1's scout moves:
## the economy takes the whole income for the build order, production's first QUEUE is at 4,275.
const SCOUT_MOVE_TICK: int = 4555
const MATCH_TICKS: int = 5400

# --- The scout ---------------------------------------------------------------------------------


func test_a_wanted_scout_is_queued_ahead_of_the_draw_and_counts_toward_the_queue() -> void:
	var world: World = _world(RICH, true)
	var memory: AiMemory = _memory("fossil")
	memory.scout_wanted = AiRig.type_of(world, "light_tank")
	var production: AiProduction = _production("fossil", "normal")
	var sent: Array[Command] = _run(production, memory, world, true)
	var ids: Array[String] = _ids(sent, world)
	assert_str(ids[0]).is_equal("light_tank")
	assert_int(ids.count("light_tank")).is_equal(1)
	assert_int(production.scouts_queued).is_equal(1)
	# The vehicle tab has queue_target places: the scout takes one, so one more vehicle at most.
	var target: int = _def().queue_target
	assert_int(_in_tab(sent, world, World.Tab.VEHICLES)).is_equal(target)
	assert_int(sent.size()).is_equal(2 * target)


func test_a_queued_scout_with_the_field_still_set_gets_no_second_scout() -> void:
	var world: World = _world(RICH, true)
	var memory: AiMemory = _memory("fossil")
	var scout: int = AiRig.type_of(world, "light_tank")
	memory.scout_wanted = scout
	var loop: MatchLoop = AiRig.loop_of(world)
	var production: AiProduction = _production("fossil", "normal")
	AiRig.step(world, loop, _run(production, memory, world))
	# The scout is in the vehicle queue and the field is still set (it does not live yet).
	assert_int(production.scouts_queued).is_equal(1)
	for _think: int in 5:
		var sent: Array[Command] = _run(production, memory, world)
		assert_int(_ids(sent, world).count("light_tank")).is_equal(0)
		AiRig.step(world, loop, sent)
	assert_int(production.scouts_queued).is_equal(1)
	assert_int(production.queued).is_greater(1)


func test_a_scout_that_cannot_be_paid_yet_closes_its_tab_only_and_goes_when_paid() -> void:
	var world: World = _world(0, true)
	var memory: AiMemory = _memory("fossil")
	memory.scout_wanted = AiRig.type_of(world, "light_tank")
	var cost: int = _cost(world, "light_tank")
	world.credits[1] = cost - 1
	var production: AiProduction = _production("fossil", "normal")
	# The vehicle tab waits for the scout (no tank is drawn); the infantry draw goes on.
	var sent: Array[Command] = _run(production, memory, world)
	assert_int(sent.size()).is_equal(_def().queue_target)
	assert_int(_in_tab(sent, world, World.Tab.INFANTRY)).is_equal(sent.size())
	world.credits[1] = cost
	assert_str(_ids(_run(production, memory, world), world)[0]).is_equal("light_tank")
	# A scout the credits fall short of (a heavy tank stands in) closes the vehicle tab even to a
	# cheaper vehicle (the artillery) that the credits could pay; no barracks, so only the artillery
	# could be drawn.
	var bare: World = _world(0, true)
	AiRig.kill(bare, AiRig.loop_of(bare), AiRig.row_of(bare, 1, "barracks"))
	assert_bool(_cost(bare, "artillery") < _cost(bare, "heavy_tank")).is_true()
	var dear: AiMemory = _memory("fossil")
	dear.scout_wanted = AiRig.type_of(bare, "heavy_tank")
	bare.credits[1] = _cost(bare, "artillery")
	assert_array(_run(_production("fossil", "normal"), dear, bare)).is_empty()
	dear.scout_wanted = NONE
	assert_array(_ids(_run(_production("fossil", "normal"), dear, bare), bare)).is_equal(
		["artillery"]
	)
	# The reserve is respected for the scout as for any unit.
	memory.reserve_credits = 1
	(
		assert_int(
			_ids(_run(_production("fossil", "normal"), memory, world), world).count("light_tank")
		)
		. is_equal(0)
	)


func test_a_scout_is_not_queued_without_a_factory_and_the_draw_goes_on() -> void:
	var world: World = _world(RICH, true)
	AiRig.kill(world, AiRig.loop_of(world), AiRig.row_of(world, 1, "vehicle_factory"))
	var memory: AiMemory = _memory("fossil")
	memory.scout_wanted = AiRig.type_of(world, "light_tank")
	var production: AiProduction = _production("fossil", "normal")
	var sent: Array[Command] = _run(production, memory, world)
	assert_int(production.scouts_queued).is_equal(0)
	assert_int(sent.size()).is_equal(_def().queue_target)
	for id: String in _ids(sent, world):
		assert_array(["rifle_squad", "rocket_squad"]).contains([id])


func test_a_scout_waiting_in_a_queue_with_room_left_gets_no_second_scout() -> void:
	var world: World = _world(RICH, true)
	var memory: AiMemory = _memory("fossil")
	var scout: int = AiRig.type_of(world, "light_tank")
	memory.scout_wanted = scout
	# One scout waits in the vehicle queue (room for one more): the field is still set, so
	# no second scout is queued, and the draw fills the room with a role's unit.
	var queue: int = World.TABS + World.Tab.VEHICLES
	world.queue_type[queue * world.queue_slots] = scout
	world.queue_count[queue] = 1
	var production: AiProduction = _production("fossil", "normal")
	var sent: Array[Command] = _run(production, memory, world)
	assert_int(_ids(sent, world).count("light_tank")).is_equal(0)
	assert_int(production.scouts_queued).is_equal(0)
	assert_int(_in_tab(sent, world, World.Tab.VEHICLES)).is_equal(_def().queue_target - 1)


func test_a_living_scout_with_the_field_still_set_gets_no_second_scout() -> void:
	var world: World = _world(RICH, true)
	AiRig.add_unit_of(world, 1, "light_tank", 8500, 8500)
	var memory: AiMemory = _memory("fossil")
	memory.scout_wanted = AiRig.type_of(world, "light_tank")
	var production: AiProduction = _production("fossil", "normal")
	var sent: Array[Command] = _run(production, memory, world)
	assert_int(_ids(sent, world).count("light_tank")).is_equal(0)
	assert_int(production.scouts_queued).is_equal(0)
	assert_int(sent.size()).is_equal(2 * _def().queue_target)


func test_a_scout_finishing_between_two_thinks_gets_no_second_scout_in_any_phase() -> void:
	# Intel clears the field in its own slot; production reads a stale one for up to 5 ticks. A
	# light tank waits at the vehicle head `phase` ticks short of done, and production runs every
	# tick over the spawn with the field kept set.
	var scout: int = -1
	for phase: int in 15:
		var world: World = _world(RICH, true)
		scout = AiRig.type_of(world, "light_tank")
		var queue: int = World.TABS + World.Tab.VEHICLES
		world.queue_type[queue * world.queue_slots] = scout
		world.queue_count[queue] = 1
		world.queue_progress[queue] = (
			(world.type_build_ticks[scout] - phase) * Production.PROGRESS_PER_TICK
		)
		var memory: AiMemory = _memory("fossil")
		memory.scout_wanted = scout
		var production: AiProduction = _production("fossil", "normal")
		var loop: MatchLoop = AiRig.loop_of(world)
		for _tick: int in phase + 30:
			var sent: Array[Command] = _run(production, memory, world)
			AiRig.step(world, loop, sent)
		(
			assert_int(production.scouts_queued)
			. override_failure_message("phase %d queued a second scout" % phase)
			. is_equal(0)
		)
		assert_int(AiRig.count_of(world, 1, "light_tank")).is_equal(1)


func test_the_economys_queues_of_the_same_think_count_toward_the_room_and_the_cap() -> void:
	# A refinery without a tanker: the economy queues tankers in this think, from the same view.
	var def: OpponentDef = _def()
	for spare: int in [0, 1, 2, 3]:
		var world: World = _world(RICH, true)
		AiRig.give(world, 1, "refinery", 10, 10)
		Power.run(world)
		var units: int = AiRig.count_of(world, 1, "rifle_squad")
		world.unit_cap = units + 2 + spare
		var memory: AiMemory = _memory("fossil")
		var out: Array[Command] = []
		var view: PlayerView = PlayerView.of(world, 1)
		AiEconomy.create(def, _level("normal"), 1).run(view, memory, _stream(), out)
		_production("fossil", "normal").run(view, memory, _stream(), out)
		AiRig.step(world, AiRig.loop_of(world), out)
		var vehicles: int = world.queue_count[World.TABS + World.Tab.VEHICLES]
		var mobile: int = units + vehicles + world.queue_count[World.TABS + World.Tab.INFANTRY]
		assert_int(vehicles).is_less_equal(def.queue_target)
		assert_int(world.queue_count[World.TABS + World.Tab.INFANTRY]).is_less_equal(
			def.queue_target
		)
		assert_int(mobile).is_less_equal(world.unit_cap)
		assert_array([world.dropped_commands, world.spawn_refused]).is_equal([0, 0])


func test_a_queue_with_fewer_slots_than_the_target_is_filled_to_its_slots() -> void:
	var world: World = _world(RICH, true)
	world.queue_slots = 1
	var sent: Array[Command] = _run(_production("fossil", "normal"), _memory("fossil"), world)
	assert_int(sent.size()).is_equal(2)
	assert_int(_in_tab(sent, world, World.Tab.INFANTRY)).is_equal(1)
	assert_int(_in_tab(sent, world, World.Tab.VEHICLES)).is_equal(1)


func test_no_scout_is_queued_when_the_field_is_none_or_a_structure() -> void:
	var world: World = _world(RICH, true)
	var memory: AiMemory = _memory("fossil")
	var production: AiProduction = _production("fossil", "normal")
	assert_int(_ids(_run(production, memory, world), world).count("light_tank")).is_equal(0)
	memory.scout_wanted = AiRig.type_of(world, "barracks")
	assert_int(_ids(_run(production, memory, world), world).count("barracks")).is_equal(0)
	memory.scout_wanted = 9999
	assert_int(_run(production, memory, world).size()).is_equal(2 * _def().queue_target)
	assert_int(production.scouts_queued).is_equal(0)


# --- Matches -----------------------------------------------------------------------------------


func test_a_normal_match_scouts_once_and_the_sim_drops_nothing() -> void:
	var world: World = FactionRig.start("fossil", "renew")
	Power.run(world)
	var loop: MatchLoop = AiRig.loop_of(world)
	var controllers: Array = []
	for at: int in 2:
		# Without the army, so the scout's tick is the economy's, production's and intel's alone.
		var ai: Variant = NoArmy.new()
		ai.copy_from(Rig.opponent(Rig.FACTIONS[at], "normal", at + 1, 1))
		controllers.append(ai)
	var first_scout: int = NONE
	var kinds: Dictionary[int, bool] = {}
	for _tick: int in MATCH_TICKS:
		var tick: int = world.tick
		var sent: Array[Command] = AiRig.tick(world, loop, controllers)
		if first_scout == NONE and (controllers[0] as OpponentAi).scouts == 1:
			first_scout = tick
		for command: Command in sent:
			if (
				command.type == Command.Type.QUEUE
				and world.type_tab[command.payload[0]] != World.Tab.STRUCTURES
			):
				kinds[command.payload[0]] = true
	assert_array([world.dropped_commands, world.spawn_refused]).is_equal([0, 0])
	for controller: OpponentAi in controllers:
		assert_int(controller.commands_cut).is_equal(0)
		assert_int(controller.work_max).is_less_equal(3)
		assert_int(controller.production.queued).is_greater(5)
	assert_int((controllers[0] as OpponentAi).scouts).is_equal(1)
	assert_int((controllers[0] as OpponentAi).production.scouts_queued).is_equal(1)
	assert_int(first_scout).is_equal(SCOUT_MOVE_TICK)
	assert_int(kinds.size()).is_greater(3)
