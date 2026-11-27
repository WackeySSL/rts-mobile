extends GdUnitTestSuite
## The two medic squads' art (plan row P280, STYLE.md "The medic squads"): the Derrick League's
## Patchers (`fossil_patchers`) and the Lumen Accord's Menders (`renew_menders`). Each is an `inf`
## model of two figures with a hull in 8 directions, a walk of 4 frames, an idle of 2 and a cast
## shadow, and an item card. It pins the sheet's parts and frames, the stride of the walk, the team
## share at zoom 1 (30 to 65 % of the key band in every frame of the default view, 25 to 75 % in
## the other directions, ADR 0050 amendment A3), a shadow that is one connected mark, the two
## figures, the colour of the kit mark, and the silhouettes at 32 px in greyscale against the four
## squads. That the bytes equal a fresh run is test_artgen.gd.

const MODEL: String = "res://assets/art/models/%s/%s.tres"
const Support: GDScript = preload("res://tests/art/building_picture_support.gd")
const IDS: Array[StringName] = [&"fossil_patchers", &"renew_menders"]
const NAMES: Dictionary[StringName, String] = {
	&"fossil_patchers": "Patchers", &"renew_menders": "Menders"
}
## The squads each medic must read apart from: its own faction's two and the other faction's two.
const OTHERS: Array[StringName] = [
	&"rifle_squad",
	&"rocket_squad",
	&"renew_rifle",
	&"renew_rocket",
	&"fossil_patchers",
	&"renew_menders"
]
const MAX_OVERLAP: float = 0.85
const STRIDE: Dictionary[StringName, int] = {&"fossil_patchers": 352, &"renew_menders": 376}
## The kit marks of ADR 0037 section 6: the League's is the team band, the Accord's a mint ring.
const MINT: Array[String] = ["#A8F5B0"]
## Never a red cross, crescent or crystal: no red or pink fill in any frame of either model.
const RED_HUE: float = 20.0

var _index: IsoIndex = null


func before() -> void:
	_index = load(IsoIndex.PATH) as IsoIndex


func test_a_sheet_is_a_hull_a_walk_an_idle_and_a_shadow_in_8_directions_with_a_card() -> void:
	for id: StringName in IDS:
		var model: ArtModel = _model(id)
		assert_array(Array(model.problems())).override_failure_message(String(id)).is_empty()
		assert_str(String(model.category)).is_equal("inf")
		assert_int(model.footprint).is_equal(0)
		assert_bool(model.flies()).is_false()
		assert_bool(model.silhouette.contains("\n")).is_false()
		assert_str(model.silhouette).starts_with(NAMES[id] + ":")
		var sheet: IsoSheetDef = _index.sheet(id)
		assert_array(Array(sheet.parts)).override_failure_message(String(id)).is_equal(
			["hull", "walk", "idle", "shadow"]
		)
		assert_array(Array(sheet.frames)).is_equal([1, 4, 2, 1])
		assert_int(sheet.stride_milli).is_equal(STRIDE[id])
		for part: StringName in [&"hull", &"walk", &"idle", &"shadow"]:
			assert_array(sheet.directions(part)).is_equal([0, 2, 4, 6, 8, 10, 12, 14])
		for part: StringName in [&"turret", &"head", &"anim", &"dmg1", &"dmg2"]:
			assert_bool(sheet.has_part(part)).override_failure_message(String(part)).is_false()
		assert_bool(sheet.icon.ends_with("item_%s.svg" % id)).is_true()
		assert_bool(FileAccess.file_exists(sheet.icon)).is_true()
		for dir: int in range(0, 16, 2):
			assert_bool(FileAccess.file_exists(sheet.path(&"hull", dir))).is_true()
			assert_bool(FileAccess.file_exists(sheet.path(&"shadow", dir))).is_true()
			for frame: int in 4:
				assert_bool(FileAccess.file_exists(sheet.path(&"walk", dir, frame))).is_true()
			for frame: int in 2:
				assert_bool(FileAccess.file_exists(sheet.path(&"idle", dir, frame))).is_true()


func test_a_squad_is_two_figures_and_the_walk_cadence_is_in_the_pinned_band() -> void:
	for id: StringName in IDS:
		var feet: Array[Vector2] = []
		for prim: ArtPrim in _model(id).primitives(&"hull"):
			if is_zero_approx(prim.z0):
				feet.append(prim.centre)
		assert_int(feet.size()).override_failure_message(String(id)).is_equal(4)
		var groups: Dictionary[StringName, bool] = {}
		for prim: ArtPrim in _model(id).primitives(&"hull"):
			groups[String(prim.group).split("_")[0] as StringName] = true
		(
			assert_array(groups.keys())
			. override_failure_message(String(id))
			. contains_exactly_in_any_order([&"a", &"b"])
		)
		var def: UnitDef = load("res://data/units/%s.tres" % id) as UnitDef
		assert_str(def.display_name).is_equal(NAMES[id])
		var cycles: float = float(def.speed) * 15.0 / float(STRIDE[id])
		assert_float(cycles).override_failure_message("%s %.2f" % [id, cycles]).is_between(1.5, 3.5)


func test_the_team_share_of_the_default_view_is_30_to_65_percent_in_every_frame() -> void:
	for id: StringName in IDS:
		var dir: int = _model(id).default_dir()
		for frame: Array in _frames():
			var share: float = _share(id, dir, frame[0], frame[1])
			(
				assert_float(share)
				. override_failure_message(
					"%s d%02d %s%d: %.3f" % [id, dir, frame[0], frame[1], share]
				)
				. is_between(Support.TEAM_BAND.x, Support.TEAM_BAND.y)
			)


func test_the_team_share_holds_in_every_direction_and_frame() -> void:
	for id: StringName in IDS:
		for dir: int in range(0, 16, 2):
			for frame: Array in _frames():
				var share: float = _share(id, dir, frame[0], frame[1])
				(
					assert_float(share)
					. override_failure_message(
						"%s d%02d %s%d: %.3f" % [id, dir, frame[0], frame[1], share]
					)
					. is_between(Support.TEAM_BAND_DIRS.x, Support.TEAM_BAND_DIRS.y)
				)


func test_the_kit_mark_is_the_factions_own_and_no_frame_has_a_red_cross() -> void:
	# The League's kit mark is its team band (orange) and the lid; the Accord's a mint ring.
	var mint: int = 0
	for prim: ArtPrim in _model(&"renew_menders").primitives(&"hull"):
		mint += int(prim.material == &"mint" and prim.shape == &"prism" and prim.sides == 6)
	assert_int(mint).is_equal(2)
	var lamps: int = 0
	for prim: ArtPrim in _model(&"fossil_patchers").primitives(&"hull"):
		lamps += int(prim.material == &"lamp")
	assert_int(lamps).is_greater(1)
	# Every frame of both: the hull, the 4 walk and 2 idle frames, in all 8 directions.
	var hex: RegEx = RegEx.create_from_string("#[0-9A-Fa-f]{6}")
	for id: StringName in IDS:
		var sheet: IsoSheetDef = _index.sheet(id)
		for dir: int in range(0, 16, 2):
			for frame: Array in _frames():
				var text: String = FileAccess.get_file_as_string(
					sheet.path(frame[0], dir, frame[1])
				)
				for found: RegExMatch in hex.search_all(text):
					var colour: Color = Color(found.get_string())
					var degrees: float = colour.h * 360.0
					var reddish: bool = (degrees < RED_HUE or degrees > 340.0) and colour.s > 0.5
					(
						assert_bool(reddish)
						. override_failure_message(
							"%s d%02d %s%d %s" % [id, dir, frame[0], frame[1], found.get_string()]
						)
						. is_false()
					)


func test_the_cast_shadow_is_one_connected_mark_in_every_direction() -> void:
	for id: StringName in IDS:
		var sheet: IsoSheetDef = _index.sheet(id)
		for dir: int in range(0, 16, 2):
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


func test_each_medic_squad_reads_apart_from_the_squads_at_32_px_in_greyscale() -> void:
	for id: StringName in IDS:
		var mask: Image = Support.mask_32(_picture(id, _model(id).default_dir(), &"hull", 0))
		var ink: int = 0
		for y: int in 32:
			for x: int in 32:
				ink += int(mask.get_pixel(x, y).a > 0.5)
		assert_float(float(ink) / 1024.0).override_failure_message("%s fills" % id).is_greater(0.1)
		for other: StringName in OTHERS:
			if other == id:
				continue
			var rival: Image = Support.mask_32(
				_picture(other, _model(other).default_dir(), &"hull", 0)
			)
			var overlap: float = Support.overlap(mask, rival)
			(
				assert_float(overlap)
				. override_failure_message("%s against %s: %.2f" % [id, other, overlap])
				. is_less(MAX_OVERLAP)
			)


## The tones of a greyscale view are spread (a body, dark legs, a pale helmet), not one flat grey.
func test_a_medic_squad_keeps_a_spread_of_tones_in_greyscale_in_every_walk_and_idle_frame() -> void:
	for id: StringName in IDS:
		for frame: Array in _frames():
			var picture: Image = _picture(id, _model(id).default_dir(), frame[0], frame[1])
			var low: float = 1.0
			var high: float = 0.0
			for y: int in picture.get_height():
				for x: int in picture.get_width():
					if picture.get_pixel(x, y).a > 0.95:
						var grey: float = Support.grey(picture, Vector2i(x, y))
						low = minf(low, grey)
						high = maxf(high, grey)
			assert_float(high - low).override_failure_message("%s %s" % [id, frame]).is_greater(0.4)


## [part, frame] of the seven frames of a default view: the standing hull, 4 walk and 2 idle.
func _frames() -> Array[Array]:
	return [
		[&"hull", 0],
		[&"walk", 0],
		[&"walk", 1],
		[&"walk", 2],
		[&"walk", 3],
		[&"idle", 0],
		[&"idle", 1],
	]


func _model(id: StringName) -> ArtModel:
	var faction: String = "renew" if String(id).begins_with("renew") else "fossil"
	return load(MODEL % [faction, id]) as ArtModel


func _picture(id: StringName, dir: int, part: StringName, frame: int) -> Image:
	var sheet: IsoSheetDef = _index.sheet(id)
	var picture: Image = Image.create_empty(
		Support.PAGE.x, Support.PAGE.y, false, Image.FORMAT_RGBA8
	)
	var body: Image = Support.raster(
		FileAccess.get_file_as_string(sheet.path(part, dir, frame)), Support.SCALE
	)
	picture.blend_rect(
		body,
		Rect2i(Vector2i.ZERO, body.get_size()),
		Support.GROUND_POINT - Vector2i(Vector2(sheet.origin(part)) * Support.SCALE)
	)
	return picture


func _share(id: StringName, dir: int, part: StringName, frame: int) -> float:
	return Support.model_share(_model(id), _picture(id, dir, part, frame))
