extends GdUnitTestSuite
## The mine marks (plan row P292, STYLE.md "The minelayers"): per faction the mark of an own mine
## and of a known enemy mine, hand-written SVG in `assets/art/svg/decals/` (`mine_<faction>_own`,
## `mine_<faction>_known`, the Derrick League's shot charge and the Lumen Accord's pulse seed).
## Each is 144 x 96 px at 2x with its ground point at (72, 60), a "Keep File" import (the
## match-start bake swaps the faction's key triad for the player's, as it does for the iso frames),
## the faction's triad present, no other colour in the faction's key band, and the known mark
## carries the notched rim the own one has not. P293's `MineLayer` draws them.

const DIR: String = "res://assets/art/svg/decals/mine_%s_%s.svg"
const FACTIONS: Array[String] = ["fossil", "renew"]
const KINDS: Array[String] = ["own", "known"]
const KEYS: Dictionary[String, Array] = {
	"fossil": ["#FF9446", "#E8681F", "#B04B12"], "renew": ["#62D6EE", "#1FA6C8", "#137C99"]
}
const ALLOWED: PackedStringArray = [
	"svg", "g", "path", "ellipse", "circle", "polygon", "rect", "polyline", "line"
]
const MAX_BYTES: int = 28 * 1024
## The known mark's ring must add at least this much ink to the own mark's (share of the own ink).
const RIM_INK_MIN: float = 0.15


func test_each_mark_is_144_x_96_with_a_shape_line_and_an_untouched_import() -> void:
	for faction: String in FACTIONS:
		for kind: String in KINDS:
			var path: String = DIR % [faction, kind]
			var text: String = FileAccess.get_file_as_string(path)
			assert_int(text.length()).override_failure_message(path).is_between(200, MAX_BYTES)
			assert_str(text).contains('width="144" height="96" viewBox="0 0 144 96"')
			var lines: PackedStringArray = text.split("\n")
			assert_bool(lines[0].begins_with("<!-- ") and lines[0].ends_with(" -->")).is_true()
			assert_bool(lines[1].begins_with("<!-- Silhouette: ")).is_true()
			assert_str(FileAccess.get_file_as_string(path + ".import")).contains('importer="keep"')


func test_only_the_allowed_tags_are_used_and_no_text_image_or_filter() -> void:
	var tag: RegEx = RegEx.create_from_string("<([a-zA-Z]+)")
	for faction: String in FACTIONS:
		for kind: String in KINDS:
			var text: String = FileAccess.get_file_as_string(DIR % [faction, kind])
			for found: RegExMatch in tag.search_all(text):
				(
					assert_bool(ALLOWED.has(found.get_string(1)))
					. override_failure_message("%s %s <%s>" % [faction, kind, found.get_string(1)])
					. is_true()
				)
			for banned: String in ["href", "<text", "<image", "<filter", "<pattern", "<style"]:
				assert_bool(text.contains(banned)).is_false()


func test_each_mark_carries_its_factions_whole_key_triad_and_no_other_key_hue() -> void:
	for faction: String in FACTIONS:
		var other: String = "renew" if faction == "fossil" else "fossil"
		for kind: String in KINDS:
			var text: String = FileAccess.get_file_as_string(DIR % [faction, kind]).to_upper()
			for key: String in KEYS[faction]:
				(
					assert_bool(text.contains(key))
					. override_failure_message("%s %s lacks %s" % [faction, kind, key])
					. is_true()
				)
			for key: String in KEYS[other]:
				assert_bool(text.contains(key)).is_false()
			var hex: RegEx = RegEx.create_from_string("#[0-9A-Fa-f]{6}")
			for found: RegExMatch in hex.search_all(text):
				var colour: Color = Color(found.get_string())
				if KEYS[faction].has(found.get_string()):
					continue
				var near: bool = false
				for key: String in KEYS[faction]:
					var hue_gap: float = absf(colour.h - Color(key).h) * 360.0
					hue_gap = minf(hue_gap, 360.0 - hue_gap)
					near = near or (hue_gap < 20.0 and colour.s >= 0.30)
				(
					assert_bool(near)
					. override_failure_message("%s %s %s" % [faction, kind, found.get_string()])
					. is_false()
				)


func test_the_known_mark_has_the_notched_rim_the_own_mark_has_not() -> void:
	for faction: String in FACTIONS:
		var own: String = FileAccess.get_file_as_string(DIR % [faction, "own"])
		var known: String = FileAccess.get_file_as_string(DIR % [faction, "known"])
		assert_bool(own.contains("stroke-dasharray")).is_false()
		assert_bool(known.contains("stroke-dasharray")).is_true()
		var own_ink: int = _ink(own)
		var known_ink: int = _ink(known)
		(
			assert_float(float(known_ink - own_ink) / float(own_ink))
			. override_failure_message("%s rim ink %d against %d" % [faction, known_ink, own_ink])
			. is_greater_equal(RIM_INK_MIN)
		)


func test_the_own_marks_stand_on_the_ground_point_inside_the_canvas_and_read_at_phone_zoom(
) -> void:
	for faction: String in FACTIONS:
		for kind: String in KINDS:
			var image: Image = _raster(FileAccess.get_file_as_string(DIR % [faction, kind]))
			var box: Rect2i = Rect2i()
			var first: bool = true
			for y: int in image.get_height():
				for x: int in image.get_width():
					if image.get_pixel(x, y).a > 0.5:
						var cell: Rect2i = Rect2i(x, y, 1, 1)
						box = cell if first else box.merge(cell)
						first = false
			var label: String = "%s %s %s" % [faction, kind, box]
			# 144 x 96 at 2x is 72 x 48 px at zoom 1: the ink spans at least half a tile in
			# width and stays off the outer pixel.
			assert_int(box.size.x).override_failure_message(label).is_greater_equal(36)
			assert_int(box.position.x).override_failure_message(label).is_greater(0)
			assert_int(box.position.y).override_failure_message(label).is_greater(0)
			assert_int(box.end.x).override_failure_message(label).is_less(image.get_width())
			assert_int(box.end.y).override_failure_message(label).is_less(image.get_height())
			# The ground point (72, 60) at 2x is (36, 30) at zoom 1: it is on the mark's body.
			assert_float(image.get_pixel(36, 30).a).override_failure_message(label).is_greater(0.5)


func _raster(text: String) -> Image:
	var image: Image = Image.new()
	image.load_svg_from_string(text, 0.5)
	return image


func _ink(text: String) -> int:
	var image: Image = _raster(text)
	var count: int = 0
	for y: int in image.get_height():
		for x: int in image.get_width():
			count += int(image.get_pixel(x, y).a > 0.5)
	return count
