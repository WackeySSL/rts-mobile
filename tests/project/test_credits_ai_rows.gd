extends GdUnitTestSuite
## Plan P623 (ADR 0051 section 4, 5): every CREDITS row marked AI-made carries the Figma link and
## frame, the feature, the date, a short prompt, the hand edits and "screened: ...", and
## assets/LICENSE.md excludes the marked files. No row is AI-made today, so the checker is also run
## on crafted rows.

const CREDITS: String = "res://assets/CREDITS.md"
const LICENCE: String = "res://assets/LICENSE.md"
const MARK: String = "AI-made with Figma AI, no copyright claimed by AppCode ApS"

const GOOD_NOTES: String = (
	"Feature: Make image. Date: 2026-11-24. Prompt: a misty ridge at dawn. "
	+ "Hand edits: cropped and graded. Screened: no resemblance to an existing game"
)
const GOOD_SOURCE: String = "https://www.figma.com/design/AbC123/rts (frame Menu backdrop)"


func test_every_ai_made_row_in_credits_is_complete() -> void:
	var rows: Array[PackedStringArray] = _rows(FileAccess.get_file_as_string(CREDITS))
	for row: PackedStringArray in rows:
		if _is_ai(row):
			var problems: Array[String] = _problems(row)
			assert_array(problems).override_failure_message(row[0]).is_empty()


func test_the_licence_excludes_the_marked_files() -> void:
	var text: String = FileAccess.get_file_as_string(LICENCE)
	assert_bool(text.contains(MARK)).is_true()
	assert_bool(text.contains("outside this notice")).is_true()


func test_no_row_mentions_ai_without_the_exact_marking() -> void:
	for row: PackedStringArray in _rows(FileAccess.get_file_as_string(CREDITS)):
		var lowered: String = row[3].to_lower()
		if lowered.contains("ai-made") or lowered.contains("figma ai"):
			assert_str(row[3].strip_edges()).override_failure_message(row[0]).is_equal(MARK)


func test_the_checker_accepts_a_good_row() -> void:
	assert_array(_problems(_row(GOOD_SOURCE, GOOD_NOTES))).is_empty()


func test_the_checker_rejects_a_row_missing_each_field() -> void:
	var cases: Dictionary = {
		"figma link": _row("frame Menu backdrop", GOOD_NOTES),
		"frame": _row("https://www.figma.com/design/AbC123/rts", GOOD_NOTES),
		"feature": _row(GOOD_SOURCE, GOOD_NOTES.replace("Feature: Make image. ", "")),
		"date": _row(GOOD_SOURCE, GOOD_NOTES.replace("Date: 2026-11-24. ", "")),
		"prompt": _row(GOOD_SOURCE, GOOD_NOTES.replace("Prompt: a misty ridge at dawn. ", "")),
		"hand edits": _row(GOOD_SOURCE, GOOD_NOTES.replace("Hand edits: cropped and graded. ", "")),
		"screened":
		_row(GOOD_SOURCE, GOOD_NOTES.replace("Screened: no resemblance to an existing game", "")),
	}
	for key: String in cases:
		var row: PackedStringArray = cases[key]
		assert_bool(_is_ai(row)).is_true()
		assert_array(_problems(row)).override_failure_message(key).is_not_empty()


func test_the_checker_rejects_an_empty_screen_and_a_row_without_a_path() -> void:
	var empty_screen: PackedStringArray = _row(
		GOOD_SOURCE, GOOD_NOTES.replace("no resemblance to an existing game", "")
	)
	assert_array(_problems(empty_screen)).is_not_empty()
	var no_path: PackedStringArray = _row(GOOD_SOURCE, GOOD_NOTES)
	no_path[0] = "the menu backdrop"
	assert_array(_problems(no_path)).is_not_empty()


func _row(source: String, notes: String) -> PackedStringArray:
	return PackedStringArray(["`assets/art/menu/backdrop.png`", "Figma AI", source, MARK, notes])


func _is_ai(row: PackedStringArray) -> bool:
	return row.size() >= 5 and row[3].contains("AI-made")


## Problems of one AI-made row; empty when it is complete.
func _problems(row: PackedStringArray) -> Array[String]:
	var found: Array[String] = []
	if row[3].strip_edges() != MARK:
		found.append("licence column is not the exact marking")
	if not row[0].contains("`assets/"):
		found.append("no assets/ path in backticks")
	var source: String = row[2]
	if not source.contains("figma.com/"):
		found.append("no Figma link")
	if not source.to_lower().contains("frame"):
		found.append("no frame")
	var notes: String = row[4].to_lower()
	for label: String in ["feature:", "prompt:", "hand edits:"]:
		if not notes.contains(label + " ") or notes.contains(label + " ."):
			found.append("no " + label)
	var date: RegEx = RegEx.create_from_string("date: \\d{4}-\\d{2}-\\d{2}")
	if date.search(notes) == null:
		found.append("no date")
	var screen: RegEx = RegEx.create_from_string("screened: \\S")
	if screen.search(notes) == null:
		found.append("no screened:")
	return found


## Table rows with five cells; the header and rule rows are skipped by their content.
func _rows(text: String) -> Array[PackedStringArray]:
	var rows: Array[PackedStringArray] = []
	for line: String in text.split("\n"):
		if not line.begins_with("| "):
			continue
		var cells: PackedStringArray = PackedStringArray()
		for cell: String in line.trim_prefix("| ").trim_suffix(" |").split(" | "):
			cells.append(cell)
		if cells.size() >= 5 and cells[0] != "File or folder" and not cells[0].begins_with("---"):
			rows.append(cells)
	return rows
