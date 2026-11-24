extends GdUnitTestSuite
## P580: a PLACE the opponent's economy sends is checked against the view at tick T and applied at
## T+1 (ADR 0038 section 1). A mobile unit that steps onto the footprint in the lag tick makes the
## sim refuse it (`Placement.Reason.OCCUPIED`): the stale drop that Hard's matches showed. The
## economy now asks `PlayerView.placement` with `COMMAND_LAG_TICKS`, so a slot a unit can reach in
## the lag tick is left for the next one. The case is crafted: a harvester stands one half step
## outside the first slot's footprint and walks onto it.

const Rig: GDScript = preload("res://tests/ai/support/opponent_rig.gd")
const AiRig: GDScript = preload("res://tests/ai/support/ai_rig.gd")
const FactionRig: GDScript = preload("res://tests/ai/support/faction_rig.gd")

const RICH: int = 100000
const HEAD: String = "power_plant"
const MOVER: String = "harvester"
const THINKS: int = 20


func test_a_slot_a_unit_reaches_in_the_lag_tick_is_not_placed_and_nothing_is_dropped() -> void:
	var first: Array[int] = _tile_of(_place(_world(false)))
	var world: World = _world(true)
	var loop: MatchLoop = AiRig.loop_of(world)
	var view: PlayerView = PlayerView.of(world, 1)
	var head: int = AiRig.type_of(world, HEAD)
	# The case is crafted right: the slot is free now and taken one tick later.
	assert_int(view.placement(head, first[0], first[1])).is_equal(Placement.Reason.OK)
	assert_int(view.placement(head, first[0], first[1], PlayerView.COMMAND_LAG_TICKS)).is_equal(
		Placement.Reason.OCCUPIED
	)
	var place: Command = _place(world)
	assert_object(place).is_not_null()
	assert_array(_tile_of(place)).is_not_equal(first)
	var chosen: Array[int] = _tile_of(place)
	assert_int(view.placement(head, chosen[0], chosen[1], PlayerView.COMMAND_LAG_TICKS)).is_equal(
		Placement.Reason.OK
	)
	# The view of tick T is taken; step T (the lag tick) runs; the Command lands in step T+1.
	AiRig.step(world, loop)
	AiRig.step(world, loop, [place])
	assert_int(world.dropped_commands).is_equal(0)
	assert_int(AiRig.count_of(world, 1, HEAD)).is_equal(1)


func test_the_same_slot_is_dropped_when_it_is_sent_without_the_lag_margin() -> void:
	# The control of the case above: the old rule (lag 0) sends the first slot, and the sim drops it.
	var first: Array[int] = _tile_of(_place(_world(false)))
	var world: World = _world(true)
	var loop: MatchLoop = AiRig.loop_of(world)
	var old: Command = Command.place(
		1,
		first[0] * PlayerView.MILLI_PER_TILE + PlayerView.TILE_CENTRE,
		first[1] * PlayerView.MILLI_PER_TILE + PlayerView.TILE_CENTRE
	)
	AiRig.step(world, loop)
	AiRig.step(world, loop, [old])
	assert_int(world.dropped_commands).is_equal(1)
	assert_int(AiRig.count_of(world, 1, HEAD)).is_equal(0)


func test_the_lag_is_one_tick_and_the_margin_is_one_step() -> void:
	# ADR 0038 section 1: the Commands made from the view of tick T enter step T + 1.
	assert_int(PlayerView.COMMAND_LAG_TICKS).is_equal(1)
	var first: Array[int] = _tile_of(_place(_world(false)))
	var world: World = _world(false)
	var head: int = AiRig.type_of(world, HEAD)
	var mover: int = AiRig.type_of(world, MOVER)
	var gap: int = world.type_radius[mover] + world.type_speed[mover] + 1
	var middle: int = (first[1] * 2 + world.type_foot_h[head]) * PlayerView.MILLI_PER_TILE / 2
	AiRig.add_unit_of(world, 1, MOVER, first[0] * PlayerView.MILLI_PER_TILE - gap, middle)
	var view: PlayerView = PlayerView.of(world, 1)
	# One milli-tile past one step: the lag-1 margin leaves the slot, a margin of two steps does not.
	assert_int(view.placement(head, first[0], first[1], PlayerView.COMMAND_LAG_TICKS)).is_equal(
		Placement.Reason.OK
	)
	assert_int(view.placement(head, first[0], first[1], 2)).is_equal(Placement.Reason.OCCUPIED)


func test_the_sim_path_still_accepts_at_lag_zero_what_the_ai_skips_at_lag_one() -> void:
	var first: Array[int] = _tile_of(_place(_world(false)))
	var world: World = _world(true)
	var head: int = AiRig.type_of(world, HEAD)
	var input: PlacementInput = PlacementInput.of_world(world)
	# The default argument is what Production and the ghost call: lag 0, the rule as it was.
	assert_int(Placement.reason(input, 1, head, first[0], first[1])).is_equal(Placement.Reason.OK)
	(
		assert_int(
			PlayerView.of(world, 1).placement(
				head, first[0], first[1], PlayerView.COMMAND_LAG_TICKS
			)
		)
		. is_equal(Placement.Reason.OCCUPIED)
	)
	var command: Command = Command.place(
		1,
		first[0] * PlayerView.MILLI_PER_TILE + PlayerView.TILE_CENTRE,
		first[1] * PlayerView.MILLI_PER_TILE + PlayerView.TILE_CENTRE,
		head
	)
	command.tick = world.tick
	assert_bool(Production.apply_place(world, command)).is_true()


## A start for player 1 (fossil) with a ready `HEAD` at the front of its STRUCTURES queue, the map
## explored and credits to spare. With `crafted`, a harvester stands left of the first slot's
## footprint, half a step further out than its radius, and has been ordered onto the footprint.
@warning_ignore("integer_division")
func _world(crafted: bool) -> World:
	var world: World = FactionRig.start("fossil", "renew")
	Power.run(world)
	AiRig.explore_all(world)
	world.credits[1] = RICH
	var type: int = AiRig.type_of(world, HEAD)
	var queue: int = World.TABS + World.Tab.STRUCTURES
	world.queue_type[queue * world.queue_slots] = type
	world.queue_count[queue] = 1
	world.queue_progress[queue] = world.type_build_ticks[type] * Production.PROGRESS_PER_TICK
	if crafted:
		var tile: Array[int] = _tile_of(_place(_world(false)))
		var mover: int = AiRig.type_of(world, MOVER)
		var out: int = world.type_radius[mover] + world.type_speed[mover] / 2
		var wide: int = world.type_foot_w[type]
		var tall: int = world.type_foot_h[type]
		var middle: int = (tile[1] * 2 + tall) * PlayerView.MILLI_PER_TILE / 2
		var id: int = AiRig.add_unit_of(
			world,
			1,
			MOVER,
			tile[0] * PlayerView.MILLI_PER_TILE - out - world.type_speed[mover],
			middle
		)
		var goal: int = (tile[0] * 2 + wide) * PlayerView.MILLI_PER_TILE / 2
		AiRig.step(
			world, AiRig.loop_of(world), [Command.move(1, PackedInt32Array([id]), goal, middle)]
		)
		# The unit is one half step outside the reach of its radius now.
	return world


## The PLACE of the economy for the head on a fresh view of `world`, as the economy's thinks send it
## (the first think whose placement budget finds a slot).
func _place(world: World) -> Command:
	var economy: AiEconomy = AiEconomy.create(Rig.def_of("fossil"), Rig.level_of("normal"), 1)
	var memory: AiMemory = AiMemory.create(Rig.def_of("fossil"))
	var view: PlayerView = PlayerView.of(world, 1)
	for _think: int in THINKS:
		var out: Array[Command] = []
		memory.commands_left = 99
		economy.run(view, memory, DetRandom.create(1, DetRandom.STREAM_AI_BASE + 1), out)
		for command: Command in out:
			if command.type == Command.Type.PLACE:
				return command
	return null


@warning_ignore("integer_division")
func _tile_of(command: Command) -> Array[int]:
	return [
		command.target_x / PlayerView.MILLI_PER_TILE, command.target_y / PlayerView.MILLI_PER_TILE
	]
