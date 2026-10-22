extends GdUnitTestSuite
## Command v2 (plan P70b, ADR 0017 section 4): the six Phase 3 types and their ids, the factories
## with the payloads of the ADR, that every factory copies its arrays, and that each new type
## encodes and decodes (the replay log needs no change) and keeps the (tick, player_id, sequence)
## order. The numbers are literals.

const Samples: GDScript = preload("res://tests/sim/support/command_samples.gd")
const NEW_TYPES: Array[int] = [10, 11, 12, 13, 14, 20]


func test_the_phase_3_types_have_the_ids_of_the_adr() -> void:
	var expected: Dictionary = {"NONE": 0, "ATTACK_MOVE": 1, "MOVE": 2, "ATTACK": 3, "STOP": 4}
	expected.merge({"PLACE": 10, "QUEUE": 11, "CANCEL": 12, "RALLY": 13, "HARVEST": 14})
	expected["SURRENDER"] = 20
	assert_dict(Command.Type).is_equal(expected)


## Each factory sets its type, its player and the fields of the ADR table and leaves the rest and
## the stamps alone: PLACE a point, QUEUE [type_index], CANCEL [tab, slot], RALLY a building and a
## point, HARVEST the units and a point, SURRENDER nothing.
func test_each_factory_sets_the_fields_and_the_payload_of_the_adr() -> void:
	var place: Command = Command.place(2, 12500, -700)
	assert_array(Samples.fields(place)).is_equal([-1, 2, 0, 10, 12500, -700, 0, [], []])
	var queue: Command = Command.queue(1, 7)
	assert_array(Samples.fields(queue)).is_equal([-1, 1, 0, 11, 0, 0, 0, [], [7]])
	var cancel: Command = Command.cancel(1, 2, 3)
	assert_array(Samples.fields(cancel)).is_equal([-1, 1, 0, 12, 0, 0, 0, [], [2, 3]])
	var rally: Command = Command.rally(2, 41, 8500, 9500)
	assert_array(Samples.fields(rally)).is_equal([-1, 2, 0, 13, 8500, 9500, 41, [], []])
	var harvest: Command = Command.harvest(1, PackedInt32Array([5, 6]), 20500, 4500)
	assert_array(Samples.fields(harvest)).is_equal([-1, 1, 0, 14, 20500, 4500, 0, [5, 6], []])
	var surrender: Command = Command.surrender(2)
	assert_array(Samples.fields(surrender)).is_equal([-1, 2, 0, 20, 0, 0, 0, [], []])


## A command changes hands once (ADR 0012 section 2): changing the caller's unit ids after the call
## does not reach the command, and every call makes its own payload.
func test_the_factories_copy_their_arrays() -> void:
	var ids: PackedInt32Array = PackedInt32Array([31, 33])
	var harvest: Command = Command.harvest(1, ids, 5, 6)
	ids[0] = 99
	assert_array(harvest.unit_ids).is_equal([31, 33])
	var first: Command = Command.queue(1, 4)
	var second: Command = Command.queue(1, 4)
	first.payload[0] = 9
	assert_array(second.payload).is_equal([4])
	var one: Command = Command.cancel(1, 0, 1)
	var other: Command = Command.cancel(1, 0, 1)
	one.payload[1] = 8
	assert_array(other.payload).is_equal([0, 1])


## Encoding writes every field and the payload as it is, so a new type needs no change in the
## replay log: a command with every field set round-trips, and so does each factory's command.
func test_each_new_type_encodes_and_decodes() -> void:
	for type: int in NEW_TYPES:
		var command: Command = Samples.full(type, 40, 6)
		var data: PackedInt32Array = PackedInt32Array()
		command.encode(data)
		var back: Command = Command.new()
		assert_int(Command.decode(data, 0, back)).is_equal(data.size())
		assert_array(Samples.fields(back)).override_failure_message(str(type)).is_equal(
			Samples.fields(command)
		)
	var made: Array[Command] = [
		Command.place(2, 12500, -700),
		Command.queue(1, 7),
		Command.cancel(1, 2, 3),
		Command.rally(2, 41, 8500, 9500),
		Command.harvest(1, PackedInt32Array([5, 6]), 20500, 4500),
		Command.surrender(2),
	]
	var log: PackedInt32Array = PackedInt32Array()
	for command: Command in made:
		command.tick = 3
		command.sequence = 1
		command.encode(log)
	var at: int = 0
	for command: Command in made:
		var back: Command = Command.new()
		at = Command.decode(log, at, back)
		assert_array(Samples.fields(back)).is_equal(Samples.fields(command))
	assert_int(at).is_equal(log.size())


## The commands of one tick are applied in (tick, player_id, sequence) order whatever their type.
func test_the_new_types_sort_by_tick_player_and_sequence() -> void:
	var late: Command = Command.surrender(1)
	late.tick = 5
	var second: Command = Command.queue(2, 1)
	second.tick = 4
	var first: Command = Command.place(1, 0, 0)
	first.tick = 4
	var again: Command = Command.cancel(1, 0, 0)
	again.tick = 4
	again.sequence = 1
	var list: Array[Command] = [late, second, again, first]
	list.sort_custom(Command.compare)
	assert_array(list).is_equal([first, again, second, late])
