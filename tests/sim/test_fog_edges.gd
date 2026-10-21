extends GdUnitTestSuite
## The edges of the fog update (P46 fix 1), the cases test_fog.gd leaves open: the unstamp of a
## dying row for every kind of row (a mover that left its stamped tile, a player 2 row, a row never
## stamped, a row on cell 0), the clipping of FOG_CELLS on the bottom edge and on a map that is not
## square, a position on or past the map edge (and past one edge of a map that is not square), the
## cadence at other periods than 3, and the pad mask of a type with no entry after a mask was added.
## Hand-built worlds with literal numbers; the expected cells come from a brute force over the whole
## map, never from FogGrid. Units stand idle (speed 0) and the tests move them by writing the
## position between steps.
##
## Every case runs under both implementations (ADR 0013 section 3, P46n): the GDScript phase and
## the C++ kernel, through `_both()` and `_in()`.

const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const FOG: int = SimProbe.Phase.FOG
const SQUARE: int = 30
## Type indexes: 0 sees 6000 (113 cells), 1 sees 2000 (13 cells).
const SCOUT: int = 0
const POST: int = 1


## The scout moves two tiles after its player's update (tick 0) and dies on tick 2, which is
## nobody's turn: the row stands on tile 12 and is stamped on tile 10. Its vision ends where it was
## stamped, so the only disc left is the survivor's, no count is negative, and the dead disc is
## listed.
func test_a_row_that_moved_after_its_update_is_unstamped_where_it_was_stamped(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _world()
	world.add_unit(1, SCOUT, _centre(10), _centre(10))
	world.add_unit(1, POST, _centre(25), _centre(25))
	world.add_unit(2, POST, _centre(5), _centre(25))
	_in(world, impl)
	Sim.step(world, [])
	world.pos_x[0] = _centre(12)
	Sim.step(world, [])
	assert_int(world.fog_cell[0]).is_equal(10 * SQUARE + 10)
	world.hp[0] = 0
	Sim.step(world, [])
	assert_int(world.tick).is_equal(3)
	assert_int(world.unit_count()).is_equal(2)
	assert_array(_block(world, 1)).is_equal(
		_counts(SQUARE, SQUARE, [_disc(SQUARE, SQUARE, 25, 25, 2000)])
	)
	assert_int(_negatives(_block(world, 1))).is_equal(0)
	assert_array(_sorted(world.fog.dirty_cells(1))).is_equal(_disc(SQUARE, SQUARE, 10, 10, 6000))
	assert_array(_block(world, 2)).is_equal(
		_counts(SQUARE, SQUARE, [_disc(SQUARE, SQUARE, 5, 25, 2000)])
	)


## Player 2's row dies on player 2's own turn (tick 1): its disc leaves player 2's grid, player 1's
## grid and dirty list are as they were, and player 2's explored cells stay.
func test_a_player_2_row_dies_in_its_own_players_grid(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _world()
	world.add_unit(1, SCOUT, _centre(10), _centre(10))
	world.add_unit(2, SCOUT, _centre(20), _centre(20))
	world.add_unit(2, POST, _centre(5), _centre(25))
	_in(world, impl)
	Sim.step(world, [])
	var own: PackedInt32Array = _block(world, 1)
	var version: int = world.fog.version_of(1)
	assert_array(own).is_equal(_counts(SQUARE, SQUARE, [_disc(SQUARE, SQUARE, 10, 10, 6000)]))
	world.hp[1] = 0
	Sim.step(world, [])
	assert_int(world.unit_count()).is_equal(2)
	assert_array(_block(world, 1)).is_equal(own)
	assert_int(world.fog.version_of(1)).is_equal(version)
	assert_array(world.fog.dirty_cells(1)).is_empty()
	assert_array(_block(world, 2)).is_equal(
		_counts(SQUARE, SQUARE, [_disc(SQUARE, SQUARE, 5, 25, 2000)])
	)
	assert_int(_negatives(_block(world, 2))).is_equal(0)
	assert_array(_sorted(world.fog.dirty_cells(2))).is_equal(_disc(SQUARE, SQUARE, 20, 20, 6000))
	for cell: int in _disc(SQUARE, SQUARE, 20, 20, 6000):
		assert_bool(world.fog.is_explored(2, cell)).is_true()


## A row added after prepare() is stamped at its player's next update, and a neutral row never. Both
## die before that, with fog_cell -1: nothing is unstamped, so no count and no version changes (an
## unstamp at cell -1 would wrap into another block).
func test_a_row_that_was_never_stamped_dies_without_changing_a_count(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _world()
	world.add_unit(1, POST, _centre(5), _centre(5))
	world.add_unit(2, POST, _centre(5), _centre(25))
	_in(world, impl)
	Sim.step(world, [])
	world.add_unit(1, SCOUT, _centre(15), _centre(15))
	world.add_unit(0, SCOUT, _centre(20), _centre(20))
	assert_array(world.fog_cell.slice(2)).is_equal([-1, -1])
	var versions: Array[int] = [world.fog.version_of(1), world.fog.version_of(2)]
	var before: PackedInt32Array = world.fog.visible.duplicate()
	world.hp[2] = 0
	world.hp[3] = 0
	Sim.step(world, [])
	assert_int(world.tick).is_equal(2)
	assert_int(world.unit_count()).is_equal(2)
	assert_array(world.fog.visible).is_equal(before)
	assert_array([world.fog.version_of(1), world.fog.version_of(2)]).is_equal(versions)
	assert_array(world.fog.dirty_cells(1)).is_empty()
	assert_array(world.fog.dirty_cells(2)).is_empty()
	assert_int(_negatives(world.fog.visible)).is_equal(0)


## A row on cell 0 is stamped (a stamp of cell 0 is not "not stamped") and gives up its vision when
## it dies.
func test_a_row_on_cell_0_gives_up_its_vision(impl: int, _test_parameters := _both()) -> void:
	var world: World = _world()
	world.add_unit(1, SCOUT, _centre(0), _centre(0))
	world.add_unit(1, POST, _centre(25), _centre(25))
	_in(world, impl)
	Sim.step(world, [])
	assert_int(world.fog_cell[0]).is_equal(0)
	assert_bool(world.fog.is_visible(1, 6)).is_true()
	world.hp[0] = 0
	Sim.step(world, [])
	assert_array(_block(world, 1)).is_equal(
		_counts(SQUARE, SQUARE, [_disc(SQUARE, SQUARE, 25, 25, 2000)])
	)
	assert_array(_sorted(world.fog.dirty_cells(1))).is_equal(_disc(SQUARE, SQUARE, 0, 0, 6000))
	assert_bool(world.fog.is_explored(1, 6)).is_true()


## The same unit steps along the bottom row: its two discs are clipped at the bottom edge, and
## stats[FOG_CELLS] counts only the cells inside the map (brute force).
func test_fog_cells_clip_the_discs_on_the_bottom_row(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _world()
	world.add_unit(1, SCOUT, _centre(15), _centre(29))
	world.prepare()
	_in(world, impl)
	world.pos_x[0] = _centre(16)
	Sim.step(world, [])
	var cells: int = _disc(SQUARE, SQUARE, 16, 29, 6000).size()
	cells += _disc(SQUARE, SQUARE, 15, 29, 6000).size()
	assert_int(world.stats[World.Stat.FOG_CELLS]).is_equal(cells)
	assert_bool(cells < 2 * 113).is_true()
	assert_array(_block(world, 1)).is_equal(
		_counts(SQUARE, SQUARE, [_disc(SQUARE, SQUARE, 16, 29, 6000)])
	)


## A map of 40 x 20 tiles: the cell is row * 40 + column, the grids are 800 cells, and the discs
## are clipped at column 39 and row 19. Player 1 steps down a column near the top right, player 2
## across the bottom row near the left.
func test_a_map_wider_than_it_is_tall_is_indexed_by_its_columns(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _world(40, 20)
	world.add_unit(1, SCOUT, _centre(38), _centre(3))
	world.add_unit(2, POST, _centre(2), _centre(19))
	world.prepare()
	_in(world, impl)
	assert_int(world.fog.cells).is_equal(800)
	assert_array(world.fog_cell).is_equal([3 * 40 + 38, 19 * 40 + 2])
	world.pos_y[0] = _centre(4)
	world.pos_x[1] = _centre(3)
	Sim.step(world, [])
	assert_int(world.fog_cell[0]).is_equal(4 * 40 + 38)
	assert_int(world.stats[World.Stat.FOG_CELLS]).is_equal(
		_disc(40, 20, 38, 4, 6000).size() + _disc(40, 20, 38, 3, 6000).size()
	)
	Sim.step(world, [])
	assert_int(world.fog_cell[1]).is_equal(19 * 40 + 3)
	assert_int(world.stats[World.Stat.FOG_CELLS]).is_equal(
		_disc(40, 20, 3, 19, 2000).size() + _disc(40, 20, 2, 19, 2000).size()
	)
	assert_array(_block(world, 1)).is_equal(_counts(40, 20, [_disc(40, 20, 38, 4, 6000)]))
	assert_array(_block(world, 2)).is_equal(_counts(40, 20, [_disc(40, 20, 3, 19, 2000)]))
	assert_int(world.fog.dirty_cells(1).size()).is_equal(_flips(40, 20, 38, 3, 38, 4, 6000).size())


## A position on the map's far edge, past it, or before its origin stamps the cell that
## World.cell_of gives (the nearest tile inside the map): the corner cells 899 and 0, not a cell of
## the next row or one outside the grid.
func test_a_position_on_or_past_the_map_edge_stamps_the_nearest_cell(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _world()
	world.add_unit(1, POST, _centre(10), _centre(10))
	world.add_unit(1, POST, _centre(12), _centre(10))
	world.prepare()
	_in(world, impl)
	world.pos_x[0] = 30000
	world.pos_y[0] = 30700
	world.pos_x[1] = -1500
	world.pos_y[1] = -1
	Sim.step(world, [])
	assert_array(world.fog_cell).is_equal([899, 0])
	assert_int(world.fog_cell[0]).is_equal(world.cell_of(30000, 30700))
	assert_int(world.fog_cell[1]).is_equal(world.cell_of(-1500, -1))
	var expected: PackedInt32Array = _counts(
		SQUARE, SQUARE, [_disc(SQUARE, SQUARE, 29, 29, 2000), _disc(SQUARE, SQUARE, 0, 0, 2000)]
	)
	assert_array(_block(world, 1)).is_equal(expected)


## Each axis clamps to its own side of a map that is not square: a position far past the right edge
## stamps column cols - 1 and one far below the bottom edge row rows - 1, on a map wider than it is
## tall (40 x 20) and on one taller than it is wide (20 x 40). The square map of the case above
## cannot tell cols from rows apart, and neither can an in-map position.
func test_each_axis_of_a_map_that_is_not_square_clamps_to_its_own_side(
	impl: int, _test_parameters := _both()
) -> void:
	for size: Vector2i in [Vector2i(40, 20), Vector2i(20, 40)]:
		var world: World = _world(size.x, size.y)
		world.add_unit(1, POST, _centre(3), _centre(3))
		world.add_unit(1, POST, _centre(4), _centre(5))
		world.prepare()
		_in(world, impl)
		world.pos_x[0] = size.x * 1000 + 7000
		world.pos_y[1] = size.y * 1000 + 7000
		Sim.step(world, [])
		var right: int = 3 * size.x + size.x - 1
		var bottom: int = (size.y - 1) * size.x + 4
		assert_array(world.fog_cell).override_failure_message("map %s" % size).is_equal(
			[right, bottom]
		)
		assert_int(world.fog_cell[0]).is_equal(world.cell_of(world.pos_x[0], world.pos_y[0]))
		assert_int(world.fog_cell[1]).is_equal(world.cell_of(world.pos_x[1], world.pos_y[1]))
		var edge: Array[PackedInt32Array] = [
			_disc(size.x, size.y, size.x - 1, 3, 2000), _disc(size.x, size.y, 4, size.y - 1, 2000)
		]
		assert_array(_block(world, 1)).override_failure_message("map %s" % size).is_equal(
			_counts(size.x, size.y, edge)
		)


## The period is the rule int of the World, not 3: with 2 and with 4, player 1 updates on ticks
## 0, 2, 4... and 0, 4, 8..., player 2 one tick later, and at each update the dirty list is emptied
## first, so it holds the flips of that update alone.
func test_the_cadence_follows_the_period_of_the_world(
	impl: int, _test_parameters := _both()
) -> void:
	var expected: Dictionary = {
		2: [[0, 2, 4, 6, 8, 10], [1, 3, 5, 7, 9, 11]], 4: [[0, 4, 8], [1, 5, 9]]
	}
	for period: int in expected:
		var world: World = _world()
		world.fog_period_ticks = period
		world.add_unit(1, SCOUT, _centre(8), _centre(10))
		world.add_unit(2, SCOUT, _centre(8), _centre(20))
		world.prepare()
		_in(world, impl)
		var ticks: Array[PackedInt32Array] = [PackedInt32Array(), PackedInt32Array()]
		var at: PackedInt32Array = PackedInt32Array([8, 8])
		for tick: int in 12:
			world.pos_x[0] = _centre(9 + tick)
			world.pos_x[1] = _centre(9 + tick)
			Sim.step(world, [])
			for row: int in 2:
				if world.fog_cell[row] != (10 + row * 10) * SQUARE + 9 + tick:
					continue
				ticks[row].append(tick)
				var flips: PackedInt32Array = _flips(
					SQUARE, SQUARE, at[row], 10 + row * 10, 9 + tick, 10 + row * 10, 6000
				)
				(
					assert_array(_sorted(world.fog.dirty_cells(row + 1)))
					. override_failure_message(
						"period %d player %d tick %d" % [period, row + 1, tick]
					)
					. is_equal(flips)
				)
				at[row] = 9 + tick
		assert_array(ticks[0]).override_failure_message("period %d" % period).is_equal(
			expected[period][0]
		)
		assert_array(ticks[1]).override_failure_message("period %d" % period).is_equal(
			expected[period][1]
		)


## A period of 0 (or less) is read as 1: every player updates on every tick, and nothing divides
## by zero.
func test_a_period_below_1_updates_every_player_on_every_tick(
	impl: int, _test_parameters := _both()
) -> void:
	for period: int in [0, -2]:
		var world: World = _world()
		world.fog_period_ticks = period
		world.add_unit(1, POST, _centre(8), _centre(10))
		world.add_unit(2, POST, _centre(8), _centre(20))
		world.prepare()
		_in(world, impl)
		for tick: int in 5:
			world.pos_x[0] = _centre(9 + tick)
			world.pos_x[1] = _centre(9 + tick)
			Sim.step(world, [])
			assert_array(world.fog_cell).override_failure_message("tick %d" % tick).is_equal(
				[10 * SQUARE + 9 + tick, 20 * SQUARE + 9 + tick]
			)


## A type with no entry sees its own tile with the pad mask, the one that prepare() added after one
## mask per type. A mask added later (a test's, here 3000) changes no id: the row moves and dies
## with the pad mask, so the counts stay exact.
func test_a_type_with_no_entry_keeps_the_pad_mask_when_a_mask_is_added_later(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _world()
	world.add_unit(1, 4, _centre(7), _centre(9))
	world.prepare()
	_in(world, impl)
	assert_int(world.fog.mask_start.size()).is_equal(3)
	assert_int(world.fog.add_mask(3000)).is_equal(3)
	world.pos_x[0] = _centre(8)
	FogUpdate.run(world)
	assert_int(world.fog_cell[0]).is_equal(9 * SQUARE + 8)
	assert_array(_block(world, 1)).is_equal(
		_counts(SQUARE, SQUARE, [_disc(SQUARE, SQUARE, 8, 9, 0)])
	)
	assert_int(world.stats[World.Stat.FOG_CELLS]).is_equal(2)
	world.hp[0] = 0
	world.remove_dead()
	assert_array(_block(world, 1)).is_equal(_counts(SQUARE, SQUARE, []))


## The dirty list is in the order the cells first flip, which is the order of the rows (ascending),
## and within a row the new disc's cells by cell index, then the old disc's. Two movers of player 1
## with overlapping discs, from a model of the counts with a brute force of the discs: the list is
## compared as it stands, not sorted, so a walk of the rows in reverse (the order of two rows'
## flips swapped) or a sorted list fails. Row 1 also finds cells that row 0 listed already.
func test_the_dirty_list_is_in_the_order_the_cells_first_flip(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _world()
	world.add_unit(1, SCOUT, _centre(10), _centre(10))
	world.add_unit(1, SCOUT, _centre(14), _centre(12))
	world.add_unit(2, POST, _centre(20), _centre(20))
	world.prepare()
	_in(world, impl)
	var moves: Array[Array] = [
		[Vector2i(10, 10), Vector2i(11, 10)], [Vector2i(14, 12), Vector2i(14, 13)]
	]
	world.pos_x[0] = _centre(11)
	world.pos_y[1] = _centre(13)
	var counts: PackedInt32Array = _counts(
		SQUARE, SQUARE, [_disc(SQUARE, SQUARE, 10, 10, 6000), _disc(SQUARE, SQUARE, 14, 12, 6000)]
	)
	var expected: PackedInt32Array = _first_flips(counts, moves)
	Sim.step(world, [])
	assert_array(world.fog_cell.slice(0, 2)).is_equal([10 * SQUARE + 11, 13 * SQUARE + 14])
	assert_array(world.fog.dirty_cells(1)).is_equal(expected)
	assert_array(_sorted(expected)).is_equal(_sorted(world.fog.dirty_cells(1)))
	# The case tells the orders apart: not sorted, not the rows reversed.
	assert_array(expected).is_not_equal(_sorted(expected))
	var swapped: Array[Array] = [moves[1], moves[0]]
	assert_array(expected).is_not_equal(_first_flips(counts, swapped))
	assert_bool(world.fog.dirty_overflowed(1)).is_false()


## Player p updates on the ticks with tick % period == (p - 1) % period, for seven players and
## periods 1, 2, 3 and 5, from tick 0: the test of the update is `(tick - p + 1) % period == 0`, a
## left side below 0 for a player above tick + 1 (-3 % 3 is 0 and -4 % 3 is -1, both truncating
## toward zero in either implementation). Every row steps a tile on every tick, so a row updates
## exactly when it is stamped at its new tile.
func test_every_player_updates_on_its_own_ticks_from_tick_0(
	impl: int, _test_parameters := _both()
) -> void:
	for period: int in [1, 2, 3, 5]:
		var world: World = _world()
		world.fog_period_ticks = period
		for player: int in range(1, 8):
			world.add_unit(player, POST, _centre(2), _centre(player * 3))
		world.prepare()
		_in(world, impl)
		for tick: int in 12:
			for row: int in 7:
				world.pos_x[row] = _centre(3 + tick)
			Sim.step(world, [])
			for row: int in 7:
				var updated: bool = world.fog_cell[row] == (row + 1) * 3 * SQUARE + 3 + tick
				var turn: bool = tick % period == row % period
				(
					assert_bool(updated)
					. override_failure_message(
						"period %d player %d tick %d" % [period, row + 1, tick]
					)
					. is_equal(turn)
				)


## A World of `cols` x `rows` tiles with two players, a scout type (sight 6000) and a post type
## (sight 2000).
func _world(cols: int = SQUARE, rows: int = SQUARE) -> World:
	var world: World = World.new()
	world.map_w = cols * 1000
	world.map_h = rows * 1000
	world.type_ids.append_array([&"scout", &"post"])
	world.type_sight.append_array([6000, 2000])
	return world


## The middle of tile `tile` in milli-tiles.
func _centre(tile: int) -> int:
	return tile * 1000 + 500


## gdUnit4's parameter sets: the GDScript phase and the C++ kernel, a case each (SimImpls.CASES).
func _both() -> Array[Array]:
	return SimImpls.CASES.duplicate(true)


## `world` running `impl`: the kernels attached and the FOG phase really in the implementation
## asked for (the problems of SimImpls.attach, none).
func _in(world: World, impl: int) -> World:
	assert_array(SimImpls.attach(world, impl, FOG)).is_empty()
	return world


## The cells in the order they first flip when each move (a [from, to] pair of tiles, sight 6000)
## is made in turn with the new disc stamped before the old one is unstamped, from a model of the
## visible counts: the cells of a disc by cell index, each listed once.
func _first_flips(counts: PackedInt32Array, moves: Array[Array]) -> PackedInt32Array:
	var visible: PackedInt32Array = counts.duplicate()
	var out: PackedInt32Array = PackedInt32Array()
	for move: Array in moves:
		var from: Vector2i = move[0]
		var to: Vector2i = move[1]
		for cell: int in _disc(SQUARE, SQUARE, to.x, to.y, 6000):
			visible[cell] += 1
			if visible[cell] == 1 and not out.has(cell):
				out.append(cell)
		for cell: int in _disc(SQUARE, SQUARE, from.x, from.y, 6000):
			visible[cell] -= 1
			if visible[cell] == 0 and not out.has(cell):
				out.append(cell)
	return out


## The tiles of a `cols` x `rows` map inside the disc of `sight` milli-tiles at tile (cx, cy), by
## a brute force over every tile: (dx * 1000)^2 + (dy * 1000)^2 <= sight^2, ascending.
func _disc(cols: int, rows: int, cx: int, cy: int, sight: int) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for y: int in rows:
		for x: int in cols:
			var dx: int = (x - cx) * 1000
			var dy: int = (y - cy) * 1000
			if dx * dx + dy * dy <= sight * sight:
				out.append(y * cols + x)
	return out


## The cells that differ between the discs of `sight` at (x1, y1) and at (x2, y2), ascending.
func _flips(
	cols: int, rows: int, x1: int, y1: int, x2: int, y2: int, sight: int
) -> PackedInt32Array:
	var one: PackedInt32Array = _disc(cols, rows, x1, y1, sight)
	var two: PackedInt32Array = _disc(cols, rows, x2, y2, sight)
	var out: PackedInt32Array = PackedInt32Array()
	for cell: int in cols * rows:
		if one.has(cell) != two.has(cell):
			out.append(cell)
	return out


## How many of `discs` cover each cell of a `cols` x `rows` map.
func _counts(cols: int, rows: int, discs: Array[PackedInt32Array]) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	out.resize(cols * rows)
	for disc: PackedInt32Array in discs:
		for cell: int in disc:
			out[cell] += 1
	return out


## The visible counts of one player, one per cell.
func _block(world: World, player: int) -> PackedInt32Array:
	var cells: int = world.fog.cells
	return world.fog.visible.slice((player - 1) * cells, player * cells)


## How many counts are below 0.
func _negatives(counts: PackedInt32Array) -> int:
	var below: int = 0
	for count: int in counts:
		if count < 0:
			below += 1
	return below


func _sorted(cells: PackedInt32Array) -> PackedInt32Array:
	var out: PackedInt32Array = cells.duplicate()
	out.sort()
	return out
