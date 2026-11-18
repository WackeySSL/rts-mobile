extends GdUnitTestSuite
## Plan P530 (ADR 0044 section 4): every row of docs/HOW_TO_PLAY.md has a stable id in its first
## column. The tutorial beats (`covers`) and the help entries name rows by these ids, so an id is
## unique, well formed, starts with its section's prefix and is never reused.

const DOC: String = "res://docs/HOW_TO_PLAY.md"
const HELP: String = "res://data/help/how_to_play.tres"
const ID_PATTERN: String = "^[a-z0-9]+(-[a-z0-9]+)+$"
const MAX_LENGTH: int = 48

## Section heading -> the prefix every id of its rows starts with (followed by a dash).
const PREFIXES: Dictionary = {
	"Camera": "camera",
	"Turn the phone": "turn-the-phone",
	"Units": "units",
	"Buildings": "buildings",
	"Selection": "selection",
	"Orders": "orders",
	"Combat": "combat",
	"Terrain": "terrain",
	"Economy": "economy",
	"Fog": "fog",
	"Groups (left edge)": "groups",
	"The screen in battle": "the-screen-in-battle",
	"Pause": "pause",
	"Build menu (the build drawer)": "build-menu",
	"Superweapon": "superweapon",
	"Factions": "factions",
	"The computer opponent": "the-computer-opponent",
	"Winning": "winning",
	"Menus (the menu frame)": "menus",
	"The intro": "the-intro",
	"Not yet in the game": "later",
}

## Where the id of a deleted row goes, so that no later row takes it. Never remove an entry.
const RETIRED: Array[String] = []


## Every table row as {"id", "section", "line"}; an `id` of "" is a row without one.
func _rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var section: String = ""
	var in_table: bool = false
	var number: int = 0
	for line: String in FileAccess.get_file_as_string(DOC).split("\n"):
		number += 1
		if line.begins_with("## "):
			section = line.substr(3).strip_edges()
			in_table = false
		elif line.begins_with("| Id |"):
			in_table = true
		elif in_table and line.begins_with("|---"):
			continue
		elif line.begins_with("|"):
			var cells: PackedStringArray = line.split("|")
			var id: String = cells[1].strip_edges() if cells.size() > 1 else ""
			rows.append({"id": id, "section": section, "line": number})
		else:
			in_table = false
	return rows


func test_every_table_starts_with_an_id_column() -> void:
	var tables: int = 0
	var headers: int = 0
	for line: String in FileAccess.get_file_as_string(DOC).split("\n"):
		if line.begins_with("| Action |"):
			tables += 1
		if line.begins_with("| Id | Action |"):
			headers += 1
	assert_int(headers).is_greater(0)
	assert_int(tables).override_failure_message("a table without an Id column").is_equal(0)


func test_every_section_has_a_prefix_and_rows() -> void:
	var seen: Dictionary = {}
	for row: Dictionary in _rows():
		seen[row["section"]] = true
		(
			assert_bool(PREFIXES.has(row["section"]))
			. override_failure_message("section without a prefix: " + String(row["section"]))
			. is_true()
		)
	for heading: String in PREFIXES:
		(
			assert_bool(seen.has(heading))
			. override_failure_message("no rows under " + heading)
			. is_true()
		)


func test_every_row_has_an_id() -> void:
	var rows: Array[Dictionary] = _rows()
	assert_int(rows.size()).is_greater(100)
	for row: Dictionary in rows:
		(
			assert_str(String(row["id"]))
			. override_failure_message("line %d has no id" % row["line"])
			. is_not_empty()
		)


func test_every_id_is_well_formed() -> void:
	var pattern: RegEx = RegEx.create_from_string(ID_PATTERN)
	for row: Dictionary in _rows():
		var id: String = row["id"]
		(
			assert_bool(pattern.search(id) != null)
			. override_failure_message("line %d: '%s' is not plain kebab case" % [row["line"], id])
			. is_true()
		)
		(
			assert_int(id.length())
			. override_failure_message(
				"line %d: '%s' is longer than %d" % [row["line"], id, MAX_LENGTH]
			)
			. is_less_equal(MAX_LENGTH)
		)


func test_every_id_is_unique() -> void:
	var seen: Dictionary = {}
	for row: Dictionary in _rows():
		var id: String = row["id"]
		(
			assert_bool(seen.has(id))
			. override_failure_message(
				"line %d: '%s' repeats line %s" % [row["line"], id, str(seen.get(id))]
			)
			. is_false()
		)
		seen[id] = row["line"]


func test_every_id_starts_with_its_section_prefix() -> void:
	for row: Dictionary in _rows():
		var prefix: String = PREFIXES.get(row["section"], "")
		assert_str(prefix).is_not_empty()
		(
			assert_bool(String(row["id"]).begins_with(prefix + "-"))
			. override_failure_message(
				"line %d: '%s' must start with '%s-'" % [row["line"], row["id"], prefix]
			)
			. is_true()
		)


func test_no_id_is_retired() -> void:
	for row: Dictionary in _rows():
		(
			assert_bool(RETIRED.has(row["id"]))
			. override_failure_message(
				"line %d: '%s' is retired and never reused" % [row["line"], row["id"]]
			)
			. is_false()
		)


func test_retired_ids_are_well_formed_and_unique() -> void:
	var pattern: RegEx = RegEx.create_from_string(ID_PATTERN)
	var seen: Dictionary = {}
	for id: String in RETIRED:
		assert_bool(pattern.search(id) != null).override_failure_message(id).is_true()
		assert_bool(seen.has(id)).override_failure_message("twice: " + id).is_false()
		seen[id] = true


func test_every_help_entry_names_an_existing_row() -> void:
	var ids: Dictionary = {}
	for row: Dictionary in _rows():
		ids[row["id"]] = true
	var help: HelpDef = load(HELP) as HelpDef
	assert_object(help).is_not_null()
	var checked: int = 0
	for section: HelpSectionDef in help.sections:
		for entry: HelpEntryDef in section.entries:
			checked += 1
			(
				assert_bool(ids.has(String(entry.id)))
				. override_failure_message(
					"help entry '%s' names no row of HOW_TO_PLAY.md" % entry.id
				)
				. is_true()
			)
	assert_int(checked).is_greater(0)
