extends GdUnitTestSuite
## Plan P528 (ADR 0044 section 5, rules 1 and 4): every row of `docs/HOW_TO_PLAY.md` except the
## "Not yet in the game" rows has player text in `data/help/how_to_play.tres`, under the help
## section of its own heading, and no player text holds a developer reference. The full coverage
## test (Teach rows in lessons, the pending list) is P545's.

const DOC: String = "res://docs/HOW_TO_PLAY.md"
const HELP: String = "res://data/help/how_to_play.tres"
const NOT_FOR_PLAYERS: String = "Not yet in the game"

## What a player must never read: a code span, a data path or file, a setting's unit suffix.
const FORBIDDEN: Array[String] = [
	"`",
	"data/",
	".tres",
	"_ms",
	"res://",
	"_ticks",
	"_milli",
	"_dp",
	"_percent",
	"ADR ",
	"dev menu",
	"Developer menu",
]

var _help: HelpDef


func before_test() -> void:
	_help = load(HELP) as HelpDef


func after_test() -> void:
	_help = null


func test_every_player_row_has_non_empty_help_text_under_its_own_section() -> void:
	var checked: int = 0
	for row: Dictionary in _rows():
		var id: String = row["id"]
		var entry: HelpEntryDef = _help.entry(StringName(id))
		(
			assert_object(entry)
			. override_failure_message("row '%s' has no help entry" % id)
			. is_not_null()
		)
		if entry == null:
			continue
		checked += 1
		assert_str(entry.title.strip_edges()).override_failure_message(id + " title").is_not_empty()
		assert_str(entry.body.strip_edges()).override_failure_message(id + " body").is_not_empty()
		(
			assert_str(String(_section_of(entry.id)))
			. override_failure_message("'%s' is in the wrong help section" % id)
			. is_equal(_slug(row["section"]))
		)
	assert_int(checked).is_greater(100)


func test_no_row_of_the_not_yet_section_has_help_text() -> void:
	for row: Dictionary in _rows(true):
		(
			assert_object(_help.entry(StringName(row["id"])))
			. override_failure_message("'%s' is not in the game yet" % row["id"])
			. is_null()
		)


func test_player_text_has_no_developer_reference() -> void:
	for section: HelpSectionDef in _help.sections:
		for entry: HelpEntryDef in section.entries:
			var text: String = entry.title + "\n" + entry.body
			for bad: String in FORBIDDEN:
				(
					assert_bool(text.contains(bad))
					. override_failure_message("%s contains '%s'" % [entry.id, bad])
					. is_false()
				)


## The rows as {"id", "section"}; the "Not yet in the game" rows only when `later` is set.
func _rows(later: bool = false) -> Array[Dictionary]:
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
			if (section == NOT_FOR_PLAYERS) == later:
				var cells: PackedStringArray = line.split("|")
				rows.append({"id": cells[1].strip_edges(), "section": section})
		else:
			in_table = false
	return rows


func _section_of(entry_id: StringName) -> StringName:
	for section: HelpSectionDef in _help.sections:
		if section.entries.any(func(item: HelpEntryDef) -> bool: return item.id == entry_id):
			return section.id
	return &""


## "Groups (left edge)" -> "groups"; "The screen in battle" -> "the-screen-in-battle".
func _slug(heading: String) -> String:
	var open: int = heading.find(" (")
	var base: String = heading if open < 0 else heading.substr(0, open)
	return base.to_lower().replace(" ", "-")
