extends GdUnitTestSuite
## Facts that live in two files and would drift apart without a word: the zoom levels of the camera
## (data/input_settings.tres) and the zoom row of the art gallery that judges them, and the licence
## credit for the default launcher icon of the debug APKs (ADR 0005, plan risk 12).

const SETTINGS_PATH: String = "res://data/input_settings.tres"
const GALLERY_PATH: String = "res://scenes/dev/art_gallery.tscn"
const CREDITS_PATH: String = "res://assets/CREDITS.md"
const ZOOM_ROWS: Array[String] = ["Grass/ZoomRow", "Sand/ZoomRow"]


func test_the_gallery_zoom_row_shows_the_camera_zoom_levels() -> void:
	var levels: Array[float] = []
	for level: float in (load(SETTINGS_PATH) as InputSettings).zoom_levels:
		levels.append(level)
	assert_array(levels).is_not_empty()
	var gallery: Node = auto_free((load(GALLERY_PATH) as PackedScene).instantiate())
	for row_path: String in ZOOM_ROWS:
		var scales: Array[float] = []
		for rig: Node in gallery.get_node(row_path).get_children():
			if rig is Node2D:  # The labels under the rigs are Controls.
				scales.append((rig as Node2D).scale.x)
		scales.sort()
		assert_array(scales).override_failure_message(row_path).is_equal(levels)


## Whitespace is normalised, so a re-wrapped line does not break the check.
func test_credits_name_the_debug_launcher_icon_and_the_licence_file() -> void:
	var credits: String = FileAccess.get_file_as_string(CREDITS_PATH)
	assert_str(credits).is_not_empty()
	var flat: String = RegEx.create_from_string("\\s+").sub(credits, " ", true)
	assert_str(flat).contains("default launcher icon of the debug APKs")
	assert_str(flat).contains("THIRD_PARTY_LICENSES.txt")
