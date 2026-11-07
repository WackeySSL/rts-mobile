extends "res://tests/ai/support/strike_suite.gd"
## The strike manager inside `OpponentAi` (plan row P181, ADR 0030 sections 2, 4 and 6): it runs in
## the INTEL slot after the intel run and counts no pass, `strikes` counts the shots, a level that
## uses no strike neither builds nor fires (the economy leaves the step out of the order), and a
## no-army controller made by `copy_from` keeps the manager.

const NoArmy: GDScript = preload("res://tests/ai/support/no_army.gd")
const RICH: int = 100000
## The order's steps before the strike: the first nine of `SPOTS`.
const STEPS: int = 9
## The economy numbers the World is built for: power margin, tankers per refinery, and the caps on
## refineries, factories and defences.
const MARGIN: int = 20
const TANKERS: int = 2
const REFINERIES: int = 2
const FACTORIES: int = 1
const DEFENCES: int = 2
## The suite's economy: a fossil World whose player 1 owns every building of the suite's order but
## the Deep Bore (the order is `SPOTS`' first nine, then the Deep Bore), and an extra refinery.
const SPOTS: Array = [
	["power_plant", 10, 2],
	["power_plant", 13, 2],
	["power_plant", 16, 2],
	["refinery", 10, 10],
	["barracks", 2, 2],
	["vehicle_factory", 2, 12],
	["fossil_radar", 22, 2],
	["defence_turret", 22, 8],
	["defence_turret", 22, 12],
	["refinery", 30, 2],
]


func test_the_intel_slot_sends_the_shot_after_the_intel_run_and_counts_no_pass() -> void:
	_cluster()
	var ai: OpponentAi = _controller("normal", 1)
	var shots: Array[Command] = _think_until_shot(ai)
	assert_int(shots.size()).is_equal(1)
	assert_int(ai.last_slot).is_equal(OpponentAi.Slot.INTEL)
	assert_int(ai.strikes).is_equal(1)
	assert_int(ai.work_max).is_less_equal(3)
	assert_int(ai.commands_cut).is_equal(0)
	assert_array([shots[0].target_x, shots[0].target_y]).is_equal([31500, 31500])


func test_a_controller_whose_level_uses_no_strike_never_fires() -> void:
	_cluster()
	var ai: OpponentAi = _controller("normal", 0)
	assert_array(_think_until_shot(ai)).is_empty()
	assert_int(ai.strikes).is_equal(0)


func test_a_no_army_copy_keeps_the_strike_manager() -> void:
	var ai: OpponentAi = _controller("normal", 1)
	var copy: Variant = NoArmy.new()
	copy.copy_from(ai)
	assert_object(copy.striker).is_same(ai.striker)


func test_a_level_that_uses_no_strike_never_queues_the_strike_building() -> void:
	var world: World = _economy_world()
	assert_array(_queued(_economy_run(1, world), world)).is_equal(["fossil_strike"])
	# The same order at a level whose `uses_strike` is 0 leaves the step out.
	assert_array(_queued(_economy_run(0, world), world)).is_empty()


## A full controller (the fossil def and `level` with the suite's minimum, tests and reaction, and
## `uses_strike` as given).
func _controller(level: String, uses: int) -> OpponentAi:
	var def: OpponentDef = Rig.def_of("fossil").duplicate() as OpponentDef
	def.strike_min_value = MIN
	def.target_tests_max = TESTS
	var chosen: AiDifficultyDef = Rig.level_of(level).duplicate() as AiDifficultyDef
	chosen.uses_strike = uses
	chosen.reaction_ticks = REACTION
	return OpponentAi.create(def, chosen, 1, DetRandom.create(1, DetRandom.STREAM_AI_BASE + 1))


## Thinks on a fresh view of the unstepped World at every tick from `READY` for 90 ticks (each
## slot comes up six times), keeping the SUPERWEAPON Commands of the first think that sent one.
func _think_until_shot(ai: OpponentAi) -> Array[Command]:
	for tick: int in range(READY, READY + 90):
		if (tick + ai.think_offset) % ai.think_period != 0:
			continue
		_world.tick = tick
		var sent: Array[Command] = []
		ai.think(_view(), sent)
		_out = sent
		if not _shots().is_empty():
			return _shots()
	return []


func _economy_world() -> World:
	var world: World = FactionRig.start("fossil", "renew")
	AiRig.explore_all(world)
	world.credits[1] = RICH
	for row: Array in SPOTS:
		AiRig.give(world, 1, row[0], row[1], row[2])
	for at: int in 4:
		AiRig.add_unit_of(world, 1, "harvester", 12000 + at * 600, 14000)
	Power.run(world)
	return world


func _economy_run(uses: int, world: World) -> Array[Command]:
	var def: OpponentDef = Rig.def_of("fossil").duplicate() as OpponentDef
	def.power_margin = MARGIN
	var order: AiBuildOrderDef = AiBuildOrderDef.new()
	for spot: Array in SPOTS:
		if order.steps.size() < STEPS:
			order.steps.append(StringName(spot[0]))
	order.steps.append(&"fossil_strike")
	var orders: Array[AiBuildOrderDef] = [order, order, order]
	def.build_orders = orders
	var chosen: AiDifficultyDef = Rig.level_of("normal").duplicate() as AiDifficultyDef
	chosen.uses_strike = uses
	chosen.harvesters_per_refinery = TANKERS
	chosen.refineries_max = REFINERIES
	chosen.factories_max = FACTORIES
	chosen.defences_max = DEFENCES
	var economy: AiEconomy = AiEconomy.create(def, chosen, 1)
	var memory: AiMemory = AiMemory.create(def)
	memory.commands_left = 99
	var out: Array[Command] = []
	economy.run(PlayerView.of(world, 1), memory, _rng, out)
	return out


func _queued(sent: Array[Command], world: World) -> Array[String]:
	var found: Array[String] = []
	for command: Command in sent:
		if command.type == Command.Type.QUEUE:
			found.append(String(world.type_ids[command.payload[0]]))
	return found
