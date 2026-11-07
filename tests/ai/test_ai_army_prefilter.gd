extends "res://tests/ai/support/army_suite.gd"
## The box pre-filter of `AiArmy`'s threat search (plan row P180, the 2026-11-07 note of P26bf from
## P179's review): a seen unit outside the box round the own buildings, grown by the defence
## radius, costs no test, so distant units with low ids cannot use up the cap and hide an attacker.
## The lists the search walks are filled by hand and `run` is called directly (no refresh).

## The tests per slot of the suite's def and the buildings it lists.
const CAP: int = 40
const SITES: int = 40


func before_test() -> void:
	super()
	var def: OpponentDef = _def()
	def.target_tests_max = CAP
	_arm("normal", def)


func test_distant_low_id_units_cost_no_test_and_do_not_hide_an_attacker() -> void:
	_sites(SITES)
	var far: PackedInt32Array = PackedInt32Array()
	for index: int in 12:
		far.append(_enemy("heavy_tank", 35500 + index % 3 * 500, 35500 + index / 3 * 500))
	var attacker: int = _enemy("heavy_tank", 15500, 7500)
	_see_all()
	_memory.seen_unit_id = far
	_memory.seen_unit_id.append(attacker)
	_run_army(5)
	# Only the attacker was tested, against each of the 40 buildings, and it was found.
	assert_int(_army.tests).is_equal(SITES)
	assert_int(_memory.threat_first_tick).is_equal(5)


func test_without_the_box_the_first_far_unit_would_have_used_the_cap() -> void:
	# The same crowd with the far units inside the box (a building near them): each costs the 40
	# tests of the cap, and the attacker behind them is never tested. This pins what the box saves.
	_sites(SITES - 1)
	_memory.site_id.append(900)
	_memory.site_x.append(36500)
	_memory.site_y.append(36500)
	var far: int = _enemy("heavy_tank", 35500, 35500)
	var attacker: int = _enemy("heavy_tank", 15500, 7500)
	_see_all()
	_memory.seen_unit_id = PackedInt32Array([far, attacker])
	_run_army(5)
	assert_int(_army.tests).is_equal(CAP)
	assert_int(_memory.threat_first_tick).is_equal(5)


func test_a_unit_outside_the_box_is_not_tested_at_all() -> void:
	_sites(1)
	var far: int = _enemy("heavy_tank", 30500, 30500)
	_see_all()
	_memory.seen_unit_id = PackedInt32Array([far])
	_run_army(5)
	assert_int(_army.tests).is_equal(0)
	assert_int(_memory.threat_first_tick).is_equal(-1)


func test_the_box_edge_is_inside_and_one_milli_tile_past_it_is_outside() -> void:
	_memory.site_id = PackedInt32Array([900])
	_memory.site_x = PackedInt32Array([7500])
	_memory.site_y = PackedInt32Array([7500])
	var edge: int = _enemy("heavy_tank", 7500 + RADIUS * 1000, 7500)
	var past: int = _enemy("heavy_tank", 7500 + RADIUS * 1000 + 1, 7500)
	_see_all()
	_memory.seen_unit_id = PackedInt32Array([past])
	_run_army(5)
	assert_array([_army.tests, _memory.threat_first_tick]).is_equal([0, -1])
	_memory.seen_unit_id = PackedInt32Array([edge])
	_run_army(20)
	assert_array([_army.tests, _memory.threat_first_tick]).is_equal([1, 20])


func test_a_unit_in_the_box_but_beyond_every_radius_is_tested_and_is_no_threat() -> void:
	# Two buildings in opposite corners: the box covers the map, the middle is 20 tiles from both.
	_memory.site_id = PackedInt32Array([900, 901])
	_memory.site_x = PackedInt32Array([5500, 35500])
	_memory.site_y = PackedInt32Array([5500, 35500])
	var middle: int = _enemy("heavy_tank", 20500, 20500)
	_see_all()
	_memory.seen_unit_id = PackedInt32Array([middle])
	_run_army(5)
	assert_array([_army.tests, _memory.threat_first_tick]).is_equal([2, -1])


func test_no_building_means_no_search() -> void:
	var foe: int = _enemy("heavy_tank", 15500, 7500)
	_see_all()
	_memory.seen_unit_id = PackedInt32Array([foe])
	_run_army(5)
	assert_array([_army.tests, _memory.threat_first_tick]).is_equal([0, -1])


## `count` buildings by hand in a block near the Headquarters, in milli-tiles, ids from 900.
func _sites(count: int) -> void:
	_memory.site_id.clear()
	_memory.site_x.clear()
	_memory.site_y.clear()
	for index: int in count:
		_memory.site_id.append(900 + index)
		_memory.site_x.append(5500 + index % 8 * 500)
		_memory.site_y.append(5500 + index / 8 * 500)


## The army alone on the hand-filled lists, at `tick`.
func _run_army(tick: int) -> void:
	_world.tick = tick
	_memory.commands_left = 8
	_out = []
	_army.run(_view(), _memory, _rng, _out)
