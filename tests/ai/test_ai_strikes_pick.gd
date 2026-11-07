extends "res://tests/ai/support/strike_suite.gd"
## Which point the Deep Bore picks (plan row P181, ADR 0030 section 4) on hand-built Worlds: the
## point of most value rather than the richest thing, tankers in the value, the own rows and army
## goals that keep a point clear (a row exactly on the radius included), a clear point found among
## blocked richer ones, fresh own units, a thing seen and remembered once, and the cap on tests.
## The cap's rule: the first `target_tests_max` things in id order are kept (seen buildings, units,
## other units, ghosts), the anchors are ranked by sector then value, and a run ends when the next
## anchor's sum or own check would pass the cap.

const BORE_POINT: Vector2i = Vector2i(31500, 31500)
const BARRACKS_POINT: Vector2i = Vector2i(30000, 34000)
## A refinery, a barracks and a power plant 2,550 milli-tiles from it: 2,100 in a radius of 3,000.
const MIXED_POINT: Vector2i = Vector2i(9500, 25500)


func test_the_point_of_most_value_wins_over_the_richest_thing() -> void:
	# The lone factory is the richest thing (1,800); the refinery's radius holds 2,100.
	_arm_strikes("normal", 1, "fossil", 1000)
	_enemy_building("vehicle_factory", 30, 30)
	_enemy_building("refinery", 8, 24)
	_enemy_building("barracks", 11, 24)
	_enemy_building("power_plant", 8, 27)
	_see_all()
	_fire(READY)
	_fire(KNOWN)
	assert_array(_target()).is_equal([MIXED_POINT.x, MIXED_POINT.y])


func test_seen_tankers_count_in_the_value() -> void:
	# The cluster is 2,200 without tankers; the refinery is 1,400 and with two tankers 3,800.
	_cluster()
	_enemy_building("refinery", 8, 24)
	AiRig.add_unit_of(_world, 2, "harvester", 10500, 25500)
	AiRig.add_unit_of(_world, 2, "harvester", 9500, 27000)
	_fire(READY)
	_fire(KNOWN)
	assert_array(_target()).is_equal([MIXED_POINT.x, MIXED_POINT.y])


func test_a_clear_point_is_found_when_the_richest_things_are_beside_an_own_unit() -> void:
	_see_all()
	for at: int in 12:
		AiRig.add_unit_of(_world, 2, "heavy_tank", 20000 + at * 200, 10000)
	AiRig.add_unit_of(_world, 1, "heavy_tank", 20400, 10000)
	for at: int in 28:
		AiRig.add_unit_of(_world, 2, "rifle_squad", 29000 + at % 4 * 400, 30000 + at / 4 * 400)
	_fire(READY)
	_fire(KNOWN)
	var at: Array[int] = _target()
	assert_bool(at[0] >= 29000 and at[0] <= 30200 and at[1] >= 30000 and at[1] <= 32400).is_true()


func test_an_own_unit_made_since_the_last_refresh_is_in_the_check() -> void:
	_cluster()
	_fire(READY)
	_fire(KNOWN - 5)
	AiRig.add_unit_of(_world, 1, "heavy_tank", 32500, 31500)
	# The INTEL slot, the ARMY slot's lists five ticks old: the new tank still keeps its point clear.
	_fire(KNOWN, 8, false)
	assert_array(_target()).is_equal([BARRACKS_POINT.x, BARRACKS_POINT.y])


func test_an_own_row_exactly_on_the_radius_keeps_the_point_clear() -> void:
	# The sim hits a row exactly on the radius, so the factory's point is not clear.
	_cluster()
	AiRig.add_unit_of(_world, 1, "heavy_tank", BORE_POINT.x + RADIUS, BORE_POINT.y)
	_fire(READY)
	_fire(KNOWN)
	assert_array(_target()).is_equal([BARRACKS_POINT.x, BARRACKS_POINT.y])


func test_a_thing_exactly_on_the_radius_counts_in_the_value() -> void:
	# A lone factory (1,800) and a tanker exactly on its radius (1,200): 3,000, the minimum.
	_arm_strikes("normal", 1, "fossil", 3000)
	_enemy_building("vehicle_factory", 30, 30)
	AiRig.add_unit_of(_world, 2, "harvester", BORE_POINT.x + RADIUS, BORE_POINT.y)
	_see_all()
	_fire(READY)
	_fire(KNOWN)
	assert_int(_shots().size()).is_equal(1)


func test_a_live_army_goal_keeps_a_point_clear_and_a_dead_one_does_not() -> void:
	_cluster()
	_fire(READY)
	var wave: int = AiArmy.WAVE
	# The wave's goal 2,000 from the factory's point and 4,300 from the barracks'.
	_memory.squad_role[wave] = AiArmy.ROLE_WAVE
	_memory.squad_state[wave] = AiMemory.SquadState.WAVE
	_memory.squad_goal_x[wave] = 33
	_memory.squad_goal_y[wave] = 31
	_fire(KNOWN)
	assert_array(_target()).is_equal([BARRACKS_POINT.x, BARRACKS_POINT.y])
	# A wave that has retreated has no goal that counts; a standing defence's home goal does.
	_memory.squad_state[wave] = AiMemory.SquadState.RETREAT
	_memory.threat_first_tick = KNOWN
	_memory.squad_goal_x[AiArmy.HOME] = 33
	_memory.squad_goal_y[AiArmy.HOME] = 31
	_fire(KNOWN + 15)
	assert_array(_target()).is_equal([BARRACKS_POINT.x, BARRACKS_POINT.y])
	_memory.threat_first_tick = AiMemory.NONE
	_fire(KNOWN + 30)
	assert_array(_target()).is_equal([BORE_POINT.x, BORE_POINT.y])


func test_a_building_that_is_seen_and_remembered_counts_once() -> void:
	var factory: int = _enemy_building("vehicle_factory", 30, 30)
	_see_all()
	# The sim keeps a record of a building it shows now too: 1,800, not 3,600, against a minimum
	# of 2,000.
	_ghost(factory, "vehicle_factory", 30, 30)
	_fire(READY)
	_fire(KNOWN)
	assert_array(_out).is_empty()


func test_an_own_check_that_the_cap_cuts_off_is_not_clear() -> void:
	# Six own tanks, each 4,100 from the factory but inside the things' box: the point is clear, yet
	# five tests cannot show it, so the AI holds fire; with room it fires.
	_enemy_building("vehicle_factory", 30, 30)
	for at: int in 6:
		AiRig.add_unit_of(_world, 1, "heavy_tank", 34400 + at * 10, 34400)
	_see_all()
	_arm_strikes("normal", 1, "fossil", 1, 5)
	_fire(READY)
	_fire(KNOWN)
	assert_array(_out).is_empty()
	assert_int(_striker.tests).is_equal(5)
	_arm_strikes("normal", 1, "fossil", 1, TESTS)
	_fire(READY)
	_fire(KNOWN)
	assert_array(_target()).is_equal([BORE_POINT.x, BORE_POINT.y])


func test_the_cap_keeps_the_first_things_and_ends_the_run_under_it() -> void:
	_enemy_building("vehicle_factory", 30, 30)
	for at: int in 20:
		_enemy_building("power_plant", 4 + at % 5 * 7, 16 + at / 5 * 6)
	_see_all()
	_arm_strikes("normal", 1, "fossil", 1, 10)
	_fire(READY)
	_fire(KNOWN)
	# The enemy Headquarters, the factory and eight plants are the ten things kept.
	assert_int(_striker.tests).is_less_equal(10)
	assert_int(_striker.tests).is_greater(0)
	assert_array(_target()).is_equal([BORE_POINT.x, BORE_POINT.y])
	var capped: int = _striker.tests
	_arm_strikes("normal", 1, "fossil", 1, TESTS)
	_fire(READY)
	_fire(KNOWN)
	assert_int(_striker.tests).is_greater(capped)
	assert_int(_striker.tests).is_less_equal(TESTS)
