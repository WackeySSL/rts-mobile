extends GdUnitTestSuite
## The frozen AI defs of `data/dev/arena/ai/` (plan row P189b): copies of the eleven shipped AI
## defs (the two computers, their six build orders and the three levels; the dummies are not AI
## workload) that `tests/perf/test_ai_perf.gd` and the Perf AI route play, so a tuning row on
## `data/ai/` cannot move the `[ai]` ratchet's workload. Each frozen def is compared with its
## shipped twin field by field, and only the named changes below may differ. A drift in a shipped
## def, a new field or a def without a twin fails here: re-copy the shipped def, keep the named
## changes, and say so in the PR (the `[ai]` calibration restarts then).

const FileScan: GDScript = preload("res://tests/support/file_scan.gd")
const SHIPPED_DIR: String = "res://data/ai/"
const FROZEN_DIR: String = "res://data/dev/arena/ai/"
## The shipped files that are not frozen: the dummies (the test opponents, the balance yardstick).
const NOT_FROZEN: Array[String] = ["dummy_fossil.tres", "dummy_renew.tres"]
## Properties that are not def fields.
const NOT_FIELDS: Array[String] = ["resource_path", "resource_name", "resource_local_to_scene"]
## The only fields that may differ, by file under the frozen folder: Normal's scout leaves at tick
## 30 (shipped 1800) and its first wave at 300 without jitter (shipped 4050 plus up to 300), so
## `perf_ai.tres`'s 900 ticks make contact. The first wave's strength is unchanged: the arena's
## spawned army is worth more.
const CHANGED: Dictionary[String, Array] = {
	"difficulty/normal.tres": ["scout_first_tick", "wave_first_tick", "wave_jitter_ticks"],
}


func test_every_shipped_ai_def_but_the_dummies_has_a_frozen_twin_and_the_reverse() -> void:
	var shipped: Array[String] = _relative(FileScan.list_files(SHIPPED_DIR, ".tres"), SHIPPED_DIR)
	for dummy: String in NOT_FROZEN:
		assert_bool(shipped.has(dummy)).is_true()
		shipped.erase(dummy)
	var frozen: Array[String] = _relative(FileScan.list_files(FROZEN_DIR, ".tres"), FROZEN_DIR)
	assert_int(frozen.size()).is_equal(11)
	assert_array(frozen).is_equal(shipped)


func test_a_frozen_ai_def_equals_its_shipped_twin_but_for_the_named_fields() -> void:
	for file: String in _relative(FileScan.list_files(FROZEN_DIR, ".tres"), FROZEN_DIR):
		var frozen: Resource = load(FROZEN_DIR + file)
		var shipped: Resource = load(SHIPPED_DIR + file)
		assert_object(frozen).is_not_null()
		assert_object(shipped).is_not_null()
		assert_object(frozen.get_script()).is_same(shipped.get_script())
		var differing: Array[String] = _differing(frozen, shipped, file)
		var allowed: Array = CHANGED.get(file, [])
		differing.sort()
		allowed = allowed.duplicate()
		allowed.sort()
		(
			assert_array(differing)
			. override_failure_message(
				"%s differs from its shipped twin in %s, allowed %s" % [file, differing, allowed]
			)
			. is_equal(allowed)
		)


func test_the_frozen_defs_reach_only_frozen_defs_and_the_scripts() -> void:
	for file: String in FileScan.list_files(FROZEN_DIR, ".tres"):
		var text: String = FileAccess.get_file_as_string(file)
		var reads: RegEx = RegEx.create_from_string('path="([^"]+)"')
		for found: RegExMatch in reads.search_all(text):
			var path: String = found.get_string(1)
			assert_str(path).override_failure_message("%s reads %s" % [file, path]).is_not_empty()
			if path.begins_with("res://data/"):
				assert_str(path).override_failure_message("%s reads %s" % [file, path]).starts_with(
					FROZEN_DIR
				)
			else:
				assert_str(path).override_failure_message("%s reads %s" % [file, path]).starts_with(
					"res://game/ai/"
				)


## The names of the script fields in which `frozen` and `shipped` differ. A resource field (a
## build order) is compared by its own fields in turn and by its path's tail after the folder.
func _differing(frozen: Resource, shipped: Resource, file: String) -> Array[String]:
	var found: Array[String] = []
	for info: Dictionary in shipped.get_property_list():
		if int(info["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		var field: String = String(info["name"])
		if NOT_FIELDS.has(field):
			continue
		if not _same(frozen.get(field), shipped.get(field)):
			found.append(field)
	# The frozen def has no field the shipped one lacks.
	for info: Dictionary in frozen.get_property_list():
		if int(info["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE != 0:
			var name: String = String(info["name"])
			if not NOT_FIELDS.has(name):
				(
					assert_bool(
						shipped.get_property_list().any(
							func(other: Dictionary) -> bool: return other["name"] == info["name"]
						)
					)
					. override_failure_message("%s: new field %s" % [file, name])
					. is_true()
				)
	return found


func _same(frozen: Variant, shipped: Variant) -> bool:
	if frozen is Resource and shipped is Resource:
		var left: Resource = frozen
		var right: Resource = shipped
		var tail: String = right.resource_path.trim_prefix(SHIPPED_DIR)
		if left.resource_path != FROZEN_DIR + tail:
			return false
		return _differing(left, right, tail).is_empty()
	if frozen is Array and shipped is Array:
		var a: Array = frozen
		var b: Array = shipped
		if a.size() != b.size():
			return false
		for index: int in a.size():
			if not _same(a[index], b[index]):
				return false
		return true
	return typeof(frozen) == typeof(shipped) and frozen == shipped


func _relative(paths: Array[String], dir: String) -> Array[String]:
	var out: Array[String] = []
	for path: String in paths:
		out.append(path.trim_prefix(dir))
	return out
