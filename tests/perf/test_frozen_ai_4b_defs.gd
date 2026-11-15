extends GdUnitTestSuite
## The frozen AI defs of `data/dev/arena/ai_4b/` (plan row P304, ADR 0038 section 7): copies of
## `perf_ai`'s frozen AI defs (`data/dev/arena/ai/`, P189b's early scout and wave) for
## `perf_ai_4b`, which `tests/perf/test_ai_4b_perf.gd` and the "Perf AI" route play. `ai/` and
## `test_frozen_ai_defs.gd` stay as they are. Every later AI row that adds an `OpponentDef` or
## `AiDifficultyDef` field also sets it in these copies (the shipped Normal value) in the same PR;
## this suite fails until it does: it compares the field names of each copy with its shipped twin in
## `data/ai/` (the names, never the values, so a tuning row on `data/ai/` breaks nothing here).

const FileScan: GDScript = preload("res://tests/support/file_scan.gd")
const SHIPPED_DIR: String = "res://data/ai/"
const FROZEN_DIR: String = "res://data/dev/arena/ai_4b/"
const BASE_DIR: String = "res://data/dev/arena/ai/"
## The shipped files that are not copied: the dummies (the test opponents, the balance yardstick).
const NOT_FROZEN: Array[String] = ["dummy_fossil.tres", "dummy_renew.tres"]


func test_every_shipped_ai_def_but_the_dummies_has_a_copy_and_the_reverse() -> void:
	var shipped: Array[String] = _relative(FileScan.list_files(SHIPPED_DIR, ".tres"), SHIPPED_DIR)
	for dummy: String in NOT_FROZEN:
		assert_bool(shipped.has(dummy)).is_true()
		shipped.erase(dummy)
	var frozen: Array[String] = _relative(FileScan.list_files(FROZEN_DIR, ".tres"), FROZEN_DIR)
	assert_int(frozen.size()).is_equal(11)
	assert_array(frozen).is_equal(shipped)
	assert_array(frozen).is_equal(_relative(FileScan.list_files(BASE_DIR, ".tres"), BASE_DIR))


## The field-name parity: each copy sets exactly the fields its shipped twin sets.
func test_a_copy_sets_the_same_field_names_as_its_shipped_twin() -> void:
	for file: String in _relative(FileScan.list_files(FROZEN_DIR, ".tres"), FROZEN_DIR):
		var copy: PackedStringArray = _fields(FROZEN_DIR + file)
		var shipped: PackedStringArray = _fields(SHIPPED_DIR + file)
		assert_int(copy.size()).override_failure_message(file).is_greater(1)
		assert_array(copy).override_failure_message(file).is_equal(shipped)


func test_a_copy_has_the_script_of_its_shipped_twin() -> void:
	for file: String in _relative(FileScan.list_files(FROZEN_DIR, ".tres"), FROZEN_DIR):
		var frozen: Resource = load(FROZEN_DIR + file)
		var shipped: Resource = load(SHIPPED_DIR + file)
		assert_object(frozen).is_not_null()
		assert_object(frozen.get_script()).is_same(shipped.get_script())
		assert_bool(frozen == load(BASE_DIR + file)).override_failure_message(file).is_false()


func test_the_copies_reach_only_files_of_their_own_folder_and_the_scripts() -> void:
	var reads: RegEx = RegEx.create_from_string('path="([^"]+)"')
	for file: String in FileScan.list_files(FROZEN_DIR, ".tres"):
		var text: String = FileAccess.get_file_as_string(file)
		assert_bool(text.contains('uid="')).override_failure_message(file).is_false()
		assert_bool(text.contains("; Frozen copy of ")).override_failure_message(file).is_true()
		for found: RegExMatch in reads.search_all(text):
			var path: String = found.get_string(1)
			var message: String = "%s reads %s" % [file, path]
			if path.begins_with("res://data/"):
				assert_str(path).override_failure_message(message).starts_with(FROZEN_DIR)
			else:
				assert_str(path).override_failure_message(message).starts_with("res://game/ai/")


## Same early contact as `perf_ai`'s defs (the scout at tick 30, the first wave at 300, no jitter),
## income unchanged: the arena adds Phase 4b's rows, not another AI schedule.
func test_the_normal_copy_keeps_the_early_contact_values_and_the_full_income() -> void:
	var level: AiDifficultyDef = load(FROZEN_DIR + "difficulty/normal.tres") as AiDifficultyDef
	assert_int(level.scout_first_tick).is_equal(30)
	assert_int(level.wave_first_tick).is_equal(300)
	assert_int(level.wave_jitter_ticks).is_equal(0)
	assert_int(level.income_percent).is_equal(WorldLoad.PERCENT)


## The fields that a copy set equal to the shipped Normal row's value when they were added (the mend
## pair, ADR 0037 section 11, which `ai/`'s copies leave off): this arena's Normal mends as shipped.
func test_the_mend_pair_is_set_in_every_level_copy() -> void:
	for level: String in ["easy", "normal", "hard"]:
		var copy: AiDifficultyDef = load(FROZEN_DIR + "difficulty/%s.tres" % level)
		var shipped: AiDifficultyDef = load(SHIPPED_DIR + "difficulty/%s.tres" % level)
		assert_int(copy.mend_below_percent).override_failure_message(level).is_equal(
			shipped.mend_below_percent
		)
		assert_int(copy.mend_floor).override_failure_message(level).is_equal(shipped.mend_floor)


## The names set in the `[resource]` section of the `.tres` at `path`, in file order.
func _fields(path: String) -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray()
	var inside: bool = false
	var key: RegEx = RegEx.create_from_string("^([a-z_0-9]+) = ")
	for line: String in FileAccess.get_file_as_string(path).split("\n"):
		if line == "[resource]":
			inside = true
		elif inside:
			var found: RegExMatch = key.search(line)
			if found != null:
				names.append(found.get_string(1))
	names.sort()
	return names


func _relative(paths: Array[String], dir: String) -> Array[String]:
	var out: Array[String] = []
	for path: String in paths:
		out.append(path.trim_prefix(dir))
	return out
