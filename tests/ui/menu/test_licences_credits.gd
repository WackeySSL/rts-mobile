extends GdUnitTestSuite
## Every asset under a Creative Commons Attribution licence in assets/CREDITS.md has its credit
## lines (file, author, licence and version, source) on the Licences screen, and the screen lists
## nothing else (plan P447, ADR 0041 section 7). CC BY-SA counts as attribution-required too, and
## the catalog's own filter is not trusted: the rows here come from a separate, broader parse.

const CREDITS: String = "res://assets/CREDITS.md"
const ROW_TITLE: String = "Asset credits (CC BY)"
## Any spelling of an attribution licence in the Licence column.
const ATTRIBUTION: String = "(?i)(CC[ -]?BY|Creative Commons Attribution)"
const SEPARATOR: String = "\n\n"


## The rows whose Licence cell names an attribution licence: file, author, source, licence.
func _by_rows() -> Array[PackedStringArray]:
	var by: RegEx = RegEx.create_from_string(ATTRIBUTION)
	var rows: Array[PackedStringArray] = []
	for line: String in FileAccess.get_file_as_string(CREDITS).split("\n"):
		if not line.begins_with("|"):
			continue
		var cells: PackedStringArray = line.split("|")
		if cells.size() < 6 or by.search(cells[4]) == null:
			continue
		var row: PackedStringArray = []
		for index: int in [1, 2, 3, 4]:
			row.append(cells[index].strip_edges())
		rows.append(row)
	return rows


func _screen_text() -> String:
	for entry: LicenceEntry in LicenceCatalog.from_build().build():
		if entry.title == ROW_TITLE:
			return entry.text
	return ""


func test_there_are_cc_by_rows_and_each_names_an_author_a_licence_and_a_version() -> void:
	var rows: Array[PackedStringArray] = _by_rows()
	assert_int(rows.size()).override_failure_message("no CC BY row found in CREDITS.md").is_greater(
		0
	)
	var versioned: RegEx = RegEx.create_from_string("\\d\\.\\d")
	for row: PackedStringArray in rows:
		(
			assert_str(row[1])
			. override_failure_message("CREDITS.md names no author for " + row[0])
			. is_not_empty()
		)
		(
			assert_bool(versioned.search(row[3]) != null)
			. override_failure_message(
				"CREDITS.md gives no licence version for " + row[0] + ": " + row[3]
			)
			. is_true()
		)


func test_every_cc_by_row_has_its_credit_lines_on_the_licences_screen() -> void:
	var text: String = _screen_text()
	assert_str(text).is_not_empty()
	var blocks: PackedStringArray = text.split(SEPARATOR)
	for row: PackedStringArray in _by_rows():
		var found: bool = false
		for block: String in blocks:
			var lines: PackedStringArray = block.split("\n")
			# The credit block is file, author, licence, source, one per line.
			if lines.size() == 4 and lines[0] == row[0]:
				found = true
				assert_str(lines[1]).override_failure_message("author of " + row[0]).is_equal(
					row[1]
				)
				assert_str(lines[2]).override_failure_message("licence of " + row[0]).is_equal(
					row[3]
				)
				assert_str(lines[3]).override_failure_message("source of " + row[0]).is_equal(
					row[2]
				)
		(
			assert_bool(found)
			. override_failure_message("the Licences screen has no credit lines for " + row[0])
			. is_true()
		)


func test_the_licences_screen_lists_no_cc_by_credit_that_credits_does_not_have() -> void:
	var files: PackedStringArray = []
	for row: PackedStringArray in _by_rows():
		files.append(row[0])
	var blocks: PackedStringArray = _screen_text().split(SEPARATOR)
	(
		assert_int(blocks.size())
		. override_failure_message(
			(
				"the screen lists %d credits, CREDITS.md has %d CC BY rows"
				% [blocks.size(), files.size()]
			)
		)
		. is_equal(files.size())
	)
	for block: String in blocks:
		var name: String = block.split("\n")[0]
		(
			assert_bool(files.has(name))
			. override_failure_message(
				"the Licences screen credits " + name + ", which CREDITS.md does not list as CC BY"
			)
			. is_true()
		)
