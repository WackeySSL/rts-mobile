extends GdUnitTestSuite
## The UI's fonts (plan row P605, ADR 0049 amendment of 2026-11-25, ADR 0025 section 13): Michael's
## Figma type, three families, SIL OFL 1.1, the unmodified upstream files under
## `assets/art/fonts/<family>/`: Roboto Condensed Bold (display), Inter Regular and Bold (body and
## buttons) and IBM Plex Mono Regular (labels and numbers). Every font file has the family's
## `OFL.txt` beside it and a row in `assets/CREDITS.md`, every file is the file that was downloaded
## (the pinned SHA-256), each one holds the Danish and German letters of the GDD's languages, and
## nothing under `game/`, `scenes/` or `data/` names the two faces that went (Big Shoulders, Chakra
## Petch).

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
	"ibm-plex-mono/IBMPlexMono-Regular.ttf":
	"7c6fbddca4b700be918f5f6183d9bd4464fa427fe435f0b480d77fe2bb8c5a43",
	"ibm-plex-mono/OFL.txt": "7e6b2818edbd8f6a01ae80641cc8f16a51080d08fb4e532be3a0b6f74adb07da",
	"inter/Inter-Bold.ttf": "288316099b1e0a47a4716d159098005eef7c0066921f34e3200393dbdb01947f",
	"inter/Inter-Regular.ttf": "40d692fce188e4471e2b3cba937be967878f631ad3ebbbdcd587687c7ebe0c82",
	"inter/OFL.txt": "262481e844521b326f5ecd053e59b98c8b2da78c8ee1bdbb6e8174305e54935a",
	"roboto-condensed/OFL.txt": "061402327a96aadb0bfb694a960ed289ecd38d383e396243831ab81feb109c41",
	"roboto-condensed/RobotoCondensed-Bold.ttf":
	"dd4dffb78aa4bfe0fc7185c75570ddef7d6faf9695405f918b2a313588f4942c",
}
## The weight Godot reads from each file, and the name table's family: what the theme relies on.
const FACES: Dictionary[String, Array] = {
	"roboto-condensed/RobotoCondensed-Bold.ttf": [700, "Roboto Condensed"],
	"inter/Inter-Regular.ttf": [400, "Inter"],
	"inter/Inter-Bold.ttf": [700, "Inter"],
	"ibm-plex-mono/IBMPlexMono-Regular.ttf": [400, "IBM Plex Mono"],
}
## The words that name a face of the retired set; nothing of the game may mention them.
const RETIRED: Array[String] = ["big-shoulders", "bigshoulders", "big shoulders", "chakra"]
const SCAN_ROOTS: Array[String] = ["res://game", "res://scenes", "res://data"]
const SCAN_EXTENSIONS: Array[String] = [".gd", ".tscn", ".tres", ".res", ".json", ".cfg", ".md"]
## The Nordic letters of the GDD's Danish text, which the task names one by one.
const NORDIC: String = "ÆæØøÅå"


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


## The copyright line before the licence text may add "with Reserved Font Name ...": only IBM's does
## ("Plex"). The OFL's rule on renaming binds a modified version only, and the files are unmodified,
## so the reserved name changes nothing here; this pins which family has one, so another is noticed.
func test_only_ibm_plex_declares_a_reserved_font_name() -> void:
	for path: String in _font_files():
		var ofl: String = path.get_base_dir().path_join(OFL_NAME)
		var text: String = FileAccess.get_file_as_string(ofl)
		var header: String = text.substr(0, text.find(LICENCE_START))
		assert_int(text.find(LICENCE_START)).override_failure_message(ofl).is_greater(0)
		var declares: bool = header.to_lower().contains("reserved font name")
		assert_bool(declares).override_failure_message(ofl).is_equal(path.contains("ibm-plex-mono"))


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


## The task's own check, letter by letter: Æ, æ, Ø, ø, Å and å are glyphs of every face.
func test_every_font_has_ae_oe_aa_in_both_cases() -> void:
	assert_int(_font_files().size()).is_equal(FACES.size())
	for path: String in _font_files():
		var font: FontFile = load(path)
		for letter: String in NORDIC:
			(
				assert_bool(font.has_char(letter.unicode_at(0)))
				. override_failure_message("%s has no %s" % [path, letter])
				. is_true()
			)


func test_the_files_are_the_weights_and_families_the_theme_names() -> void:
	for name: String in FACES:
		var font: FontFile = load(FONT_DIR.path_join(name))
		assert_int(font.font_weight).override_failure_message(name).is_equal(FACES[name][0])
		assert_str(font.get_font_name()).override_failure_message(name).contains(FACES[name][1])


## Static files only: a variable font has variation axes, and none of these has one.
func test_no_font_is_a_variable_font() -> void:
	for path: String in _font_files():
		var font: FontFile = load(path)
		(
			assert_bool(font.get_supported_variation_list().is_empty())
			. override_failure_message(path)
			. is_true()
		)


## Plex Mono is fixed width: every digit is as wide as the "0", so the clock, the count and the
## credits could drop the per-digit slot code (P618). The slots stay for now (P119), and DigitRow
## measures the theme's font, so it would keep working with a proportional face too.
func test_plex_mono_digits_are_all_one_width() -> void:
	var font: FontFile = load(FONT_DIR.path_join("ibm-plex-mono/IBMPlexMono-Regular.ttf"))
	var zero: float = font.get_char_size("0".unicode_at(0), 100).x
	for digit: String in "123456789":
		var width: float = font.get_char_size(digit.unicode_at(0), 100).x
		assert_float(width).override_failure_message(digit).is_equal_approx(zero, 0.01)


## The two retired faces are gone: no script, scene, resource or data file under `game/`,
## `scenes/` or `data/` names them, in code or in a comment, and their folders are gone.
func test_nothing_references_the_retired_fonts() -> void:
	for folder: String in ["big-shoulders", "chakra-petch"]:
		(
			assert_bool(DirAccess.dir_exists_absolute(FONT_DIR.path_join(folder)))
			. override_failure_message(folder)
			. is_false()
		)
	var scanned: int = 0
	for root: String in SCAN_ROOTS:
		for extension: String in SCAN_EXTENSIONS:
			for path: String in FileScan.list_files(root, extension):
				var text: String = FileAccess.get_file_as_string(path).to_lower()
				scanned += 1
				for word: String in RETIRED:
					(
						assert_bool(text.contains(word))
						. override_failure_message("%s names the retired font '%s'" % [path, word])
						. is_false()
					)
	assert_int(scanned).is_greater(100)


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
