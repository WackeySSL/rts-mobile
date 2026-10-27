extends GdUnitTestSuite
## The sort cases of ADR 0023 section 2 with real buildings (plan P115): a building node and a unit
## rig are siblings in the one y-sorted `WorldSort`, and the engine draws the one with the larger y
## last. A building's key is its footprint centre's, `(c + r + n) * 16` px for an n x n footprint at
## tile (c, r), so a unit east or south of the footprint sorts after it and one north or west before
## it, for a 1x1, a 2x2 and a 3x3 footprint, and of two footprints the one separated along +x or +y
## is in front. The sort itself runs in the engine, which a headless test cannot see: what is
## pinned is its two inputs, the node's `y_sort_enabled` and the y of each child.
## Built on a 32 x 32 map with the building at tile (10, 10) and light tanks that the case moves.

const Rig: GDScript = preload("res://tests/view/support/building_rig.gd")
const FOOT: Vector2i = Vector2i(10, 10)
const TYPES: Dictionary[int, String] = {1: "defence_turret", 2: "power_plant", 3: "headquarters"}

var _runner: MatchRunner
var _camera: RtsCamera
var _units: UnitLayer
var _buildings: BuildingLayer


func after_test() -> void:
	CommandQueue.clear()


func test_a_unit_east_or_south_of_a_footprint_sorts_after_the_building_and_north_or_west_before(
) -> void:
	for size: int in [1, 2, 3]:  # A 1x1, a 2x2 and a 3x3 footprint at tile (10, 10).
		var cases: Array[Array] = []  # [position, after the building?]
		for step: int in range(1, 8):
			var along: int = step * size * 1000 / 8  # Strictly inside the footprint's span.
			cases.append(
				[Vector2i((FOOT.x + size) * 1000 + 250 * step, FOOT.y * 1000 + along), true]
			)
			cases.append(
				[Vector2i(FOOT.x * 1000 + along, (FOOT.y + size) * 1000 + 250 * step), true]
			)
			cases.append([Vector2i(FOOT.x * 1000 + along, FOOT.y * 1000 - 250 * step), false])
			cases.append([Vector2i(FOOT.x * 1000 - 250 * step, FOOT.y * 1000 + along), false])
		_open(size, cases.size())
		var building: Node2D = _buildings.building(1)
		assert_object(building.get_parent()).is_same(_units.world_sort)
		assert_bool(_units.world_sort.y_sort_enabled).is_true()
		var key: float = float(FOOT.x + FOOT.y + size) * 16.0
		assert_float(building.position.y).is_equal(key)
		for row: int in cases.size():
			_set_position(row + 1, cases[row][0])
		_units._process(0.0)
		for row: int in cases.size():
			var after: bool = cases[row][1]
			var rig: Node2D = _units.rig(row + 1)
			assert_object(rig.get_parent()).is_same(building.get_parent())  # Siblings, so sorted.
			(
				assert_bool(rig.position.y > key if after else rig.position.y < key)
				. override_failure_message(
					(
						"%dx%d footprint, unit at %s: y %s against %s"
						% [size, size, cases[row][0], rig.position.y, key]
					)
				)
				. is_true()
			)
		_free()


func test_of_two_footprints_the_one_east_or_south_of_the_other_is_in_front() -> void:
	var spawns: Array[SpawnDef] = [
		Rig.spawn(1, "headquarters", 4, 4),  # 3x3: (4 + 4 + 3) * 16 = 176.
		Rig.spawn(1, "power_plant", 7, 4),  # 2x2 east of it: 13 * 16 = 208.
		Rig.spawn(1, "defence_turret", 4, 7),  # 1x1 south of it: 12 * 16 = 192.
		Rig.spawn(2, "renew_barracks", 7, 7),  # 2x2 south-east: 16 * 16 = 256.
		Rig.spawn(2, "renew_defence", 1, 4),  # 1x1 west of it: 6 * 16 = 96.
	]
	_open_with(spawns)
	var y: Array[float] = []
	for id: int in range(1, 6):
		y.append(_buildings.building(id).position.y)
	assert_array(y).is_equal([176.0, 208.0, 192.0, 256.0, 96.0])
	assert_float(y[1]).is_greater(y[0])  # East.
	assert_float(y[2]).is_greater(y[0])  # South.
	assert_float(y[3]).is_greater(y[1])  # South of the plant.
	assert_float(y[3]).is_greater(y[2])  # East of the Redoubt.
	assert_float(y[4]).is_less(y[0])  # West.
	for id: int in range(1, 6):  # One sorted list: no building has a parent of its own.
		assert_object(_buildings.building(id).get_parent()).is_same(_units.world_sort)


func _open(size: int, units: int) -> void:
	var tanks: SpawnDef = Rig.spawn(1, "light_tank", 2, 2)
	tanks.count = units
	tanks.columns = 1
	tanks.spacing = 1000
	var spawns: Array[SpawnDef] = [Rig.spawn(1, TYPES[size], FOOT.x, FOOT.y), tanks]
	_open_with(spawns)


func _open_with(spawns: Array[SpawnDef]) -> void:
	_runner = auto_free(Rig.runner(Rig.scenario(spawns)))
	_camera = auto_free(RtsCamera.new())
	add_child(_camera)
	var sort: WorldSort = auto_free(WorldSort.new())
	sort.runner = _runner
	add_child(sort)
	_units = auto_free(UnitLayer.new())
	_units.runner = _runner
	_units.camera = _camera
	_units.world_sort = sort
	add_child(_units)
	_units.set_process(false)
	_buildings = auto_free(BuildingLayer.new())
	_buildings.runner = _runner
	_buildings.world_sort = sort
	_buildings.reveal_enemies = true
	add_child(_buildings)
	_buildings.set_process(false)
	_units._process(0.0)
	_buildings._process(0.0)


## Writes both positions of row `row` of the published snapshot (the layer draws alpha 0).
func _set_position(row: int, at: Vector2i) -> void:
	var snap: MatchSnapshot = _runner.snapshot
	snap.pos_x[row] = at.x
	snap.pos_y[row] = at.y
	snap.prev_pos_x[row] = at.x
	snap.prev_pos_y[row] = at.y


func _free() -> void:
	for node: Node in [_buildings, _units, _units.world_sort, _camera]:
		remove_child(node)
		node.free()
	_runner.free()
