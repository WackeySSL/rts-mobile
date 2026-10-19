extends GdUnitTestSuite
## Separation.run, the direction of the fixed push of a near-coincident pair that is not on one
## point (P39 fix 4). The push is signed by geometry, away from the other unit on each axis where
## the two differ, never by the order of the ids: only a pair on exactly the same point has no
## geometry and takes the id order (the lower id towards -x, test_separation.gd). In a match about
## half of all near-coincident pairs have the lower id east or south of the higher one, which the
## other suites (lower id west or north) do not reach. Tanks have radius 400, so R = 800 and a
## pair closer than R / 4 = 200 takes the fixed push min(200, 60) = 60, 30 each (both idle). Each
## case is a pair alone on the map; the first unit (the lower id) is placed relative to the second.

const GridWorld: GDScript = preload("res://tests/sim/support/grid_world.gd")
const Rig: GDScript = preload("res://tests/sim/support/separation_rig.gd")
const COLS: int = 20
const ROWS: int = 8
## The point of the higher id in every case.
const HIGHER: Vector2i = Vector2i(5000, 4000)
## Each unit's share of the pair's fixed push of 60.
const SHARE: int = 30


## A prepared open map of COLS x ROWS tiles with a tank (type 0, radius 400) at each point.
func _tanks(points: Array[Vector2i]) -> World:
	var world: World = GridWorld.from_rows(GridWorld.grass(COLS, ROWS))
	for point: Vector2i in points:
		world.add_unit(1, 0, point.x, point.y)
	return world


func _pushes(world: World) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	for row: int in world.unit_count():
		found.append(Vector2i(world.push_x[row], world.push_y[row]))
	return found


## The lower id `offset` from the higher one: it is pushed `lower`, the higher one the opposite.
func _assert_pair(offset: Vector2i, lower: Vector2i) -> void:
	var world: World = _tanks([HIGHER + offset, HIGHER])
	Rig.separate(world)
	(
		assert_array(_pushes(world))
		. override_failure_message("lower id at %s from the higher" % offset)
		. is_equal([lower, -lower])
	)


## The lower id east of the higher one along x, 1, 2, 100 and 199 milli (the last just inside the
## limit of 200): it is pushed east and the higher one west, 30 each. A 1-milli pair is the nearest
## to one point that is not on it (d2 = 1), and it is not treated as the same point.
func test_a_lower_id_east_of_the_higher_one_is_pushed_east() -> void:
	for gap: int in [1, 2, 100, 199]:
		_assert_pair(Vector2i(gap, 0), Vector2i(SHARE, 0))


## The lower id south of the higher one along y (y grows downwards), at the same distances: it is
## pushed south and the higher one north.
func test_a_lower_id_south_of_the_higher_one_is_pushed_south() -> void:
	for gap: int in [1, 2, 100, 199]:
		_assert_pair(Vector2i(0, gap), Vector2i(0, SHARE))


## The same gaps with the lower id west and north, the cases the other suites have only in part (a
## 1-milli pair along y with the lower id north is in none): the push is still away from the other.
func test_a_lower_id_west_or_north_of_the_higher_one_is_pushed_west_or_north() -> void:
	for gap: int in [1, 2, 100, 199]:
		_assert_pair(Vector2i(-gap, 0), Vector2i(-SHARE, 0))
		_assert_pair(Vector2i(0, -gap), Vector2i(0, -SHARE))


## A diagonal pair is signed on each axis by its own geometry, whichever of the four corners the
## lower id stands on: (1, 1), (2, 2), (100, 100) and the pairs that differ by 100 along one axis
## and 1 along the other. A sign taken from the ids on either axis would be wrong on two of the
## four corners.
func test_a_diagonal_pair_is_signed_on_each_axis_by_its_geometry() -> void:
	var offsets: Array[Vector2i] = [
		Vector2i(1, 1), Vector2i(2, 2), Vector2i(100, 100), Vector2i(100, 1), Vector2i(1, 100)
	]
	for offset: Vector2i in offsets:
		for sign_x: int in [-1, 1]:
			for sign_y: int in [-1, 1]:
				_assert_pair(
					Vector2i(sign_x * offset.x, sign_y * offset.y),
					Vector2i(sign_x * SHARE, sign_y * SHARE)
				)


## The lower id south-east of the higher one with the higher id moving: the idle lower unit takes
## 75% of the fixed push of 60 (45) and is pushed away on both axes, the moving one 15. The share
## belongs to the unit, the direction to the geometry.
func test_the_idle_share_of_a_pair_with_the_lower_id_south_east_follows_the_geometry() -> void:
	var world: World = _tanks([HIGHER + Vector2i(100, 100), HIGHER])
	world.intent_x[1] = 120
	Rig.separate(world)
	assert_array(_pushes(world)).is_equal([Vector2i(45, 45), Vector2i(-15, -15)])
	world = _tanks([HIGHER + Vector2i(100, 100), HIGHER])
	world.intent_x[0] = 120
	Rig.separate(world)
	assert_array(_pushes(world)).is_equal([Vector2i(15, 15), Vector2i(-45, -45)])
