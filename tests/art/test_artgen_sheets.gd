extends GdUnitTestSuite
## The sheets of the generator (plan row P99b, ADR 0023 sections 2 and 5): `assets/art/iso/
## index.tres` lists the `IsoSheetDef` of every art id, and each sheet says what the frames say
## (parts, frame counts, canvases, anchors, the turret's mount for each hull frame, the three
## lifts), so the per-match atlas bake (P113) and the rigs (P114) can build on it without opening a
## frame. That the committed files equal a fresh run is test_artgen.gd; what a sheet must say is
## pinned here.

const MOUNT_TOLERANCE: Vector2 = Vector2.ONE * 0.06  ## Written with one decimal, stored as floats.

var _index: IsoIndex = null


func before() -> void:
	_index = load(IsoIndex.PATH) as IsoIndex


func test_the_index_lists_every_type_of_both_factions_once_sorted_by_art_id() -> void:
	assert_object(_index).is_not_null()
	var found: Array[String] = []
	for sheet: IsoSheetDef in _index.sheets:
		found.append(String(sheet.art_id))
	var want: Array[String] = []
	for path: String in ArtGen.model_paths():
		want.append(String((load(path) as ArtModel).art_id))
	want.sort()
	assert_int(want.size()).is_equal(28)
	assert_array(found).is_equal(want)
	assert_object(_index.sheet(&"heavy_tank")).is_same(_index.sheets[found.find("heavy_tank")])
	assert_object(_index.sheet(&"no_such_type")).is_null()


func test_every_sheet_says_what_the_frames_say() -> void:
	for path: String in ArtGen.model_paths():
		var model: ArtModel = load(path) as ArtModel
		var sheet: IsoSheetDef = _index.sheet(model.art_id)
		assert_object(sheet).override_failure_message(path).is_not_null()
		assert_str(sheet.faction).is_equal(model.faction)
		assert_str(sheet.category).is_equal(model.category)
		assert_int(sheet.footprint).is_equal(model.footprint)
		var names: Array[String] = []
		for part: StringName in model.frame_parts():
			names.append(String(part))
		assert_array(Array(sheet.parts)).override_failure_message(path).is_equal(names)
		var layouts: Dictionary[StringName, ArtGen.Layout] = ArtGen.layouts(model)
		for part: StringName in model.frame_parts():
			assert_vector(Vector2(sheet.frame_size(part))).is_equal(Vector2(layouts[part].size))
			assert_vector(Vector2(sheet.anchor(part))).is_equal(Vector2(layouts[part].anchor))
			assert_vector(Vector2(sheet.origin(part))).is_equal(Vector2(layouts[part].origin))
			assert_array(Array(sheet.directions(part))).is_equal(model.directions(part))
			for dir: int in model.directions(part):
				# The frame is on disk under the sheet's path, on the canvas the sheet gives.
				var root: String = (
					FileAccess.get_file_as_string(sheet.path(part, dir)).split("\n")[1]
				)
				assert_str(root).override_failure_message(sheet.path(part, dir)).contains(
					'width="%d" height="%d"' % [sheet.frame_size(part).x, sheet.frame_size(part).y]
				)
		assert_str(sheet.icon).is_equal(ArtGen.icon_path(model))
		assert_bool(FileAccess.file_exists(sheet.icon)).is_true()


func test_a_sheet_gives_the_mount_of_a_turret_or_head_for_every_hull_frame() -> void:
	for path: String in ArtGen.model_paths():
		var model: ArtModel = load(path) as ArtModel
		var sheet: IsoSheetDef = _index.sheet(model.art_id)
		var turning: bool = model.parts().has(&"turret") or model.parts().has(&"head")
		var hull: Array[int] = model.directions(&"hull")
		assert_int(sheet.mounts.size()).override_failure_message(path).is_equal(
			hull.size() if turning else 0
		)
		if turning:
			for dir: int in hull:
				var at: int = 6 if dir < 0 else dir
				assert_vector(sheet.mount(at)).override_failure_message(path).is_equal_approx(
					ArtGen.mount_px(model, at), MOUNT_TOLERANCE
				)
	# A vehicle has 16, a building with a head one, the squads and the tanker none.
	assert_int(_index.sheet(&"heavy_tank").mounts.size()).is_equal(16)
	assert_int(_index.sheet(&"defence_turret").mounts.size()).is_equal(1)
	assert_int(_index.sheet(&"rifle_squad").mounts.size()).is_equal(0)
	assert_vector(_index.sheet(&"harvester").mount(6)).is_equal(Vector2.ZERO)


func test_the_lifts_are_world_px_that_lie_inside_the_frame_and_the_bar_clears_most_poses() -> void:
	for path: String in ArtGen.model_paths():
		var model: ArtModel = load(path) as ArtModel
		var sheet: IsoSheetDef = _index.sheet(model.art_id)
		var layouts: Dictionary[StringName, ArtGen.Layout] = ArtGen.layouts(model)
		# The highest point of any pose above the ground point, in 2x px, and the mean of the
		# hulls alone (the turret only raises a pose).
		var highest: float = layouts[&"hull"].origin.y
		var hull_tops: float = 0.0
		for dir: int in model.directions(&"hull"):
			var turned: float = ArtGen.yaw(dir) if dir >= 0 else 0.0
			var polys: Array[ArtRender.Poly] = ArtRender.render(
				model.primitives(&"hull"), turned, model.faction
			)
			hull_tops -= ArtRender.bounds(polys).position.y
			for part: StringName in [&"turret", &"head"]:
				if layouts.has(part):
					var at: Vector2 = ArtGen.mount_px(model, 6 if dir < 0 else dir)
					highest = maxf(highest, layouts[part].anchor.y - at.y)
		hull_tops /= model.directions(&"hull").size()
		assert_float(sheet.bar_lift_px * 2.0).override_failure_message(path).is_less_equal(
			highest + 2.0
		)
		assert_float(sheet.bar_lift_px * 2.0).override_failure_message(path).is_greater_equal(
			hull_tops - 1.0
		)
		assert_int(sheet.pick_lift_px).is_equal(roundi(sheet.bar_lift_px / 2.0))
		if model.category != &"bld":
			# World px at zoom 1: a figure is 22, a vehicle 27 to 39 (the 2x number would be twice).
			assert_int(sheet.bar_lift_px).override_failure_message(path).is_between(14, 45)


func test_the_muzzle_lift_is_where_the_barrel_ends_and_zero_for_a_building_without_a_head() -> void:
	for path: String in ArtGen.model_paths():
		var model: ArtModel = load(path) as ArtModel
		var sheet: IsoSheetDef = _index.sheet(model.art_id)
		var armed: bool = model.category != &"bld" or model.parts().has(&"head")
		assert_int(sheet.muzzle_lift_px).override_failure_message(path).is_equal(
			roundi(model.muzzle_z() * ArtRender.Z_PX / 2.0)
		)
		assert_bool(sheet.muzzle_lift_px > 0).override_failure_message(path).is_equal(armed)
		assert_int(sheet.muzzle_lift_px).is_less(sheet.bar_lift_px)


func test_the_muzzle_is_the_centre_height_of_the_primitive_that_reaches_farthest_forward() -> void:
	var tank: ArtModel = _model(
		&"veh",
		[
			"box hull steel 0 0 0 1 0.5 0.3",
			"prism turret iron 0 0 0 0.4 0.4 0.2",
			"box turret iron 0.6 0 0.05 0.5 0.06 0.06",
		]
	)
	tank.mount = Vector3(0.0, 0.0, 0.3)
	# The barrel ends at x 0.85, its centre is 0.08 above the turret's origin, which is 0.3 up.
	assert_float(tank.muzzle_z()).is_equal_approx(0.38, 1e-6)
	var squad: ArtModel = _model(
		&"inf", ["box hull olive 0 0 0 0.2 0.2 0.3", "box hull iron 0.3 0 0.2 0.3 0.03 0.03"]
	)
	assert_float(squad.muzzle_z()).is_equal_approx(0.215, 1e-6)
	var wall: ArtModel = _model(&"bld", ["box hull concrete 0 0 0 1 1 1"])
	wall.footprint = 1
	assert_float(wall.muzzle_z()).is_equal(0.0)
	var gun: ArtModel = _model(
		&"bld", ["box hull concrete 0 0 0 1 1 1", "box head steel 0.4 0 0 0.6 0.1 0.1"]
	)
	gun.footprint = 1
	gun.mount = Vector3(0.0, 0.0, 1.2)
	assert_float(gun.muzzle_z()).is_equal_approx(1.25, 1e-6)


func test_a_sheet_answers_for_its_parts_and_a_missing_part_has_no_size() -> void:
	var sheet: IsoSheetDef = IsoSheetDef.new()
	sheet.art_id = &"yard"
	sheet.faction = &"fossil"
	sheet.category = &"bld"
	sheet.footprint = 2
	sheet.parts = PackedStringArray(["hull", "shadow"])
	sheet.counts = PackedInt32Array([1, 1])
	sheet.sizes = PackedInt32Array([256, 300, 280, 140])
	sheet.anchors = PackedInt32Array([128, 150, 128, 0])
	assert_str(sheet.path(&"hull", -1)).is_equal("res://assets/art/iso/fossil/bld/yard_hull.svg")
	assert_array(Array(sheet.directions(&"hull"))).is_equal([-1])
	assert_vector(Vector2(sheet.origin(&"hull"))).is_equal(Vector2(128, 214))
	assert_vector(Vector2(sheet.origin(&"shadow"))).is_equal(Vector2(128, 64))
	assert_vector(Vector2(sheet.frame_size(&"shadow"))).is_equal(Vector2(280, 140))
	assert_bool(sheet.has_part(&"head")).is_false()
	assert_vector(Vector2(sheet.frame_size(&"head"))).is_equal(Vector2.ZERO)
	assert_array(Array(sheet.directions(&"head"))).is_empty()
	sheet.counts = PackedInt32Array([8, 16])
	assert_array(Array(sheet.directions(&"hull"))).is_equal([0, 2, 4, 6, 8, 10, 12, 14])
	assert_int(sheet.directions(&"shadow").size()).is_equal(16)
	assert_str(sheet.path(&"shadow", 10)).ends_with("/yard_shadow_d10.svg")
	sheet.mounts = PackedVector2Array([Vector2(1, 2)])
	assert_vector(sheet.mount(13)).is_equal(Vector2(1, 2))
	sheet.mounts = PackedVector2Array([Vector2(0, 0), Vector2(5, 5), Vector2(7, 7), Vector2.ONE])
	assert_vector(sheet.mount(5)).is_equal(Vector2(5, 5))  # Four frames: 5 x 4 / 16 is 1.


func test_the_text_of_a_sheet_loads_as_that_sheet() -> void:
	var sheet: IsoSheetDef = _index.sheet(&"light_tank")
	var access: DirAccess = DirAccess.create_temp("sheet_text_")
	var file: String = access.get_current_dir().path_join("sheet.tres")
	var written: FileAccess = FileAccess.open(file, FileAccess.WRITE)
	written.store_string(ArtSheet.text(sheet))
	written.close()
	var loaded: IsoSheetDef = ResourceLoader.load(file, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_object(loaded).is_not_null()
	assert_str(ArtSheet.text(loaded)).is_equal(ArtSheet.text(sheet))
	assert_array(Array(loaded.sizes)).is_equal(Array(sheet.sizes))
	assert_int(loaded.bar_lift_px).is_equal(sheet.bar_lift_px)
	assert_str(ArtSheet.text(sheet)).starts_with(ArtSheet.MARKER)


func test_the_index_text_is_sorted_by_art_id_whatever_the_order_it_is_given() -> void:
	var models: Array[ArtModel] = [_model(&"veh", ["box hull steel 0 0 0 1 1 1"])]
	models.append(_model(&"veh", ["box hull steel 0 0 0 1 1 1"]))
	models[0].art_id = &"zeta"
	models[1].art_id = &"alpha"
	var text: String = ArtSheet.index_text(models)
	assert_int(text.find("s_alpha")).is_less(text.find("s_zeta"))
	models.reverse()
	assert_str(ArtSheet.index_text(models)).is_equal(text)
	assert_str(text).contains('sheets = Array[ExtResource("1_sheet")]([ExtResource("s_alpha")')


func test_stale_names_the_files_that_are_missing_or_differ_and_only_those() -> void:
	var fresh: String = FileAccess.get_file_as_string(IsoIndex.PATH)
	var files: Dictionary[String, String] = {
		IsoIndex.PATH: fresh,
		"res://assets/art/iso/icons/item_heavy_tank.svg": "changed",
		"res://assets/art/iso/icons/item_not_there.svg": "new",
	}
	assert_array(ArtGen.stale(files)).is_equal(
		[
			"res://assets/art/iso/icons/item_heavy_tank.svg",
			"res://assets/art/iso/icons/item_not_there.svg"
		]
	)


func _model(category: StringName, lines: Array[String]) -> ArtModel:
	var model: ArtModel = ArtModel.new()
	model.art_id = &"x"
	model.faction = &"fossil"
	model.category = category
	model.prims = PackedStringArray(lines)
	return model
