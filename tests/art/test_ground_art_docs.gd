extends GdUnitTestSuite
## The texts of plan row P105: STYLE.md ("Iso ground tiles" in "Fog and terrain", "Fields", the
## catalogue and the Terrain page) says what the files are, with the numbers the other suites
## measure, and assets/CREDITS.md has a row for every new file. The art is in test_ground_art.gd
## and test_field_art.gd.

const Support: GDScript = preload("res://tests/art/ground_art_support.gd")
const TerrainPage: GDScript = preload("res://game/view/art_gallery_ground.gd")
const STYLE_PATH: String = "res://assets/art/STYLE.md"
const CREDITS_PATH: String = "res://assets/CREDITS.md"
const HEX: String = "#[0-9A-Fa-f]{6}"


func test_style_md_names_the_version_the_sections_and_the_tile_rules() -> void:
	var style: String = FileAccess.get_file_as_string(STYLE_PATH)
	assert_str(style).contains("**v1.8 (Phase 3, P105)**")
	var terrain: String = _section(style, "## Fog and terrain")
	assert_str(terrain).contains("### Iso ground tiles (P105)")
	assert_str(terrain).contains("**128 x 64 at 2x**")
	assert_str(terrain).contains("`(column + row) % 2`")
	# The soft rim is withdrawn (Michael, 2026-10-27): the text says so and has no rim column.
	assert_str(_flat(terrain)).contains("**No rim**")
	assert_str(_flat(terrain)).contains("ADR 0023 section 5's soft rim is withdrawn")
	assert_str(terrain).not_contains("| Rim")
	assert_str(terrain).not_contains("The soft rim**")
	assert_str(terrain).contains("`clipPath` called `inner`")
	assert_str(_flat(_section(style, "## Fields"))).contains("**full** above two thirds")
	assert_str(_flat(_section(style, "## Gallery"))).contains("**Terrain** (the sixth page")


func test_the_palette_table_starts_with_the_base_colour_each_file_fills_its_diamond_with() -> void:
	var terrain: String = _section(FileAccess.get_file_as_string(STYLE_PATH), "## Fog and terrain")
	var row: RegEx = RegEx.create_from_string("\\n\\| (\\w+) \\| (" + HEX + ") \\|([^\\n]*)")
	var hex: RegEx = RegEx.create_from_string(HEX)
	var seen: Array[String] = []
	for found: RegExMatch in row.search_all(terrain):
		var id: String = found.get_string(1)
		seen.append(id)
		for variant: String in ["a", "b"]:
			var raw: String = Support.text(Support.ground_path(id, variant))
			var text: String = raw.to_upper()
			# The base is the first fill after the clip path, and every tone of the row is in the file.
			var fill: RegExMatch = RegEx.create_from_string('fill="(' + HEX + ')"').search(raw)
			assert_str(fill.get_string(1).to_upper()).override_failure_message(id).is_equal(
				found.get_string(2).to_upper()
			)
			for tone: RegExMatch in hex.search_all(found.get_string(3)):
				assert_str(text).override_failure_message(id + tone.get_string()).contains(
					tone.get_string().to_upper()
				)
	var ids: Array[String] = []
	for id: StringName in Support.TERRAIN_IDS:
		ids.append(String(id))
	assert_array(seen).is_equal(ids)


func test_the_greyscale_numbers_of_the_style_guide_are_the_measured_means() -> void:
	var style: String = FileAccess.get_file_as_string(STYLE_PATH)
	var means: Dictionary[String, float] = Support.grey_means()
	var ground: RegExMatch = (
		RegEx
		. create_from_string(
			(
				"means \\(a and b\\) grass (\\d+) and (\\d+), sand (\\d+) and (\\d+), scrub (\\d+) and (\\d+), "
				+ "rock (\\d+) and (\\d+), water (\\d+) and (\\d+), ore (\\d+) and (\\d+)"
			)
		)
		. search(_flat(style))
	)
	assert_object(ground).is_not_null()
	var index: int = 1
	for id: StringName in Support.TERRAIN_IDS:
		for variant: String in ["a", "b"]:
			var key: String = "%s_%s" % [id, variant]
			assert_float(means[key]).override_failure_message(key).is_equal_approx(
				float(ground.get_string(index)), 1.0
			)
			index += 1
	var fields: RegExMatch = (
		RegEx
		. create_from_string(
			"oil full (\\d+), half (\\d+), dry (\\d+) and gas full (\\d+), half (\\d+), dry (\\d+)"
		)
		. search(_flat(style))
	)
	assert_object(fields).is_not_null()
	index = 1
	for kind: String in Support.KINDS:
		for stage: String in Support.STAGES:
			var key: String = "%s_%s" % [kind, stage]
			assert_float(means[key]).override_failure_message(key).is_equal_approx(
				float(fields.get_string(index)), 1.0
			)
			index += 1


func test_the_off_map_colour_the_canvases_and_the_anchors_are_in_the_text() -> void:
	var style: String = FileAccess.get_file_as_string(STYLE_PATH)
	var terrain: String = _section(style, "## Fog and terrain")
	assert_str(terrain).contains("**#%s**" % TerrainPage.OFF_MAP_COLOR.to_html(false).to_upper())
	var fields: String = _flat(_section(style, "## Fields"))
	for snippet: String in [
		"**128 x 64 at 2x**",
		"**112 x 116** at 2x",
		"**(56, 88)**",
		"**140 x 72**",
		"**(56, 31)**",
		"**288 x 144** at 2x",
		"**(144, 72)**",
		"**radius 1.5 tiles (1500 milli)**",
		"scale `r / 1500`",
	]:
		assert_str(fields).override_failure_message(snippet).contains(snippet)
	for kind: String in Support.KINDS:
		for stage: String in Support.STAGES:
			assert_str(fields).contains("`%s_%s.svg`" % [kind, stage])
	# Every colour the Fields section names is in one of the files of the row.
	var drawn: String = ""
	for dir: String in [Support.FIELDS_DIR, Support.DECALS_DIR]:
		for path: String in Support.FileScan.list_files(dir, ".svg"):
			drawn += Support.text(path).to_upper()
	for found: RegExMatch in RegEx.create_from_string(HEX).search_all(fields):
		assert_str(drawn).override_failure_message(found.get_string()).contains(
			found.get_string().to_upper()
		)


func test_the_catalogue_lists_the_ground_the_stages_the_wellhead_and_the_crater() -> void:
	var style: String = FileAccess.get_file_as_string(STYLE_PATH)
	for snippet: String in [
		"`ground/<terrain_id>_{a,b}.svg`, 128x64",
		"`fields/<kind>_<stage>.svg`, 128x64",
		"`fields/wellhead.svg`, 112x116, anchor (56, 88)",
		"`fields/wellhead_shadow.svg`, 140x72, anchor (56, 31)",
		"`decals/crater.svg`, 288x144, anchor (144, 72)",
	]:
		assert_str(style).override_failure_message(snippet).contains(snippet)


func test_every_new_file_has_a_row_in_the_credits() -> void:
	var credits: String = FileAccess.get_file_as_string(CREDITS_PATH)
	var files: Array[String] = []
	for dir: String in [Support.GROUND_DIR, Support.FIELDS_DIR, Support.DECALS_DIR]:
		files.append_array(Support.FileScan.list_files(dir, ".svg"))
	assert_int(files.size()).is_equal(12 + 8 + 1)
	for path: String in files:
		var short: String = path.trim_prefix("res://")
		assert_str(credits).override_failure_message(short).contains("`%s`" % short)


## The text from `heading` to the next heading of the same level.
func _section(style: String, heading: String) -> String:
	var start: int = style.find(heading)
	return style.substr(start, style.find("\n## ", start + 1) - start)


## The text with every line break made a space, so a sentence wrapped over two lines is one.
func _flat(text: String) -> String:
	return RegEx.create_from_string("\\s+").sub(text, " ", true)
