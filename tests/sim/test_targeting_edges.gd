extends GdUnitTestSuite
## The edges of target acquisition (P41; ADR 0009 section 2): the cells that cover the reach (cell
## borders, the range edge, map corners, partial and outside cells), the filters of a candidate
## (minimum range, damage percent, owner), the edges of a kept target, types that cannot shoot
## (and the type and weapon tables each read by its own index), the work count, and what `run`
## reads and writes (the grid as it stands, the target column and the work count only). The
## priority, the stagger, stickiness and the position in the tick are in test_targeting.gd. The
## worlds are those of TargetingRig: the shipped unit types as 0 rifle squad (range 4000, sight
## 6000), 1 rocket squad and 2 light tank, or test-only types for a weapon the shipped ones lack.

const Rig: GDScript = preload("res://tests/sim/support/targeting_rig.gd")
const GridWorld: GDScript = preload("res://tests/sim/support/grid_world.gd")
const RIFLE: int = 0
const ROCKET: int = 1
const TANK: int = 2
const IDLE: int = World.Order.IDLE
const ATTACK_MOVE: int = World.Order.ATTACK_MOVE
const MOVE: int = World.Order.MOVE
const ATTACK: int = World.Order.ATTACK


## The cells that cover the reach: a rifle squad (reach 4000) finds an enemy exactly 4000 away on
## the other side of a border of the 4000-milli cells, whichever side it stands, along an axis and
## along a diagonal (2800 each way, 3960 away), and none that is 4001 away. Each case is a subject
## and an enemy position and whether it is found.
func test_cells_across_a_border_are_searched_and_the_range_edge_is_inclusive() -> void:
	var cases: Array[Array] = [
		[Vector2i(3999, 3999), Vector2i(7999, 3999), true],
		[Vector2i(4000, 4000), Vector2i(0, 4000), true],
		[Vector2i(3999, 3999), Vector2i(3999, 7999), true],
		[Vector2i(4000, 4000), Vector2i(4000, 0), true],
		[Vector2i(4000, 4000), Vector2i(1200, 1200), true],
		[Vector2i(3999, 3999), Vector2i(6799, 6799), true],
		[Vector2i(4000, 4000), Vector2i(6800, 1200), true],
		[Vector2i(4000, 4000), Vector2i(8001, 4000), false],
		[Vector2i(3999, 3999), Vector2i(3999, 7000), true],
		[Vector2i(4000, 4000), Vector2i(0, 3999), false],
		[Vector2i(4000, 4000), Vector2i(8000, 4000), true],
		[Vector2i(7999, 4000), Vector2i(3999, 4000), true],
		[Vector2i(4000, 4000), Vector2i(4000, 8000), true],
		[Vector2i(4000, 7999), Vector2i(4000, 3999), true],
	]
	for item: Array in cases:
		var world: World = Rig.data_world()
		var at: Vector2i = item[0]
		var other: Vector2i = item[1]
		world.add_unit(1, RIFLE, at.x, at.y)
		world.add_unit(2, RIFLE, other.x, other.y)
		var found: bool = Rig.target_of(world, 1) == 2
		assert_bool(found).override_failure_message(str(item)).is_equal(item[2])


## The corners of the map, a partial last cell and positions outside the map (a unit the grid puts
## in an edge cell): the 10 x 6 tile map has 3 x 2 cells, the last of each row and column partial.
## A subject at (0, 0) and one at the far corner find a neighbour, so does one at (9500, 5500) in
## the partial cell, and so do subjects west of, east of and south of the map, which the grid
## clamps to an edge cell and the search reaches through the same clamp.
func test_corners_partial_cells_and_positions_outside_the_map() -> void:
	var cases: Array[Array] = [
		[Vector2i(0, 0), Vector2i(3000, 0)],
		[Vector2i(9999, 5999), Vector2i(7999, 5999)],
		[Vector2i(9500, 5500), Vector2i(6000, 5500)],
		[Vector2i(-500, 100), Vector2i(2000, 100)],
		[Vector2i(11000, 5500), Vector2i(8000, 5500)],
		[Vector2i(9000, 7000), Vector2i(9000, 5500)],
		[Vector2i(0, 0), Vector2i(0, 3999)],
	]
	for item: Array in cases:
		var world: World = Rig.data_world(10, 6)
		var at: Vector2i = item[0]
		var other: Vector2i = item[1]
		world.add_unit(1, RIFLE, at.x, at.y)
		world.add_unit(2, RIFLE, other.x, other.y)
		assert_int(Rig.target_of(world, 1)).override_failure_message(str(item)).is_equal(2)


## The minimum range keeps close candidates out, the edge included: an enemy at exactly the minimum
## range (2000) is a candidate, one at 1500 is not, even though it is nearer. A target held at 1500
## is not valid either, so the scan replaces it. With only the near one, nothing is found.
func test_a_candidate_inside_the_minimum_range_is_not_taken() -> void:
	var gun: UnitDef = Rig.unit(&"gun", 8000, 8000, 6000, 2000, [100, 100, 100, 100])
	var world: World = Rig.world_of([gun])
	world.add_unit(1, 0, 10000, 6000)
	world.add_unit(2, 0, 11500, 6000)
	world.add_unit(2, 0, 12000, 6000)
	world.add_unit(2, 0, 15000, 6000)
	assert_int(Rig.target_of(world, 1)).is_equal(3)
	world.target[0] = 2
	assert_int(Rig.retarget(world, 1)).is_equal(3)
	world.pos_x[2] = 16500
	world.pos_x[3] = 16500
	assert_int(Rig.retarget(world, 1)).is_equal(0)


## A damage percent of 0 against the armour is not a candidate, a held target included, and the
## percent of each of the four armour classes is read from its own column: a weapon with 60 against
## one class and 20 against the others takes the unit of that class, whether the distances grow
## with the class or shrink with it (so the distance does not decide).
func test_a_zero_percent_is_no_candidate_and_each_armour_class_has_its_own_column() -> void:
	var sniper: UnitDef = Rig.unit(&"sniper", 8000, 8000, 6000, 0, [100, 0, 0, 0])
	var light: UnitDef = Rig.unit(&"armoured", 8000, 8000, 0, 0, [])
	light.armour = World.Armour.LIGHT
	var world: World = Rig.world_of([sniper, light, Rig.unit(&"grunt", 8000, 8000, 0, 0, [])])
	world.add_unit(1, 0, 10000, 6000)
	world.add_unit(2, 1, 11500, 6000)
	world.add_unit(2, 2, 13000, 6000)
	assert_int(Rig.target_of(world, 1)).is_equal(3)
	world.pos_x[2] = 18000
	world.target[0] = 2
	assert_int(Rig.retarget(world, 1)).is_equal(0)
	for increasing: bool in [true, false]:
		for chosen: int in 4:
			var classes: Array[UnitDef] = [Rig.unit(&"gun", 8000, 8000, 6000, 0, _column(chosen))]
			for armour: int in 4:
				var dummy: UnitDef = Rig.unit(StringName("class%d" % armour), 8000, 8000, 0, 0, [])
				dummy.armour = armour
				classes.append(dummy)
			var classed: World = Rig.world_of(classes)
			classed.add_unit(1, 0, 10000, 6000)
			var directions: Array[Vector2i] = [
				Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)
			]
			for armour: int in 4:
				var gap: int = 1500 + 500 * armour if increasing else 3000 - 500 * armour
				var at: Vector2i = Vector2i(10000, 6000) + directions[armour] * gap
				classed.add_unit(2, armour + 1, at.x, at.y)
			var label: String = "class %d, increasing %s" % [chosen, increasing]
			assert_int(Rig.target_of(classed, 1)).override_failure_message(label).is_equal(
				2 + chosen
			)


## Friends and neutral units are never candidates, however near: the rifle squad passes its
## neighbour of its own player and a neutral unit (owner 0) for the enemy farther off, and with
## only those two around it takes nothing.
func test_friends_and_neutral_units_are_never_candidates() -> void:
	var world: World = Rig.data_world()
	world.add_unit(1, RIFLE, 10000, 6000)
	world.add_unit(1, RIFLE, 10500, 6000)
	world.add_unit(0, RIFLE, 11000, 6000)
	world.add_unit(2, RIFLE, 13000, 6000)
	assert_int(Rig.target_of(world, 1)).is_equal(4)
	world.owner[3] = 1
	assert_int(Rig.retarget(world, 1)).is_equal(0)


## A type without a weapon never acquires: a scout (no weapon, so the pad -1) stays at 0 whether
## idle or attack-moving with an enemy 1000 away. A hand-built World whose type names weapon 0
## without having a weapon table is read as unarmed too, and `Targeting.run` raises no error for it.
func test_a_type_without_a_weapon_acquires_nothing() -> void:
	var scout: UnitDef = Rig.unit(&"scout", 6000, 5000, 0, 0, [])
	var rifle: UnitDef = load(Rig.RIFLE_PATH) as UnitDef
	var world: World = Rig.world_of([scout, rifle])
	world.add_unit(1, 0, 10000, 6000)
	world.add_unit(2, 1, 11000, 6000)
	assert_int(Rig.target_of(world, 1)).is_equal(0)
	world.order[0] = ATTACK_MOVE
	assert_int(Rig.retarget(world, 1)).is_equal(0)
	assert_int(Rig.target_of(world, 2)).is_equal(1)
	var bare: World = GridWorld.from_rows(GridWorld.grass(10, 6))
	bare.player_count = 2
	bare.type_weapon[0] = 0
	bare.add_unit(1, 0, 3000, 3000)
	bare.add_unit(2, 0, 4000, 3000)
	assert_int(bare.weapon_range.size()).is_equal(0)
	assert_int(Rig.target_of(bare, 1)).is_equal(0)
	assert_int(Rig.target_of(bare, 2)).is_equal(0)


## The work count: the rows looked at in the cells that cover the reach, the unit itself left out,
## whoever they belong to (3 here: the enemy, a friend and a neutral unit in the 3 x 3 cells around
## unit 1; the enemy in the next column of cells is not looked at). A kept target costs nothing: the
## unit does not scan again.
func test_the_work_count_is_the_rows_looked_at_and_a_kept_target_costs_none() -> void:
	var world: World = Rig.data_world()
	world.add_unit(1, RIFLE, 10000, 6000)
	world.add_unit(2, RIFLE, 12000, 6000)
	world.add_unit(1, RIFLE, 7000, 3000)
	world.add_unit(0, RIFLE, 13000, 8000)
	world.add_unit(2, RIFLE, 18000, 6000)
	world.stats.fill(0)
	assert_int(Rig.target_of(world, 1)).is_equal(2)
	assert_int(world.stats[World.Stat.TARGET_CANDIDATES]).is_equal(3)
	world.stats.fill(0)
	assert_int(Rig.retarget(world, 1)).is_equal(2)
	assert_int(world.stats[World.Stat.TARGET_CANDIDATES]).is_equal(0)
	world.target[0] = 0
	assert_int(Rig.retarget(world, 1)).is_equal(2)
	assert_int(world.stats[World.Stat.TARGET_CANDIDATES]).is_equal(3)


## A World with no map has no grid cells: an armed unit with an enemy 140 away finds nothing and
## nothing fails (a World built by hand, with a weapon of range 4000 and no map size). The pass
## still runs over the rows: a stale target on a due idle row is replaced by 0, and a MOVE row
## holds no target (the rule of every World, here a target written by hand).
func test_a_world_without_a_map_has_no_targets() -> void:
	var world: World = World.new()
	world.type_ids.append(&"type")
	world.type_weapon.append(0)
	world.type_acquire.append(5000)
	world.weapon_range.append(4000)
	world.weapon_min_range.append(0)
	world.weapon_vs_armour = PackedInt32Array([100, 100, 100, 100])
	world.add_unit(1, 0, 100, 100)
	world.add_unit(2, 0, 200, 200)
	world.add_unit(1, 0, 300, 300)
	world.prepare()
	assert_int(world.target_grid.cols).is_equal(0)
	world.order[2] = MOVE
	world.target[2] = 2
	world.target[0] = 99
	assert_int(Rig.target_of(world, 1)).is_equal(0)
	assert_int(Rig.target_of(world, 2)).is_equal(0)
	assert_array(world.target).is_equal([0, 0, 0])
	assert_int(world.stats[World.Stat.TARGET_CANDIDATES]).is_equal(0)


## The keep check is inclusive at both ends: a target held at exactly the reach, or at exactly the
## weapon's minimum range, is kept over a better one. An idle rocket squad (weapon range 5000)
## holds a rifle squad (20%) 5000 away and keeps it when a tank (100%) arrives 2000 away. A gun with
## a minimum range of 2000 (20% against infantry, 100% against light armour) holds an infantry unit
## 2000 away and keeps it when a light unit arrives 3000 away. The same targets, one milli beyond
## the reach or inside the minimum range, are not valid (nor candidates), so the tank and the light
## unit are taken.
func test_a_target_at_exactly_the_reach_or_the_minimum_range_is_kept() -> void:
	for beyond: int in [0, 1]:
		var rocket: World = Rig.data_world()
		rocket.add_unit(1, ROCKET, 10000, 6000)
		rocket.add_unit(2, RIFLE, 15000 + beyond, 6000)
		rocket.target[0] = 2
		rocket.add_unit(2, TANK, 12000, 6000)
		var reach_wanted: int = 3 if beyond == 1 else 2
		assert_int(Rig.target_of(rocket, 1)).override_failure_message("reach").is_equal(
			reach_wanted
		)
		var gun: UnitDef = Rig.unit(&"gun", 8000, 8000, 6000, 2000, [20, 100, 100, 100])
		var plate: UnitDef = Rig.unit(&"plate", 8000, 8000, 0, 0, [])
		plate.armour = World.Armour.LIGHT
		var world: World = Rig.world_of([gun, Rig.unit(&"grunt", 8000, 8000, 0, 0, []), plate])
		world.add_unit(1, 0, 10000, 6000)
		world.add_unit(2, 1, 12000 - beyond, 6000)
		world.target[0] = 2
		world.add_unit(2, 2, 13000, 6000)
		var min_wanted: int = 3 if beyond == 1 else 2
		assert_int(Rig.target_of(world, 1)).override_failure_message("minimum").is_equal(min_wanted)


## Each table is read by its own index: the type tables (acquire range, armour) by the unit's type
## and the weapon tables by the type's weapon. Type 0 is a scout with no weapon and an acquire
## range of 3000, type 1 a gun (weapon 0) with an acquire range of 5000 and a weapon range of 3000.
## An attack-moving gun finds an enemy 4500 away (the acquire range of type 1), an idle one does
## not (the weapon range of weapon 0).
func test_acquire_is_read_by_type_and_the_weapon_by_weapon_index() -> void:
	var scout: UnitDef = Rig.unit(&"scout", 8000, 3000, 0, 0, [])
	var gun: UnitDef = Rig.unit(&"gun", 8000, 5000, 3000, 0, [100, 100, 100, 100])
	var world: World = Rig.world_of([scout, gun])
	world.add_unit(1, 1, 10000, 6000)
	world.add_unit(2, 1, 14500, 6000)
	world.order[0] = ATTACK_MOVE
	assert_int(Rig.target_of(world, 1)).is_equal(2)
	world.order[0] = IDLE
	world.target[0] = 0
	assert_int(Rig.retarget(world, 1)).is_equal(0)


## A subject at a corner of the map looks only at the cells that cover its reach: the work count is
## the rows of those cells, so a cell index below zero (the reach reaching past the edge) must be
## clamped to the first cell and not wrap to the far end of the grid. Unit 1 stands at (0, 0) of
## the 20 x 12 tile map (5 x 3 cells) with one enemy 3000 away; neutral units stand in the three
## far cells that a wrapped column or line would read (the last cell, the last cell of the first
## line, the first cell of the last line). The count is the one row of the covering cells.
func test_a_corner_subject_looks_only_at_the_covering_cells() -> void:
	var world: World = Rig.data_world()
	world.add_unit(1, RIFLE, 0, 0)
	world.add_unit(2, RIFLE, 3000, 0)
	world.add_unit(0, RIFLE, 19500, 11500)
	world.add_unit(0, RIFLE, 17000, 1000)
	world.add_unit(0, RIFLE, 500, 9000)
	world.stats.fill(0)
	assert_int(Rig.target_of(world, 1)).is_equal(2)
	assert_int(world.stats[World.Stat.TARGET_CANDIDATES]).is_equal(1)


## `run` reads the grid as it stands and never rebuilds it (the caller does, in GRIDS): the enemy is
## moved next to unit 1 after the rebuild, so the grid still lists it in its old cell, 8000 away,
## and unit 1 does not find it; the grid and the work count are left as they were. A pass that
## rebuilt the grid would find it, as the caller's own rebuild does in the last step.
func test_run_reads_the_grid_as_it_stands_and_never_rebuilds_it() -> void:
	var world: World = Rig.data_world()
	world.add_unit(1, RIFLE, 10000, 6000)
	world.add_unit(2, RIFLE, 18000, 6000)
	world.tick = Rig.due_tick_for(world, 1)
	world.prepare()
	world.target_grid.rebuild(world.pos_x, world.pos_y, world.unit_count())
	var heads: PackedInt32Array = world.target_grid.head.duplicate()
	var links: PackedInt32Array = world.target_grid.next.duplicate()
	world.pos_x[1] = 12000
	Targeting.run(world)
	assert_int(world.target[0]).is_equal(0)
	assert_array(world.target_grid.head).is_equal(heads)
	assert_array(world.target_grid.next).is_equal(links)
	assert_int(world.stats[World.Stat.TARGET_CANDIDATES]).is_equal(0)
	Rig.acquire(world)
	assert_int(world.target[0]).is_equal(2)


## `run` writes the `target` column and the work count, nothing else: not the orders, the order
## targets, the goals, the navigation, any other column of the rows, the other work counts or the
## events. The rows: an idle rocket squad that acquires a tank, a MOVE row and an ATTACK row that
## hold a stale target (cleared), and an idle rifle squad with nothing in reach (0).
func test_run_writes_only_the_target_column_and_the_work_count() -> void:
	var world: World = Rig.data_world()
	world.add_unit(1, ROCKET, 10000, 6000)
	world.add_unit(2, TANK, 12000, 6000)
	world.add_unit(2, RIFLE, 8000, 6000)
	world.add_unit(1, RIFLE, 10000, 3000)
	world.add_unit(1, RIFLE, 10000, 9000)
	world.add_unit(1, RIFLE, 1000, 11000)
	world.order[3] = MOVE
	world.target[3] = 2
	world.order[4] = ATTACK
	world.order_target[4] = 3
	world.target[4] = 3
	world.goal_x[0] = 7000
	world.cooldown[0] = 5
	world.tick = Rig.due_tick_for(world, 1)
	var before: Dictionary[StringName, PackedInt32Array] = {}
	for column: StringName in World.ROW_ARRAYS:
		before[column] = (world.get(column) as PackedInt32Array).duplicate()
	var stats: PackedInt32Array = world.stats.duplicate()
	var events: PackedInt32Array = world.events.duplicate()
	var tick: int = world.tick
	Rig.acquire(world)
	assert_array(world.target).is_equal([2, 0, 0, 0, 0, 0])
	for column: StringName in World.ROW_ARRAYS:
		if column != &"target":
			assert_array(world.get(column)).override_failure_message(str(column)).is_equal(
				before[column]
			)
	assert_array(world.events).is_equal(events)
	assert_int(world.tick).is_equal(tick)
	assert_int(world.stats[World.Stat.TARGET_CANDIDATES]).is_greater(0)
	stats[World.Stat.TARGET_CANDIDATES] = world.stats[World.Stat.TARGET_CANDIDATES]
	assert_array(world.stats).is_equal(stats)


## A weapon's percents with `chosen` at 60 and the other three armour classes at 20.
func _column(chosen: int) -> Array[int]:
	var percents: Array[int] = [20, 20, 20, 20]
	percents[chosen] = 60
	return percents
