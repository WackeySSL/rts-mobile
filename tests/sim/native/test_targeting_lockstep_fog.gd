extends GdUnitTestSuite
## The vision rule of both TARGETING versions on the fogs that `FogGrid.configure` never makes (ADR
## 0013 section 4, plan P41n2 and P46b), against each other: the GDScript twin and the kernel get
## the same World with the same fog bent, run one TARGETING phase as Sim.step does it (the work
## counts cleared, the grid rebuilt from the positions, Targeting.run) and are compared in full
## (StateDiff, through the rig), and the twin's targets are held to what the rule says, so that two
## versions that agree on the wrong answer fail as well. The suites of test_targeting_lockstep*.gd
## run the fogs that configure() makes, and TargetingTallyProbe works the rule out through
## `FogGrid.is_visible` and `World.cell_of`, which is right for those and not for these (a fog
## that is bent has its own sides), so the phase is driven by hand here, with no probe:
## - a fog whose sides do not make its cells (a column or a row more or less, none, negative, cells
##   that the columns do not divide) is no fog and every cell is seen: two guns that no disc of
##   their own reaches take each other, where the fog as configured gives them nothing;
## - the fog's player blocks follow its `player_count`, not a count of two: an owner past it (a
##   third player of a fog of one) has no grid and sees every cell, and the third player of a fog
##   of three has a block of its own, which does not;
## - the cell is the one of the fog's own sides: a 40 x 20 map whose fog says 20 x 40 (the same 800
##   cells, so a grid) puts an enemy of the tile (33, 10) in the cell 219, which is the tile (19, 5)
##   of the map, where no disc stands.
##
## Two guns of 30 x 30 tiles with a sight of 3000 and a reach of 4000, at (10500, 10500) and (14000,
## 10500): 3500 apart, in each other's reach and each outside the other's disc (the tiles 3 away are
## seen, the one 4 away is not). Every cadence is 1, so each gun scans on every tick.

const Rig: GDScript = preload("res://tests/sim/support/targeting_lockstep_rig.gd")
const TargetingRig: GDScript = preload("res://tests/sim/support/targeting_rig.gd")
const Worlds: GDScript = preload("res://tests/sim/support/targeting_worlds.gd")
const Bends: GDScript = preload("res://tests/sim/support/fog_bends.gd")
const StateDiff: GDScript = preload("res://tests/sim/support/state_diff.gd")
const GUN: int = 0
const SQUARE: int = 30


func test_a_fog_whose_sides_do_not_make_its_cells_is_no_fog_in_both_versions() -> void:
	# The fog as configured: neither gun sees the other.
	var found: Array[int] = _duel_targets(_duel.bind(""), "as configured")
	assert_array(found).is_equal([0, 0])
	for how: String in Bends.NAMES:
		assert_array(_duel_targets(_duel.bind(how), how)).override_failure_message(how).is_equal(
			[2, 1]
		)


func test_the_blocks_of_the_fog_follow_its_player_count_and_not_a_count_of_two() -> void:
	# [the players of the fog, the owners of the two guns, the targets they take]. Owner 2 of a fog of
	# one has no block and sees every cell, so its gun takes the other; owner 3 of a fog of three has
	# a block, of cells it does not see, and takes nobody (a count of two would give it no block).
	var cases: Array[Array] = [
		[2, 1, 2, [0, 0]],
		[1, 1, 2, [0, 1]],
		[3, 3, 1, [0, 0]],
		[3, 1, 3, [0, 0]],
		[3, 2, 3, [0, 0]]
	]
	for item: Array in cases:
		var label: String = "%d players, owners %d and %d" % [item[0], item[1], item[2]]
		var build: Callable = _duel.bind("", item[0], item[1], item[2])
		assert_array(_duel_targets(build, label)).override_failure_message(label).is_equal(item[3])


func test_the_cell_is_the_one_of_the_fogs_own_sides_and_not_of_the_maps() -> void:
	# A gun of player 1 at the tile (30, 10) of a map of 40 x 20 and an enemy at (33, 10): in its disc
	# and in the disc of the enemy, who sees it back (the fog stamps the discs on the layout of the
	# map).
	var as_made: Callable = _wide.bind(false)
	assert_array(_duel_targets(as_made, "as made")).is_equal([2, 1])
	# The same fog read as 20 columns of 40 rows: the tile (33, 10) is the cell 10 * 20 + 19 = 219,
	# and the tile (30, 10) the same, which the layout of 40 columns has as (19, 5), a cell that no
	# disc covers.
	assert_array(_duel_targets(_wide.bind(true), "swapped")).is_equal([0, 0])


func test_an_enemy_on_a_far_half_border_is_seen_by_the_cell_before_it_in_both_versions() -> void:
	# ADR 0033: a point on a tile border past the middle of the map is in the tile before it, for
	# the new lock, the held target and the scan candidate alike, in the twin and in the kernel
	# (`Pass::seen`). The enemy at x = 20000 (the columns 19 | 20) or y = 20000 (the lines 19 | 20)
	# of the 30 x 30 map, player 1's block dark but for the cell before the border (the enemy is
	# seen) or the one after it (it is not).
	var cases: Array[Array] = [
		[Vector2i(20000, 10500), Vector2i(17500, 10500), 10 * SQUARE + 19, 10 * SQUARE + 20],
		[Vector2i(10500, 20000), Vector2i(10500, 17500), 19 * SQUARE + 10, 20 * SQUARE + 10],
		# On the centre line x = 15000 (not past the middle): the tile after the border is the read
		# one, so the cell read is the column 15 and the cell beside it, the column 14, is not.
		[Vector2i(15000, 10500), Vector2i(12500, 10500), 10 * SQUARE + 15, 10 * SQUARE + 14],
	]
	for item: Array in cases:
		for seen_cell: int in [item[2], item[3]]:
			var before: bool = seen_cell == item[2]  # The cell the rule reads is the seen one.
			for mode: String in ["scan", "held", "lock"]:
				var label: String = "%s, %s, cell %d" % [item[0], mode, seen_cell]
				var build: Callable = _border.bind(item[1], item[0], seen_cell, mode)
				var found: Array = _border_run(build, label)
				assert_int(found[0]).override_failure_message(label).is_equal(2 if before else 0)
				if mode == "held":
					assert_bool(found[1] == 0).override_failure_message(label).is_equal(before)


## One TARGETING phase of the pair that `build` makes: the twin's World and the kernel's, compared
## in full, and the targets of the two guns of the twin's World (the kernel's are asserted equal).
## `label` heads a failure.
func _duel_targets(build: Callable, label: String) -> Array[int]:
	var problems: Array[String] = []
	var worlds: Array[World] = Rig.pair(build, Rig.ALL, problems)
	assert_array(problems).override_failure_message(label).is_empty()
	for world: World in worlds:
		world.stats.fill(0)
		world.target_grid.rebuild(world.pos_x, world.pos_y, world.unit_count())
		Targeting.run(world)
	assert_str(StateDiff.first(worlds[0], worlds[1])).override_failure_message(label).is_empty()
	var found: Array[int] = []
	for row: int in 2:
		found.append(worlds[0].target[row])
		assert_int(worlds[1].target[row]).override_failure_message(label).is_equal(found[row])
	# The scan looked at the other gun, as it does a row in reach whatever its fog says.
	var looked: int = worlds[0].stats[World.Stat.TARGET_CANDIDATES]
	assert_int(looked).override_failure_message(label).is_equal(2)
	return found


## The two guns on a 30 x 30 map with `players` players (owners `first` and `second`), the fog
## stamped and then bent as `how` says (nothing for "").
func _duel(how: String, players: int = 2, first: int = 1, second: int = 2) -> World:
	var gun: UnitDef = TargetingRig.unit(&"gun", 3000, 5000, 4000, 0, [100, 100, 100, 100])
	var units: Array[UnitDef] = [gun]
	var world: World = TargetingRig.world_of(units, SQUARE, SQUARE, false, players)
	world.retarget_period_ticks = 1
	world.fog_period_ticks = 1
	# add_unit() takes the owners of the World's players only, and a row of an owner past the fog's
	# count is not stamped, so the owners are set before the stamp.
	world.add_unit(1, GUN, 10500, 10500)
	world.add_unit(1, GUN, 14000, 10500)
	world.owner[0] = first
	world.owner[1] = second
	Worlds.stamp_fog(world)
	if how != "":
		Bends.apply(world.fog, how)
	return world


## A gun of each player on a map of 40 x 20 tiles, in the tiles (30, 10) and (33, 10), the fog
## stamped, and with its sides swapped (20 columns, 40 rows: the same 800 cells) if `swapped`.
func _wide(swapped: bool) -> World:
	var gun: UnitDef = TargetingRig.unit(&"gun", 3000, 5000, 4000, 0, [100, 100, 100, 100])
	var units: Array[UnitDef] = [gun]
	var world: World = TargetingRig.world_of(units, 40, 20, false)
	world.retarget_period_ticks = 1
	world.fog_period_ticks = 1
	world.add_unit(1, GUN, 30500, 10500)
	world.add_unit(2, GUN, 33500, 10500)
	Worlds.stamp_fog(world)
	if swapped:
		world.fog.cols = 20
		world.fog.rows = 40
	return world


## The twin's target and candidate count of the subject (the kernel's are asserted equal), after one
## TARGETING phase of the pair that `build` makes. `label` heads a failure.
func _border_run(build: Callable, label: String) -> Array:
	var problems: Array[String] = []
	var worlds: Array[World] = Rig.pair(build, Rig.ALL, problems)
	assert_array(problems).override_failure_message(label).is_empty()
	for world: World in worlds:
		world.stats.fill(0)
		world.target_grid.rebuild(world.pos_x, world.pos_y, world.unit_count())
		Targeting.run(world)
	assert_str(StateDiff.first(worlds[0], worlds[1])).override_failure_message(label).is_empty()
	assert_int(worlds[1].target[0]).override_failure_message(label).is_equal(worlds[0].target[0])
	var candidates: int = worlds[0].stats[World.Stat.TARGET_CANDIDATES]
	# A kept target is no scan, so no candidate is looked at: the count tells a kept target from one
	# that was dropped and found again by the scan.
	return [worlds[0].target[0], candidates]


## Player 1's gun at `subject` and player 2's at `enemy` on the 30 x 30 map, the fog stamped, then
## dark in player 1's block but for `seen_cell`; `mode` is how the subject holds the enemy: "scan"
## (an idle gun), "held" (the enemy is its target already) or "lock" (an ATTACK on it).
func _border(subject: Vector2i, enemy: Vector2i, seen_cell: int, mode: String) -> World:
	var gun: UnitDef = TargetingRig.unit(&"gun", 3000, 5000, 4000, 0, [100, 100, 100, 100])
	var units: Array[UnitDef] = [gun]
	var world: World = TargetingRig.world_of(units, SQUARE, SQUARE, false)
	world.retarget_period_ticks = 1
	world.fog_period_ticks = 1
	world.add_unit(1, GUN, subject.x, subject.y)
	world.add_unit(2, GUN, enemy.x, enemy.y)
	Worlds.stamp_fog(world)
	world.fog.visible.fill(0)
	world.fog.visible[seen_cell] = 1
	# The enemy moves, so it scans nothing and the candidate count is the subject's alone.
	world.order[1] = World.Order.MOVE
	if mode == "held":
		world.target[0] = 2
	elif mode == "lock":
		world.order[0] = World.Order.ATTACK
		world.order_target[0] = 2
	return world
