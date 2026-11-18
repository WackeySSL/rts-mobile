extends GdUnitTestSuite
## The two repair buildings' art (plan row P279, STYLE.md "The repair buildings"): the Derrick
## League's Weld Shed (`fossil_weld_shed`) and the Lumen Accord's Drone Dock (`renew_drone_dock`),
## each a 2 x 2 model with a hull, an `anim` loop, a KRITISK picture, no SKADET picture (ADR 0034)
## and one cast shadow. It pins what the row promises: the sheet's parts, the card, the team share
## at zoom 1 in every frame of the loop (the rule asks for 8 to 12 %), the KRITISK share in ADR
## 0029's band, a shadow that is one connected mark, and the silhouettes at 32 px in greyscale
## against every other building. That the bytes equal a fresh run is test_artgen.gd.

const MODEL: String = "res://assets/art/models/%s/%s.tres"
const Support: GDScript = preload("res://tests/art/building_picture_support.gd")
const DamageSupport: GDScript = preload("res://tests/art/artgen_v5_support.gd")
const IDS: Array[StringName] = [&"fossil_weld_shed", &"renew_drone_dock"]
const FACTION: Dictionary[StringName, StringName] = {
	&"fossil_weld_shed": &"fossil", &"renew_drone_dock": &"renew"
}
const VIEW_DIR: Dictionary[StringName, int] = {&"fossil": 6, &"renew": 10}
const SHARE: Vector2 = Vector2(0.08, 0.12)
const MAX_OVERLAP: float = 0.85
var _index: IsoIndex = null


func before() -> void:
	_index = load(IsoIndex.PATH) as IsoIndex


func test_a_sheet_has_a_body_a_kritisk_patch_and_a_shadow_and_the_card() -> void:
	for id: StringName in IDS:
		var model: ArtModel = load(MODEL % [FACTION[id], id]) as ArtModel
		assert_array(Array(model.problems())).override_failure_message(String(id)).is_empty()
		assert_int(model.footprint).is_equal(2)
		assert_bool(model.silhouette.contains("\n")).is_false()
		var sheet: IsoSheetDef = _index.sheet(id)
		assert_array(Array(sheet.parts)).override_failure_message(String(id)).is_equal(
			["hull", "anim", "dmg2", "shadow"]
		)
		assert_bool(sheet.has_part(&"dmg1")).is_false()  # No SKADET picture (ADR 0034).
		assert_bool(sheet.icon.ends_with("item_%s.svg" % id)).is_true()
		assert_bool(FileAccess.file_exists(sheet.icon)).is_true()


func test_the_model_matches_the_footprint_of_its_data() -> void:
	for id: StringName in IDS:
		var def: BuildingDef = load("res://data/units/%s.tres" % id) as BuildingDef
		var model: ArtModel = load(MODEL % [FACTION[id], id]) as ArtModel
		assert_that(def.footprint).is_equal(Vector2i(model.footprint, model.footprint))


func test_the_team_share_of_the_default_view_is_8_to_12_percent_at_zoom_1_in_every_frame() -> void:
	for id: StringName in IDS:
		var sheet: IsoSheetDef = _index.sheet(id)
		for frame: int in sheet.frame_count(&"anim"):
			var picture: Image = Support.default_picture(sheet, VIEW_DIR[FACTION[id]], frame)
			var share: float = Support.team_share(picture, FACTION[id])
			(
				assert_float(share)
				. override_failure_message("%s frame %d team share %.3f" % [id, frame, share])
				. is_between(SHARE.x, SHARE.y)
			)


func test_the_loop_has_eight_frames_and_each_is_a_picture_of_its_own() -> void:
	for id: StringName in IDS:
		var sheet: IsoSheetDef = _index.sheet(id)
		assert_int(sheet.frame_count(&"anim")).is_equal(8)
		var seen: Dictionary[String, bool] = {}
		for frame: int in 8:
			seen[FileAccess.get_file_as_string(sheet.path(&"anim", -1, frame))] = true
		assert_int(seen.size()).override_failure_message(String(id)).is_equal(8)


## ADR 0029 section 5: the KRITISK picture keeps 20 to 50 % of the intact picture's team colour.
func test_the_kritisk_picture_keeps_its_team_colour_in_the_band() -> void:
	for id: StringName in IDS:
		var model: ArtModel = load(MODEL % [FACTION[id], id]) as ArtModel
		assert_array(Array(DamageSupport.share_problems(model))).is_empty()
		var share: float = DamageSupport.key_share(model, 2)
		var band: Vector2 = DamageSupport.SHARE_BANDS[1]
		assert_float(share).override_failure_message("%s: %.2f" % [id, share]).is_between(
			band.x, band.y
		)


func test_the_cast_shadow_is_one_connected_mark() -> void:
	for id: StringName in IDS:
		var sheet: IsoSheetDef = _index.sheet(id)
		var shadow: Image = Support.raster(
			FileAccess.get_file_as_string(sheet.path(&"shadow", -1)), 1.0
		)
		shadow.convert(Image.FORMAT_RGBA8)
		for y: int in shadow.get_height():
			for x: int in shadow.get_width():
				if shadow.get_pixel(x, y).a > 0.0:
					shadow.set_pixel(x, y, Color.BLACK)
		assert_int(Support.pieces(shadow)).override_failure_message(String(id)).is_equal(1)


func test_each_reads_apart_from_every_other_building_at_32_px_in_greyscale() -> void:
	var masks: Dictionary[StringName, Image] = {}
	for sheet: IsoSheetDef in _index.sheets:
		if sheet.category == &"bld":
			masks[sheet.art_id] = Support.mask_32(
				Support.default_picture(sheet, 6 if sheet.faction == &"fossil" else 10)
			)
	assert_int(masks.size()).is_equal(26)
	for id: StringName in IDS:
		var ink: int = 0
		for y: int in 32:
			for x: int in 32:
				ink += int(masks[id].get_pixel(x, y).a > 0.5)
		assert_float(float(ink) / 1024.0).override_failure_message("%s fills" % id).is_greater(0.1)
		for other: StringName in masks:
			if other == id:
				continue
			var overlap: float = Support.overlap(masks[id], masks[other])
			(
				assert_float(overlap)
				. override_failure_message("%s against %s: %.2f" % [id, other, overlap])
				. is_less(MAX_OVERLAP)
			)


## The loop closes (STYLE.md "The repair buildings"): after frame 7 comes frame 0 again. The Weld
## Shed's arm swings by at most 5 degrees a frame, and the step from the last frame to the first is
## no bigger than the steps inside the loop; the Drone Dock's drone rides 8 points of one ring (a
## constant radius round the first frame's centre), so the step back to frame 0 is as long as any
## other and the turn is 45 degrees.
func test_the_arm_swings_and_the_drone_rides_a_loop_that_closes_on_frame_0() -> void:
	var shed: ArtModel = load(MODEL % ["fossil", "fossil_weld_shed"]) as ArtModel
	var angles: Array[float] = []
	for frame: int in 8:
		var angle: float = 0.0
		for move: ArtMove in shed.pose_moves(&"anim", frame):
			if move.group == &"arm" and move.axis == 1:
				angle = move.degrees
		angles.append(angle)
	var steps: Array[float] = []
	for frame: int in 8:
		steps.append(absf(angles[(frame + 1) % 8] - angles[frame]))
	assert_float(angles[0]).is_equal(0.0)
	assert_float(steps.max()).is_less_equal(5.0)
	assert_float(steps[7]).override_failure_message("last to first %s" % [steps]).is_equal(steps[0])
	var dock: ArtModel = load(MODEL % ["renew", "renew_drone_dock"]) as ArtModel
	var places: Array[Vector2] = []
	for frame: int in 8:
		for move: ArtMove in dock.pose_moves(&"anim", frame):
			if move.group == &"drn":
				places.append(Vector2(move.shift.x, move.shift.y))
	assert_int(places.size()).is_equal(8)
	var chord: float = places[0].distance_to(places[1])
	for frame: int in 8:
		assert_float(places[frame].length()).is_equal_approx(places[0].length(), 0.002)
		assert_float(places[frame].distance_to(places[(frame + 1) % 8])).is_equal_approx(
			chord, 0.002
		)


## No moving part is drawn over the body where the body should stand in front of it: every anim
## primitive of the Weld Shed hangs below the fascia's lower edge and in front of it (STYLE.md
## "Where an element may stand").
func test_the_weld_sheds_arm_stays_below_the_fascia_and_in_front_of_it() -> void:
	var shed: ArtModel = load(MODEL % ["fossil", "fossil_weld_shed"]) as ArtModel
	var fascia: float = 99.0
	for prim: ArtPrim in shed.primitives(&"hull"):
		if prim.group == &"eave":
			fascia = minf(fascia, prim.aabb().position.z)
	assert_float(fascia).is_less(99.0)
	for prim: ArtPrim in shed.primitives(&"anim"):
		assert_float(prim.aabb().end.z).override_failure_message(prim.line).is_less_equal(
			fascia - 0.1
		)
		assert_float(prim.aabb().position.y).override_failure_message(prim.line).is_greater(0.3)


## The spark rides the torch: in every frame the centre of its primitives is within 0.04 tile (5 px
## at 2x) of the torch tip's bottom centre across the ground and no higher than the tip's bottom
## (so the torch box, which is drawn over it, never hides it); the arm swings it about the torch,
## which is why the spin is written before the swing in the model.
func test_the_weld_sheds_spark_sits_at_the_torch_tip_in_every_frame() -> void:
	var shed: ArtModel = load(MODEL % ["fossil", "fossil_weld_shed"]) as ArtModel
	for frame: int in 8:
		var torch: AABB = AABB()
		var spark: Array[AABB] = []
		for prim: ArtPrim in shed.frame_prims(&"anim", frame):
			if prim.group == &"arc":
				spark.append(prim.aabb())
			elif prim.material == &"iron" and prim.size.z > 0.1 and prim.size.x < 0.1:
				if prim.aabb().position.z > 0.2 and prim.aabb().position.z < 0.3:
					torch = prim.aabb()
		(
			assert_float(torch.size.x)
			. override_failure_message("no torch in frame %d" % frame)
			. is_greater(0.0)
		)
		var centre: Vector3 = Vector3.ZERO
		var top: float = 0.0
		for box: AABB in spark:
			centre += box.get_center() / float(spark.size())
			top = maxf(top, box.end.z)
		var tip: Vector3 = Vector3(torch.get_center().x, torch.get_center().y, torch.position.z)
		var label: String = "frame %d: spark %s, torch %s" % [frame, centre, tip]
		(
			assert_float(Vector2(centre.x, centre.y).distance_to(Vector2(tip.x, tip.y)))
			. override_failure_message(label)
			. is_less_equal(0.04)
		)
		assert_float(top).override_failure_message(label).is_less_equal(torch.position.z + 0.02)
		assert_float(centre.z).override_failure_message(label).is_less(torch.position.z)
