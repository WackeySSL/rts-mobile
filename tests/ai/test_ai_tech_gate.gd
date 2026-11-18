extends "res://tests/ai/support/air_suite.gd"
## The tech gate of the opponent's economy (plan row P250b): an order step that is a tech building
## (airfield, engineering centre, space centre; found by role) does not start while the own army's
## value is under the level's `tech_army_value_min`; the steps after it wait, the anti-air wish, the
## loop and the army's production go on.


func test_the_gate_holds_below_the_value_and_releases_at_it() -> void:
	for id: String in ["fossil_airfield", "fossil_engineering", "fossil_space"]:
		var held: Array[String] = _structures(id, 3999, 4000)
		assert_array(held).override_failure_message("%s below" % id).is_empty()
		var open: Array[String] = _structures(id, 4000, 4000)
		assert_array(open).override_failure_message("%s at" % id).is_equal([id])


func test_zero_means_no_gate() -> void:
	assert_array(_structures("fossil_airfield", 0, 0)).is_equal(["fossil_airfield"])


func test_a_step_that_is_no_tech_building_is_not_gated() -> void:
	assert_array(_structures("defence_turret", 0, 4000)).is_equal(["defence_turret"])


func test_the_steps_after_a_gated_step_wait_for_it() -> void:
	var def: OpponentDef = _def_with(["fossil_airfield", "defence_turret"])
	var sent: Array[Command] = _run_gate(def, _gate_level(4000), _base(), 0, 0)
	assert_array(_ids_in_tab(sent, _base(), World.Tab.STRUCTURES)).is_empty()
	# Released, the airfield goes first and the turret follows it in the queue.
	var world: World = _base()
	var open: Array[String] = _ids_in_tab(
		_run_gate(def, _gate_level(4000), world, 4000, 0), world, World.Tab.STRUCTURES
	)
	assert_array(open).is_equal(["fossil_airfield", "defence_turret"])


func test_the_anti_air_wish_is_not_gated() -> void:
	var world: World = _base()
	var sent: Array[Command] = _run_gate(
		_def_with(["fossil_airfield"]), _gate_level(4000), world, 0, 2
	)
	assert_array(_ids_in_tab(sent, world, World.Tab.STRUCTURES)).is_equal(["fossil_aa"])


func test_the_economy_keeps_no_credits_for_a_gated_step_and_production_goes_on() -> void:
	var world: World = _base()
	var def: OpponentDef = _def_with(["fossil_airfield"])
	var memory: AiMemory = _memory("fossil")
	memory.army_value = 0
	var economy: AiEconomy = AiEconomy.create(def, _gate_level(4000), 1)
	var out: Array[Command] = []
	economy.run(PlayerView.of(world, 1), memory, _stream(), out)
	# What it holds is what it queued (the tankers): no hold for the airfield that waits.
	var spent: int = 0
	for command: Command in out:
		spent += world.type_cost[command.payload[0]]
	assert_int(memory.reserve_credits).is_equal(spent)
	var units: Array[Command] = _run(_production("fossil", "normal"), memory, world)
	assert_bool(units.size() > 0).is_true()


func test_the_reveal_kind_is_the_sims() -> void:
	assert_int(AiEconomy._REVEAL_KIND).is_equal(Strike.Kind.REVEAL)


func test_easy_is_ungated_and_normal_and_hard_are_gated() -> void:
	assert_int(Rig.level_of("easy").tech_army_value_min).is_equal(0)
	assert_int(Rig.level_of("normal").tech_army_value_min).is_greater(0)
	assert_int(Rig.level_of("hard").tech_army_value_min).is_greater(0)


func test_the_frozen_copies_set_no_gate() -> void:
	for level: String in Rig.LEVELS:
		var copy: AiDifficultyDef = load("res://data/dev/arena/ai_4b/difficulty/%s.tres" % level)
		assert_int(copy.tech_army_value_min).is_equal(0)


## The structures one economy run queues for the single step `id` at `army` value with the gate at
## `gate`, on a base that has what `id` needs.
func _structures(id: String, army: int, gate: int) -> Array[String]:
	var world: World = _base() if id == "fossil_airfield" or id == "defence_turret" else _air_base()
	var sent: Array[Command] = _run_gate(_def_with([id]), _gate_level(gate), world, army, 0)
	return _ids_in_tab(sent, world, World.Tab.STRUCTURES)


func _run_gate(
	def: OpponentDef, level: AiDifficultyDef, world: World, army: int, air_peak: int
) -> Array[Command]:
	var memory: AiMemory = _memory("fossil")
	memory.army_value = army
	memory.seen_air_peak = air_peak
	memory.commands_left = 99
	var out: Array[Command] = []
	AiEconomy.create(def, level, 1).run(PlayerView.of(world, 1), memory, _stream(), out)
	return out


## Normal's level with the gate at `gate`, no loop wishes (a refinery, a factory, a defence) and
## no repair building (P283's `_add_repair_building`, live once P279 rostered the sheds).
func _gate_level(gate: int) -> AiDifficultyDef:
	var level: AiDifficultyDef = Rig.level_of("normal").duplicate() as AiDifficultyDef
	level.tech_army_value_min = gate
	level.repair_retreat_percent = 0
	level.refineries_max = 1
	level.factories_max = 1
	level.defences_max = 0
	return level


func _def_with(steps: Array) -> OpponentDef:
	var def: OpponentDef = Rig.def_of("fossil").duplicate() as OpponentDef
	var order: AiBuildOrderDef = AiBuildOrderDef.new()
	for id: String in steps:
		order.steps.append(StringName(id))
	var orders: Array[AiBuildOrderDef] = [order, order, order]
	def.build_orders = orders
	return def
