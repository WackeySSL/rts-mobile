extends GdUnitTestSuite
## The art gallery zoom row (the light tank at 0.75, 1.0 and 1.5, team A on grass and team B on
## sand) and the feedback marker numbers in assets/art/STYLE.md that P16 draws from.

const GALLERY: String = "res://scenes/dev/art_gallery.tscn"
const STYLE_GUIDE: String = "res://assets/art/STYLE.md"
const HULL_SVG: String = "res://assets/art/svg/units/light_tank_hull.svg"
const ZOOM_RIGS: Dictionary[String, float] = {"Zoom075": 0.75, "Zoom100": 1.0, "Zoom150": 1.5}
const GROUND_TINTS: Dictionary[String, String] = {"Grass": "2F80ED", "Sand": "E5484D"}
## 128 px canvas at import scale 0.5.
const TANK_TEXTURE_PX: float = 64.0


func _open_gallery() -> Control:
	var gallery: Control = auto_free((load(GALLERY) as PackedScene).instantiate())
	add_child(gallery)
	await await_idle_frame()
	return gallery


func _zoom_rig(gallery: Node, ground: String, rig_name: String) -> Node2D:
	return gallery.get_node("%s/ZoomRow/%s" % [ground, rig_name]) as Node2D


func _rig_rect(rig: Node2D) -> Rect2:
	var size: Vector2 = Vector2.ONE * TANK_TEXTURE_PX * rig.global_scale.x
	return Rect2(rig.global_position - size / 2.0, size)


## The text of the "## Feedback markers" section of STYLE.md.
func _marker_section() -> String:
	var text: String = FileAccess.get_file_as_string(STYLE_GUIDE)
	var start: int = text.find("## Feedback markers")
	assert_int(start).override_failure_message("no Feedback markers section").is_greater(-1)
	return text.substr(start, text.find("\n## ", start + 1) - start)


func _row(section: String, marker: String) -> String:
	for line: String in section.split("\n"):
		if line.begins_with("| %s |" % marker):
			return line
	return ""


func test_zoom_row_shows_the_light_tank_at_three_zooms_on_grass_and_sand() -> void:
	var gallery: Control = await _open_gallery()
	for ground: String in GROUND_TINTS:
		for rig_name: String in ZOOM_RIGS:
			var zoom: float = ZOOM_RIGS[rig_name]
			var rig: Node2D = _zoom_rig(gallery, ground, rig_name)
			assert_vector(rig.scale).is_equal(Vector2(zoom, zoom))
			var hull: Sprite2D = rig.get_node("Hull") as Sprite2D
			assert_str(hull.texture.resource_path).is_equal(HULL_SVG)
			assert_float(hull.texture.get_size().x).is_equal(TANK_TEXTURE_PX)
			var team: Sprite2D = rig.get_node("Team") as Sprite2D
			assert_bool(team.modulate.is_equal_approx(Color(GROUND_TINTS[ground]))).is_true()
			assert_object(rig.get_node("Turret")).is_not_null()


func test_gallery_has_five_rigs_per_team_two_at_scale_one_and_three_in_the_zoom_row() -> void:
	var gallery: Control = await _open_gallery()
	for group: StringName in [&"gallery_team_a", &"gallery_team_b"]:
		var rigs: Array[Node] = get_tree().get_nodes_in_group(group).filter(
			func(n: Node) -> bool: return gallery.is_ancestor_of(n)
		)
		assert_int(rigs.size()).is_equal(5)


func test_zoom_row_tanks_fit_their_half_and_clear_the_back_button_and_each_other() -> void:
	var gallery: Control = await _open_gallery()
	var back: Rect2 = (gallery.find_child("BackButton", true, false) as Control).get_global_rect()
	assert_vector((gallery.find_child("BackButton", true, false) as Control).size).is_equal(
		Vector2(120, 120)
	)
	for ground: String in GROUND_TINTS:
		var half: Rect2 = (gallery.get_node(ground) as Control).get_global_rect()
		var rects: Array[Rect2] = []
		for rig_name: String in ZOOM_RIGS:
			var rect: Rect2 = _rig_rect(_zoom_rig(gallery, ground, rig_name))
			assert_bool(half.encloses(rect)).override_failure_message(rig_name).is_true()
			assert_bool(back.intersects(rect)).override_failure_message(rig_name).is_false()
			for other: Rect2 in rects:
				assert_bool(other.intersects(rect)).override_failure_message(rig_name).is_false()
			rects.append(rect)
		# Tank sizes on screen: 0.75 x 64, 1.0 x 64 and 1.5 x 64 px.
		assert_float(rects[0].size.x).is_equal(48.0)
		assert_float(rects[1].size.x).is_equal(64.0)
		assert_float(rects[2].size.x).is_equal(96.0)


## The marker spec is the contract between art-director and touch-ux-dev: a changed number must
## change a test, not slip by.
func test_marker_spec_pins_shapes_sizes_colours_and_motion() -> void:
	var section: String = _marker_section()
	assert_str(section).contains("width + 2 dp").contains("#1C2127")
	assert_str(section).contains("200 ms").contains("`marker_ms` (600)")
	var ring: String = _row(section, "Own selection ring")
	assert_str(ring).contains("Circle").contains("0.05) x 64 world px, 18 dp)")
	assert_str(ring).contains("| 3 dp | #FFFFFF |")
	var flash: String = _row(section, "Enemy target flash")
	assert_str(flash).contains("Diamond").contains("1.3 x R").contains("| 3 dp | #E5484D |")
	assert_str(flash).contains("1.5 x size").contains("1.0 x in 150 ms")
	var chevrons: String = _row(section, "Attack-move marker")
	assert_str(chevrons).contains("Four chevrons").contains("(d + 7, -7), (d, 0), (d + 7, 7) dp")
	assert_str(chevrons).contains("d = 12 dp").contains("| 3 dp | #F5A524 |")
	assert_str(chevrons).contains("36 dp to 12 dp in 200 ms")
	var anchor: String = _row(section, "Long-press anchor")
	assert_str(anchor).contains("radius 32 dp").contains("#FFFFFF at 15%")
	assert_str(anchor).contains("| 3 dp | #FFFFFF |").contains("48 dp to 32 dp in 150 ms")
	var box: String = _row(section, "Selection box")
	assert_str(box).contains("inset by 1 dp").contains("#FFFFFF at 15%")
	assert_str(box).contains("| 2 dp | #FFFFFF |")
