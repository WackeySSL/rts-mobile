extends GdUnitTestSuite
## The frozen defs of the pinned scenarios (plan row P171, ADR 0031): the perf arena, the base
## arena and the controls test map load their rules, units, weapons and factions from
## `data/dev/arena/`, never from the shipped `data/units/`, `data/weapons/`, `data/factions/` or
## `data/rules.tres`, so a tuning change to a shipped file cannot move a golden hash. No test here
## compares a copy with its shipped original field by field: the first tuning row would break it.

const FileScan: GDScript = preload("res://tests/support/file_scan.gd")
const Frozen: GDScript = preload("res://tests/sim/support/frozen_scenarios.gd")
const ARENA_DIR: String = Frozen.ARENA_DIR
const SCENARIOS: Array[String] = Frozen.SCENARIOS
## The only data folders a pinned scenario may reach, through any chain of ext_resources.
const ALLOWED: Array[String] = [ARENA_DIR + "/", "res://data/maps/", "res://data/terrain/"]
## Every ext_resource path, whatever its form: a relative path or a uid would get past a walk that
## reads only `res://` paths, so the walk asserts there are none.
const ANY_PATH: String = 'path="([^"]+)"'


func test_the_three_scenarios_reach_only_frozen_maps_and_terrain_files() -> void:
	for scenario_path: String in SCENARIOS:
		var reached: Array[String] = _closure(scenario_path)
		for walked: String in reached + [scenario_path]:
			if walked.ends_with(".tres"):
				_assert_plain_paths(walked)
		var arena_files: int = 0
		for path: String in reached:
			(
				assert_bool(ALLOWED.any(func(dir: String) -> bool: return path.begins_with(dir)))
				. override_failure_message("%s reaches %s" % [scenario_path, path])
				. is_true()
			)
			if path.begins_with(ARENA_DIR + "/"):
				arena_files += 1
		# The walk must not pass on nothing: a scenario takes rules, units, weapons and factions.
		var least: int = 30 if scenario_path.ends_with("perf_bases.tres") else 1
		(
			assert_int(arena_files)
			. override_failure_message("%s reached %d arena files" % [scenario_path, arena_files])
			. is_greater_equal(least)
		)


func test_a_frozen_file_points_only_at_frozen_files() -> void:
	var files: Array[String] = FileScan.list_files(ARENA_DIR, ".tres")
	assert_int(files.size()).is_greater(30)
	for file: String in files:
		_assert_plain_paths(file)
		for path: String in _resource_paths(file):
			if path.begins_with("res://data/"):
				assert_str(path).override_failure_message("%s reads %s" % [file, path]).starts_with(
					ARENA_DIR + "/"
				)


func test_the_loaded_scenarios_hold_frozen_resources_only() -> void:
	for scenario_path: String in SCENARIOS:
		var scenario: ScenarioDef = load(scenario_path)
		assert_str(scenario.rules.resource_path).starts_with(ARENA_DIR + "/")
		for spawn: SpawnDef in scenario.spawns:
			assert_str(spawn.unit.resource_path).starts_with(ARENA_DIR + "/")
		for faction: FactionDef in scenario.factions:
			if faction == null:
				continue
			assert_str(faction.resource_path).starts_with(ARENA_DIR + "/")
			for unit: UnitDef in faction.roster:
				assert_str(unit.resource_path).starts_with(ARENA_DIR + "/")


## The arena's tanks are the frozen light tank, not the shipped object, so a tuning change to the
## shipped file has nothing to reach.
func test_the_arena_spawns_use_the_frozen_tank_and_not_the_shipped_one() -> void:
	var shipped: UnitDef = load("res://data/units/light_tank.tres")
	var frozen: UnitDef = load(ARENA_DIR + "/units/light_tank.tres")
	assert_bool(shipped == frozen).is_false()
	assert_str(frozen.resource_path).is_not_equal(shipped.resource_path)
	var arena: ScenarioDef = load(SCENARIOS[0])
	var matches: int = 0
	for spawn: SpawnDef in arena.spawns:
		if spawn.unit.type_id == shipped.type_id:
			matches += 1
			assert_bool(spawn.unit == shipped).is_false()
			assert_bool(spawn.unit == frozen).is_true()
	assert_int(matches).is_greater(0)


## Every data file reachable from `file` through ext_resource paths (the file itself left out),
## each once, whatever its format: a `.res` def is listed for the allowlist too. Only `.tres` files
## are read further; scripts, art and binary resources end the walk.
func _closure(file: String) -> Array[String]:
	var visited: Array[String] = [file]
	var todo: Array[String] = [file]
	while not todo.is_empty():
		var next: String = todo.pop_back()
		for path: String in _resource_paths(next):
			if not path.begins_with("res://data/") or path in visited:
				continue
			visited.append(path)
			if path.ends_with(".tres"):
				todo.append(path)
	visited.erase(file)
	return visited


## Every ext_resource of `file` names an absolute `res://` path and no uid, so the text walk sees
## the file Godot loads.
func _assert_plain_paths(file: String) -> void:
	var text: String = FileAccess.get_file_as_string(file)
	assert_bool(text.contains('uid="')).override_failure_message("%s holds a uid" % file).is_false()
	for path: String in _resource_paths(file):
		assert_str(path).override_failure_message("%s reads %s" % [file, path]).starts_with(
			"res://"
		)


func _resource_paths(file: String) -> Array[String]:
	var found: Array[String] = []
	var regex: RegEx = RegEx.create_from_string(ANY_PATH)
	for hit: RegExMatch in regex.search_all(FileAccess.get_file_as_string(file)):
		found.append(hit.get_string(1))
	return found
