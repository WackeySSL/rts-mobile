extends GdUnitTestSuite
## Plan row P545 (ADR 0044 section 5, rules 2, 3 and 5): the lessons cover the Teach rows of
## `docs/HOW_TO_PLAY.md`. Every row marked Teach is in the `covers` of at least one lesson beat
## (`data/tutorial/*.tres`), and every `covers` id names a real row of the game (not one of the
## "Not yet in the game" rows). The help text of every row, and its wording, are P528's
## (`test_how_to_play_help_copy.gd`).
## `PENDING` lists the Teach rows that no lesson covers yet, each with the plan row that will cover
## it. It must be empty from the gate row P560 on: a row is never added to it to quiet this suite,
## and an entry whose row is covered (or is no Teach row) fails as stale.

const DOC: String = "res://docs/HOW_TO_PLAY.md"
const LESSON_DIR: String = "res://data/tutorial/"
const NOT_FOR_PLAYERS: String = "Not yet in the game"
const TEACH_MARK: String = "yes"
## Teach row id -> the plan row that covers it. Empty today: every Teach row is in a lesson.
const PENDING: Dictionary[String, String] = {}


func test_every_teach_row_is_covered_by_a_lesson_beat() -> void:
	var uncovered: Array[String] = _uncovered(_teach_ids(), _covered_ids())
	for id: String in PENDING:
		uncovered.erase(id)
	(
		assert_array(uncovered)
		. override_failure_message(
			(
				"Teach rows no lesson beat covers (add the id to a beat's covers): %s"
				% ", ".join(uncovered)
			)
		)
		. is_empty()
	)


func test_every_covers_id_names_a_row_that_is_in_the_game() -> void:
	var stale: Array[String] = _stale(_player_ids(), _covered_ids())
	(
		assert_array(stale)
		. override_failure_message(
			(
				"covers ids that are no row of docs/HOW_TO_PLAY.md (or a Not-yet row): %s"
				% ", ".join(stale)
			)
		)
		. is_empty()
	)


## An id of `PENDING` that is covered now, or that is no Teach row, is stale: it comes off the list.
func test_every_pending_entry_is_a_teach_row_that_no_lesson_covers() -> void:
	var covered: Array[String] = _covered_ids()
	var teach: Array[String] = _teach_ids()
	var stale: Array[String] = []
	for id: String in PENDING:
		if covered.has(id) or not teach.has(id) or PENDING[id].strip_edges().is_empty():
			stale.append(id)
	(
		assert_array(stale)
		. override_failure_message("stale PENDING entries: %s" % ", ".join(stale))
		. is_empty()
	)


## From the gate row P560 on the list stays empty (ADR 0044 section 5, rule 5).
func test_the_pending_list_is_empty() -> void:
	(
		assert_array(PENDING.keys())
		. override_failure_message(
			"PENDING must be empty at the gate (P560): %s" % ", ".join(PENDING.keys())
		)
		. is_empty()
	)


func test_the_four_lessons_are_found_and_the_doc_has_teach_rows() -> void:
	var lessons: Array[TutorialLessonDef] = _lessons()
	var ids: Array[String] = []
	for lesson: TutorialLessonDef in lessons:
		ids.append(String(lesson.id))
	ids.sort()
	assert_array(ids).is_equal(["air", "basics", "strikes", "support"])
	assert_int(_teach_ids().size()).is_greater(50)


## The check itself names every row it finds uncovered, and only those.
func test_the_check_names_the_uncovered_and_the_stale_ids() -> void:
	var teach: Array[String] = ["a-one", "a-two", "b-three"]
	assert_array(_uncovered(teach, ["a-two", "x-gone"])).is_equal(["a-one", "b-three"])
	assert_array(_uncovered(teach, teach)).is_empty()
	assert_array(_stale(["a-one", "a-two"], ["a-two", "x-gone", "x-gone"])).is_equal(["x-gone"])
	assert_array(_stale(["a-one"], ["a-one"])).is_empty()


## The Teach ids of rows that are in the game, in document order.
func _teach_ids() -> Array[String]:
	var found: Array[String] = []
	for row: Dictionary in _rows():
		if row["teach"]:
			found.append(row["id"])
	return found


## Every id of a row in the game.
func _player_ids() -> Array[String]:
	var found: Array[String] = []
	for row: Dictionary in _rows():
		found.append(row["id"])
	return found


## Every id any beat of any lesson covers, without repeats.
func _covered_ids() -> Array[String]:
	var found: Array[String] = []
	for lesson: TutorialLessonDef in _lessons():
		for id: StringName in lesson.covered_ids():
			if not found.has(String(id)):
				found.append(String(id))
	return found


## What of `teach` is not in `covered`.
func _uncovered(teach: Array[String], covered: Array[String]) -> Array[String]:
	var missing: Array[String] = []
	for id: String in teach:
		if not covered.has(id):
			missing.append(id)
	return missing


## What of `covered` is not in `known`, each once.
func _stale(known: Array[String], covered: Array[String]) -> Array[String]:
	var stale: Array[String] = []
	for id: String in covered:
		if not known.has(id) and not stale.has(id):
			stale.append(id)
	return stale


## Every lesson of `data/tutorial/`, by file name order.
func _lessons() -> Array[TutorialLessonDef]:
	var found: Array[TutorialLessonDef] = []
	var names: PackedStringArray = DirAccess.get_files_at(LESSON_DIR)
	names.sort()
	for file_name: String in names:
		if not file_name.ends_with(".tres"):
			continue
		var lesson: TutorialLessonDef = load(LESSON_DIR + file_name) as TutorialLessonDef
		if lesson != null:
			found.append(lesson)
	return found


## The rows of the tables outside the "Not yet in the game" section, as {"id", "teach"}. The Teach
## mark is the last cell of the row.
func _rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var section: String = ""
	var in_table: bool = false
	for line: String in FileAccess.get_file_as_string(DOC).split("\n"):
		if line.begins_with("## "):
			section = line.substr(3).strip_edges()
			in_table = false
		elif line.begins_with("| Id |"):
			in_table = true
		elif in_table and line.begins_with("|---"):
			continue
		elif in_table and line.begins_with("|"):
			if section != NOT_FOR_PLAYERS:
				var cells: PackedStringArray = line.split("|")
				(
					rows
					. append(
						{
							"id": cells[1].strip_edges(),
							"teach": cells[cells.size() - 2].strip_edges() == TEACH_MARK,
						}
					)
				)
		else:
			in_table = false
	return rows
