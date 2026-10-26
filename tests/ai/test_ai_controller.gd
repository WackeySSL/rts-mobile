extends GdUnitTestSuite
## The controller contract (plan row P83, ADR 0020 section 2): `AiController`'s fields and `think`,
## what `DummyAi.create` copies from its def and where its thinks fall. The economy is in
## test_dummy_economy.gd and test_dummy_wishes.gd, the placement in test_dummy_placement.gd.

const Rig: GDScript = preload("res://tests/ai/support/ai_rig.gd")


func test_the_base_controller_has_the_contract_fields_and_sends_nothing() -> void:
	var controller: AiController = AiController.new()
	controller.player_id = 3
	controller.think_period = 15
	controller.think_offset = 4
	assert_array([controller.player_id, controller.think_period, controller.think_offset]).is_equal(
		[3, 15, 4]
	)
	var world: World = Rig.start()
	var sent: Array[Command] = []
	controller.think(PlayerView.of(world, 3), sent)
	assert_array(sent).is_empty()
	# A fresh controller thinks on every tick: period 1, offset 0 (a division by 0 never happens).
	assert_array([AiController.new().think_period, AiController.new().think_offset]).is_equal(
		[1, 0]
	)


func test_a_dummy_is_made_from_its_def_player_and_stream() -> void:
	var def: AiDef = Rig.dummy_def()
	var stream: DetRandom = DetRandom.create(5, DetRandom.STREAM_AI_BASE + 2)
	var ai: DummyAi = DummyAi.create(def, 2, stream)
	assert_object(ai).is_instanceof(AiController)
	assert_int(ai.player_id).is_equal(2)
	assert_int(ai.think_period).is_equal(def.think_period)
	assert_object(ai.rng).is_same(stream)


func test_a_dummy_thinks_on_tick_7_8_9_of_the_period_for_players_2_3_4() -> void:
	for player: int in [2, 3, 4]:
		var ai: DummyAi = Rig.dummy(player)
		var turns: Array[int] = []
		for tick: int in 30:
			if (tick + ai.think_offset) % ai.think_period == 0:
				turns.append(tick)
		var first: int = 7 + player - 2
		assert_array(turns).is_equal([first, first + 15])
		# A checkpoint hashes after the step that starts at tick % 15 == 14: no think is there.
		assert_int(turns[0] % 15).is_not_equal(14)
	assert_array([Rig.dummy(2).think_offset, Rig.dummy(3).think_offset]).is_equal([8, 7])


func test_the_offset_follows_the_period_and_the_tick_of_the_def() -> void:
	var def: AiDef = Rig.dummy_def().duplicate() as AiDef
	def.think_period = 30
	def.think_tick = 0
	var ai: DummyAi = DummyAi.create(def, 1, DetRandom.create(1, DetRandom.STREAM_AI_BASE + 1))
	# Player 1 is one slot before player 2: tick 29 of 30, and the offset is not negative.
	assert_array([ai.think_period, ai.think_offset]).is_equal([30, 1])
	assert_int((29 + ai.think_offset) % ai.think_period).is_equal(0)
	def.think_period = 0
	assert_int(DummyAi.create(def, 2, null).think_period).is_equal(1)


func test_a_dummy_keeps_no_resource_and_no_node() -> void:
	var ai: DummyAi = Rig.dummy(2)
	var kept: Array[String] = []
	for property: Dictionary in ai.get_property_list():
		if int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		var value: Variant = ai.get(property["name"])
		var items: Array = value if value is Array else [value]
		for item: Variant in items:
			if item is Node or item is Resource:
				kept.append(String(property["name"]))
	assert_array(kept).is_empty()


func test_the_def_is_copied_when_the_dummy_is_made() -> void:
	# `def_with` gives the def an array of its own, so the in-place change below reaches no Resource
	# that another test loads.
	var def: AiDef = Rig.def_with(["power_plant", "refinery"])
	var ai: DummyAi = DummyAi.create(def, 1, DetRandom.create(1, DetRandom.STREAM_AI_BASE + 1))
	# The order is emptied in place: binding a new array to the property would leave the one that a
	# dummy holding a reference kept, and the test would pass without a copy.
	def.build_order.clear()
	def.queue_target = 0
	def.hq_type = &"nothing"
	var world: World = Rig.start()
	var sent: Array[Command] = []
	ai.think(PlayerView.of(world, 1), sent)
	assert_array(_types(world, sent)).is_equal(["power_plant"])


func test_a_dummy_draws_no_random_number() -> void:
	var world: World = Rig.start()
	var loop: MatchLoop = Rig.loop_of(world)
	var stream: DetRandom = DetRandom.create(7, DetRandom.STREAM_AI_BASE + 1)
	var ai: DummyAi = DummyAi.create(Rig.dummy_def(), 1, stream)
	var before: PackedInt64Array = stream.state()
	Rig.run(world, loop, [ai], 600)
	assert_array(Array(stream.state())).is_equal(Array(before))


## The type ids that the QUEUE commands of `sent` name.
func _types(world: World, sent: Array[Command]) -> Array[String]:
	var found: Array[String] = []
	for command: Command in sent:
		if command.type == Command.Type.QUEUE:
			found.append(String(world.type_ids[command.payload[0]]))
	return found
