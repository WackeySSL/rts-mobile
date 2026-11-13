extends GdUnitTestSuite
## SEPARATION per layer (plan row P240, ADR 0036 section 4): a pair counts only when both rows have
## the same `type_layer_bit`. Aircraft spread among themselves, drone squads among themselves, and
## neither pushes tanks. A row of another layer is not looked at (no `SEP_PAIRS`, no scan cap used).
## Run under both implementations; the lockstep over crowds is
## tests/sim/native/test_air_movement_lockstep.gd.

const GridWorld: GDScript = preload("res://tests/sim/support/grid_world.gd")
const Rig: GDScript = preload("res://tests/sim/support/separation_rig.gd")
const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const GROUND: int = World.Layer.GROUND
const AIR: int = World.Layer.AIR
const LOW_AIR: int = World.Layer.LOW_AIR
const POINT: Vector2i = Vector2i(5000, 4000)


## A map of 20 x 8 tiles with one type per layer bit of `layers` (type k has bit `layers[k]`) and a
## row of each type on `POINT`, in reverse type order (row r has type n - 1 - r).
func _stack(layers: Array[int], impl: int) -> World:
	var kinds: Array = []
	kinds.resize(layers.size())
	kinds.fill(World.MoveClass.TRACKED)
	var world: World = GridWorld.from_rows(GridWorld.grass(20, 8), kinds)
	for kind: int in layers.size():
		world.type_layer_bit[kind] = layers[kind]
	# The rows are added in reverse type order, so that row r has type n - 1 - r and a slip that
	# indexes the layer table by row instead of by type changes the answer.
	for kind: int in range(layers.size() - 1, -1, -1):
		world.add_unit(1, kind, POINT.x, POINT.y)
	assert_array(SimImpls.attach(world, impl, SimProbe.Phase.SEPARATION)).is_empty()
	return world


func _both() -> Array[Array]:
	return SimImpls.CASES.duplicate(true)


func _layers_and_impls() -> Array[Array]:
	var found: Array[Array] = []
	for layer: int in [GROUND, AIR, LOW_AIR]:
		for impl: Array in SimImpls.CASES:
			found.append([layer, impl[0]])
	return found


## Two rows on one point of the same layer push one another (30 each), whichever layer it is.
func test_rows_of_one_layer_push_one_another(
	layer: int, impl: int, _test_parameters := _layers_and_impls()
) -> void:
	var world: World = _stack([layer, layer], impl)
	Rig.separate(world)
	assert_int(world.push_x[0]).is_equal(-30)
	assert_int(world.push_x[1]).is_equal(30)
	assert_int(world.stats[World.Stat.SEP_PAIRS]).is_equal(2)


## Rows on one point of different layers push nothing and look at nothing: a tank under a jet, a
## jet over a drone squad, a drone squad over a tank.
func test_rows_of_another_layer_are_no_pair(impl: int, _test_parameters := _both()) -> void:
	var world: World = _stack([GROUND, AIR, LOW_AIR], impl)
	Rig.separate(world)
	for row: int in 3:
		assert_int(world.push_x[row]).is_equal(0)
		assert_int(world.push_y[row]).is_equal(0)
	assert_int(world.stats[World.Stat.SEP_PAIRS]).is_equal(0)


## Of tank, jet, tank, jet on one point, each tank is pushed by the other tank and each jet by the
## other jet only.
func test_two_pairs_on_one_point_push_only_within_their_layer(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _stack([GROUND, AIR, GROUND, AIR], impl)
	Rig.separate(world)
	# The rows are jet, tank, jet, tank (the types are added in reverse).
	assert_array([world.push_x[0], world.push_x[2]]).is_equal([-30, 30])
	assert_array([world.push_x[1], world.push_x[3]]).is_equal([-30, 30])
	assert_int(world.stats[World.Stat.SEP_PAIRS]).is_equal(4)


## A row of another layer is not looked at, so it uses no scan: with `separation_scan` 1, two tanks
## and two jets on one point still pair within their layer (each row looks at its one mate, 4
## looks), where a scan that counted the rows of the other layer would stop the two jets (rows 2 and
## 3) on a tank they skip, with no push at all.
func test_rows_of_another_layer_use_no_scan(impl: int, _test_parameters := _both()) -> void:
	var world: World = _stack([AIR, AIR, GROUND, GROUND], impl)
	world.separation_scan = 1
	Rig.separate(world)
	# The rows are tank, tank, jet, jet.
	assert_array([world.push_x[0], world.push_x[1]]).is_equal([-30, 30])
	assert_array([world.push_x[2], world.push_x[3]]).is_equal([-30, 30])
	assert_int(world.stats[World.Stat.SEP_PAIRS]).is_equal(4)
