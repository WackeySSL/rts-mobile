extends GdUnitTestSuite
## The TARGETING kernel told which index reads which table (ADR 0013 section 4, plan P41n): the type
## tables (movement class, armour, acquire range) are read by the unit's type, the weapon tables
## (range, minimum range, damage percents) by the weapon of the type, and the columns of a row by
## the row. Every roster of the module's other suites has a weapon index equal to its type index
## (the shipped rifle, rocket and tank), and a pass that reads `weapon_range[type]` where the twin
## reads `weapon_range[weapon]` ends the same there. This roster has an unarmed scout first, so the
## two guns have types 1 and 2 and weapons 0 and 1, and a row that is neither:
##   type 0  scout, foot, no weapon, acquire range 9000
##   type 1  gun A, wheeled, light armour, weapon 0: range 4000, minimum range 1000, acquire range
##           5000, 0% against light armour
##   type 2  gun B, tracked, infantry armour, weapon 1: range 3000, minimum range 500, acquire
##           range 6000
## Gun A (row 0, id 1) stands at (10000, 1500) with a gun B far to the south (row 1, in the way of
## nothing) and the enemy in row 2, `gap` to its east. Every case runs on two identical Worlds, one
## with the GDScript phase and one with the kernel, asserts the value the rule gives on each and
## compares their whole state (StateDiff).

const Rig: GDScript = preload("res://tests/sim/support/targeting_rig.gd")
const GridWorld: GDScript = preload("res://tests/sim/support/grid_world.gd")
const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const StateDiff: GDScript = preload("res://tests/sim/support/state_diff.gd")
const TARGETING: int = SimProbe.Phase.TARGETING
const GUN_A: int = 1
const GUN_B: int = 2
const ATTACK_MOVE: int = World.Order.ATTACK_MOVE
const ATTACK: int = World.Order.ATTACK
const DIRECT: int = World.NavMode.DIRECT
const HOLD: int = World.NavMode.HOLD
const CHASE: int = World.NavMode.CHASE
## A `retarget_period_ticks` that no tick of a test reaches: nobody scans.
const NEVER_DUE: int = 1000000
## The terrain that wheeled units cannot cross and foot and tracked units can (the 't' tile).
const BLOCKS_WHEELED: int = 4
const MAP_COLUMNS: int = 20
## The tile of the wall: column 12 of the line (tile row 1) that the units stand on.
const WALL_TILE: int = 1 * MAP_COLUMNS + 12


## The roster is what the cases below need it to be: the weapon index is not the type index, and
## the three tables that the pass reads by type differ between the two guns.
func test_the_roster_has_weapon_indexes_that_are_not_type_indexes() -> void:
	var world: World = _world(3500, false, ATTACK_MOVE, NEVER_DUE, GUN_A)
	assert_array(world.type_weapon).is_equal([-1, 0, 1])
	assert_array(world.type_move_class).is_equal(
		[World.MoveClass.FOOT, World.MoveClass.WHEELED, World.MoveClass.TRACKED]
	)
	assert_array(world.type_armour).is_equal(
		[World.Armour.INFANTRY, World.Armour.LIGHT, World.Armour.INFANTRY]
	)
	assert_array(world.type_acquire).is_equal([9000, 5000, 6000])
	assert_array(world.weapon_range).is_equal([4000, 3000])
	assert_array(world.weapon_min_range).is_equal([1000, 500])
	assert_array(world.weapon_vs_armour).is_equal([100, 0, 100, 100, 100, 100, 100, 100])


## Engagement reads the weapon range by the weapon index: the enemy 3500 away is inside the range
## of gun A's weapon 0 (4000) and outside that of weapon 1 (3000), so gun A holds.
func test_engagement_reads_the_weapon_range_by_the_weapon_index() -> void:
	var pair: Array[World] = _pair(_world.bind(3500, false, ATTACK_MOVE, NEVER_DUE, GUN_A))
	for world: World in pair:
		Rig.acquire(world)
		assert_int(world.nav_mode[0]).override_failure_message(_label(world)).is_equal(HOLD)
	assert_str(StateDiff.first(pair[0], pair[1])).is_empty()


## Engagement reads the minimum range by the weapon index: the enemy 700 away is inside the
## minimum range of weapon 0 (1000) and outside that of weapon 1 (500), so gun A does not hold; it
## chases, the enemy being inside its acquire range on a clear line.
func test_engagement_reads_the_minimum_range_by_the_weapon_index() -> void:
	var pair: Array[World] = _pair(_world.bind(700, false, ATTACK_MOVE, NEVER_DUE, GUN_A))
	for world: World in pair:
		Rig.acquire(world)
		assert_int(world.nav_mode[0]).override_failure_message(_label(world)).is_equal(CHASE)
	assert_str(StateDiff.first(pair[0], pair[1])).is_empty()


## Engagement reads the acquire range by the type index: the enemy 5500 away is outside the acquire
## range of gun A (5000) and inside that of the scout, type 0 (9000), so gun A keeps its path and
## runs no line test.
func test_engagement_reads_the_acquire_range_by_the_type_index() -> void:
	var pair: Array[World] = _pair(_world.bind(5500, false, ATTACK_MOVE, NEVER_DUE, GUN_A))
	for world: World in pair:
		Rig.acquire(world)
		var label: String = _label(world)
		assert_int(world.nav_mode[0]).override_failure_message(label).is_equal(DIRECT)
		assert_int(world.stats[World.Stat.LINE_CHECKS]).override_failure_message(label).is_equal(0)
	assert_str(StateDiff.first(pair[0], pair[1])).is_empty()


## The chase line is tested for the movement class of the type: gun A is wheeled and the wall tile
## stops wheeled units only. Type 0 is a foot unit that crosses it, and 0 is the weapon index of
## gun A, so a class read by the weapon index would find the line clear. The enemy is 4500 away,
## out of weapon range and inside the acquire range, so the line is tested and found blocked: gun A
## keeps its path instead of chasing.
func test_the_chase_line_is_tested_for_the_move_class_of_the_type() -> void:
	var pair: Array[World] = _pair(_world.bind(4500, true, ATTACK_MOVE, NEVER_DUE, GUN_A))
	for world: World in pair:
		Rig.acquire(world)
		var label: String = _label(world)
		assert_int(world.nav_mode[0]).override_failure_message(label).is_equal(DIRECT)
		assert_int(world.stats[World.Stat.LINE_CHECKS]).override_failure_message(label).is_equal(1)
	assert_str(StateDiff.first(pair[0], pair[1])).is_empty()


## The same for an ATTACK unit that has marked its line clear (nav_cell 0): it tests the line again
## on its turn, for the movement class of the type, finds it blocked and resets to DIRECT with an
## unchecked line (nav_cell -1).
func test_the_attack_retest_uses_the_move_class_of_the_type() -> void:
	var pair: Array[World] = _pair(_world.bind(4500, true, ATTACK, NEVER_DUE, GUN_A))
	for world: World in pair:
		world.nav_cell[0] = 0
		Rig.acquire(world)
		var label: String = _label(world)
		assert_int(world.nav_cell[0]).override_failure_message(label).is_equal(-1)
		assert_int(world.nav_mode[0]).override_failure_message(label).is_equal(DIRECT)
		assert_int(world.stats[World.Stat.LINE_CHECKS]).override_failure_message(label).is_equal(1)
	assert_str(StateDiff.first(pair[0], pair[1])).is_empty()


## Acquisition reads the minimum range by the weapon index: gun A, scanning, has gun B 700 away,
## inside the minimum range of weapon 0 (1000) and outside that of weapon 1 (500), so it is no
## candidate and gun A takes no target. Gun B 1100 away is one, which tells the scan from a scan
## that finds nobody.
func test_the_scan_reads_the_minimum_range_by_the_weapon_index() -> void:
	# [the distance of gun B, the target that gun A takes]
	for item: Array in [[700, 0], [1100, 3]]:
		var pair: Array[World] = _pair(_world.bind(item[0], false, ATTACK_MOVE, 1, GUN_B))
		for world: World in pair:
			world.target[0] = 0
			Rig.acquire(world)
			var label: String = "%d, %s" % [item[0], _label(world)]
			assert_int(world.target[0]).override_failure_message(label).is_equal(item[1])
		assert_str(StateDiff.first(pair[0], pair[1])).is_empty()


## A target that is kept is tested against the armour of its type, not of its row: gun A holds the
## enemy in row 2 in range. Row 2 is also the index of type 2 in the armour table (infantry, 100%),
## so a kept-target test that indexed the table by row would keep a gun A (light armour, 0% for
## weapon 0) there. The target is dropped, and the scan that follows finds no candidate (the same
## enemy is 0% too), so gun A ends with 0; a gun B in its place (infantry, 100%) is kept.
func test_a_kept_target_is_tested_against_the_armour_of_its_type_not_of_its_row() -> void:
	# [the type of the enemy, the target that gun A ends with]
	for item: Array in [[GUN_A, 0], [GUN_B, 3]]:
		var pair: Array[World] = _pair(_world.bind(3500, false, ATTACK_MOVE, 1, item[0]))
		for world: World in pair:
			Rig.acquire(world)
			var label: String = "type %d, %s" % [item[0], _label(world)]
			assert_int(world.target[0]).override_failure_message(label).is_equal(item[1])
		assert_str(StateDiff.first(pair[0], pair[1])).is_empty()


## The World of the cases: see the header. Gun A (owner 1, row 0, id 1) has the enemy of type
## `enemy` (owner 2, row 2, id 3) `gap` to its east on the line y = 1500, held by hand
## (`target` 3, and `order_target` 3 for an ATTACK order) with the navigation mode DIRECT; the wall
## tile of that line blocks wheeled units when `wall` is set. Every tick is on the unit's
## line-check turn, and `scan` is the retarget period (NEVER_DUE: nobody scans, so the held target
## stays).
func _world(gap: int, wall: bool, order: int, scan: int, enemy: int) -> World:
	var world: World = Rig.world_of(_roster(), MAP_COLUMNS, 12)
	world.terrain_cost = PackedByteArray(GridWorld.GROUND_COST)
	if wall:
		world.set_terrain(WALL_TILE, BLOCKS_WHEELED)
	world.add_unit(1, GUN_A, 10000, 1500)
	world.add_unit(2, GUN_B, 10000, 9500)
	world.add_unit(2, enemy, 10000 + gap, 1500)
	world.order[0] = order
	world.target[0] = 3
	if order == ATTACK:
		world.order_target[0] = 3
	world.nav_mode[0] = DIRECT
	world.retarget_period_ticks = scan
	world.line_check_period_ticks = 1
	return world


func _roster() -> Array[UnitDef]:
	var scout: UnitDef = Rig.unit(&"scout", 9000, 9000, 0, 0, [])
	var gun_a: UnitDef = Rig.unit(&"gun_a", 9000, 5000, 4000, 1000, [100, 0, 100, 100])
	gun_a.move_class = World.MoveClass.WHEELED
	gun_a.armour = World.Armour.LIGHT
	var gun_b: UnitDef = Rig.unit(&"gun_b", 9000, 6000, 3000, 500, [100, 100, 100, 100])
	gun_b.move_class = World.MoveClass.TRACKED
	return [scout, gun_a, gun_b]


## Two Worlds from the same builder, the first running the GDScript phase and the second the kernel.
func _pair(build: Callable) -> Array[World]:
	var pair: Array[World] = []
	for impl: int in SimImpls.IMPLS:
		var world: World = build.call()
		assert_array(SimImpls.attach(world, impl, TARGETING)).is_empty()
		pair.append(world)
	return pair


func _label(world: World) -> String:
	return "native %s" % (world.native_phases != 0)
