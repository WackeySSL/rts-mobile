extends GdUnitTestSuite
## The sim suites' shared builders play the frozen defs (plan row P171b, ADR 0031): every
## `res://data/` literal in the code of a file under `tests/sim/support` must start with the frozen
## folder `data/dev/arena`, the maps or the terrain, or be one of the three pinned scenarios
## (`Frozen.SCENARIOS`), so no support file loads a unit, weapon, faction, the shipped rules or a
## shipped scenario, however it spells the path, and a tuning row cannot move a rule suite built on
## them. An allowlist, as `test_frozen_defs_data.gd` has: a `"res://data/" + "units/..."` or a
## `"res://data/%s/%s.tres"` form fails because its literal starts with none of the entries.
## `kestrel_rig.gd` and `kestrel_run.gd` play the shipped Skirmish on purpose (plan exception 20
## lists their suites as tuning pins). Only code is scanned: a comment may name a shipped file.

const FileScan: GDScript = preload("res://tests/support/file_scan.gd")
const Frozen: GDScript = preload("res://tests/sim/support/frozen_scenarios.gd")
const SUPPORT_DIR: String = "res://tests/sim/support"
## Support files that play the shipped Skirmish on purpose.
const SHIPPED_ON_PURPOSE: Array[String] = [
	"res://tests/sim/support/kestrel_rig.gd", "res://tests/sim/support/kestrel_run.gd"
]
const ALLOWED_PREFIXES: Array[String] = [
	"res://data/dev/arena", "res://data/maps/", "res://data/terrain/"
]
## Every `res://data` literal, up to the closing quote (or the end of the line).
const LITERAL: String = "res://data[^\"\\']*"


func test_no_support_file_names_a_data_path_outside_the_frozen_ones() -> void:
	var files: Array[String] = FileScan.list_files(SUPPORT_DIR, ".gd")
	assert_array(files).contains(SHIPPED_ON_PURPOSE)
	var scanned: int = 0
	for path: String in files:
		if path in SHIPPED_ON_PURPOSE:
			continue
		scanned += 1
		var lines: PackedStringArray = FileScan.code_lines(FileAccess.get_file_as_string(path))
		var bad: Array[String] = _outside(lines)
		assert_array(bad).override_failure_message("%s: %s" % [path, bad]).is_empty()
	assert_int(scanned).is_greater(40)


## The five spellings a blocklist of slash-ended folders let through, and the four it caught, all
## fail here; the allowed forms pass.
func test_the_scan_fails_every_spelling_of_a_shipped_path_and_passes_the_allowed_ones() -> void:
	var shipped: PackedStringArray = [
		'load("res://data/units/light_tank.tres")',
		'const A: GDScript = preload("res://data/weapons/rifle.tres")',
		'ResourceLoader.load("res://data/factions/fossil.tres")',
		'var p: String = "res://data/units/" + "light_tank.tres"',
		'const UNITS_DIR: String = "res://data/units"',
		'var p: String = "res://data/" + "units/light_tank.tres"',
		'var p: String = "res://data/%s/%s.tres" % [a, b]',
		'var p: String = "res://data/" + "rules.tres"',
		'load("res://data/scenarios/dev_strikes.tres")',
	]
	for line: String in shipped:
		(
			assert_array(_outside(PackedStringArray([line])))
			. override_failure_message(line)
			. is_not_empty()
		)
	var allowed: PackedStringArray = [
		'load("res://data/dev/arena/units/light_tank.tres")',
		'const T: String = "res://data/terrain/standard.tres"',
		'const M: String = "res://data/maps/perf_arena.tres"',
		'const P: String = "res://data/scenarios/perf_arena.tres"',
		'const P: String = "res://data/scenarios/controls_test.tres"',
		"var x: int = 1",
	]
	for line: String in allowed:
		assert_array(_outside(PackedStringArray([line]))).override_failure_message(line).is_empty()


## The `res://data` literals of `lines` that start with none of the allowed entries.
func _outside(lines: PackedStringArray) -> Array[String]:
	var found: Array[String] = []
	var pattern: RegEx = RegEx.create_from_string(LITERAL)
	for line: String in lines:
		for hit: RegExMatch in pattern.search_all(line):
			var text: String = hit.get_string()
			var ok: bool = text in Frozen.SCENARIOS
			for prefix: String in ALLOWED_PREFIXES:
				ok = ok or text.begins_with(prefix)
			if not ok:
				found.append(text)
	return found
