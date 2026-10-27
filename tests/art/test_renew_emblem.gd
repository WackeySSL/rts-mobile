extends GdUnitTestSuite
## The Lumen Accord's emblem (plan row P104, ADR 0023 section 6): `emblem_renew.svg`, drawn in the
## Derrick League's style (greys only, a dark rim round a white ring round a dark panel, rivets on
## the ring, 128 px at import scale 1.0) but in a different frame: a flat-topped hexagon, not an
## octagon. The panel holds a white three-blade rotor on a round hub, turned off the vertical so it
## is a turbine and not a three-pointed star, above two shallow horizon arcs. No star, no flag, no
## wreath, no crest and no letter. The Derrick League's twin is in test_fossil_buildings.gd.

const Support: GDScript = preload("res://tests/art/building_picture_support.gd")
const EMBLEM: String = "res://assets/art/svg/icons/emblem_renew.svg"
const FOSSIL_EMBLEM: String = "res://assets/art/svg/icons/emblem_fossil.svg"
const HUD_BACKDROP: Color = Color("0F141C")
## The mean difference, 0 to 255, of the two emblems' greyscale rasters at 32 px over the HUD
## backdrop: the hexagon with its rotor is told from the octagon with its beam.
const EMBLEM_GAP: float = 40.0
const ICONS_STYLE: String = "res://assets/art/STYLE.md"
const CENTRE: Vector2 = Vector2(64, 64)
const HUB: Vector2 = Vector2(64, 53)
const RIM_RADIUS: float = 62.0
const RING_RADIUS: float = 57.0
const PANEL_RADIUS: float = 45.0
const RIVET_RADIUS: float = 51.0
## Degrees off the vertical of the first blade; the other two are 120 and 240 further round.
const BLADE_TURN: float = 20.0
const GREYS: Array[String] = ["4D4D4D", "FFFFFF", "BFBFBF"]


func test_the_emblem_is_a_hexagon_with_a_three_blade_rotor_two_arcs_and_six_rivets() -> void:
	var text: String = FileAccess.get_file_as_string(EMBLEM)
	assert_bool(text.is_empty()).is_false()
	assert_str(text).contains('width="128" height="128" viewBox="0 0 128 128"')
	var lines: PackedStringArray = text.split("\n")
	assert_str(lines[0]).starts_with("<!-- Lumen Accord emblem: ")
	assert_str(lines[1]).starts_with("<!-- Shape: ")
	assert_int(lines[1].length()).is_greater(60)
	var polygons: Array[PackedVector2Array] = _polygons(text)
	# The rim, the ring and the panel (hexagons), then a blade and its grey edge three times, then
	# the two arcs; nothing with four, five or ten corners, so no flag, no star.
	var sizes: Array[int] = []
	for polygon: PackedVector2Array in polygons:
		sizes.append(polygon.size())
	assert_array(sizes).is_equal([6, 6, 6, 7, 7, 7, 7, 7, 7, 16, 16])
	# Two circles make the hub, six more the rivets.
	assert_int(_circles(text).size()).is_equal(8)
	# A different frame from the Derrick League's octagon: six corners against its eight.
	var fossil: String = FileAccess.get_file_as_string(
		"res://assets/art/svg/icons/emblem_fossil.svg"
	)
	assert_int(_polygons(fossil)[0].size()).is_equal(8)


## A flat-topped regular hexagon: two corners on the middle line, four on the lines y = 64 +- r
## sin 60, the three hexagons sharing a centre and the radii 62, 57 and 45 (a dark rim 5 px thick,
## a white ring 12 px thick); nothing in the outer 2 px.
func test_the_three_hexagons_are_concentric_flat_topped_and_regular() -> void:
	var polygons: Array[PackedVector2Array] = _polygons(FileAccess.get_file_as_string(EMBLEM))
	var radii: Array[float] = [RIM_RADIUS, RING_RADIUS, PANEL_RADIUS]
	for i: int in 3:
		var hexagon: PackedVector2Array = polygons[i]
		var corners: Array[float] = []
		for point: Vector2 in hexagon:
			corners.append(point.distance_to(CENTRE))
		for corner: float in corners:
			assert_float(corner).override_failure_message("hexagon %d" % i).is_equal_approx(
				radii[i], 0.15
			)
		var midline: int = 0
		for point: Vector2 in hexagon:
			midline += int(is_equal_approx(point.y, 64.0))
		assert_int(midline).override_failure_message("hexagon %d" % i).is_equal(2)
	var rim: Rect2 = Rect2(polygons[0][0], Vector2.ZERO)
	for point: Vector2 in polygons[0]:
		rim = rim.expand(point)
	assert_float(rim.position.x).is_equal(2.0)
	assert_float(rim.end.x).is_equal(126.0)
	assert_float(rim.position.y).is_equal_approx(10.3, 0.05)
	assert_float(rim.end.y).is_equal_approx(117.7, 0.05)


## The rotor reads as a turbine and not as a star: three leaves of seven corners that stay inside
## the panel with room to spare, tips 120 degrees apart and turned 20 degrees off the vertical (no
## blade points straight up or down), round a round hub that is not on any blade's tip.
func test_the_rotor_is_three_swept_blades_turned_off_the_vertical_inside_the_panel() -> void:
	var text: String = FileAccess.get_file_as_string(EMBLEM)
	var polygons: Array[PackedVector2Array] = _polygons(text)
	for blade_index: int in 3:
		var blade: PackedVector2Array = polygons[3 + 2 * blade_index]
		var tip: Vector2 = HUB
		for point: Vector2 in blade:
			if point.distance_to(HUB) > tip.distance_to(HUB):
				tip = point
			(
				assert_bool(_inside_hexagon(point, PANEL_RADIUS - 3.0))
				. override_failure_message("blade %d leaves the panel at %s" % [blade_index, point])
				. is_true()
			)
		assert_float(tip.distance_to(HUB)).is_between(24.0, 27.0)
		var turn: float = rad_to_deg(atan2(tip.x - HUB.x, HUB.y - tip.y))
		var want: float = wrapf(BLADE_TURN + 120.0 * blade_index, -180.0, 180.0)
		assert_float(turn).override_failure_message("blade %d" % blade_index).is_equal_approx(
			want, 3.0
		)
		# The grey edge shares the leaf's tip: it is the leaf's trailing half.
		var edge: PackedVector2Array = polygons[4 + 2 * blade_index]
		assert_bool(edge.has(tip)).override_failure_message("blade %d edge" % blade_index).is_true()
	for circle: Vector3 in _circles(text).slice(0, 2):
		assert_vector(Vector2(circle.x, circle.y)).is_equal(HUB)
	assert_float(_circles(text)[0].z).is_greater(6.0)


## Two shallow horizon arcs under the rotor, each symmetric about the middle and clear of the
## rotor and of the panel's edge; six rivets on the ring, one on every corner of a hexagon of radius
## 51 that has two corners on the middle line.
func test_two_horizon_arcs_lie_under_the_rotor_and_six_rivets_sit_on_the_ring() -> void:
	var text: String = FileAccess.get_file_as_string(EMBLEM)
	var polygons: Array[PackedVector2Array] = _polygons(text)
	var lowest: float = 0.0
	for blade_polygon: PackedVector2Array in polygons.slice(3, 9):
		for point: Vector2 in blade_polygon:
			lowest = maxf(lowest, point.y)
	for arc_index: int in [9, 10]:
		var arc: PackedVector2Array = polygons[arc_index]
		var box: Rect2 = Rect2(arc[0], Vector2.ZERO)
		for point: Vector2 in arc:
			box = box.expand(point)
			(
				assert_bool(_inside_hexagon(point, PANEL_RADIUS - 2.0))
				. override_failure_message("arc %d leaves the panel at %s" % [arc_index, point])
				. is_true()
			)
		assert_float(box.get_center().x).is_equal_approx(64.0, 0.1)
		assert_float(box.position.y).is_greater(lowest + 6.0)
		assert_float(box.size.y).is_less(18.0)
	var rivets: Array[Vector3] = _circles(text).slice(2)
	assert_int(rivets.size()).is_equal(6)
	var angles: Array[int] = []
	for rivet: Vector3 in rivets:
		var at: Vector2 = Vector2(rivet.x, rivet.y)
		assert_float(at.distance_to(CENTRE)).is_equal_approx(RIVET_RADIUS, 0.2)
		assert_float(rivet.z).is_equal_approx(2.6, 0.01)
		angles.append(posmod(roundi(rad_to_deg((at - CENTRE).angle())), 360))
	angles.sort()
	assert_array(angles).is_equal([0, 60, 120, 180, 240, 300])


## White and grey only (#FFFFFF, #BFBFBF, #4D4D4D, as the Derrick League's emblem), so the HUD
## tints it; 128 px at import scale 1.0 with nothing on the outer pixel; and at 32 px in greyscale
## the white ring, the dark panel and the white rotor are three levels.
func test_the_emblem_is_greys_only_clear_at_the_edge_and_three_levels_at_32_px() -> void:
	var text: String = FileAccess.get_file_as_string(EMBLEM)
	var hex: RegEx = RegEx.create_from_string("#([0-9A-Fa-f]{2})([0-9A-Fa-f]{2})([0-9A-Fa-f]{2})")
	var found: int = 0
	for match: RegExMatch in hex.search_all(text):
		found += 1
		assert_str(match.get_string(1)).override_failure_message(match.get_string()).is_equal(
			match.get_string(2)
		)
		assert_str(match.get_string(2)).is_equal(match.get_string(3))
		assert_array(GREYS).contains([match.get_string().trim_prefix("#").to_upper()])
	assert_int(found).is_greater(10)
	var texture: Texture2D = load(EMBLEM) as Texture2D
	assert_vector(texture.get_size()).is_equal(Vector2(128, 128))
	var import_text: String = FileAccess.get_file_as_string(EMBLEM + ".import")
	assert_str(import_text).contains("svg/scale=1.0")
	var image: Image = texture.get_image()
	for i: int in 128:
		for edge: Vector2i in [Vector2i(i, 0), Vector2i(i, 127), Vector2i(0, i), Vector2i(127, i)]:
			assert_float(image.get_pixelv(edge).a).override_failure_message("%s" % edge).is_less(
				0.05
			)
	var small: Image = Support.raster(text, 0.25)
	assert_float(Support.grey(small, Vector2i(16, 5))).is_greater(0.8)  # The ring.
	assert_float(Support.grey(small, Vector2i(7, 16))).is_less(0.4)  # The panel.
	var brightest: float = 0.0
	for y: int in range(5, 20):
		for x: int in range(8, 24):
			brightest = maxf(brightest, Support.grey(small, Vector2i(x, y)))
	assert_float(brightest).is_greater(0.85)  # The rotor.


## The two factions' emblems read apart at 32 px in greyscale over the HUD's dark backdrop.
func test_the_two_emblems_read_apart_at_32_px_in_greyscale() -> void:
	var fossil: Image = _hud_grey(FOSSIL_EMBLEM)
	var renew: Image = _hud_grey(EMBLEM)
	var total: float = 0.0
	for y: int in 32:
		for x: int in 32:
			total += absf(
				Support.grey(fossil, Vector2i(x, y)) - Support.grey(renew, Vector2i(x, y))
			)
	var mean: float = 255.0 * total / (32 * 32)
	assert_float(mean).override_failure_message("mean difference %.1f" % mean).is_greater_equal(
		EMBLEM_GAP
	)


## The style guide says what the emblem is and where it is.
func test_the_style_guide_describes_the_emblem() -> void:
	var style: String = FileAccess.get_file_as_string(ICONS_STYLE).replace("\n", " ")
	for line: String in [
		"`emblem_renew.svg`",
		"Lumen Accord emblem",
		"flat-topped hexagon",
		"three-blade rotor",
		"horizon arcs",
		"not a star",
	]:
		assert_str(style).override_failure_message(line).contains(line)


## A flat-topped regular hexagon of radius `radius` round the emblem's centre holds `point`.
func _inside_hexagon(point: Vector2, radius: float) -> bool:
	var d: Vector2 = (point - CENTRE).abs()
	var half: float = radius * sqrt(3.0) / 2.0
	return d.y <= half + 0.001 and sqrt(3.0) / 2.0 * d.x + 0.5 * d.y <= half + 0.001


func _polygons(text: String) -> Array[PackedVector2Array]:
	var found: Array[PackedVector2Array] = []
	var points: RegEx = RegEx.create_from_string('<polygon points="([^"]*)"')
	for match: RegExMatch in points.search_all(text):
		var polygon: PackedVector2Array = PackedVector2Array()
		for pair: String in match.get_string(1).split(" ", false):
			var xy: PackedStringArray = pair.split(",")
			polygon.append(Vector2(xy[0].to_float(), xy[1].to_float()))
		found.append(polygon)
	return found


## Each circle as (cx, cy, r).
func _circles(text: String) -> Array[Vector3]:
	var found: Array[Vector3] = []
	var circle: RegEx = RegEx.create_from_string('<circle cx="([^"]*)" cy="([^"]*)" r="([^"]*)"')
	for match: RegExMatch in circle.search_all(text):
		found.append(
			Vector3(
				match.get_string(1).to_float(),
				match.get_string(2).to_float(),
				match.get_string(3).to_float()
			)
		)
	return found


## An emblem at 32 px over the HUD backdrop, as the HUD draws it (untinted).
func _hud_grey(path: String) -> Image:
	var small: Image = Support.raster(FileAccess.get_file_as_string(path), 0.25)
	var page: Image = Image.create_empty(32, 32, false, Image.FORMAT_RGBA8)
	for y: int in 32:
		for x: int in 32:
			var pixel: Color = small.get_pixel(x, y)
			page.set_pixel(x, y, HUD_BACKDROP.lerp(Color(pixel, 1.0), pixel.a))
	return page
