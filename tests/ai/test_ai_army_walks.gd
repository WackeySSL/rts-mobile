extends "res://tests/ai/support/army_suite.gd"
## The id-list walks of `AiArmy._join` and `_unseen_hit` (plan row P198): one pass down two
## ascending lists replaces a bsearch a unit. Pinned here against the bsearch rules they replaced
## (`_is_pending`, `_hp_was`, the old `_join`) on seeded random lists with deaths at the front and
## in the middle, new ids between known ones and a pending id that died; and `AiIntel.refresh`
## keeps `unit_id` strictly ascending on a World whose table has compacted, the order the walks
## rest on. Also: two joiners at budget 0 are both ordered at the next slot.

const FIRST: int = 5
const NEAR: Vector2i = Vector2i(15500, 7500)
const CASES: int = 300
const SHIFT: int = 4


func test_unit_id_is_strictly_ascending_after_a_refresh_on_a_compacted_table() -> void:
	var added: PackedInt32Array = PackedInt32Array()
	for at: int in 6:
		added.append(AiRig.add_unit_of(_world, 1, "rifle_squad", 8500 + at * 500, 9500))
	_settle()
	for victim: int in [_squads()[0], added[1], added[4]]:
		AiRig.kill(_world, _loop, _row_in_world(victim))
	var new_one: int = AiRig.add_unit_of(_world, 1, "heavy_tank", 8500, 10500)
	_settle()
	_intel.refresh(_view(), _memory)
	assert_array(_memory.unit_id).is_not_empty()
	assert_bool(_memory.unit_id.has(new_one)).is_true()
	assert_bool(_memory.unit_id.has(added[1]) or _memory.unit_id.has(added[4])).is_false()
	for at: int in range(1, _memory.unit_id.size()):
		assert_int(_memory.unit_id[at]).is_greater(_memory.unit_id[at - 1])


func test_join_equals_the_bsearch_rules_on_random_ascending_lists() -> void:
	var seed: int = 7
	for _case: int in CASES:
		var known: PackedInt32Array = PackedInt32Array()
		var squads: PackedInt32Array = PackedInt32Array()
		var fresh: PackedInt32Array = PackedInt32Array()
		var units: PackedInt32Array = PackedInt32Array()
		var id: int = 0
		for _step: int in 24:
			id += 1 + seed % 3
			seed = _next(seed)
			var in_known: bool = seed % 3 != 0
			seed = _next(seed)
			var alive: bool = seed % 4 != 0
			seed = _next(seed)
			if in_known:
				known.append(id)
				squads.append(seed % 2)
				seed = _next(seed)
				if seed % 3 == 0:
					fresh.append(id)
				seed = _next(seed)
			if alive:
				units.append(id)
		_memory.unit_id = units
		_memory.member_id = known.duplicate()
		_memory.member_squad = squads.duplicate()
		_army._fresh = fresh.duplicate()
		var expected: Array[PackedInt32Array] = _old_join(units, known, squads, fresh)
		_army._join(_memory)
		assert_array(_memory.member_id).is_equal(expected[0])
		assert_array(_memory.member_squad).is_equal(expected[1])
		assert_array(_army._fresh).is_equal(expected[2])


func test_unseen_hit_shifts_exactly_when_the_bsearch_rules_find_a_hurt_home_unit() -> void:
	_arm_shift()
	_settle()
	_see_all()
	for at: int in 5:
		AiRig.add_unit_of(_world, 1, "rifle_squad", 8500 + at * 500, 9500)
	_settle()
	var seed: int = 11
	var shifted: int = 0
	for _case: int in 40:
		_arm_shift()
		_think(FIRST)
		var view: PlayerView = _view()
		_intel.refresh(view, _memory)
		_army._join(_memory)
		var ids: PackedInt32Array = _memory.unit_id.duplicate()
		assert_int(ids.size()).is_greater(4)
		# The last think's hp list: some ids missing, some with more hp than now.
		_memory.hp_id = PackedInt32Array()
		_memory.hp_value = PackedInt32Array()
		var now: PackedInt32Array = PackedInt32Array()
		var kept: int = 0
		for at: int in ids.size():
			now.append(100)
			if seed % 3 != 0:
				_memory.hp_id.append(ids[at])
				_memory.hp_value.append(100 + (seed % 5 - 2) * 10 if seed % 7 < 2 else 100)
				kept += 1
			seed = _next(seed)
		_memory.unit_hp = now
		var expected: bool = false
		for at: int in ids.size():
			if _army._hp_was(_memory, ids[at]) > now[at]:
				expected = true
		_world.tick = FIRST + 15
		_memory.commands_left = 8
		_out = []
		_army._unseen_hit(view, _memory, _out, true)
		assert_int(_army.shifts).is_equal(1 if expected else 0)
		shifted += _army.shifts
		assert_array(_memory.hp_id).is_equal(ids)
		assert_array(_memory.hp_value).is_equal(now)
	assert_int(shifted).is_greater(0)
	assert_int(shifted).is_less(40)


func test_two_joiners_at_budget_zero_are_both_ordered_at_the_next_slot() -> void:
	_enemy("heavy_tank", NEAR.x, NEAR.y)
	_settle()
	_see_all()
	for tick: int in [0, 15, 30]:
		_think(FIRST + tick)
	var first: int = AiRig.add_unit_of(_world, 1, "heavy_tank", 8500, 9500)
	var second: int = AiRig.add_unit_of(_world, 1, "heavy_tank", 9000, 9500)
	_think(FIRST + 45, 0)
	assert_array(_out).is_empty()
	_think(FIRST + 60)
	var sent: Array[Command] = _of(Command.Type.ATTACK_MOVE)
	assert_int(sent.size()).is_equal(1)
	assert_array(sent[0].unit_ids).is_equal(PackedInt32Array([first, second]))
	_think(FIRST + 75)
	assert_array(_out).is_empty()


## The shift suite's managers: a shift of 4 tiles, no defence radius.
func _arm_shift() -> void:
	var def: OpponentDef = _def()
	def.defend_radius_tiles = 0
	def.unseen_hit_shift_tiles = SHIFT
	_arm("normal", def)


## A linear congruence, so the cases are the same on every machine.
static func _next(seed: int) -> int:
	return ((seed * 1103515245 + 12345) >> 4) & 0x7FFFFFF


## The `_join` of main: a bsearch a unit down `known` and `fresh`. Returns the new member ids, their
## squads and the new pending list.
func _old_join(
	units: PackedInt32Array,
	known: PackedInt32Array,
	squads: PackedInt32Array,
	fresh: PackedInt32Array
) -> Array[PackedInt32Array]:
	var ids: PackedInt32Array = PackedInt32Array()
	var out_squads: PackedInt32Array = PackedInt32Array()
	var pending: PackedInt32Array = PackedInt32Array()
	for id: int in units:
		var at: int = known.bsearch(id)
		ids.append(id)
		if at < known.size() and known[at] == id:
			out_squads.append(squads[at])
			var found: int = fresh.bsearch(id)
			if found < fresh.size() and fresh[found] == id:
				pending.append(id)
		else:
			out_squads.append(AiArmy.HOME)
			pending.append(id)
	return [ids, out_squads, pending]
