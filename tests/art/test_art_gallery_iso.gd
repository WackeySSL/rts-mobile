extends GdUnitTestSuite
## The Iso page of the art gallery (plan row P99, ADR 0023 section 5): it steps through the
## generated blockouts of both factions, a type at a time. Every direction of the type is a rig in
## each team colour on grass and on sand, its default view comes at the three camera zooms, the
## frames carry the triad of the row they are in, and everything stays on its ground at the base
## size of a phone held the wide way. The generator is in test_artgen.gd.

const GALLERY_PATH: String = "res://scenes/dev/art_gallery.tscn"
const ISO_PAGE: int = 4
const ROWS: Array[String] = ["Signal", "Arktisk"]
const ZOOM_RIGS: Array[String] = ["Zoom75", "Zoom100", "Zoom150"]
const SIGNAL_KEYS: Array[String] = ["#FF9446", "#E8681F", "#B04B12"]
const ARKTISK_KEYS: Array[String] = ["#62D6EE", "#1FA6C8", "#137C99"]
const BASE: Vector2 = Vector2(1280, 720)


## A gallery switches `SceneTree.quit_on_go_back` off while it is open and restores what it found,
## so galleries alive together restore it in the wrong order (see test_art_assets.gd).
func before_test() -> void:
	_assert_quit_on_go_back_restored()


func after() -> void:
	_assert_quit_on_go_back_restored()


func test_the_iso_page_is_built_when_it_is_first_shown_and_names_the_first_type() -> void:
	var gallery: Control = await _open_gallery()
	var page: Control = gallery.get_node("IsoPage")
	assert_bool(page.visible).is_false()
	assert_int(page.get_child_count()).is_equal(0)
	_show(gallery)
	assert_bool(page.visible).is_true()
	assert_str((gallery.get_node("%PageButton") as Button).text).is_equal("Iso")
	var paths: Array[String] = ArtGen.model_paths()
	assert_str((page.get_node("Title") as Label).text).is_equal(
		"1 / %d  Derrick League: artillery (veh)" % paths.size()
	)
	for ground: String in ["Grass", "Sand"]:
		var names: Array[StringName] = []
		for row: Node in page.get_node("Scroll/Content/" + ground).get_children():
			names.append(row.name)
		# The artillery is a vehicle: the Damage rows (P160) come after its two triads.
		assert_array(names).is_equal([&"Signal", &"Arktisk", &"Damage"])


func test_every_type_shows_each_direction_in_both_triads_and_its_default_view_at_three_zooms(
) -> void:
	var gallery: Control = await _open_gallery()
	var page: Control = _show(gallery)
	var seen: Array[String] = []
	for path: String in ArtGen.model_paths():
		var model: ArtModel = load(path) as ArtModel
		seen.append(String(model.art_id))
		assert_str((page.get_node("Title") as Label).text).contains(String(model.art_id))
		var turning: StringName = &"head" if model.parts().has(&"head") else &"hull"
		var dirs: Array[int] = []
		if model.category != &"bld" or turning == &"head":
			dirs = model.directions(turning)
		for ground: String in ["Grass", "Sand"]:
			for row_name: String in ROWS:
				var row: Node = page.get_node("Scroll/Content/%s/%s" % [ground, row_name])
				var rigs: Array[String] = []
				for node: Node in row.get_children():
					if node is Node2D:
						rigs.append(String(node.name))
				var want: Array[String] = []
				for dir: int in dirs:
					want.append("Dir%02d" % dir)
				want.append_array(ZOOM_RIGS)
				(
					assert_array(rigs)
					. override_failure_message("%s %s %s" % [path, ground, row_name])
					. is_equal(want)
				)
		page.get_node("Next").pressed.emit()
		await await_idle_frame()
	assert_int(seen.size()).is_equal(28)
	# The last step went round to the first type again.
	assert_str((page.get_node("Title") as Label).text).contains("artillery")
	page.get_node("Previous").pressed.emit()
	await await_idle_frame()
	assert_str((page.get_node("Title") as Label).text).contains("renew_tanker")


func test_a_vehicle_shows_its_16_directions_at_stage_1_and_2_with_the_neutral_overlays() -> void:
	var gallery: Control = await _open_gallery()
	var page: Control = _show(gallery)
	var sheet: IsoSheetDef = IsoAtlas.load_neutral_sheet(IsoAtlas.NEUTRAL_SHEET)
	var checked: int = 0
	for path: String in ArtGen.model_paths():
		var model: ArtModel = load(path) as ArtModel
		for ground: String in ["Grass", "Sand"]:
			var row: Node = page.get_node("Scroll/Content/%s" % ground).get_node_or_null("Damage")
			if model.category != &"veh":
				assert_object(row).override_failure_message(path).is_null()
				continue
			assert_object(row).override_failure_message(path).is_not_null()
			var committed: IsoSheetDef = load(
				"res://assets/art/iso/%s/veh/%s_sheet.tres" % [model.faction, model.art_id]
			)
			var damage_at: int = committed.emitters.find("damage")
			var hang_at: int = committed.emitters.find("hang")
			for stage: int in [1, 2]:
				for dir: int in 16:
					var rig: Node2D = row.get_node("Stage%dDir%02d" % [stage, dir])
					var hull: Sprite2D = rig.get_node("Hull")
					var scar: Sprite2D = rig.get_node("Scar")
					var scale: Vector2 = Vector2.ONE * model.scar_milli / 1000.0
					var label: String = "%s s%d d%02d" % [model.art_id, stage, dir]
					# Where: the committed sheet's points, at half (zoom 1 of the 2x art).
					assert_vector(scar.position).override_failure_message(label).is_equal_approx(
						committed.emitter_point(damage_at, dir) * 0.5, Vector2.ONE * 0.06
					)
					assert_vector(scar.scale).is_equal(scale)
					assert_int(scar.z_index).is_equal(hull.z_index)
					assert_bool(scar.flip_h).is_false()
					# Which: the frame of the part, drawn as the sheet's file says.
					var part: StringName = &"scar1" if stage == 1 else &"scar2"
					_assert_frame(scar, sheet.path(part, -1, dir % 2), label)
					# Order: over the hull, under the turret.
					assert_bool(rig.has_node("Loose")).is_equal(stage == 2)
					assert_int(scar.get_index()).is_greater(hull.get_index())
					if model.parts().has(&"turret"):
						assert_int(scar.get_index()).is_less(rig.get_node("Turret").get_index())
					if stage == 2:
						var loose: Sprite2D = rig.get_node("Loose")
						var hang: Vector2 = committed.emitter_point(hang_at, dir)
						(
							assert_vector(loose.position)
							. override_failure_message(label)
							. is_equal_approx(hang * 0.5, Vector2.ONE * 0.06)
						)
						assert_vector(loose.scale).is_equal(scale)
						assert_bool(loose.flip_h).is_equal(hang.x < 0.0)
						assert_int(loose.z_index).is_equal(hull.z_index)
						assert_int(loose.get_index()).is_greater(hull.get_index())
						if model.parts().has(&"turret"):
							assert_int(loose.get_index()).is_less(
								rig.get_node("Turret").get_index()
							)
						# The bolt is at the anchor, mirrored or not.
						(
							assert_bool(loose.is_pixel_opaque(Vector2.ZERO))
							. override_failure_message(label)
							. is_true()
						)
						var look: int = dir % 2 + (0 if model.marks == &"tracks" else 2)
						_assert_frame(loose, sheet.path(&"loose", -1, look), label)
						checked += 1
		page.get_node("Next").pressed.emit()
		await await_idle_frame()
	assert_int(checked).is_equal(8 * 16 * 2)
	assert_object(sheet).is_not_null()


func test_a_turret_sits_at_its_mount_and_a_frame_carries_the_triad_of_its_row() -> void:
	var gallery: Control = await _open_gallery()
	var page: Control = _show(gallery)
	# The first type is the Derrick League's artillery; its key triad is Signal.
	var model: ArtModel = load(ArtGen.model_paths()[0]) as ArtModel
	assert_str(model.art_id).is_equal("artillery")
	var rig: Node2D = page.get_node("Scroll/Content/Grass/Signal/Dir06")
	var turret: Sprite2D = rig.get_node("Turret")
	var factor: float = 0.5
	assert_vector(turret.position).is_equal_approx(
		ArtGen.mount_px(model, 6) * factor, Vector2.ONE * 1e-3
	)
	var layouts: Dictionary[StringName, ArtGen.Layout] = ArtGen.layouts(model)
	assert_vector(turret.offset).is_equal_approx(
		-Vector2(layouts[&"turret"].origin) * factor, Vector2.ONE * 1e-3
	)
	var signal_hull: Image = (rig.get_node("Hull") as Sprite2D).texture.get_image()
	var arktisk: Node2D = page.get_node("Scroll/Content/Grass/Arktisk/Dir06")
	var arktisk_hull: Image = (arktisk.get_node("Hull") as Sprite2D).texture.get_image()
	# The mid tone is the left face of the team band; its top is a thin ledge that a texture at
	# gallery size blurs into the edge.
	assert_bool(_has_colour(signal_hull, SIGNAL_KEYS[1])).is_true()
	assert_bool(_has_colour(signal_hull, ARKTISK_KEYS[1])).is_false()
	assert_bool(_has_colour(arktisk_hull, ARKTISK_KEYS[1])).is_true()
	assert_bool(_has_colour(arktisk_hull, SIGNAL_KEYS[1])).is_false()
	# Grass and sand show the same frame: one texture.
	var sand_rig: Node2D = page.get_node("Scroll/Content/Sand/Signal/Dir06")
	assert_object((sand_rig.get_node("Hull") as Sprite2D).texture).is_same(
		(rig.get_node("Hull") as Sprite2D).texture
	)


func test_everything_stays_on_its_ground_at_the_base_size_and_under_the_two_corner_buttons(
) -> void:
	var gallery: Control = await _open_gallery(BASE)
	var page: Control = _show(gallery)
	await await_idle_frame()
	var corners: Array[Rect2] = [
		(gallery.get_node("%BackButton") as Control).get_global_rect(),
		(gallery.get_node("%PageButton") as Control).get_global_rect(),
	]
	for button: String in ["Previous", "Next"]:
		var box: Rect2 = (page.get_node(button) as Control).get_global_rect()
		assert_vector(box.size).is_greater_equal(Vector2(120, 120))
		for corner: Rect2 in corners:
			assert_bool(box.intersects(corner)).override_failure_message(button).is_false()
	for path: String in ArtGen.model_paths():
		var content: Control = page.get_node("Scroll/Content")
		for ground_name: String in ["Grass", "Sand"]:
			var ground: Control = content.get_node(ground_name)
			var field: Rect2 = ground.get_global_rect()
			for sprite: Node in ground.find_children("*", "Sprite2D", true, false):
				var item: Sprite2D = sprite as Sprite2D
				var at: Vector2 = item.global_position + item.offset
				var box: Rect2 = Rect2(at, item.texture.get_size())
				(
					assert_float(box.position.x)
					. override_failure_message(
						"%s %s %s" % [path, ground_name, item.get_parent().name]
					)
					. is_greater_equal(field.position.x)
				)
				(
					assert_float(box.end.x)
					. override_failure_message(
						"%s %s %s" % [path, ground_name, item.get_parent().name]
					)
					. is_less_equal(field.end.x)
				)
		assert_float(content.custom_minimum_size.y).is_greater(300.0)
		page.get_node("Next").pressed.emit()
		await await_idle_frame()


func test_a_shadow_lies_under_every_rig_and_a_units_default_view_has_its_ellipse_and_its_card(
) -> void:
	var gallery: Control = await _open_gallery()
	var page: Control = _show(gallery)
	# The first type is the Derrick League's artillery, the second its barracks.
	for index: int in 2:
		var model: ArtModel = load(ArtGen.model_paths()[index]) as ArtModel
		var layouts: Dictionary[StringName, ArtGen.Layout] = ArtGen.layouts(model)
		assert_str((page.get_node("Icon") as TextureRect).texture.resource_path).is_equal(
			ArtGen.icon_path(model)
		)
		for ground: String in ["Grass", "Sand"]:
			for row_name: String in ROWS:
				var row: Node = page.get_node("Scroll/Content/%s/%s" % [ground, row_name])
				for node: Node in row.get_children():
					if not node is Node2D:
						continue
					var shadow: Sprite2D = node.get_node("Shadow") as Sprite2D
					var hull: Sprite2D = node.get_node("Hull") as Sprite2D
					assert_int(shadow.z_index).is_less(hull.z_index)
					var zoom: float = 1.0
					if node.name.begins_with("Zoom"):
						zoom = node.name.trim_prefix("Zoom").to_int() / 100.0
					assert_vector(shadow.offset).is_equal_approx(
						-Vector2(layouts[&"shadow"].origin) * 0.5 * zoom, Vector2.ONE * 1e-3
					)
					# The ring is the default view's, a unit's, on the ground between the two.
					var ringed: bool = node.name.begins_with("Zoom") and model.category != &"bld"
					assert_bool(node.has_node("Ring")).override_failure_message(node.name).is_equal(
						ringed
					)
					if ringed:
						var ring: Sprite2D = node.get_node("Ring") as Sprite2D
						assert_str(ring.texture.resource_path).ends_with("ui/selection_ellipse.svg")
						assert_int(ring.z_index).is_between(shadow.z_index + 1, hull.z_index - 1)
						# A 600 milli radius: 600 x 32 x sqrt 2 / 1000 px along its long axis.
						assert_float(ring.scale.x * 72.0).is_equal_approx(
							0.6 * 32.0 * sqrt(2.0) * zoom, 1e-3
						)
		page.get_node("Next").pressed.emit()
		await await_idle_frame()


## The Iso page lists the models and loads them at run time and uses the generator's global classes,
## and the dev menu (so the gallery) is on in the web preview and in the debug APK: no export preset
## may leave out `tools/` or `assets/art/models/` (or the frames, shadows and cards the page reads)
## while it does. P99b's `index.tres` and its sheets exist, and the per-match bake (P113) reads
## them in a match, which needs `tools/artgen/IsoSheetDef.gd` and `IsoIndex.gd` too; the page stops
## reading the models when `IsoAtlas` replaces its rasterising, and the exclusion of `tools/` and
## `assets/art/models/` waits for that, or for a preset that the dev menu is off in.
func test_no_export_preset_leaves_out_what_the_iso_page_reads() -> void:
	var presets: ConfigFile = ConfigFile.new()
	assert_int(presets.load("res://export_presets.cfg")).is_equal(OK)
	var needed: Array[String] = [
		"tools/artgen/ArtGen.gd",
		"tools/artgen/IsoSheetDef.gd",
		"tools/artgen/IsoIndex.gd",
		"assets/art/models/fossil/headquarters.tres",
		"assets/art/iso/fossil/bld/headquarters_hull.svg",
		"assets/art/iso/fossil/bld/headquarters_shadow.svg",
		"assets/art/iso/fossil/bld/headquarters_sheet.tres",
		"assets/art/iso/index.tres",
		"assets/art/iso/icons/item_headquarters.svg",
		"assets/art/svg/ui/selection_ellipse.svg",
		"assets/art/svg/damage/damage_sheet.tres",
		"assets/art/svg/damage/damage_scar1_f0.svg",
		"assets/art/svg/damage/damage_loose_f3.svg",
	]
	var filtered: int = 0
	for section: String in presets.get_sections():
		if not presets.has_section_key(section, "exclude_filter"):
			continue
		filtered += 1
		var filters: PackedStringArray = String(presets.get_value(section, "exclude_filter")).split(
			",", false
		)
		for filter: String in filters:
			for path: String in needed:
				(
					assert_bool(path.matchn(filter.strip_edges()))
					. override_failure_message(
						"%s: exclude_filter '%s' leaves out %s" % [section, filter, path]
					)
					. is_false()
				)
	assert_int(filtered).is_greater(0)


## `sprite` shows the SVG at `path`, rasterised at half scale like the gallery does.
func _assert_frame(sprite: Sprite2D, path: String, label: String) -> void:
	var want: Image = Image.new()
	want.load_svg_from_string(FileAccess.get_file_as_string(path), 0.5)
	var got: Image = sprite.texture.get_image()
	assert_vector(got.get_size()).override_failure_message(label).is_equal(want.get_size())
	want.convert(got.get_format())
	(
		assert_bool(got.get_data() == want.get_data())
		. override_failure_message("%s: not the frame %s" % [label, path])
		. is_true()
	)


func _open_gallery(base_size: Vector2 = BASE) -> Control:
	var gallery: Control = auto_free((load(GALLERY_PATH) as PackedScene).instantiate())
	var parent: Control = auto_free(Control.new())
	parent.size = base_size
	add_child(parent)
	parent.add_child(gallery)
	await await_idle_frame()
	return gallery


func _show(gallery: Control) -> Control:
	for step: int in ISO_PAGE:
		gallery.get_node("%PageButton").pressed.emit()
	return gallery.get_node("IsoPage")


func _has_colour(image: Image, hex: String) -> bool:
	var want: Color = Color(hex)
	for y: int in image.get_height():
		for x: int in image.get_width():
			var pixel: Color = image.get_pixel(x, y)
			if (
				pixel.a > 0.95
				and absf(pixel.r - want.r) + absf(pixel.g - want.g) + absf(pixel.b - want.b) < 0.03
			):
				return true
	return false


func _assert_quit_on_go_back_restored() -> void:
	var restored: bool = get_tree().quit_on_go_back
	assert_bool(restored).override_failure_message("quit_on_go_back leaked").is_true()
