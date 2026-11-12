extends GdUnitTestSuite
## The two space centres (plan row P236, ADR 0036 section 11 and section 15, STYLE.md "The space
## centres"): the Derrick League's Skyrig (`fossil_space`) and the Lumen Accord's Zenith
## (`renew_space`), each a 3 x 3 model with a lift as its `anim` part and a KRITISK picture, and no
## SKADET picture (ADR 0034). It pins what the art row promises: the model and the sheet's parts,
## the canvas of every frame and its anchor at the back corner, the height of Spec 05, the team
## share, the lift (every frame its own picture, one rise and one fall, steps of at most 0.37 tile,
## resting on something, clear of the beam or the crown above), shape sample points in the
## pictures, the open gantry and the plain tower (no spire, STYLE.md "Palette per faction"), the
## KRITISK picture, the silhouettes at 32 px in greyscale against every other building, the
## emitters, the bake and the guide. That the bytes equal a fresh run is test_artgen.gd; the pages
## of the atlas are in tests/view/test_iso_atlas_budget.gd; the Build page lists the models by
## itself.

const STYLE_PATH: String = "res://assets/art/STYLE.md"
const MODEL: String = "res://assets/art/models/%s/%s.tres"
const Support: GDScript = preload("res://tests/art/building_picture_support.gd")
const IDS: Array[StringName] = [&"fossil_space", &"renew_space"]
const FACTION: Dictionary[StringName, StringName] = {
	&"fossil_space": &"fossil", &"renew_space": &"renew"
}
## The default view's direction of each faction (Spec 04), which only the other buildings need.
const VIEW_DIR: Dictionary[StringName, int] = {&"fossil": 6, &"renew": 10}
## Hull canvas (w, h), the anchor's y, shadow canvas (w, h), lift canvas (w, h), KRITISK patch
## canvas (w, h) and its cut row. Run `bash scripts/gen-art.sh` and read the sheets when the art
## changes on purpose.
const CANVAS: Dictionary[StringName, Array] = {
	&"fossil_space": [384, 438, 246, 392, 198, 88, 272, 158, 186, 209],
	&"renew_space": [384, 410, 218, 410, 194, 142, 230, 306, 212, 285],
}
## The lift: frames, `anim_ms`, how far up it goes in tiles, the group it moves, the height it rests
## at (the top of a primitive under it) and the height of the member above it (the Skyrig's beam,
## the Zenith's crown), which it never reaches.
const LIFT: Dictionary[StringName, Array] = {
	&"fossil_space": [16, 150, 1.55, &"lift", 0.48, 3.32],
	&"renew_space": [12, 200, 1.4, &"lift", 0.72, 3.3],
}
const MAX_STEP: float = 0.37  ## Tiles a lift moves between two frames at most (14 px at zoom 1).
const HEIGHT_BAND: Vector2 = Vector2(80.0, 150.0)  ## Spec 05, a superweapon building.
const SHARE: Dictionary[StringName, Vector2] = {
	&"fossil": Vector2(0.07, 0.13), &"renew": Vector2(0.065, 0.125)
}
const MAX_OVERLAP: float = 0.8  ## Against every other building at 32 px, intersection over union.
const OPEN_MEAN: float = 0.25  ## The Skyrig's members cover this share of their box at most.

var _index: IsoIndex = null


func before() -> void:
	_index = load(IsoIndex.PATH) as IsoIndex


func test_each_model_is_a_3x3_building_of_its_faction_with_one_silhouette_line() -> void:
	for id: StringName in IDS:
		var model: ArtModel = _model(id)
		assert_object(model).override_failure_message("%s" % id).is_not_null()
		assert_array(Array(model.problems())).override_failure_message("%s" % id).is_empty()
		assert_str(String(model.art_id)).is_equal(String(id))
		assert_str(String(model.faction)).override_failure_message("%s" % id).is_equal(
			String(FACTION[id])
		)
		assert_str(String(model.category)).is_equal("bld")
		assert_int(model.footprint).override_failure_message("%s" % id).is_equal(3)
		assert_bool(model.silhouette.contains("\n")).is_false()
		assert_int(model.silhouette.length()).is_greater(90)
		assert_bool(model.silhouette.ends_with(".")).is_true()


func test_a_sheet_has_a_body_a_lift_a_kritisk_patch_and_a_shadow_and_no_skadet_picture() -> void:
	for id: StringName in IDS:
		var sheet: IsoSheetDef = _index.sheet(id)
		var model: ArtModel = _model(id)
		assert_object(sheet).override_failure_message("%s" % id).is_not_null()
		# ADR 0034: the generator writes no `dmg1`; the SKADET picture is the intact one.
		assert_array(Array(sheet.parts)).override_failure_message("%s" % id).is_equal(
			["hull", "anim", "dmg2", "shadow"]
		)
		assert_array(Array(sheet.counts)).is_equal([1, 1, 1, 1])
		assert_array(Array(sheet.frames)).is_equal([1, LIFT[id][0], 1, 1])
		assert_array(model.damage_parts()).is_equal([&"dmg2"])
		assert_bool(sheet.has_part(&"dmg1")).is_false()
		(
			assert_bool(FileAccess.file_exists(sheet.path(&"hull", -1).replace("hull", "dmg1")))
			. is_false()
		)
		assert_int(sheet.anim_ms).is_equal(LIFT[id][1])
		assert_str(String(model.anim_kritisk)).is_equal("hide")  # The lift's tower is down.
		assert_int(sheet.cuts.size()).is_equal(2)
		assert_int(sheet.cuts[0]).is_equal(0)  # No dmg1 patch: its cut says "nothing".
		for path: String in [sheet.path(&"hull", -1), sheet.path(&"shadow", -1), sheet.icon]:
			assert_bool(FileAccess.file_exists(path)).override_failure_message(path).is_true()
			assert_bool(FileAccess.file_exists(path + ".import")).is_true()
		assert_bool(FileAccess.file_exists(sheet.path(&"dmg2", -1))).is_true()
		assert_str(sheet.icon).ends_with("item_%s.svg" % id)


func test_every_canvas_and_anchor_is_pinned_and_the_anchor_is_the_back_corner() -> void:
	for id: StringName in IDS:
		var sheet: IsoSheetDef = _index.sheet(id)
		var want: Array = CANVAS[id]
		var hull: Vector2i = sheet.frame_size(&"hull")
		var shadow: Vector2i = sheet.frame_size(&"shadow")
		var lift: Vector2i = sheet.frame_size(&"anim")
		var patch: Vector2i = sheet.frame_size(&"dmg2")
		(
			assert_array(
				[
					hull.x,
					hull.y,
					sheet.anchor(&"hull").y,
					shadow.x,
					shadow.y,
					lift.x,
					lift.y,
					patch.x,
					patch.y,
					sheet.cuts[1]
				]
			)
			. override_failure_message("%s canvas" % id)
			. is_equal(want)
		)
		assert_int(hull.x).is_equal(384)
		for part: StringName in [&"hull", &"shadow", &"dmg2"]:
			var anchor: Vector2i = sheet.anchor(part)
			if part == &"hull":
				assert_int(anchor.x).is_equal(192)
			if part == &"shadow":
				assert_int(anchor.y).override_failure_message("%s shadow" % id).is_equal(0)
			assert_vector(Vector2(sheet.origin(part) - anchor)).is_equal(Vector2(0, 96))
			var size: Vector2i = sheet.frame_size(part)
			assert_str(Support.svg_size(sheet.path(part, -1))).is_equal("%d %d" % [size.x, size.y])
		# The lift's anchor is the footprint's centre, as every `anim` part's.
		assert_vector(Vector2(sheet.anchor(&"anim"))).is_equal(Vector2(sheet.origin(&"anim")))
		# The shadow falls to the south-east, so it reaches at least as far east as the body.
		assert_int(shadow.x - sheet.anchor(&"shadow").x).is_greater_equal(
			hull.x - sheet.anchor(&"hull").x
		)
		# The patch is the top of the body, so it ends well above the body's foot.
		assert_int(sheet.cuts[1]).is_less(hull.y - 96)


func test_each_space_centre_is_as_tall_as_spec_05_says_with_its_lift_at_rest() -> void:
	for id: StringName in IDS:
		var top: float = Support.top(_model(id)) * Support.Z_PX
		(
			assert_float(top)
			. override_failure_message(
				"%s is %.0f px tall, the band is %s" % [id, top, HEIGHT_BAND]
			)
			. is_between(HEIGHT_BAND.x, HEIGHT_BAND.y)
		)


func test_the_team_share_of_the_default_view_is_about_a_tenth_in_every_frame_of_the_lift() -> void:
	for id: StringName in IDS:
		var sheet: IsoSheetDef = _index.sheet(id)
		for frame: int in sheet.frame_count(&"anim"):
			var picture: Image = Support.default_picture(sheet, VIEW_DIR[FACTION[id]], frame)
			var share: float = Support.team_share(picture, FACTION[id])
			(
				assert_float(share)
				. override_failure_message("%s frame %d team share %.3f" % [id, frame, share])
				. is_between(SHARE[FACTION[id]].x, SHARE[FACTION[id]].y)
			)


## A lift is a shift of one group: frame 0 at rest, one rise to the top and one fall, every frame
## its own picture, no step above `MAX_STEP`, the loop's last frame as near to the first.
func test_a_lift_rises_once_falls_once_and_every_frame_is_a_picture_of_its_own() -> void:
	for id: StringName in IDS:
		var model: ArtModel = _model(id)
		var frames: int = LIFT[id][0]
		assert_int(model.pose_frames(&"anim")).is_equal(frames)
		assert_bool(model.pose_moves(&"anim", 0).is_empty()).is_true()
		var rise: Array[float] = []
		for frame: int in frames:
			var moves: Array[ArtMove] = model.pose_moves(&"anim", frame)
			var z: float = 0.0
			for move: ArtMove in moves:
				assert_str(String(move.kind)).is_equal("shift")
				assert_str(String(move.group)).is_equal(String(LIFT[id][3]))
				assert_float(move.shift.x).is_equal(0.0)
				assert_float(move.shift.y).is_equal(0.0)
				z += move.shift.z
			rise.append(z)
		var peak: int = frames / 2
		assert_float(rise[peak]).is_equal_approx(LIFT[id][2], 0.001)
		for frame: int in frames:
			var next: int = (frame + 1) % frames
			var step: float = absf(rise[next] - rise[frame])
			(
				assert_float(step)
				. override_failure_message("%s frame %d to %d moves %.3f" % [id, frame, next, step])
				. is_less_equal(MAX_STEP)
			)
			assert_float(rise[frame]).is_between(0.0, LIFT[id][2] + 0.001)
			if frame < peak:
				assert_float(rise[next]).override_failure_message("%s rise" % id).is_greater(
					rise[frame]
				)
			elif frame < frames - 1:
				assert_float(rise[next]).override_failure_message("%s fall" % id).is_less(
					rise[frame]
				)
		var sheet: IsoSheetDef = _index.sheet(id)
		var texts: Dictionary[String, int] = {}
		for frame: int in frames:
			var text: String = FileAccess.get_file_as_string(sheet.path(&"anim", -1, frame))
			assert_bool(text.is_empty()).is_false()
			(
				assert_bool(texts.has(text))
				. override_failure_message(
					"%s: frame %d is frame %d" % [id, frame, texts.get(text, -1)]
				)
				. is_false()
			)
			texts[text] = frame


## The lift stands on something at rest and stays clear of what is above it at the top.
func test_a_lift_rests_on_something_and_never_touches_what_is_above_it() -> void:
	for id: StringName in IDS:
		var model: ArtModel = _model(id)
		var lowest: float = INF
		var highest: float = 0.0
		for prim: ArtPrim in model.frame_prims(&"anim", 0):
			lowest = minf(lowest, prim.aabb().position.z)
		for prim: ArtPrim in model.frame_prims(&"anim", LIFT[id][0] / 2):
			highest = maxf(highest, prim.aabb().end.z)
		assert_float(lowest).override_failure_message("%s rest" % id).is_equal_approx(
			LIFT[id][4], 0.005
		)
		var held: bool = false
		var ceiling: bool = false
		for prim: ArtPrim in model.primitives(&"hull"):
			var box: AABB = prim.aabb()
			held = held or absf(box.end.z - lowest) < 0.011
			ceiling = ceiling or absf(box.position.z - LIFT[id][5]) < 0.011
		assert_bool(held).override_failure_message("%s: nothing under the lift" % id).is_true()
		assert_bool(ceiling).override_failure_message("%s: nothing above it" % id).is_true()
		(
			assert_float(highest)
			. override_failure_message("%s: the lift reaches %.2f" % [id, highest])
			. is_less(LIFT[id][5])
		)


## Sample points of the pictures: the pod rises out of the Skyrig's pad into the gantry's frame, the
## beam crosses its top and the frame is open between the rails; the Zenith's collar rides from the
## shaft's foot to its middle and its crown stands on the top.
func test_sample_points_of_the_pictures_are_where_the_models_put_them() -> void:
	var sky: ArtModel = _model(&"fossil_space")
	var sky_hull: Array[ArtRender.Poly] = _polys(sky, &"hull", 0)
	var sky_low: Array[ArtRender.Poly] = _polys(sky, &"anim", 0)
	var sky_high: Array[ArtRender.Poly] = _polys(sky, &"anim", 8)
	assert_bool(_ink(sky_hull, Vector3(-0.9, 0.0, 3.4))).override_failure_message("beam").is_true()
	(
		assert_bool(_ink(sky_hull, Vector3(-0.9, 0.0, 2.2)))
		. override_failure_message("opening")
		. is_false()
	)
	(
		assert_bool(_ink(sky_hull, Vector3(-0.76, -0.78, 2.5)))
		. override_failure_message("post")
		. is_true()
	)
	(
		assert_bool(_ink(sky_low, Vector3(-0.9, 0.0, 0.9)))
		. override_failure_message("pod at rest")
		. is_true()
	)
	(
		assert_bool(_ink(sky_low, Vector3(-0.9, 0.0, 2.45)))
		. override_failure_message("rest, high")
		. is_false()
	)
	(
		assert_bool(_ink(sky_high, Vector3(-0.9, 0.0, 2.45)))
		. override_failure_message("pod at top")
		. is_true()
	)
	(
		assert_bool(_ink(sky_high, Vector3(-0.9, 0.0, 0.9)))
		. override_failure_message("top, low")
		. is_false()
	)
	var zen: ArtModel = _model(&"renew_space")
	var zen_hull: Array[ArtRender.Poly] = _polys(zen, &"hull", 0)
	var zen_low: Array[ArtRender.Poly] = _polys(zen, &"anim", 0)
	var zen_high: Array[ArtRender.Poly] = _polys(zen, &"anim", 6)
	(
		assert_bool(_ink(zen_hull, Vector3(-0.2, -0.2, 3.43)))
		. override_failure_message("crown")
		. is_true()
	)
	(
		assert_bool(_ink(zen_hull, Vector3(-0.2, -0.2, 1.7)))
		. override_failure_message("shaft")
		. is_true()
	)
	(
		assert_bool(_ink(zen_low, Vector3(-0.2, -0.2, 1.0)))
		. override_failure_message("collar at rest")
		. is_true()
	)
	(
		assert_bool(_ink(zen_low, Vector3(-0.2, -0.2, 2.4)))
		. override_failure_message("rest, high")
		. is_false()
	)
	(
		assert_bool(_ink(zen_high, Vector3(-0.2, -0.2, 2.4)))
		. override_failure_message("collar at top")
		. is_true()
	)
	(
		assert_bool(_ink(zen_high, Vector3(-0.2, -0.2, 1.0)))
		. override_failure_message("top, low")
		. is_false()
	)


## The Skyrig is an open gantry (STYLE.md "Palette per faction": a tall structure is a lattice,
## never a solid spire): between its deck and its beam the members cover little of the box they
## stand in.
func test_the_skyrig_is_an_open_gantry_with_a_clear_opening_between_two_posts() -> void:
	var model: ArtModel = _model(&"fossil_space")
	var sum: float = 0.0
	var levels: int = 0
	var z: float = 0.8
	while z <= 3.2:
		var cover: float = Support.cross_section(model, z)
		assert_float(cover).override_failure_message("cover at %.1f" % z).is_less(0.4)
		sum += cover
		levels += 1
		z += 0.2
	assert_float(sum / levels).override_failure_message("mean cover").is_less(OPEN_MEAN)
	# Four posts' legs stand tall, and a beam as wide as the opening lies across their tops.
	var legs: int = 0
	var beam: float = 0.0
	for prim: ArtPrim in model.primitives(&"hull"):
		if prim.shape == &"box" and prim.size.z > 1.0 and prim.size.x < 0.2 and prim.size.y < 0.2:
			legs += 1
		if prim.group == &"beam" and prim.material == &"steel":
			beam = maxf(beam, prim.size.y)
	assert_int(legs).is_greater_equal(4)
	assert_float(beam).is_greater(1.9)
	assert_bool(model.silhouette.contains("open")).is_true()


## The Zenith is a plain round tower and no spire (CLAUDE.md Legal; STYLE.md "Palette per
## faction"): drums with steps, not a column that tapers to a point, no four-sided prism, a flat
## crown, and no lamp or team cap at the tip.
func test_the_zenith_is_a_round_tower_with_a_flat_crown_and_no_light_or_team_cap_at_its_tip(
) -> void:
	var model: ArtModel = _model(&"renew_space")
	var top: float = 0.0
	var tip: ArtPrim = null
	for prim: ArtPrim in model.primitives(&"hull"):
		(
			assert_bool(prim.shape == &"prism" and prim.sides == 4)
			. override_failure_message(prim.line)
			. is_false()
		)
		if prim.shape == &"prism" and prim.size.z > 0.8:
			assert_float(prim.taper).override_failure_message(prim.line).is_equal(1.0)
		if prim.damage == 0 and prim.aabb().end.z > top:
			top = prim.aabb().end.z
			tip = prim
	assert_float(top).is_greater(3.5)
	assert_str(String(tip.material)).is_equal("ceramic")  # A lid, not a lamp or a team cap.
	assert_float(tip.size.z).is_less_equal(0.1)  # Flat.
	assert_float(tip.size.x).is_greater_equal(0.5)  # Wider than a point.
	for prim: ArtPrim in model.primitives(&"hull"):
		if prim.damage == 0 and prim.aabb().end.z > top - 0.3:
			(
				assert_bool(prim.material in [&"team", &"mint", &"lamp"])
				. override_failure_message(prim.line)
				. is_false()
			)
	# The shaft is three round drums, each narrower than the one below and each cut by a team ring
	# (the first drum's upper piece is under a quarter tile and not listed).
	var drums: Array[float] = []
	for prim: ArtPrim in model.primitives(&"hull"):
		if prim.shape == &"prism" and prim.sides == 12 and prim.material == &"ceramic":
			if prim.size.z >= 0.25 and prim.size.x < 0.8 and prim.z0 > 0.45 and prim.damage == 0:
				drums.append(prim.size.x)
	var want_drums: Array[float] = [0.74, 0.58, 0.58, 0.46, 0.46]
	assert_int(drums.size()).is_equal(want_drums.size())
	for i: int in want_drums.size():
		assert_float(drums[i]).is_equal_approx(want_drums[i], 0.001)
	# The collar is the one wide thing on the shaft: a flat hexagon wider than a tile and a quarter.
	var wide: float = 0.0
	for prim: ArtPrim in model.primitives(&"anim"):
		wide = maxf(wide, prim.size.x)
	assert_float(wide).is_between(1.2, 1.5)


## KRITISK: the Skyrig loses the top of its right post and its rails and its beam sags; the Zenith's
## upper drums and crown lie beside the tower. The picture differs from the intact one where the
## model says, and at no point of the intact picture the stage keeps is the damage a hole.
func test_the_kritisk_pictures_break_the_top_of_each_tower() -> void:
	var sky: ArtModel = _model(&"fossil_space")
	var sky_intact: Array[ArtRender.Poly] = _polys(sky, &"hull", 0)
	var sky_broken: Array[ArtRender.Poly] = ArtGen.stage_polys(sky, 2)
	assert_bool(_ink(sky_intact, Vector3(-0.76, -0.78, 2.5))).is_true()
	assert_bool(_ink(sky_broken, Vector3(-0.76, -0.78, 2.5))).is_false()
	assert_bool(_ink(sky_broken, Vector3(-0.76, 0.78, 2.5))).is_true()  # The left post stands.
	assert_bool(_ink(sky_intact, Vector3(-0.9, -0.9, 3.4))).is_true()
	assert_bool(_ink(sky_broken, Vector3(-0.9, -0.9, 3.4))).is_false()  # The beam's end sagged.
	var zen: ArtModel = _model(&"renew_space")
	var zen_intact: Array[ArtRender.Poly] = _polys(zen, &"hull", 0)
	var zen_broken: Array[ArtRender.Poly] = ArtGen.stage_polys(zen, 2)
	assert_bool(_ink(zen_intact, Vector3(-0.2, -0.2, 3.43))).is_true()
	assert_bool(_ink(zen_broken, Vector3(-0.2, -0.2, 3.43))).is_false()  # The crown came down.
	assert_bool(_ink(zen_broken, Vector3(-0.2, -0.2, 1.7))).is_true()  # The lower tower stands.
	# Both stage-2 pictures are patches of the body's top and not its whole (the page's rows).
	for id: StringName in IDS:
		var sheet: IsoSheetDef = _index.sheet(id)
		var patch: Vector2i = sheet.frame_size(&"dmg2")
		assert_int(patch.y).override_failure_message("%s" % id).is_less(
			sheet.frame_size(&"hull").y / 2 + 10
		)


func test_each_default_view_reads_apart_from_every_other_building_at_32_px_in_greyscale() -> void:
	var masks: Dictionary[StringName, Image] = {}
	for path: String in ArtGen.model_paths():
		var model: ArtModel = load(path) as ArtModel
		if model.category == &"bld":
			masks[model.art_id] = Support.mask_32(
				Support.default_picture(_index.sheet(model.art_id), VIEW_DIR[model.faction])
			)
	assert_int(masks.size()).is_equal(18)
	for id: StringName in IDS:
		var mask: Image = masks[id]
		var ink: int = 0
		for y: int in 32:
			for x: int in 32:
				ink += int(mask.get_pixel(x, y).a > 0.5)
		# A body, not a thread: the silhouette fills a fifth of its 32 px page at least.
		assert_float(float(ink) / 1024.0).override_failure_message("%s fills" % id).is_greater(0.2)
		(
			assert_int(Support.pieces(mask.duplicate()))
			. override_failure_message("%s" % id)
			. is_less_equal(3)
		)
		for other: StringName in masks:
			if other == id:
				continue
			var overlap: float = Support.overlap(mask, masks[other])
			(
				assert_float(overlap)
				. override_failure_message("%s and %s overlap %.2f" % [id, other, overlap])
				. is_less(MAX_OVERLAP)
			)


func test_the_emitters_are_the_damage_points_and_a_launch_point_above_the_tower() -> void:
	for id: StringName in IDS:
		var model: ArtModel = _model(id)
		var kinds: Array = model.emitter_list().map(func(e: Array) -> StringName: return e[0])
		assert_bool(kinds.has(&"launch")).override_failure_message("%s" % id).is_true()
		var typed: int = 0
		for kind: StringName in ArtModel.DAMAGE_POINTS:
			typed += kinds.count(kind)
		assert_int(typed).is_between(2, 4)
		for emitter: Array in model.emitter_list():
			if emitter[0] == &"launch":
				# Above the top of the hull's body, at the tower's axis.
				assert_float(emitter[1].z).is_greater(3.4)


## Both models are on the match's page: a bake of the two sheets for one player of each faction has
## a region for every part, in the faction's own slot, the shadow on page 2 and no `dmg1`.
func test_a_bake_of_the_two_sheets_holds_every_part_on_its_page_and_no_skadet_patch() -> void:
	var sheets: Array[IsoSheetDef] = []
	for id: StringName in IDS:
		sheets.append(_index.sheet(id))
	var players: Array[IsoPlayerArt] = []
	for faction: StringName in [&"fossil", &"renew"]:
		var key: PackedStringArray = (
			(load(WorldSort.FACTION_FILE % faction) as FactionDef).key_triad
		)
		players.append(IsoPlayerArt.make(faction, key, key))
	var atlas: IsoAtlas = IsoAtlas.build(sheets, players, 0.25)
	assert_bool(atlas.is_empty()).is_false()
	for slot: int in 2:
		var id: StringName = IDS[slot]
		for part: StringName in [&"hull", &"dmg2", &"shadow"]:
			(
				assert_bool(atlas.region(id, part, -1, slot).has_area())
				. override_failure_message("%s %s" % [id, part])
				. is_true()
			)
		for frame: int in LIFT[id][0]:
			(
				assert_bool(atlas.frame_region(atlas.base(id, &"anim", -1, slot), frame).has_area())
				. is_true()
			)
		assert_int(atlas.base(id, &"dmg1", -1, slot)).is_equal(-1)
		assert_object(atlas.texture_for(&"shadow")).is_not_same(atlas.texture_for(&"hull"))


## STYLE.md says what these two are: their silhouette lines, their files and their rules.
func test_the_style_guide_names_the_two_space_centres_their_lifts_and_the_rules() -> void:
	var style: String = FileAccess.get_file_as_string(STYLE_PATH)
	var start: int = style.find("### The space centres (P236)")
	assert_int(start).is_greater(-1)
	var section: String = style.substr(start, style.find("\n## ", start + 1) - start)
	for id: StringName in IDS:
		assert_str(section).override_failure_message("%s" % id).contains(_model(id).silhouette)
		assert_str(section).contains("`%s`" % id)
	var flat: String = section.replace("\n", " ")
	for line: String in [
		"Skyrig",
		"Zenith",
		"no `dmg1`",
		"ADR 0034",
		"lift",
		"back corner",
		"no spire",
		"open gantry",
		"Spec 05",
	]:
		assert_str(flat).override_failure_message(line).contains(line)


func _model(id: StringName) -> ArtModel:
	return load(MODEL % [FACTION[id], id]) as ArtModel


## The polygons of one picture of `model`: its body, or frame `frame` of its lift.
func _polys(model: ArtModel, part: StringName, frame: int) -> Array[ArtRender.Poly]:
	return ArtRender.render(model.frame_prims(part, frame), 0.0, model.faction)


func _ink(polys: Array[ArtRender.Poly], point: Vector3) -> bool:
	return ArtDamage.inked(polys, ArtRender.project(point))
