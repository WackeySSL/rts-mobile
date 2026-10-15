extends GdUnitTestSuite
## Facts that live in two files and would drift apart without a word: the camera's zoom levels
## (data/input_settings.tres) and the art gallery's zoom row, the licence credit for the debug APKs'
## default launcher icon (ADR 0005, plan risk 12), the selection ring's texture radius that the unit
## layer and the art gallery each hold (P56d), and the error scan's allowlist, which hides engine
## errors from verify.sh and both export scripts: a new or widened entry must show up here.

const SETTINGS_PATH: String = "res://data/input_settings.tres"
const GALLERY_PATH: String = "res://scenes/dev/art_gallery.tscn"
const CREDITS_PATH: String = "res://assets/CREDITS.md"
const ALLOWLIST_PATH: String = "res://scripts/verify-allowlist.txt"
const ZOOM_ROWS: Array[String] = ["Grass/ZoomRow", "Sand/ZoomRow"]
## The gallery has no class_name: a preloaded script gives its constants.
const ArtGallery: GDScript = preload("res://game/view/art_gallery.gd")


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
				var rig_scale: Vector2 = (rig as Node2D).scale
				assert_float(rig_scale.y).override_failure_message(row_path).is_equal(rig_scale.x)
				scales.append(rig_scale.x)
		scales.sort()
		assert_array(scales).override_failure_message(row_path).is_equal(levels)


## Both scale a ring by `radius / RING_TEX_RADIUS_PX`, so the gallery (art-director's) shows the
## ring sizes of the game (touch-ux-dev's UnitLayer) only while the two constants agree. The
## texture itself is pinned to the same 72 px by tests/art.
func test_the_unit_layer_and_the_art_gallery_scale_the_ring_texture_by_the_same_radius() -> void:
	assert_float(ArtGallery.RING_TEX_RADIUS_PX).is_equal(UnitLayer.RING_TEX_RADIUS_PX)


## Whitespace is normalised, so a re-wrapped line does not break the check.
func test_credits_name_the_debug_launcher_icon_and_the_licence_file() -> void:
	var credits: String = FileAccess.get_file_as_string(CREDITS_PATH)
	assert_str(credits).is_not_empty()
	var flat: String = RegEx.create_from_string("\\s+").sub(credits, " ", true)
	assert_str(flat).contains("default launcher icon of the debug APKs")
	assert_str(flat).contains("THIRD_PARTY_LICENSES.txt")
	assert_str(flat).contains("Andrea Calabró")  # CC BY: the author and the licence are the credit.
	assert_str(flat).contains("CC BY 4.0")


func test_the_allowlist_holds_only_the_icon_entry() -> void:
	var entries: Array[String] = []
	for line: String in FileAccess.get_file_as_string(ALLOWLIST_PATH).split("\n"):
		if not line.strip_edges().is_empty() and not line.begins_with("#"):
			entries.append(line)
	assert_array(entries).is_equal(["^ERROR: No project icon specified\\.[ ]"])
