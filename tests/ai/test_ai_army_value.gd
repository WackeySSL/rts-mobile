extends "res://tests/ai/support/control_suite.gd"
## `AiMemory.army_value` (plan row P250b): the value of the home and the wave squad, cost scaled by
## hp, written by `AiArmy` on every think, so the economy's tech gate never reads a stale army.


func test_the_army_value_follows_the_members_hp_after_a_launch_and_when_the_wave_dies() -> void:
	var tank: int = _launched()
	var ids: PackedInt32Array = _all_ids(tank)
	_think(80)
	assert_int(_memory.army_value).is_greater(0)
	assert_int(_memory.army_value).is_equal(_value_of(ids))
	# A hurt unit counts its share of its cost.
	_hp(tank, _world.hp[_row_in_world(tank)] / 2)
	_think(95)
	assert_int(_memory.army_value).is_equal(_value_of(ids))
	var hurt: int = _memory.army_value
	assert_int(hurt).is_less(_value_of_full(ids))
	# The whole wave dies: the value follows at the next think, not at the next launch.
	for id: int in ids:
		_kill(id)
	_think(110)
	assert_int(_memory.army_value).is_equal(0)


func test_the_army_value_is_written_before_any_wave_is_due() -> void:
	var tank: int = _tank()
	_settle()
	_think(5)
	assert_int(_memory.wave_count).is_equal(0)
	assert_int(_memory.army_value).is_equal(_value_of(_all_ids(tank)))
	assert_int(_memory.army_value).is_greater(0)


## The value of the own rows `ids` read off the World: cost scaled by hp over the type's hp.
func _value_of(ids: PackedInt32Array) -> int:
	var total: int = 0
	for id: int in ids:
		var row: int = _row_in_world(id)
		if row < 0:
			continue
		var type: int = _world.type_index[row]
		@warning_ignore("integer_division")
		total += _world.type_cost[type] * _world.hp[row] / _world.type_max_hp[type]
	return total


## The same rows at their full hp.
func _value_of_full(ids: PackedInt32Array) -> int:
	var total: int = 0
	for id: int in ids:
		total += _world.type_cost[_world.type_index[_row_in_world(id)]]
	return total
