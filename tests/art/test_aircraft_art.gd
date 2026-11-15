extends GdUnitTestSuite
## The four aircraft's art (plan row P245, STYLE.md "The aircraft"): the Derrick League's Torchjet
## (`fossil_fighter`) and Drillhead (`fossil_bomber`), the Lumen Accord's Glint (`renew_fighter`)
## and Sunfall (`renew_bomber`). Each is a vehicle model with a hull in 16 directions, a cast
## shadow and an item card, no turret, no damage picture (a unit shows none) and a lift (`fly_px`)
## that `AirLayer` draws its hull at above the shadow. It pins what the row and the style guide
## promise: the sheet's parts and lift, that nothing of a model touches the ground (so its shadow
## has neither a pad nor a contact line), the team share at zoom 1 (the rule asks for 8 to 12 % in
## the default view; the other directions are held to a wider band), a shadow that is one
## connected mark, and the silhouettes at 32 px in greyscale against each other. That the bytes
## equal a fresh run is test_artgen.gd.

const MODEL: String = "res://assets/art/models/%s/%s.tres"
const Support: GDScript = preload("res://tests/art/building_picture_support.gd")
const IDS: Array[StringName] = [
	&"fossil_fighter", &"fossil_bomber", &"renew_fighter", &"renew_bomber"
]
const FACTION: Dictionary[StringName, StringName] = {
	&"fossil_fighter": &"fossil",
	&"fossil_bomber": &"fossil",
	&"renew_fighter": &"renew",
	&"renew_bomber": &"renew",
}
## The silhouette lines start with Michael's names (data/units, ADR 0032).
const NAMES: Dictionary[StringName, String] = {
	&"fossil_fighter": "Torchjet",
	&"fossil_bomber": "Drillhead",
	&"renew_fighter": "Glint",
	&"renew_bomber": "Sunfall",
}
## Zoom 1 of the 2x art: the zoom every suite measures the share at.
const SCALE: float = 0.5
## The rule's band in the default view of zoom 1, and the band every other direction keeps.
const SHARE: Vector2 = Vector2(0.08, 0.12)
const SHARE_WIDE: Vector2 = Vector2(0.05, 0.16)
## The lowest a primitive of an aircraft starts, tiles: `ArtShadow.GROUND_Z`, below which a
## primitive touches the ground and gets the pad and the contact line of a ground unit's shadow.
const LOWEST_Z: float = 0.25
## The hover a sheet may ask for, world px at zoom 1: high enough to clear the shadow and the ring
## under it, low enough that the hull still belongs to them. `AirLayer.DEFAULT_FLY_PX` is 28.
const FLY_PX: Vector2i = Vector2i(16, 36)
## How much of another aircraft's 32 px silhouette one may cover (both over either).
const MAX_OVERLAP: float = 0.85

var _index: IsoIndex = null


func before() -> void:
	_index = load(IsoIndex.PATH) as IsoIndex


func test_a_sheet_is_a_hull_in_16_directions_and_a_shadow_with_a_lift() -> void:
	for id: StringName in IDS:
		var model: ArtModel = _model(id)
		assert_str(String(model.art_id)).is_equal(String(id))
		assert_str(String(model.category)).is_equal("veh")
		assert_int(model.footprint).is_equal(0)
		var sheet: IsoSheetDef = _index.sheet(id)
		assert_array(Array(sheet.parts)).override_failure_message(String(id)).is_equal(
			["hull", "shadow"]
		)
		assert_array(sheet.directions(&"hull")).is_equal(range(16))
		assert_array(sheet.directions(&"shadow")).is_equal(range(16))
		for part: StringName in [&"turret", &"head", &"anim", &"dmg1", &"dmg2", &"walk", &"idle"]:
			assert_bool(sheet.has_part(part)).override_failure_message(String(part)).is_false()
		# Page 2 is not trimmed (P306): an aircraft's sheet has no tight boxes, every frame is whole.
		assert_int(sheet.boxes.size()).is_equal(0)
		assert_bool(sheet.flies()).is_true()
		assert_int(sheet.low_fly_px).is_equal(0)
		assert_int(sheet.fly_px).override_failure_message(String(id)).is_between(FLY_PX.x, FLY_PX.y)
		assert_int(sheet.fly_px).is_equal(model.fly_px)
		assert_bool(sheet.icon.ends_with("item_%s.svg" % id)).is_true()
		assert_bool(FileAccess.file_exists(sheet.icon)).is_true()
		for dir: int in 16:
			assert_bool(FileAccess.file_exists(sheet.path(&"hull", dir))).is_true()
			assert_bool(FileAccess.file_exists(sheet.path(&"shadow", dir))).is_true()


func test_each_is_named_in_its_silhouette_line_and_the_bomber_is_the_bigger() -> void:
	for id: StringName in IDS:
		var def: UnitDef = load("res://data/units/%s.tres" % id) as UnitDef
		assert_str(def.display_name).is_equal(NAMES[id])
		assert_str(_model(id).silhouette).override_failure_message(String(id)).starts_with(
			NAMES[id] + ":"
		)
	for faction: String in ["fossil", "renew"]:
		var fighter: Rect2 = _box(StringName(faction + "_fighter"))
		var bomber: Rect2 = _box(StringName(faction + "_bomber"))
		assert_float(bomber.size.x).is_greater(fighter.size.x)
		assert_float(bomber.size.y).is_greater(fighter.size.y)
		# A fighter is about a tile wide and a bomber about a half again: both a unit's size.
		assert_float(fighter.size.x * SCALE).is_between(50.0, 96.0)
		assert_float(bomber.size.x * SCALE).is_between(76.0, 128.0)


## An aircraft hangs in the air: no primitive reaches the ground, so its cast shadow has no pad and
## no contact line (`ArtShadow.pad`), and the lift is `fly_px`'s alone.
func test_no_primitive_of_an_aircraft_touches_the_ground() -> void:
	for id: StringName in IDS:
		for prim: ArtPrim in _model(id).primitives(&"hull"):
			(
				assert_float(prim.aabb().position.z)
				. override_failure_message("%s: %s" % [id, prim.line])
				. is_greater_equal(LOWEST_Z)
			)


func test_the_faction_marks_are_on_each_aircraft() -> void:
	for id: StringName in IDS:
		var hexagons: int = 0
		var mint: int = 0
		var lamp: int = 0
		for prim: ArtPrim in _model(id).primitives(&"hull"):
			hexagons += int(prim.shape == &"prism" and prim.sides == 6)
			mint += int(prim.material == &"mint")
			lamp += int(prim.material == &"lamp")
		if FACTION[id] == &"renew":
			assert_int(hexagons).override_failure_message(String(id)).is_greater(0)
			assert_int(mint).override_failure_message(String(id)).is_greater(0)
		elif id == &"fossil_fighter":
			assert_int(lamp).override_failure_message(String(id)).is_greater(0)  # The flare stack.


func test_each_has_an_exhaust_and_a_damage_point_on_its_hull() -> void:
	for id: StringName in IDS:
		var kinds: Array[StringName] = []
		for emitter: Array in _model(id).emitter_list():
			kinds.append(emitter[0])
		assert_array(kinds).override_failure_message(String(id)).is_equal([&"exhaust", &"damage"])
		var sheet: IsoSheetDef = _index.sheet(id)
		assert_array(Array(sheet.emitters)).is_equal(["exhaust", "damage"])
		assert_int(sheet.emitter_points.size()).is_equal(32)  # A point a hull frame, each.
		assert_int(_model(id).scar_milli).is_equal(0)  # An aircraft shows no scar.


## The selection ring stands on the ground under the shadow and the bar at the lifted hull: the
## ring is no wider than the hull it belongs to, and the bar clears the hull's top at the lift.
func test_the_ring_on_the_ground_and_the_bar_at_the_hull_suit_the_lift() -> void:
	for id: StringName in IDS:
		var sheet: IsoSheetDef = _index.sheet(id)
		var def: UnitDef = load("res://data/units/%s.tres" % id) as UnitDef
		var ring: float = IsoProjection.ellipse_px(def.selection_radius).x * 2.0
		var hull: Rect2 = _box(id)
		var width: float = hull.size.x * SCALE
		(
			assert_float(ring)
			. override_failure_message("%s: ring %.0f against hull %.0f" % [id, ring, width])
			. is_between(width * 0.5, width * 1.1)
		)
		# The bar clears most poses of the hull (`bar_lift_px` is the top that three of four frames
		# stay under) and the hover lifts both: the bar of `AirLayer` is `fly_px + bar_lift_px` above
		# the ground point, the hull's top is `fly_px + top`.
		var top: float = -hull.position.y * SCALE
		assert_int(sheet.bar_lift_px).override_failure_message(String(id)).is_between(
			int(top * 0.7), int(top) + 4
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
			# The shadow is a translucent group: make every touched pixel solid for the count.
			for y: int in shadow.get_height():
				for x: int in shadow.get_width():
					if shadow.get_pixel(x, y).a > 0.0:
						shadow.set_pixel(x, y, Color.BLACK)
			(
				assert_int(Support.pieces(shadow))
				. override_failure_message("%s d%02d" % [id, dir])
				. is_equal(1)
			)


func test_each_reads_apart_from_every_other_aircraft_at_32_px_in_greyscale() -> void:
	var masks: Dictionary[StringName, Image] = {}
	for id: StringName in IDS:
		masks[id] = Support.mask_32(_picture(id, _model(id).default_dir()))
	for id: StringName in IDS:
		var ink: int = 0
		for y: int in 32:
			for x: int in 32:
				ink += int(masks[id].get_pixel(x, y).a > 0.5)
		assert_float(float(ink) / 1024.0).override_failure_message("%s fills" % id).is_greater(0.1)
		for other: StringName in IDS:
			if other == id:
				continue
			var overlap: float = Support.overlap(masks[id], masks[other])
			(
				assert_float(overlap)
				. override_failure_message("%s against %s: %.2f" % [id, other, overlap])
				. is_less(MAX_OVERLAP)
			)


func _model(id: StringName) -> ArtModel:
	return load(MODEL % [FACTION[id], id]) as ArtModel


## The hull's box in the 2x art, from its ground point (the union of the 16 directions).
func _box(id: StringName) -> Rect2:
	var sheet: IsoSheetDef = _index.sheet(id)
	return Rect2(-Vector2(sheet.origin(&"hull")), Vector2(sheet.frame_size(&"hull")))


## The hull facing `dir` at zoom 1 on a transparent page, its ground point at GROUND_POINT.
func _picture(id: StringName, dir: int) -> Image:
	var sheet: IsoSheetDef = _index.sheet(id)
	var picture: Image = Image.create_empty(
		Support.PAGE.x, Support.PAGE.y, false, Image.FORMAT_RGBA8
	)
	var hull: Image = Support.raster(FileAccess.get_file_as_string(sheet.path(&"hull", dir)), SCALE)
	picture.blend_rect(
		hull,
		Rect2i(Vector2i.ZERO, hull.get_size()),
		Support.GROUND_POINT - Vector2i(Vector2(sheet.origin(&"hull")) * SCALE)
	)
	return picture


## The team share of the picture facing `dir` at zoom 1.
func _share(id: StringName, dir: int) -> float:
	return Support.team_share(_picture(id, dir), FACTION[id])
