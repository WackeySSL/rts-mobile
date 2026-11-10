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


func test_a_far_unit_inside_the_box_is_tested_and_uses_the_cap() -> void:
	# A building near the far unit puts it inside the box: it costs the 40 tests of the cap, and the
	# attacker behind it is never tested. This is what the box saves when no building is near.
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


func test_the_box_edge_is_inside_and_one_milli_tile_past_it_is_outside_on_every_side() -> void:
	_memory.site_id = PackedInt32Array([900])
	_memory.site_x = PackedInt32Array([20500])
	_memory.site_y = PackedInt32Array([20500])
	var tick: int = 5
	for side: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var edge: Vector2i = Vector2i(20500, 20500) + side * RADIUS * 1000
		var past: int = _enemy("heavy_tank", edge.x + side.x, edge.y + side.y)
		var on: int = _enemy("heavy_tank", edge.x, edge.y)
		_see_all()
		_memory.seen_unit_id = PackedInt32Array([past])
		_run_army(tick)
		assert_array([_army.tests, _memory.threat_first_tick]).is_equal([0, -1])
		_memory.seen_unit_id = PackedInt32Array([on])
		_run_army(tick + 15)
		assert_array([_army.tests, _memory.threat_first_tick]).is_equal([1, tick + 15])
		tick += 30


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


func test_the_cap_ends_a_units_site_loop_at_the_cap_and_the_search_there() -> void:
	# 40 buildings far from the attacker, then 10 beside it: the cap cuts the first unit's loop
	# after the 40th test, so the near buildings are never tested and no threat is found (P198:
	# the loop counts a unit's tests at once and must stop where the one-at-a-time loop did).
	_far_block_then_near(40, 10)
	var attacker: int = _enemy("heavy_tank", 30500, 5500)
	var second: int = _enemy("heavy_tank", 30500, 6500)
	_see_all()
	_memory.seen_unit_id = PackedInt32Array([attacker, second])
	_run_army(5)
	assert_array([_army.tests, _memory.threat_first_tick]).is_equal([CAP, -1])


func test_a_near_building_inside_the_cap_is_found_and_the_rest_of_the_cap_is_spent_on_it() -> void:
	# 10 far buildings, then 40 beside the attacker: the cap ends the first unit's loop on a near
	# building, so it is found, and the second unit is left blind.
	_far_block_then_near(10, 40)
	var attacker: int = _enemy("heavy_tank", 30500, 5500)
	var second: int = _enemy("heavy_tank", 30500, 6500)
	_see_all()
	_memory.seen_unit_id = PackedInt32Array([attacker, second])
	_run_army(5)
	assert_array([_army.tests, _memory.threat_first_tick]).is_equal([CAP, 5])


func test_a_cap_already_used_up_tests_nothing_more() -> void:
	_far_block_then_near(40, 10)
	var first: int = _enemy("heavy_tank", 30500, 5500)
	_see_all()
	_memory.seen_unit_id = PackedInt32Array([first])
	_army.tests_max = 0
	_run_army(5)
	assert_array([_army.tests, _memory.threat_first_tick]).is_equal([0, -1])


func test_the_nearer_of_two_units_in_the_box_wins_when_it_comes_second() -> void:
	# One building, the farther unit first in id order: the search goes on past a fully tested unit.
	_sites(1)
	var far: int = _enemy("heavy_tank", 15500, 5500)
	var near: int = _enemy("heavy_tank", 8500, 5500)
	_see_all()
	_memory.seen_unit_id = PackedInt32Array([far, near])
	_world.tick = 5
	_army.tests = 0
	assert_int(_army._threat(_view(), _memory)).is_equal(_view().row_of(near))
	assert_int(_army.tests).is_equal(2)


func test_the_cap_at_two_units_of_three_buildings_decides_whether_the_second_is_fully_tested(
) -> void:
	# Three buildings: two in the west, one in the east beside the second unit only. With a cap of 6
	# both units are tested against all three and the second (nearer the east one) wins; with 5 it
	# is tested against the two western ones, finds nothing and the first stays the threat.
	_memory.site_id = PackedInt32Array([900, 901, 902])
	_memory.site_x = PackedInt32Array([5500, 5500, 30000])
	_memory.site_y = PackedInt32Array([5500, 5500, 5500])
	var first: int = _enemy("heavy_tank", 15500, 5500)
	var second: int = _enemy("heavy_tank", 30500, 5500)
	_see_all()
	_memory.seen_unit_id = PackedInt32Array([first, second])
	_world.tick = 5
	for cap: int in [6, 5]:
		_army.tests_max = cap
		_army.tests = 0
		var row: int = _army._threat(_view(), _memory)
		assert_int(row).append_failure_message("cap %d" % cap).is_equal(
			_view().row_of(second if cap == 6 else first)
		)
		assert_int(_army.tests).append_failure_message("cap %d" % cap).is_equal(cap)


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


## `far` buildings 25 tiles west of x 30500 (beyond the radius of the attackers), followed
## by `near` buildings beside it, ids from 900.
func _far_block_then_near(far: int, near: int) -> void:
	_memory.site_id.clear()
	_memory.site_x.clear()
	_memory.site_y.clear()
	for index: int in far + near:
		_memory.site_id.append(900 + index)
		_memory.site_x.append(5500 if index < far else 30000)
		_memory.site_y.append(5500)
