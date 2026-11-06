extends GdUnitTestSuite
## The sim suites' shared builders play the frozen defs (plan row P171b, ADR 0031): no file under
## `tests/sim/support` loads a unit, weapon or faction of the shipped data folders, the shipped
## `data/rules.tres` or a shipped Skirmish scenario, so a tuning row cannot move a rule suite built
## on them. `kestrel_rig.gd` and `kestrel_run.gd` play the shipped Skirmish on purpose (plan
## exception 20 lists their suites as tuning pins). Only code is scanned: a comment may name a
## shipped file.

const FileScan: GDScript = preload("res://tests/support/file_scan.gd")
const SUPPORT_DIR: String = "res://tests/sim/support"
## Support files that play the shipped Skirmish on purpose.
const SHIPPED_ON_PURPOSE: Array[String] = [
	"res://tests/sim/support/kestrel_rig.gd", "res://tests/sim/support/kestrel_run.gd"
]
const SHIPPED: Array[String] = [
	"res://data/units/",
	"res://data/weapons/",
	"res://data/factions/",
	"res://data/rules.tres",
	"res://data/scenarios/skirmish",
]


func test_no_support_file_loads_a_shipped_def_or_a_shipped_skirmish_scenario() -> void:
	var files: Array[String] = FileScan.list_files(SUPPORT_DIR, ".gd")
	assert_array(files).contains(SHIPPED_ON_PURPOSE)
	var scanned: int = 0
	for path: String in files:
		if path in SHIPPED_ON_PURPOSE:
			continue
		scanned += 1
		var lines: PackedStringArray = FileScan.code_lines(FileAccess.get_file_as_string(path))
		for index: int in lines.size():
			for shipped: String in SHIPPED:
				(
					assert_bool(lines[index].contains(shipped))
					. override_failure_message("%s:%d loads %s" % [path, index + 1, shipped])
					. is_false()
				)
	assert_int(scanned).is_greater(40)


func test_the_scan_sees_a_shipped_path_in_code_and_not_in_a_comment() -> void:
	var text: String = "# res://data/units/a.tres\n"
	text += 'var x: String = "res://data/units/b.tres"  # res://data/rules.tres\n'
	var lines: PackedStringArray = FileScan.code_lines(text)
	assert_bool(lines[0].contains("res://data/units/")).is_false()
	assert_bool(lines[1].contains("res://data/units/")).is_true()
	assert_bool(lines[1].contains("res://data/rules.tres")).is_false()
