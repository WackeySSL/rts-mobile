extends GdUnitTestSuite
## FixedMath.line_clear at the two places where test_fixed_math has no hand case (P37a fix 2): a
## segment that ends on the far edge of the map keeps its slope, because a point is clamped into
## the grid [0, cols * 1000] and no further (the far edge belongs to the last tile, World.cell_of),
## and a tile blocks at a move cost of 0 only (ADR 0008 section 1: 0 is blocked, 10 is normal, a
## cost above 10 is slower ground, capped at 40). The maps are built in code (GridWorld). The tiles
## that a segment touches are worked out by hand from the rule in line_clear's header, which the
## oracle in test_fixed_math states in exact integers: a tile is half-open, and a corner strictly
## between the ends of a segment along no axis touches the four tiles around it.

const GridWorld: GDScript = preload("res://tests/sim/support/grid_world.gd")
const FOOT: int = World.MoveClass.FOOT
const WHEELED: int = World.MoveClass.WHEELED
const TRACKED: int = World.MoveClass.TRACKED
const TILE: int = World.MILLI_PER_TILE
## The map of the tests: 5 x 5 tiles, so its far corner is (5000, 5000).
const SIDE: int = 5
const FAR: int = SIDE * TILE

## The tiles that block the segment a-b when they alone are rock, both ways round (a segment has no
## direction). A tile that blocks one way and not the other fails the test.
@warning_ignore("integer_division")
func _blockers(a: Vector2i, b: Vector2i, move_class: int = TRACKED) -> Array[Vector2i]:
	var world: World = GridWorld.from_rows(GridWorld.grass(SIDE, SIDE))
	var rock: int = GridWorld.GROUND.find("#")
	var found: Array[Vector2i] = []
	for cell: int in SIDE * SIDE:
		world.set_terrain(cell, rock)
		var forward: bool = FixedMath.line_clear(world, a.x, a.y, b.x, b.y, move_class)
		var backward: bool = FixedMath.line_clear(world, b.x, b.y, a.x, a.y, move_class)
		(
			assert_bool(backward)
			. override_failure_message("%s to %s, rock at cell %d" % [a, b, cell])
			. is_equal(forward)
		)
		if not forward:
			found.append(Vector2i(cell % SIDE, cell / SIDE))
		world.set_terrain(cell, 0)
	return found


## line_clear both ways round on `world`.
func _clear(world: World, a: Vector2i, b: Vector2i, move_class: int = TRACKED) -> bool:
	var forward: bool = FixedMath.line_clear(world, a.x, a.y, b.x, b.y, move_class)
	var backward: bool = FixedMath.line_clear(world, b.x, b.y, a.x, a.y, move_class)
	assert_bool(backward).override_failure_message("%s to %s" % [a, b]).is_equal(forward)
	return forward


## The diagonals of the map end exactly on its far corner (5000, 5000) or start on its other
## ones. They cross the corners (1000, 1000) to (4000, 4000) (or x + y = 5000), and each crossing
## touches the four tiles around it: 13 tiles, among them (1, 0) and (0, 1) beside the first
## corner and (4, 3) and (3, 4) beside the last. A far edge pulled in by one milli (a clamp to
## cols * 1000 - 1, on either axis) tilts the segment off the corners and drops the tiles beside
## them.
func test_a_diagonal_that_ends_on_the_far_corner_keeps_its_slope() -> void:
	# From the top left corner to the far corner: both ends of the clamp are in play.
	var falling: Array[Vector2i] = [
		Vector2i(0, 0),
		Vector2i(1, 0),
		Vector2i(0, 1),
		Vector2i(1, 1),
		Vector2i(2, 1),
		Vector2i(1, 2),
		Vector2i(2, 2),
		Vector2i(3, 2),
		Vector2i(2, 3),
		Vector2i(3, 3),
		Vector2i(4, 3),
		Vector2i(3, 4),
		Vector2i(4, 4),
	]
	assert_array(_blockers(Vector2i(0, 0), Vector2i(FAR, FAR))).contains_exactly_in_any_order(
		falling
	)
	# The case by itself: rock only at (1, 0), beside the first corner, blocks it in both directions.
	var beside: World = GridWorld.from_rows(GridWorld.grass(SIDE, SIDE, [Vector2i(1, 0)]))
	assert_bool(FixedMath.line_clear(beside, 0, 0, FAR, FAR, TRACKED)).is_false()
	assert_bool(FixedMath.line_clear(beside, FAR, FAR, 0, 0, TRACKED)).is_false()
	# From the bottom left corner to the top right one: the segment starts on the far edge of y and
	# ends on the far edge of x. Rock only at (1, 4), beside the corner (1000, 4000), blocks it.
	var rising: Array[Vector2i] = [
		Vector2i(0, 4),
		Vector2i(1, 4),
		Vector2i(0, 3),
		Vector2i(1, 3),
		Vector2i(2, 3),
		Vector2i(1, 2),
		Vector2i(2, 2),
		Vector2i(3, 2),
		Vector2i(2, 1),
		Vector2i(3, 1),
		Vector2i(4, 1),
		Vector2i(3, 0),
		Vector2i(4, 0),
	]
	assert_array(_blockers(Vector2i(0, FAR), Vector2i(FAR, 0))).contains_exactly_in_any_order(
		rising
	)
	var below: World = GridWorld.from_rows(GridWorld.grass(SIDE, SIDE, [Vector2i(1, 4)]))
	assert_bool(FixedMath.line_clear(below, 0, FAR, FAR, 0, TRACKED)).is_false()
	assert_bool(FixedMath.line_clear(below, FAR, 0, 0, FAR, TRACKED)).is_false()


## The same on a slope that is not a corner to corner diagonal: a segment from the top left corner
## to the middle of the far edge of x (1 over 2) and to the middle of the far edge of y (2 over 1).
## Each crosses two corners, and the tiles beside them are touched.
func test_a_segment_that_ends_on_a_far_edge_keeps_its_slope() -> void:
	var half: Array[Vector2i] = GridWorld.tiles(
		[[0, 0], [1, 0], [2, 0], [1, 1], [2, 1], [3, 1], [4, 1], [3, 2], [4, 2]]
	)
	assert_array(_blockers(Vector2i(0, 0), Vector2i(FAR, FAR / 2))).contains_exactly_in_any_order(
		half
	)
	var steep: Array[Vector2i] = GridWorld.tiles(
		[[0, 0], [0, 1], [0, 2], [1, 1], [1, 2], [1, 3], [1, 4], [2, 3], [2, 4]]
	)
	assert_array(_blockers(Vector2i(0, 0), Vector2i(FAR / 2, FAR))).contains_exactly_in_any_order(
		steep
	)
	# From the bottom left corner: the start is on the far edge of y.
	var rising: Array[Vector2i] = GridWorld.tiles(
		[[0, 4], [1, 3], [1, 4], [2, 3], [2, 4], [3, 2], [3, 3], [4, 2], [4, 3]]
	)
	assert_array(_blockers(Vector2i(0, FAR), Vector2i(FAR, FAR / 2))).contains_exactly_in_any_order(
		rising
	)


## A tile that costs more than grass is open: 20 and 40 are the costs of slower ground (ADR 0008
## section 1), and every class crosses it. Only a cost of 0 blocks, so the same line over rock does
## not get through, and a line over slow ground beside rock is blocked by the rock alone.
func test_a_tile_that_costs_more_than_10_does_not_block_a_line() -> void:
	var along: Array[Vector2i] = [Vector2i(500, 2500), Vector2i(4500, 2500)]
	var down: Array[Vector2i] = [Vector2i(2500, 500), Vector2i(2500, 4500)]
	var diagonal: Array[Vector2i] = [Vector2i(500, 500), Vector2i(3500, 3500)]
	for symbol: String in ["2", "4"]:
		# Slow ground at (2, 2) on the row and the column of the first two lines, and at (1, 0) and
		# (0, 1) beside the corner (1000, 1000) of the diagonal.
		var rows: PackedStringArray = GridWorld.grass(SIDE, SIDE)
		for tile: Vector2i in [Vector2i(2, 2), Vector2i(1, 0), Vector2i(0, 1)]:
			rows[tile.y] = rows[tile.y].left(tile.x) + symbol + rows[tile.y].substr(tile.x + 1)
		var world: World = GridWorld.from_rows(rows)
		for move_class: int in [FOOT, WHEELED, TRACKED]:
			for segment: Array[Vector2i] in [along, down, diagonal]:
				var text: String = "%s class %d %s" % [symbol, move_class, segment]
				(
					assert_bool(_clear(world, segment[0], segment[1], move_class))
					. override_failure_message(text)
					. is_true()
				)
			# Inside the slow tile, and from its inside out.
			var inside: Array[Vector2i] = [Vector2i(2100, 2200), Vector2i(2900, 2800)]
			assert_bool(_clear(world, inside[0], inside[1], move_class)).is_true()
			assert_bool(_clear(world, inside[0], Vector2i(4500, 2500), move_class)).is_true()
	# Rock in the same places blocks every one of the lines, and beside slow ground it blocks alone.
	var wall: World = GridWorld.from_rows(GridWorld.grass(SIDE, SIDE, [Vector2i(2, 2)]))
	assert_bool(_clear(wall, along[0], along[1])).is_false()
	assert_bool(_clear(wall, down[0], down[1])).is_false()
	var mixed: PackedStringArray = PackedStringArray(["..4..", "..2..", ".#4..", "..2..", "..4.."])
	var beside: World = GridWorld.from_rows(mixed)
	assert_bool(_clear(beside, Vector2i(2500, 500), Vector2i(2500, 1500))).is_true()
	assert_bool(_clear(beside, Vector2i(2500, 500), Vector2i(2500, 4500))).is_true()
	assert_bool(_clear(beside, Vector2i(500, 2500), Vector2i(2500, 2500))).is_false()
	assert_bool(_clear(beside, Vector2i(2500, 2500), Vector2i(4500, 2500))).is_true()


## Any cost above 0 is open, to the byte: 1 (below grass), 10, 20, 40 and 255, set on the tile for
## every class, and 0 blocks it again.
func test_every_move_cost_above_0_is_open_and_0_is_blocked() -> void:
	var world: World = GridWorld.from_rows(GridWorld.grass(SIDE, SIDE))
	var cells: int = SIDE * SIDE
	var tile: int = 2 * SIDE + 2
	for cost: int in [1, 10, 20, 40, 255, 0]:
		for move_class: int in [FOOT, WHEELED, TRACKED]:
			world.move_cost[move_class * cells + tile] = cost
		for move_class: int in [FOOT, WHEELED, TRACKED]:
			var through: bool = _clear(world, Vector2i(500, 2500), Vector2i(4500, 2500), move_class)
			(
				assert_bool(through)
				. override_failure_message("cost %d class %d" % [cost, move_class])
				. is_equal(cost > 0)
			)
