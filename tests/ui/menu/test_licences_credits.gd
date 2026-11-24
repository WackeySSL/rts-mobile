extends GdUnitTestSuite
## Every asset under a Creative Commons Attribution licence in assets/CREDITS.md has its credit
## lines (file, author, licence and version, source) on the Licences screen, and the screen's
## credit list holds nothing else (plan P447; ADR 0041 section 7; the screen is ADR 0043 section 7).
## The catalog's own filter is not trusted: the rows here come from a separate parse.
## Only CC0 1.0 and CC BY 3.0 or 4.0 are allowed among the Creative Commons licences (CLAUDE.md
## Legal; ADR 0041 section 7): CC BY-SA, NC, ND and every other spelling fail the closed allow-list
## below, so no row can slip past the attribution parse unseen.
## CC0 rows need no credit line. The screen lists none today (ADR 0041's "as a courtesy" is not
## built: `LicenceCatalog.credit_lines` keeps CC BY rows only), so a CC0 row on the screen would
## count as extra here; if the courtesy is built later, this test changes with it.

const CREDITS: String = "res://assets/CREDITS.md"
const ROW_TITLE: String = "Asset credits (CC BY)"
## The columns of a CREDITS.md table: File, Author, Source URL, Licence, Notes.
const COLUMNS: int = 5
## The closed set of Licence cells, optionally followed by a parenthetical. CC BY-SA, NC and ND are
## absent on purpose, and so is MIT: no asset may be MIT, only code is (CLAUDE.md Legal, ADR 0046).
## The AI-made marking of ADR 0051 is allowed whole (its rows are checked by test_credits_ai_rows).
const ALLOWED: String = (
	"^(CC0 1\\.0|CC[ -]BY [34]\\.0|SIL OFL 1\\.1|All rights reserved"
	+ "|AI-made with Figma AI, no copyright claimed by AppCode ApS)( \\(.*\\))?$"
)
## Any Creative Commons mention in the Licence or Source cell (the Notes may discuss rules).
const CC_MENTION: String = (
	"(?i)(\\bCC\\b|\\bCC[ -]?\\d|\\bCC[ -]?BY|" + "Creative Commons|creativecommons)"
)
const FORBIDDEN: String = "(?i)(\\b(NC|ND|SA)\\b|NonCommercial|NoDerivs|ShareAlike)"
## An attribution licence at the start of the Licence cell, in any spelling; the parenthetical after
## it may say anything ("Creative Commons 0" in a CC0 row).
const ATTRIBUTION: String = "(?i)^(CC[ -]?BY|Creative Commons Attribution|Attribution)"
const SEPARATOR: String = "\n\n"


## The table rows of `credits_md` as cells (the cells between the pipes, stripped), skipping the
## header and the separator.
func _table(credits_md: String) -> Array[PackedStringArray]:
	var rows: Array[PackedStringArray] = []
	for line: String in credits_md.split("\n"):
		if not line.begins_with("|"):
			continue
		var cells: PackedStringArray = []
		for cell: String in line.split("|"):
			cells.append(cell.strip_edges())
		# split leaves an empty cell before the first and after the last pipe.
		cells = cells.slice(1, cells.size() - 1)
		if cells[0] == "File or folder" or cells[0].begins_with("---"):
			continue
		rows.append(cells)
	return rows


## What is wrong with the rows of `credits_md`: a wrong column count, a licence outside the closed
## allow-list, or a Creative Commons or forbidden mention in the Licence or Source cell.
func _problems(credits_md: String) -> PackedStringArray:
	var allowed: RegEx = RegEx.create_from_string(ALLOWED)
	var mention: RegEx = RegEx.create_from_string(CC_MENTION)
	var forbidden: RegEx = RegEx.create_from_string(FORBIDDEN)
	var problems: PackedStringArray = []
	for row: PackedStringArray in _table(credits_md):
		if row.size() != COLUMNS:
			problems.append("%s: %d columns, expected %d" % [row[0], row.size(), COLUMNS])
			continue
		var licence: String = row[3]
		if allowed.search(licence) == null:
			problems.append("%s: licence not allowed: %s" % [row[0], licence])
		for cell: String in [licence, row[2]]:
			if mention.search(cell) != null and forbidden.search(cell) != null:
				problems.append("%s: forbidden Creative Commons term in: %s" % [row[0], cell])
	return problems


## The rows whose Licence cell names an attribution licence: file, author, source, licence.
func _by_rows() -> Array[PackedStringArray]:
	var by: RegEx = RegEx.create_from_string(ATTRIBUTION)
	var rows: Array[PackedStringArray] = []
	for row: PackedStringArray in _table(FileAccess.get_file_as_string(CREDITS)):
		if row.size() == COLUMNS and by.search(row[3]) != null:
			rows.append(PackedStringArray([row[0], row[1], row[2], row[3]]))
	return rows


func _screen_text() -> String:
	for entry: LicenceEntry in LicenceCatalog.from_build().build():
		if entry.title == ROW_TITLE:
			return entry.text
	return ""


func test_every_credits_row_has_five_columns_and_an_allowed_licence() -> void:
	var problems: PackedStringArray = _problems(FileAccess.get_file_as_string(CREDITS))
	(
		assert_array(problems)
		. override_failure_message("CREDITS.md breaks the licence rules:\n" + "\n".join(problems))
		. is_empty()
	)


func test_the_licence_check_rejects_the_forbidden_and_unknown_licences() -> void:
	var head: String = (
		"| File or folder | Author | Source URL | Licence | Notes |\n"
		+ "| --- | --- | --- | --- | --- |\n"
	)
	for licence: String in [
		"CC BY-NC 4.0",
		"CC BY-ND 4.0",
		"CC BY-SA 4.0",
		"CC-BY-SA 3.0",
		"CC BY 2.0",
		"CC BY",
		"Attribution 4.0 International",
		"https://creativecommons.org/licenses/by/4.0/",
		# No asset may be MIT; only code is (ADR 0046): own art is "All rights reserved (AppCode ApS)".
		"MIT",
		"Royalty free",
		"",
	]:
		var table: String = head + "| `a.wav` | Ann | https://x | %s | n |\n" % licence
		(
			assert_int(_problems(table).size())
			. override_failure_message("the licence check lets through: " + licence)
			. is_greater(0)
		)
	var good: String = head + "| `a.wav` | Ann | https://x | CC BY 4.0 (the page says it) | n |\n"
	assert_array(_problems(good)).is_empty()
	var shifted: String = head + "| `a|b.wav` | Ann | https://x | CC BY 4.0 | n |\n"
	assert_int(_problems(shifted).size()).is_greater(0)
	var by_url: String = (
		head + "| `a.wav` | Ann | https://creativecommons.org/licenses/by-nc/4.0/ | CC0 1.0 | n |\n"
	)
	assert_int(_problems(by_url).size()).is_greater(0)


func test_there_are_cc_by_rows_and_each_names_an_author_a_licence_and_a_version() -> void:
	var rows: Array[PackedStringArray] = _by_rows()
	assert_int(rows.size()).override_failure_message("no CC BY row found in CREDITS.md").is_greater(
		0
	)
	# The version follows "BY" directly, so a number in a parenthetical cannot satisfy it.
	var versioned: RegEx = RegEx.create_from_string("(?i)^CC[ -]BY [34]\\.0\\b")
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


func test_the_credit_list_holds_no_row_that_credits_does_not_have_as_cc_by() -> void:
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
