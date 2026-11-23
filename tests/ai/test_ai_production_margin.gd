extends "res://tests/ai/support/production_suite.gd"
## The spend margin of production (plan row P250e, iteration 2): the mend and the ground repair draw
## credits every tick between the view and the apply of a QUEUE, so a unit paid to the last credit
## was refused by the sim (a stale drop, seen on seed 36 of the Kestrel normal-vs-normal run). With
## a margin of `spend_margin_credits` production leaves that many credits unspent.

const MARGIN: int = 40


func _with_margin(margin: int) -> AiProduction:
	var level: AiDifficultyDef = _level("normal")
	level.spend_margin_credits = margin
	return AiProduction.create(_def(), level, 1)


func test_a_unit_that_leaves_less_than_the_margin_is_not_queued() -> void:
	var world: World = _world(0, true)
	var rifle: int = _cost(world, "rifle_squad")
	var memory: AiMemory = _memory("fossil")
	memory.reserve_credits = 700
	# Exactly the price above the reserve: queued without a margin (and the drain would refuse it).
	world.credits[1] = 700 + rifle
	assert_array(_ids(_run(_with_margin(0), memory, world), world)).is_equal(["rifle_squad"])
	# With the margin the same credits buy nothing, and the margin more buys the unit.
	assert_array(_run(_with_margin(MARGIN), memory, world)).is_empty()
	world.credits[1] = 700 + rifle + MARGIN
	assert_array(_ids(_run(_with_margin(MARGIN), memory, world), world)).is_equal(["rifle_squad"])


func test_every_run_leaves_the_margin_whatever_the_credits() -> void:
	var world: World = _world(0, true)
	var memory: AiMemory = _memory("fossil")
	memory.reserve_credits = 0
	for credits: int in [150, 333, 777, 1500]:
		world.credits[1] = credits
		var spent: int = 0
		for command: Command in _run(_with_margin(MARGIN), memory, world):
			spent += world.type_cost[command.payload[0]]
		assert_int(spent).override_failure_message("credits %d" % credits).is_less_equal(
			maxi(credits - MARGIN, 0)
		)


func test_the_margin_is_off_for_easy_and_the_frozen_defaults_and_on_for_the_others() -> void:
	assert_int(Rig.level_of("easy").spend_margin_credits).is_equal(0)
	assert_int(AiDifficultyDef.new().spend_margin_credits).is_equal(0)
	assert_int(Rig.level_of("normal").spend_margin_credits).is_greater(0)
	assert_int(Rig.level_of("hard").spend_margin_credits).is_greater(0)
