extends GdUnitTestSuite
## `data/help/how_to_play.tres` (plan P527): every entry has an id, a section and text, ids are
## unique and kebab case with their section's prefix, the player text has no developer reference,
## and every `## ` section of `docs/HOW_TO_PLAY.md` meant for players has a help section. The rows
## have no ids yet (P530), so the row-by-row check is P545's; this one pins the sections.

const DOC_PATH: String = "res://docs/HOW_TO_PLAY.md"
const NOT_FOR_PLAYERS: Array[String] = ["Not yet in the game"]
const FORBIDDEN: Array[String] = ["`", "data/", ".tres", "_ms", "res://"]

var _help: HelpDef


func before_test() -> void:
	_help = load("res://data/help/how_to_play.tres") as HelpDef


func after_test() -> void:
	_help = null


func test_every_entry_has_an_id_a_section_and_text() -> void:
	assert_int(_help.sections.size()).is_greater(0)
	var seen: Dictionary = {}
	for section: HelpSectionDef in _help.sections:
		assert_str(String(section.id)).is_not_empty()
		assert_str(section.title).is_not_empty()
		assert_int(section.entries.size()).override_failure_message(section.id).is_greater(0)
		for entry: HelpEntryDef in section.entries:
			var label: String = "%s/%s" % [section.id, entry.id]
			assert_str(String(entry.id)).override_failure_message(label).is_not_empty()
			assert_str(entry.title).override_failure_message(label).is_not_empty()
			assert_str(entry.body.strip_edges()).override_failure_message(label).is_not_empty()
			(
				assert_bool(String(entry.id).begins_with(String(section.id) + "-"))
				. override_failure_message(label)
				. is_true()
			)
			(
				assert_bool(seen.has(entry.id))
				. override_failure_message("duplicate " + label)
				. is_false()
			)
			seen[entry.id] = true
			assert_object(_help.entry(entry.id)).is_same(entry)


func test_player_text_has_no_developer_reference() -> void:
	for section: HelpSectionDef in _help.sections:
		for entry: HelpEntryDef in section.entries:
			var text: String = section.title + entry.title + entry.body
			for bad: String in FORBIDDEN:
				(
					assert_bool(text.contains(bad))
					. override_failure_message("%s has '%s'" % [entry.id, bad])
					. is_false()
				)


func test_every_player_section_of_the_doc_has_a_help_section() -> void:
	var ids: Dictionary = {}
	for section: HelpSectionDef in _help.sections:
		ids[section.id] = true
	var headings: Array[String] = _doc_headings()
	assert_int(headings.size()).is_greater(10)
	for heading: String in headings:
		assert_bool(ids.has(StringName(_slug(heading)))).override_failure_message(heading).is_true()
	# And the other way round: no help section names a heading the doc lacks.
	var slugs: Dictionary = {}
	for heading: String in headings:
		slugs[StringName(_slug(heading))] = true
	for id: StringName in ids:
		assert_bool(slugs.has(id)).override_failure_message(String(id)).is_true()


func _doc_headings() -> Array[String]:
	var out: Array[String] = []
	var text: String = FileAccess.get_file_as_string(DOC_PATH)
	assert_str(text).is_not_empty()
	for line: String in text.split("\n"):
		if line.begins_with("## "):
			var heading: String = line.substr(3).strip_edges()
			if not NOT_FOR_PLAYERS.has(heading):
				out.append(heading)
	return out


## "Groups (left edge)" -> "groups"; "The screen in battle" -> "the-screen-in-battle".
func _slug(heading: String) -> String:
	var open: int = heading.find(" (")
	var base: String = heading if open < 0 else heading.substr(0, open)
	return base.to_lower().replace(" ", "-")
