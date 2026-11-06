extends GdUnitTestSuite
## The frozen defs of the pinned scenarios (plan row P171, ADR 0031): the perf arena, the base
## arena and the controls test map load their rules, units, weapons and factions from
## `data/dev/arena/`, never from the shipped `data/units/`, `data/weapons/`, `data/factions/` or
## `data/rules.tres`, so a tuning change to a shipped file cannot move a golden hash. No test here
## compares a copy with its shipped original field by field: the first tuning row would break it.

const FileScan: GDScript = preload("res://tests/support/file_scan.gd")
const ARENA_DIR: String = "res://data/dev/arena"
const SCENARIOS: Array[String] = [
	"res://data/scenarios/perf_arena.tres",
	"res://data/scenarios/perf_bases.tres",
	"res://data/scenarios/controls_test.tres",
]
## Folders and files a pinned scenario must not read.
const SHIPPED: Array[String] = [
	"res://data/units/",
	"res://data/weapons/",
	"res://data/factions/",
	"res://data/rules.tres",
]
const RES_PATH: String = 'path="(res://[^"]+)"'


func test_the_three_scenarios_load_nothing_from_the_shipped_defs() -> void:
	for scenario_path: String in SCENARIOS:
		var paths: Array[String] = _resource_paths(scenario_path)
		assert_int(paths.size()).override_failure_message(scenario_path).is_greater(0)
		for path: String in paths:
			for shipped: String in SHIPPED:
				(
					assert_bool(path.begins_with(shipped))
					. override_failure_message("%s reads %s" % [scenario_path, path])
					. is_false()
				)
		# Every def a scenario takes (rules, units, weapons, factions) is a frozen copy.
		var defs: Array[String] = []
		for path: String in paths:
			if path.begins_with("res://data/") and not path.begins_with("res://data/maps/"):
				defs.append(path)
		assert_int(defs.size()).is_greater(0)
		for path: String in defs:
			if path.begins_with("res://data/terrain/"):
				continue
			assert_str(path).override_failure_message(scenario_path).starts_with(ARENA_DIR + "/")


func test_a_frozen_file_points_only_at_frozen_files_and_never_at_a_shipped_def() -> void:
	var files: Array[String] = FileScan.list_files(ARENA_DIR, ".tres")
	assert_int(files.size()).is_greater(30)
	for file: String in files:
		for path: String in _resource_paths(file):
			for shipped: String in SHIPPED:
				(
					assert_bool(path.begins_with(shipped))
					. override_failure_message("%s reads %s" % [file, path])
					. is_false()
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


## Editing a shipped def does not reach the arenas: the frozen light tank is its own file, so a
## change in memory to the shipped one leaves the arena's untouched.
func test_a_change_to_a_shipped_def_does_not_reach_the_frozen_copy() -> void:
	var shipped: UnitDef = load("res://data/units/light_tank.tres")
	var frozen: UnitDef = load(ARENA_DIR + "/units/light_tank.tres")
	assert_bool(shipped == frozen).is_false()
	assert_str(frozen.resource_path).is_not_equal(shipped.resource_path)
	var arena: ScenarioDef = load(SCENARIOS[0])
	for spawn: SpawnDef in arena.spawns:
		if spawn.unit.type_id == shipped.type_id:
			assert_bool(spawn.unit == shipped).is_false()
			assert_bool(spawn.unit == frozen).is_true()


func _resource_paths(file: String) -> Array[String]:
	var found: Array[String] = []
	var regex: RegEx = RegEx.create_from_string(RES_PATH)
	for hit: RegExMatch in regex.search_all(FileAccess.get_file_as_string(file)):
		found.append(hit.get_string(1))
	return found
