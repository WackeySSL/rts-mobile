extends GdUnitTestSuite
## The raised walls on the five shipped maps (ADR 0053 amendment A1, A4 and A11, plan P656d2): the
## number of cells a wall touches (a passable cell in the three cells behind a raised one) is the
## step-0 study's, no ore cell is touched, and the sort keys put every raised cell after a point
## behind it and before one in front of it.

const MAPS: Dictionary[String, int] = {
	"kestrel_flats": 119,
	"curlew_crags": 281,
	"heron_fords": 60,
	"tutorial_basics": 13,
	"tutorial_drills": 6,
}
const BEHIND: Array[Vector2i] = [Vector2i(-1, 0), Vector2i(0, -1), Vector2i(-1, -1)]


func test_each_shipped_map_touches_the_cells_the_study_counted_and_no_ore_cell() -> void:
	for name: String in MAPS:
		var map: MapDef = load("res://data/maps/%s.tres" % name)
		var size: Vector2i = map.size_tiles()
		var kinds: Array[StringName] = _kinds(map)
		var touched: Dictionary[int, bool] = {}
		for row: int in size.y:
			for col: int in size.x:
				if kinds[row * size.x + col] != &"rock":
					continue
				for back: Vector2i in BEHIND:
					var at: Vector2i = Vector2i(col, row) + back
					if at.x < 0 or at.y < 0:
						continue
					var kind: StringName = kinds[at.y * size.x + at.x]
					if kind == &"rock" or kind == &"water":
						continue
					touched[at.y * size.x + at.x] = true
					(
						assert_bool(kind == &"ore")
						. override_failure_message("%s: ore cell %s touched" % [name, at])
						. is_false()
					)
		assert_int(touched.size()).override_failure_message(name).is_equal(MAPS[name])


func test_no_scenarios_start_cell_is_in_ring_one_of_a_raised_cell() -> void:
	var dir: String = "res://data/scenarios"
	var checked: int = 0
	for file: String in DirAccess.get_files_at(dir):
		if not file.ends_with(".tres"):
			continue
		var scenario: ScenarioDef = load(dir.path_join(file)) as ScenarioDef
		if scenario == null or scenario.map == null:
			continue
		var name: String = scenario.map.resource_path.get_file().get_basename()
		if not MAPS.has(name):
			continue
		checked += 1
		var size: Vector2i = scenario.map.size_tiles()
		var kinds: Array[StringName] = _kinds(scenario.map)
		var ring: Dictionary[Vector2i, bool] = {}
		for row: int in size.y:
			for col: int in size.x:
				if kinds[row * size.x + col] == &"rock":
					for back: Vector2i in BEHIND:
						ring[Vector2i(col, row) + back] = true
		for spawn: SpawnDef in scenario.spawns:
			for cell: Vector2i in _start_cells(spawn):
				(
					assert_bool(ring.has(cell))
					. override_failure_message("%s: start cell %s is behind a wall" % [file, cell])
					. is_false()
				)
	assert_int(checked).is_greater(10)  # Four scenarios on each skirmish map and the tutorials.


func test_a_raised_cell_sorts_after_what_is_behind_it_and_before_what_is_in_front() -> void:
	# A raised cell's row key is its centre y. A ground point inside the cell behind, (c - 1, r),
	# has a key below it; one inside the cell in front, (c + 1, r), a key above it.
	for col: int in range(1, 6):
		for row: int in range(1, 6):
			var key: float = IsoProjection.cell_centre_px(col, row).y
			var behind: float = IsoProjection.ground_to_px(col * 1000 - 1, row * 1000 + 500).y
			var in_front: float = (
				IsoProjection.ground_to_px((col + 1) * 1000 + 1, row * 1000 + 500).y
			)
			assert_float(behind).is_less(key)
			assert_float(in_front).is_greater(key)


## The terrain id of each cell of `map`.
func _kinds(map: MapDef) -> Array[StringName]:
	var by_symbol: Dictionary[String, StringName] = {}
	for def: TerrainDef in map.terrain.terrains:
		by_symbol[def.symbol] = def.id
	var kinds: Array[StringName] = []
	for text: String in map.rows:
		for at: int in text.length():
			kinds.append(by_symbol[text[at]])
	return kinds


## The cells a spawn stands on: its building's footprint tiles, else its units' tiles.
@warning_ignore("integer_division")
func _start_cells(spawn: SpawnDef) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var columns: int = maxi(spawn.columns, 1)
	var foot: Vector2i = Vector2i.ONE
	if spawn.unit is BuildingDef:
		foot = (spawn.unit as BuildingDef).footprint
	for at: int in spawn.count:
		if spawn.unit is BuildingDef:
			var corner: Vector2i = (
				spawn.origin_tile + Vector2i(at % columns * foot.x, at / columns * foot.y)
			)
			for dx: int in foot.x:
				for dy: int in foot.y:
					cells.append(corner + Vector2i(dx, dy))
		else:
			var step: int = spawn.spacing
			cells.append(
				spawn.origin_tile + Vector2i(at % columns * step / 1000, at / columns * step / 1000)
			)
	return cells
