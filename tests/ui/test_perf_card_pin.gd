extends GdUnitTestSuite
## Pins the text of `PerfCard` and the keys of `PerfHud.summary()` (plan P184): six fixed runs
## (units arena, a failing and paused run, the base arena, Android with the library and without,
## the AI arena of P185)
## render to `fixtures/perf_card_pin.txt`, which was made on the code before the `PerfHud` split, so
## the split is proven a pure move. The machine's own values (model, engine, screen) are masked.
##
## From now on it pins the card's lines and the summary of those runs. A row that changes the card
## or the summary on purpose re-makes the fixture and says why in its PR; P185 (the `ai_think_*`
## keys) and P66b (its card keys) are expected to. Re-making it is one step: on a mismatch this
## suite writes what it got to `user://perf_card_pin.txt`, and the failure prints that file's path
## and the copy command. Check the diff of the fixture, then run the command.

const Cases: GDScript = preload("res://tests/ui/support/perf_card_cases.gd")
const FIXTURE: String = "res://tests/ui/fixtures/perf_card_pin.txt"
## Per process, so two worktrees that fail the pin at once do not overwrite each other's output.
var _remade: String = "user://perf_card_pin_%d.txt" % OS.get_process_id()


func test_every_case_renders_as_before_the_split() -> void:
	var want: String = FileAccess.get_file_as_string(FIXTURE).replace("\r\n", "\n")
	var got: String = ""
	for case_name: String in Cases.CASES:
		got += Cases.render(case_name)
	assert_int(want.length()).is_greater(0)
	var message: String = first_difference(want, got)
	if message != "":
		var file: FileAccess = FileAccess.open(_remade, FileAccess.WRITE)
		if file == null:
			message += "\n(could not write %s to re-make the fixture)" % _remade
		else:
			file.store_string(got)
			file.close()
			message += (
				"\nAn intended change of the card or the summary: cp '%s' %s"
				% [ProjectSettings.globalize_path(_remade), FIXTURE.trim_prefix("res://")]
			)
	assert_str(message).is_empty()


## "" when the two texts are the same, else the case, the line in it and both lines.
func first_difference(want: String, got: String) -> String:
	var want_lines: PackedStringArray = want.split("\n")
	var got_lines: PackedStringArray = got.split("\n")
	var case_name: String = ""
	var at: int = 0
	for i: int in maxi(want_lines.size(), got_lines.size()):
		var a: String = want_lines[i] if i < want_lines.size() else "<end of the fixture>"
		var b: String = got_lines[i] if i < got_lines.size() else "<end of the output>"
		if b.begins_with("== ") and b.ends_with(" =="):
			case_name = b
			at = 0
		at += 1
		if a != b:
			return "%s line %d differs\n  fixture: %s\n  output:  %s" % [case_name, at, a, b]
	return ""
