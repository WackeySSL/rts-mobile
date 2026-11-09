extends GdUnitTestSuite
## The frozen AI defs of `data/dev/arena/ai/` (plan row P189b): copies of the eleven shipped AI
## defs (the two computers, their six build orders and the three levels; the dummies are not AI
## workload) that `tests/perf/test_ai_perf.gd` and the Perf AI route play. A tuning row on
## `data/ai/` does not touch these copies; refreshing them is a deliberate row that restarts the
## `[ai]` calibration. So no test here compares a copy's numbers with its shipped original: the
## first tuning row would break it. What is pinned is the file set, the schema (the script), that a
## copy reaches only frozen files, and the early-contact values of the frozen Normal level.

const FileScan: GDScript = preload("res://tests/support/file_scan.gd")
const SHIPPED_DIR: String = "res://data/ai/"
const FROZEN_DIR: String = "res://data/dev/arena/ai/"
## The shipped files that are not frozen: the dummies (the test opponents, the balance yardstick).
const NOT_FROZEN: Array[String] = ["dummy_fossil.tres", "dummy_renew.tres"]


func test_every_shipped_ai_def_but_the_dummies_has_a_frozen_twin_and_the_reverse() -> void:
	var shipped: Array[String] = _relative(FileScan.list_files(SHIPPED_DIR, ".tres"), SHIPPED_DIR)
	for dummy: String in NOT_FROZEN:
		assert_bool(shipped.has(dummy)).is_true()
		shipped.erase(dummy)
	var frozen: Array[String] = _relative(FileScan.list_files(FROZEN_DIR, ".tres"), FROZEN_DIR)
	assert_int(frozen.size()).is_equal(11)
	assert_array(frozen).is_equal(shipped)


## Same script as the shipped twin, so a new field on the class reaches both.
func test_a_frozen_ai_def_has_the_script_of_its_shipped_twin() -> void:
	for file: String in _relative(FileScan.list_files(FROZEN_DIR, ".tres"), FROZEN_DIR):
		var frozen: Resource = load(FROZEN_DIR + file)
		var shipped: Resource = load(SHIPPED_DIR + file)
		assert_object(frozen).is_not_null()
		assert_object(shipped).is_not_null()
		assert_object(frozen.get_script()).is_same(shipped.get_script())
		assert_bool(frozen == shipped).is_false()


func test_the_frozen_defs_reach_only_frozen_defs_and_the_scripts() -> void:
	var reads: RegEx = RegEx.create_from_string('path="([^"]+)"')
	for file: String in FileScan.list_files(FROZEN_DIR, ".tres"):
		var text: String = FileAccess.get_file_as_string(file)
		for found: RegExMatch in reads.search_all(text):
			var path: String = found.get_string(1)
			var message: String = "%s reads %s" % [file, path]
			if path.begins_with("res://data/"):
				assert_str(path).override_failure_message(message).starts_with(FROZEN_DIR)
			else:
				assert_str(path).override_failure_message(message).starts_with("res://game/ai/")


## The values that make `perf_ai.tres`'s 900 ticks make contact, as literals so they cannot drift:
## the scout leaves at once and the first wave at tick 300 with no jitter.
func test_the_frozen_normal_level_keeps_its_early_contact_values() -> void:
	var level: AiDifficultyDef = load(FROZEN_DIR + "difficulty/normal.tres") as AiDifficultyDef
	assert_int(level.scout_first_tick).is_equal(30)
	assert_int(level.wave_first_tick).is_equal(300)
	assert_int(level.wave_jitter_ticks).is_equal(0)


func _relative(paths: Array[String], dir: String) -> Array[String]:
	var out: Array[String] = []
	for path: String in paths:
		out.append(path.trim_prefix(dir))
	return out
