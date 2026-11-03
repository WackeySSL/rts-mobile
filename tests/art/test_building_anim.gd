extends GdUnitTestSuite
## The building `anim` parts, the `emitters` and the `marks` of the models (plan row P143, ADR 0027
## section 4, STYLE.md "Building life (P143)"): the ten animated buildings of both factions play
## their frames (Signal Mast 16, Relay Tower 16, Wind Park 6, Turbine Hall 4, Deep Bore 4, Blackout
## Array 4, Grid Hub 2, Crew Hall 2), each frame is a picture of its own and the loop closes, the
## moving element leaves the body and stays in the shadow and the card, no turned face sits on a
## light cut (but for the two hexagonal sets, below), the emitters sit where the plan says and every
## vehicle model has `marks`. That the bytes equal a fresh run is test_artgen.gd; the pictures at 32
## px are in test_artgen_readability.gd; the page in tests/view/test_iso_atlas_budget.gd.

## The animated buildings: art id, frames, `anim_ms`, the angle that one loop turns each group of
## the model by when it turns (a loop closes when that is a whole number of the group's own turns:
## 360 for a panel, 90 for a four-bladed rotor or fan, 180 for a bar).
const BUILDINGS: Dictionary[StringName, Array] = {
	&"fossil_radar": [16, 140, 360.0],
	&"renew_radar": [16, 150, 360.0],
	&"renew_power": [6, 90, 90.0],
	&"power_plant": [4, 90, 90.0],
	&"fossil_strike": [4, 200, 90.0],
	&"renew_strike": [4, 220, 0.0],
	&"renew_hq": [2, 600, 180.0],
	&"renew_barracks": [2, 600, 180.0],
}
## What a turned face may be from a light cut, in shade (P139's margin, 0.016). The two hexagonal
## sets cannot reach it: a hexagon's slanted faces cross the cut of the top level at two angles of
## a turn, 96 degrees apart, and a lattice of 22.5 (or 15) degrees cannot miss both by more than a
## few degrees, whatever its phase (the best phases are used: 11 degrees for the Relay Tower, 2.5
## for the Wind Park). Their floors are what the committed frames have.
const CUT_MARGIN: float = 0.016
const CUT_FLOORS: Dictionary[StringName, float] = {&"renew_radar": 0.007, &"renew_power": 0.011}
const MIN_FACING: float = 0.12  ## A face seen at a sliver is not judged (as in test_artgen_poses).
## Where each model's emitters are (kinds, in file order); the vehicles' is one `exhaust`.
const EMITTERS: Dictionary[StringName, Array] = {
	&"headquarters": [&"smoke"],
	&"refinery": [&"steam", &"flame"],
	&"power_plant": [&"smoke", &"smoke"],
	&"renew_refinery": [&"steam", &"steam"],
	&"fossil_strike": [&"launch"],
	&"renew_strike": [&"launch"],
}
const VEHICLES: Dictionary[StringName, StringName] = {
	&"light_tank": &"wheels",
	&"heavy_tank": &"tracks",
	&"artillery": &"wheels",
	&"harvester": &"wheels",
	&"renew_scout": &"wheels",
	&"renew_tank": &"tracks",
	&"renew_artillery": &"wheels",
	&"renew_tanker": &"wheels",
}

var _index: IsoIndex = null


func before() -> void:
	_index = load(IsoIndex.PATH) as IsoIndex


func test_exactly_the_eight_buildings_have_an_anim_part_with_the_frames_and_time_of_the_plan(
) -> void:
	var seen: Array[String] = []
	for path: String in ArtGen.model_paths():
		var model: ArtModel = load(path) as ArtModel
		if model.category != &"bld":
			assert_int(model.pose_frames(&"anim")).override_failure_message(path).is_equal(0)
			continue
		var want: Array = BUILDINGS.get(model.art_id, [0, 0, 0.0])
		var frames: int = want[0]
		assert_int(model.pose_frames(&"anim")).override_failure_message(path).is_equal(frames)
		assert_int(model.anim_ms).override_failure_message(path).is_equal(want[1])
		assert_bool(model.problems().is_empty()).override_failure_message(path).is_true()
		var sheet: IsoSheetDef = _index.sheet(model.art_id)
		assert_int(sheet.frame_count(&"anim")).override_failure_message(path).is_equal(
			maxi(frames, 1)
		)
		assert_int(sheet.anim_ms).is_equal(want[1])
		if frames == 0:
			assert_bool(sheet.has_part(&"anim")).override_failure_message(path).is_false()
			continue
		seen.append(String(model.art_id))
		# A building's anim has no direction, is anchored at the footprint centre, and the frames
		# are files `<id>_anim_f<K>.svg`.
		assert_array(Array(sheet.directions(&"anim"))).is_equal([-1])
		assert_vector(Vector2(sheet.anchor(&"anim"))).is_equal(Vector2(sheet.origin(&"anim")))
		for frame: int in frames:
			var file: String = sheet.path(&"anim", -1, frame)
			assert_str(file).ends_with("%s_anim_f%d.svg" % [model.art_id, frame])
			assert_bool(FileAccess.file_exists(file)).override_failure_message(file).is_true()
		assert_bool(frames in [2, 4, 6, 16]).is_true()
	seen.sort()
	var names: Array = BUILDINGS.keys().map(func(id: StringName) -> String: return String(id))
	names.sort()
	assert_array(seen).is_equal(names)


func test_every_frame_of_a_loop_is_a_picture_of_its_own() -> void:
	for id: StringName in BUILDINGS:
		var sheet: IsoSheetDef = _index.sheet(id)
		var texts: Dictionary[String, int] = {}
		for frame: int in sheet.frame_count(&"anim"):
			var text: String = FileAccess.get_file_as_string(sheet.path(&"anim", -1, frame))
			assert_bool(text.is_empty()).override_failure_message("%s f%d" % [id, frame]).is_false()
			(
				assert_bool(texts.has(text))
				. override_failure_message(
					"%s: frame %d is frame %d" % [id, frame, texts.get(text, -1)]
				)
				. is_false()
			)
			texts[text] = frame


func test_a_loop_closes_one_step_after_its_last_frame_is_the_first() -> void:
	# Each turning group moves by a fixed step a frame (from a phase of its own: the second rotor and
	# the fans are a few frames ahead of the first), and `frames x step` is a whole number of its
	# symmetry (360 degrees for a panel or an array, 90 for a four-bladed rotor, a fan or a kelly's
	# cross, 180 for a bar): the frame after the last is the first again. The sparks of the
	# Blackout Array shift instead: a pulse that restarts.
	var turning: int = 0
	for id: StringName in BUILDINGS:
		var model: ArtModel = _model(id)
		var period: float = BUILDINGS[id][2]
		var frames: int = model.pose_frames(&"anim")
		for group: StringName in _groups(model):
			var turns: Array[float] = []
			for frame: int in frames:
				var angle: float = 0.0
				for move: ArtMove in model.pose_moves(&"anim", frame):
					if move.group == group and move.axis >= 0:
						angle = move.degrees
				turns.append(angle)
			if turns.all(func(a: float) -> bool: return is_zero_approx(a)):
				continue
			turning += 1
			var step: float = fposmod(turns[1] - turns[0], period)
			var seen: Array[int] = []
			for frame: int in frames:
				var ahead: float = fposmod(turns[frame] - turns[0], period) / step
				(
					assert_float(ahead)
					. override_failure_message(
						(
							"%s %s frame %d is not on the lattice of %.1f degrees"
							% [id, group, frame, step]
						)
					)
					. is_equal_approx(roundf(ahead), 0.001)
				)
				assert_bool(seen.has(roundi(ahead))).is_false()
				seen.append(roundi(ahead))
			(
				assert_float(step * frames / period)
				. override_failure_message(
					(
						"%s %s: %d frames of %.1f degrees do not close a loop of %.0f"
						% [id, group, frames, step, period]
					)
				)
				. is_equal_approx(1.0, 0.001)
			)
	assert_int(turning).is_equal(11)


func test_the_moving_element_is_not_in_the_body_and_stays_at_rest_in_the_shadow() -> void:
	for id: StringName in BUILDINGS:
		var model: ArtModel = _model(id)
		var anim: Array[ArtPrim] = model.primitives(&"anim")
		assert_bool(anim.is_empty()).override_failure_message(String(id)).is_false()
		# The shadow's primitives are the hull's and the element's at rest: nothing is lost to it.
		assert_int(model.shadow_prims().size()).is_equal(
			model.primitives(&"hull").size() + anim.size() + model.primitives(&"head").size()
		)
		var kept: Array[String] = []
		for prim: ArtPrim in model.primitives(&"hull"):
			kept.append(prim.line)
		for prim: ArtPrim in anim:
			assert_bool(kept.has(prim.line.replace(" anim ", " hull "))).is_false()
	# The two radars and the Wind Park lost their moving elements from the body (the Anim child
	# draws them): their bodies have fewer primitives than the same models with everything in the
	# hull. The other five only gained an element.
	for id: StringName in [
		&"fossil_radar", &"renew_radar", &"renew_power", &"renew_hq", &"renew_barracks"
	]:
		var model: ArtModel = _model(id)
		var flat: ArtModel = _model(id).duplicate() as ArtModel
		flat.prims = PackedStringArray(
			Array(flat.prims).map(func(l: String) -> String: return l.replace(" anim ", " hull "))
		)
		assert_int(flat.primitives(&"hull").size()).is_greater(model.primitives(&"hull").size())


func test_no_turned_face_of_an_anim_frame_sits_on_a_light_cut() -> void:
	var checked: int = 0
	for id: StringName in BUILDINGS:
		var model: ArtModel = _model(id)
		var floor_gap: float = CUT_FLOORS.get(id, CUT_MARGIN)
		var rest: Array[ArtPrim] = model.primitives(&"anim")
		for frame: int in model.frames(&"anim"):
			var posed: Array[ArtPrim] = model.frame_prims(&"anim", frame)
			for at: int in posed.size():
				var prim: ArtPrim = posed[at]
				if prim.moves.is_empty() or prim.shape == &"sphere":
					continue  # Not moved in this frame: a face of the standing body.
				for face: ArtMesh.Face in ArtMesh.faces(prim):
					if face.normal.dot(ArtRender.VIEW) < MIN_FACING:
						continue
					var shade: float = ArtRender.LIGHT_BASE + face.normal.dot(ArtRender.LIGHT)
					var gap: float = minf(
						absf(shade - ArtRender.CUT_TOP), absf(shade - ArtRender.CUT_LEFT)
					)
					(
						assert_float(gap)
						. override_failure_message(
							(
								"%s f%d %s shade %.4f: %s"
								% [id, frame, prim.group, shade, rest[at].line]
							)
						)
						. is_greater_equal(floor_gap)
					)
					checked += 1
	assert_int(checked).is_greater(1000)


func test_the_blinking_lamps_are_a_lit_bar_that_turns_on_its_housing() -> void:
	# Anim frames draw only anim primitives, so a lamp cannot blink by being hidden: the Grid Hub
	# and the Crew Hall carry a mint bar on a dark housing, and frame 1 turns the bar a quarter.
	for id: StringName in [&"renew_hq", &"renew_barracks"]:
		var model: ArtModel = _model(id)
		var bar: Array[ArtPrim] = []
		for prim: ArtPrim in model.primitives(&"anim"):
			if prim.group == &"beacon":
				bar.append(prim)
		assert_int(bar.size()).is_equal(1)
		assert_str(String(bar[0].material)).is_equal("mint")
		assert_bool(bar[0].size.x > 2.0 * bar[0].size.y).is_true()
		var moves: Array[ArtMove] = model.pose_moves(&"anim", 1)
		assert_int(moves.size()).is_equal(1)
		assert_int(moves[0].axis).is_equal(2)
		assert_float(moves[0].degrees).is_equal(90.0)
		assert_bool(model.pose_moves(&"anim", 0).is_empty()).is_true()
		# Both frames carry the lit bar: mint polygons in each, in different places.
		var sheet: IsoSheetDef = _index.sheet(id)
		var mint: String = ArtPalette.tone(model.faction, &"mint", ArtPalette.TOP)
		var texts: Array[String] = [
			FileAccess.get_file_as_string(sheet.path(&"anim", -1, 0)),
			FileAccess.get_file_as_string(sheet.path(&"anim", -1, 1)),
		]
		for text: String in texts:
			(
				assert_bool(text.contains(mint))
				. override_failure_message("%s %s" % [id, mint])
				. is_true()
			)
		assert_bool(texts[0] != texts[1]).is_true()


func test_the_emitters_are_where_the_plan_says_and_inside_the_picture() -> void:
	for path: String in ArtGen.model_paths():
		var model: ArtModel = load(path) as ArtModel
		var want: Array = EMITTERS.get(model.art_id, [])
		if model.category == &"veh":
			want = [&"exhaust"]
		var kinds: Array = model.emitter_list().map(func(e: Array) -> StringName: return e[0])
		assert_array(kinds).override_failure_message(path).is_equal(want)
		var sheet: IsoSheetDef = _index.sheet(model.art_id)
		assert_array(Array(sheet.emitters)).override_failure_message(path).is_equal(
			want.map(func(k: StringName) -> String: return String(k))
		)
		for index: int in want.size():
			var point: Vector3 = model.emitter_list()[index][1]
			if model.category == &"bld":
				# Where the building's art puts it, from the footprint's centre: one point.
				assert_int(sheet.emitter_points.size()).is_equal(want.size())
				assert_vector(sheet.emitter_point(index, -1)).is_equal_approx(
					ArtRender.project(point).snapped(Vector2.ONE * 0.1), Vector2.ONE * 0.11
				)
				var inside: Rect2 = Rect2()
				for part: StringName in [&"hull", &"anim"]:
					if sheet.has_part(part):
						var size: Vector2 = Vector2(sheet.frame_size(part))
						var corner: Vector2 = -Vector2(sheet.origin(part))
						var rect: Rect2 = Rect2(corner, size)
						inside = rect if inside.size == Vector2.ZERO else inside.merge(rect)
				assert_bool(inside.grow(8.0).has_point(sheet.emitter_point(index, -1))).is_true()
			else:
				# A vehicle's: a point per hull direction, behind the middle of the unit at d06.
				assert_int(sheet.emitter_points.size()).is_equal(16 * want.size())
				assert_bool(point.x < 0.0).override_failure_message(path).is_true()
				assert_bool(point.z > 0.0).override_failure_message(path).is_true()


func test_every_vehicle_model_has_marks_from_its_running_gear_and_nothing_else_has() -> void:
	var seen: int = 0
	for path: String in ArtGen.model_paths():
		var model: ArtModel = load(path) as ArtModel
		var sheet: IsoSheetDef = _index.sheet(model.art_id)
		if model.category == &"veh":
			assert_str(String(model.marks)).override_failure_message(path).is_not_empty()
			assert_bool(model.marks in ArtModel.MARKS).override_failure_message(path).is_true()
			assert_str(String(model.marks)).override_failure_message(path).is_equal(
				String(VEHICLES[model.art_id])
			)
			assert_str(String(sheet.marks)).override_failure_message(path).is_equal(
				String(model.marks)
			)
			seen += 1
			# The running gear is in the model: tracks are long boxes along the hull's sides, wheels
			# are prisms lying across it (`axis=y`).
			var wheels: int = (
				model
				. primitives(&"hull")
				. filter(func(p: ArtPrim) -> bool: return p.shape == &"prism" and p.axis == 1)
				. size()
			)
			assert_bool(wheels >= 4).override_failure_message(path).is_true()
		else:
			assert_str(String(model.marks)).override_failure_message(path).is_empty()
	assert_int(seen).is_equal(VEHICLES.size())
	assert_int(seen).is_equal(8)


func _model(id: StringName) -> ArtModel:
	for path: String in ArtGen.model_paths():
		var model: ArtModel = load(path) as ArtModel
		if model.art_id == id:
			return model
	return null


func _groups(model: ArtModel) -> Array[StringName]:
	var found: Array[StringName] = []
	for prim: ArtPrim in model.primitives(&"anim"):
		if prim.group != &"" and not found.has(prim.group):
			found.append(prim.group)
	return found
