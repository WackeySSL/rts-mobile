extends GdUnitTestSuite
## The HUD's fonts (plan row P118, ADR 0025 section 13): Big Shoulders Display ExtraBold and Chakra
## Petch at 500, 600 and 700, SIL OFL 1.1, the unmodified upstream files under
## `assets/art/fonts/<family>/`. Every font file has the family's `OFL.txt` beside it and a row in
## `assets/CREDITS.md`, no family declares a Reserved Font Name (so the files could be subset and
## renamed later; they are not), every file is the file that was downloaded (the pinned SHA-256),
## and each one holds the Danish and German letters of the GDD's languages.

const FileScan: GDScript = preload("res://tests/support/file_scan.gd")
const FONT_DIR: String = "res://assets/art/fonts"
const CREDITS_PATH: String = "res://assets/CREDITS.md"
const OFL_NAME: String = "OFL.txt"
const FONT_EXTENSIONS: Array[String] = [".ttf", ".otf", ".woff", ".woff2"]
const LICENCE_TITLE: String = "SIL OPEN FONT LICENSE Version 1.1"
const LICENCE_START: String = "This Font Software is licensed under"
## Danish and German letters (the GDD's later languages), in both cases, and the sharp s.
const LETTERS: String = "æøåäöüßÆØÅÄÖÜ"

## The SHA-256 of every file of the folder as downloaded (see CREDITS.md for the sources). A new
## font or a new version of one changes this table and its CREDITS row in the same PR.
const UPSTREAM_SHA256: Dictionary[String, String] = {
	"big-shoulders/BigShouldersDisplay-ExtraBold.ttf":
	"9850b5a13ed25975abbf7ec175d76b26e0e115016d9945b782b08179c27ea4f2",
	"big-shoulders/OFL.txt": "338f9c050f19daeda1d597243faf79f3a3d437c338af58cb7047617d0ce08771",
	"chakra-petch/ChakraPetch-Bold.ttf":
	"65fbf76d95651697275e19db4d717c0e95a789ddd3476478b05292104db278a0",
	"chakra-petch/ChakraPetch-Medium.ttf":
	"d480f4f97405fac3600652e2e14fd0b14339031c0af4da11582994878f04d919",
	"chakra-petch/ChakraPetch-SemiBold.ttf":
	"45264de3204ddbd5fb3e14a2402acd5c630d16650ae5fc221d2c52da46a6734b",
	"chakra-petch/OFL.txt": "13831d02389d917d22fcfa6c79f98f8acbf61d230add0e73a4d4dc5f3bfb9e56",
}
## The weight that the file's own name table gives it, by file: what the theme relies on.
const WEIGHTS: Dictionary[String, int] = {
	"chakra-petch/ChakraPetch-Medium.ttf": 500,
	"chakra-petch/ChakraPetch-SemiBold.ttf": 600,
	"chakra-petch/ChakraPetch-Bold.ttf": 700,
}


func test_every_font_file_has_an_ofl_text_beside_it_and_a_credits_row() -> void:
	var fonts: Array[String] = _font_files()
	assert_int(fonts.size()).is_equal(4)
	var credits: Array[String] = _credit_rows()
	for path: String in fonts:
		var ofl: String = path.get_base_dir().path_join(OFL_NAME)
		assert_bool(FileAccess.file_exists(ofl)).override_failure_message(ofl).is_true()
		var text: String = FileAccess.get_file_as_string(ofl)
		assert_str(text).override_failure_message(ofl).contains(LICENCE_TITLE)
		assert_str(text).override_failure_message(ofl).starts_with("Copyright ")
		var row: String = _row_naming(credits, "`%s`" % path.get_file())
		assert_str(row).override_failure_message("CREDITS.md row of %s" % path).is_not_empty()
		assert_str(row).override_failure_message(path).contains("SIL OFL 1.1")
		assert_str(row).override_failure_message(path).contains("https://")
		assert_str(row).override_failure_message(path).contains(
			"`%s/`" % ofl.get_base_dir().trim_prefix("res://")
		)


## The copyright lines before the licence text may add "with Reserved Font Name ..."; none does, so
## the OFL's rule on renaming a modified font does not bind us, and the files are unmodified anyway.
func test_no_family_declares_a_reserved_font_name() -> void:
	for path: String in _font_files():
		var ofl: String = path.get_base_dir().path_join(OFL_NAME)
		var text: String = FileAccess.get_file_as_string(ofl)
		var header: String = text.substr(0, text.find(LICENCE_START))
		assert_int(text.find(LICENCE_START)).override_failure_message(ofl).is_greater(0)
		assert_str(header.to_lower()).override_failure_message(ofl).not_contains(
			"reserved font name"
		)


## Unmodified upstream files: the folder holds exactly the pinned set, each with its hash.
func test_the_font_folder_holds_the_pinned_upstream_files_unmodified() -> void:
	var found: Array[String] = []
	for path: String in FileScan.list_files(FONT_DIR, ""):
		if path.ends_with(".import") or path.ends_with(".uid"):
			continue  # Godot's own files.
		found.append(path.trim_prefix(FONT_DIR + "/"))
	found.sort()
	var pinned: Array[String] = []
	pinned.assign(UPSTREAM_SHA256.keys())
	pinned.sort()
	assert_array(found).is_equal(pinned)
	for name: String in pinned:
		var path: String = FONT_DIR.path_join(name)
		assert_str(FileAccess.get_sha256(path)).override_failure_message(path).is_equal(
			UPSTREAM_SHA256[name]
		)


func test_every_font_has_the_danish_and_german_letters() -> void:
	for path: String in _font_files():
		var font: FontFile = load(path)
		assert_object(font).override_failure_message(path).is_not_null()
		var missing: String = ""
		for letter: String in LETTERS:
			if not font.has_char(letter.unicode_at(0)):
				missing += letter
		assert_str(missing).override_failure_message("%s lacks" % path).is_empty()


func test_the_chakra_petch_files_are_the_weights_the_theme_names() -> void:
	for name: String in WEIGHTS:
		var font: FontFile = load(FONT_DIR.path_join(name))
		assert_int(font.font_weight).override_failure_message(name).is_equal(WEIGHTS[name])
		assert_str(font.get_font_name()).override_failure_message(name).contains("Chakra Petch")


## The theme says the digits of a changing number keep fixed slots in code because Chakra Petch has
## no `tnum`. A new version of the font that has one fails here: the theme's header, the CREDITS row
## and P119's fallback change in the same PR.
func test_chakra_petch_has_no_tabular_figures_so_the_digits_keep_fixed_slots() -> void:
	var server: TextServer = TextServerManager.get_primary_interface()
	var tnum: int = server.name_to_tag("tnum")
	for name: String in WEIGHTS:
		var font: FontFile = load(FONT_DIR.path_join(name))
		var features: Dictionary = font.get_supported_feature_list()
		assert_bool(features.has(tnum)).override_failure_message(name).is_false()
		(
			assert_bool(features.has(server.name_to_tag("kern")))
			. override_failure_message(name)
			. is_true()
		)


## The font files of the folder: every file with a font extension below it.
func _font_files() -> Array[String]:
	var files: Array[String] = []
	for extension: String in FONT_EXTENSIONS:
		files.append_array(FileScan.list_files(FONT_DIR, extension))
	files.sort()
	return files


## The rows of the credits table, one string each (the row's own line).
func _credit_rows() -> Array[String]:
	var rows: Array[String] = []
	for line: String in FileAccess.get_file_as_string(CREDITS_PATH).split("\n"):
		if line.begins_with("| "):
			rows.append(line)
	return rows


func _row_naming(rows: Array[String], needle: String) -> String:
	for row: String in rows:
		if row.contains(needle):
			return row
	return ""
