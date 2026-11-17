extends GdUnitTestSuite
## The two ground carriers' art (plan row P291, STYLE.md "The ground carriers"): the Derrick
## League's Bunk Wagon (`fossil_bunk_wagon`) and the Lumen Accord's Linecar (`renew_linecar`). Each
## is a vehicle model with a hull in 16 directions, a cast shadow and an item card, no turret and
## no damage picture (a unit shows none). It pins the sheet's parts, the team share at zoom 1 (the
## rule asks for 8 to 12 % in the default view, a wider band in the other directions), a shadow
## that is one connected mark, and the silhouettes at 32 px in greyscale against its own faction's
## ground vehicles and the other carrier. That the bytes equal a fresh run is test_artgen.gd.

const MODEL: String = "res://assets/art/models/%s/%s.tres"
const Support: GDScript = preload("res://tests/art/building_picture_support.gd")
const IDS: Array[StringName] = [&"fossil_bunk_wagon", &"renew_linecar"]
const NAMES: Dictionary[StringName, String] = {
	&"fossil_bunk_wagon": "Bunk Wagon", &"renew_linecar": "Linecar"
}
## The ground vehicles each carrier must read apart from (its own faction's and the other carrier).
const OTHERS: Dictionary[StringName, Array] = {
	&"fossil_bunk_wagon":
	[&"light_tank", &"heavy_tank", &"artillery", &"harvester", &"renew_linecar"],
	&"renew_linecar":
	[&"renew_scout", &"renew_tank", &"renew_artillery", &"renew_tanker", &"fossil_bunk_wagon"],
}
const SHARE: Vector2 = Vector2(0.08, 0.12)
const SHARE_WIDE: Vector2 = Vector2(0.05, 0.16)
const MAX_OVERLAP: float = 0.85

var _index: IsoIndex = null


func before() -> void:
	_index = load(IsoIndex.PATH) as IsoIndex


func test_a_sheet_is_a_hull_in_16_directions_and_a_shadow_with_a_card() -> void:
	for id: StringName in IDS:
		var model: ArtModel = _model(id)
		assert_array(Array(model.problems())).override_failure_message(String(id)).is_empty()
		assert_str(String(model.category)).is_equal("veh")
		assert_int(model.footprint).is_equal(0)
		assert_bool(model.flies()).is_false()
		assert_bool(model.silhouette.contains("\n")).is_false()
		assert_str(model.silhouette).starts_with(NAMES[id] + ":")
		var sheet: IsoSheetDef = _index.sheet(id)
		assert_array(Array(sheet.parts)).override_failure_message(String(id)).is_equal(
			["hull", "shadow"]
		)
		assert_array(sheet.directions(&"hull")).is_equal(range(16))
		assert_array(sheet.directions(&"shadow")).is_equal(range(16))
		for part: StringName in [&"turret", &"head", &"anim", &"dmg1", &"dmg2", &"walk", &"idle"]:
			assert_bool(sheet.has_part(part)).override_failure_message(String(part)).is_false()
		assert_bool(sheet.flies()).is_false()
		assert_bool(sheet.icon.ends_with("item_%s.svg" % id)).is_true()
		assert_bool(FileAccess.file_exists(sheet.icon)).is_true()
		for dir: int in 16:
			assert_bool(FileAccess.file_exists(sheet.path(&"hull", dir))).is_true()
			assert_bool(FileAccess.file_exists(sheet.path(&"shadow", dir))).is_true()


func test_the_running_gear_the_name_and_the_emitters_agree() -> void:
	assert_str(String(_model(&"fossil_bunk_wagon").marks)).is_equal("tracks")
	assert_str(String(_model(&"renew_linecar").marks)).is_equal("wheels")
	for id: StringName in IDS:
		var def: UnitDef = load("res://data/units/%s.tres" % id) as UnitDef
		assert_str(def.display_name).is_equal(NAMES[id])
		var kinds: Array[StringName] = []
		for emitter: Array in _model(id).emitter_list():
			kinds.append(emitter[0])
		assert_array(kinds).override_failure_message(String(id)).is_equal(
			[&"exhaust", &"damage", &"hang"]
		)


func test_the_team_share_of_the_default_view_is_8_to_12_percent_at_zoom_1() -> void:
	for id: StringName in IDS:
		var share: float = _share(id, _model(id).default_dir())
		assert_float(share).override_failure_message("%s team share %.3f" % [id, share]).is_between(
			SHARE.x, SHARE.y
		)


func test_the_team_share_holds_in_every_direction_at_zoom_1() -> void:
	for id: StringName in IDS:
		for dir: int in 16:
			var share: float = _share(id, dir)
			(
				assert_float(share)
				. override_failure_message("%s d%02d: %.3f" % [id, dir, share])
				. is_between(SHARE_WIDE.x, SHARE_WIDE.y)
			)


func test_the_cast_shadow_is_one_connected_mark_in_every_direction() -> void:
	for id: StringName in IDS:
		var sheet: IsoSheetDef = _index.sheet(id)
		for dir: int in 16:
			var shadow: Image = Support.raster(
				FileAccess.get_file_as_string(sheet.path(&"shadow", dir)), 1.0
			)
			shadow.convert(Image.FORMAT_RGBA8)
			for y: int in shadow.get_height():
				for x: int in shadow.get_width():
					if shadow.get_pixel(x, y).a > 0.0:
						shadow.set_pixel(x, y, Color.BLACK)
			(
				assert_int(Support.pieces(shadow))
				. override_failure_message("%s d%02d" % [id, dir])
				. is_equal(1)
			)


func test_each_carrier_reads_apart_from_the_ground_vehicles_at_32_px_in_greyscale() -> void:
	for id: StringName in IDS:
		var mask: Image = Support.mask_32(_picture(id, _model(id).default_dir()))
		var ink: int = 0
		for y: int in 32:
			for x: int in 32:
				ink += int(mask.get_pixel(x, y).a > 0.5)
		assert_float(float(ink) / 1024.0).override_failure_message("%s fills" % id).is_greater(0.1)
		for other: StringName in OTHERS[id]:
			var rival: Image = Support.mask_32(_picture(other, _model(other).default_dir()))
			var overlap: float = Support.overlap(mask, rival)
			(
				assert_float(overlap)
				. override_failure_message("%s against %s: %.2f" % [id, other, overlap])
				. is_less(MAX_OVERLAP)
			)


func _model(id: StringName) -> ArtModel:
	var faction: String = "renew" if String(id).begins_with("renew") else "fossil"
	return load(MODEL % [faction, id]) as ArtModel


func _picture(id: StringName, dir: int) -> Image:
	var sheet: IsoSheetDef = _index.sheet(id)
	var picture: Image = Image.create_empty(
		Support.PAGE.x, Support.PAGE.y, false, Image.FORMAT_RGBA8
	)
	var hull: Image = Support.raster(
		FileAccess.get_file_as_string(sheet.path(&"hull", dir)), Support.SCALE
	)
	picture.blend_rect(
		hull,
		Rect2i(Vector2i.ZERO, hull.get_size()),
		Support.GROUND_POINT - Vector2i(Vector2(sheet.origin(&"hull")) * Support.SCALE)
	)
	return picture


func _share(id: StringName, dir: int) -> float:
	var faction: StringName = &"renew" if String(id).begins_with("renew") else &"fossil"
	return Support.team_share(_picture(id, dir), faction)
