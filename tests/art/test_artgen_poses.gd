extends GdUnitTestSuite
## The walk and idle poses of the four squads (plan row P139, ADR 0027 sections 4 and 5, STYLE.md
## "The frame axis"): each squad of both factions has `walk` (4 frames) and `idle` (2) in its 8
## directions, the generator drew them from the model's pose groups (that the bytes equal a fresh
## run is test_artgen.gd), the three figures of a frame are a frame apart in their step, the cast
## shadow is not posed, the feet stand on the ground, no pose face sits on a light cut, the colours
## are the faction's palette, and at its speed every squad walks 1.5 to 3.5 cycles a second from
## its `stride_milli`. The pictures at 32 px are in test_artgen_readability.gd, the key band in
## test_artgen.gd, the page budget in tests/view/test_iso_atlas_budget.gd, the gallery in
## test_art_gallery_units.gd.

const SQUADS: Array[StringName] = [&"rifle_squad", &"rocket_squad", &"renew_rifle", &"renew_rocket"]
const FIGURES: Array[String] = ["a", "b", "c"]  ## The groups of a figure are `<figure>_<limb>`.
const LIMBS: Array[String] = ["legl", "legr", "body", "head"]
const WALK_FRAMES: int = 4
const IDLE_FRAMES: int = 2
const CYCLES_PER_SECOND: Vector2 = Vector2(1.5, 3.5)  ## ADR 0027 section 5.
## No face of a turned primitive may sit nearer a light cut than the standing hex helmets do
## (0.0166 in shade); the cuts are in `ArtRender`, the faces below are the visible ones.
const CUT_MARGIN: float = 0.016
const MIN_FACING: float = 0.12  ## A face seen at a sliver is not judged.
const GROUND_TOLERANCE: float = 0.002  ## Tiles.

var _index: IsoIndex = null


func before() -> void:
	_index = load(IsoIndex.PATH) as IsoIndex


func test_each_squad_has_a_walk_of_4_and_an_idle_of_2_frames_in_its_8_directions() -> void:
	for id: StringName in SQUADS:
		var model: ArtModel = _model(id)
		assert_str(model.category).is_equal("inf")
		assert_int(model.pose_frames(&"walk")).override_failure_message(id).is_equal(WALK_FRAMES)
		assert_int(model.pose_frames(&"idle")).override_failure_message(id).is_equal(IDLE_FRAMES)
		assert_array(model.frame_parts()).is_equal([&"hull", &"walk", &"idle", &"shadow"])
		var sheet: IsoSheetDef = _index.sheet(id)
		assert_array(Array(sheet.parts)).is_equal(["hull", "walk", "idle", "shadow"])
		assert_array(Array(sheet.frames)).override_failure_message(id).is_equal([1, 4, 2, 1])
		assert_array(Array(sheet.counts)).override_failure_message(id).is_equal([8, 8, 8, 8])
		for part: StringName in [&"walk", &"idle"]:
			assert_array(model.directions(part)).is_equal([0, 2, 4, 6, 8, 10, 12, 14])
			for dir: int in model.directions(part):
				for frame: int in model.frames(part):
					var path: String = ArtGen.frame_path(model, part, dir, frame)
					assert_str(path).ends_with("_%s_d%02d_f%d.svg" % [part, dir, frame])
					assert_str(sheet.path(part, dir, frame)).is_equal(path)
					(
						assert_bool(FileAccess.file_exists(path))
						. override_failure_message(path)
						. is_true()
					)
					assert_bool(FileAccess.file_exists(path + ".import")).is_true()
		assert_int(model.stride_milli).override_failure_message(id).is_greater(0)
		assert_int(sheet.stride_milli).is_equal(model.stride_milli)
	# Nothing else has a walk or an idle: the buildings' `anim` is P143's.
	for path: String in ArtGen.model_paths():
		var other: ArtModel = load(path) as ArtModel
		if other.art_id not in SQUADS:
			for part: StringName in [&"walk", &"idle"]:
				assert_int(other.pose_frames(part)).override_failure_message(path).is_equal(0)


func test_every_frame_of_a_direction_is_a_picture_of_its_own() -> void:
	for id: StringName in SQUADS:
		var model: ArtModel = _model(id)
		for dir: int in model.directions(&"hull"):
			var seen: Dictionary[String, String] = {}
			var names: Array[String] = [ArtGen.frame_path(model, &"hull", dir)]
			for frame: int in WALK_FRAMES:
				names.append(ArtGen.frame_path(model, &"walk", dir, frame))
			for frame: int in IDLE_FRAMES:
				names.append(ArtGen.frame_path(model, &"idle", dir, frame))
			for path: String in names:
				var there: bool = FileAccess.file_exists(path)
				assert_bool(there).override_failure_message("%s is missing" % path).is_true()
				if not there:
					continue
				# The first line names the file, so it is left out of the comparison.
				var text: String = FileAccess.get_file_as_string(path).split("\n", true, 1)[1]
				(
					assert_bool(seen.has(text))
					. override_failure_message(
						"%s is the picture of %s" % [path, seen.get(text, "")]
					)
					. is_false()
				)
				seen[text] = path
			assert_int(seen.size()).is_equal(1 + WALK_FRAMES + IDLE_FRAMES)


## A figure's step is what its groups do in a frame: the kind and axis, the angle, the shift and the
## pivot counted from the figure's own place. The three figures of a squad are a frame apart: figure
## `i` does in frame `f` what figure `a` does in frame `f + i`, so a squad never marches in lockstep
## (ADR 0027 section 5). Idle has two frames for three figures, so `a` and `c` would take the same
## pose every frame: `c` looks the other way (its head's angle is the opposite).
func test_the_figures_of_a_frame_are_a_frame_apart_in_their_step() -> void:
	for id: StringName in SQUADS:
		var model: ArtModel = _model(id)
		var groups: Dictionary[StringName, bool] = {}
		for prim: ArtPrim in model.primitives(&"hull"):
			groups[prim.group] = true
		var want: Array[StringName] = []
		for figure: String in FIGURES:
			for limb: String in LIMBS:
				want.append(StringName("%s_%s" % [figure, limb]))
		want.sort()
		var got: Array[StringName] = []
		got.assign(groups.keys())
		got.sort()
		# Every primitive of the hull belongs to a group of a figure: nothing stays behind.
		assert_array(got).override_failure_message(id).is_equal(want)
		for part: StringName in [&"walk", &"idle"]:
			var count: int = model.frames(part)
			for frame: int in count:
				for i: int in FIGURES.size():
					for limb: String in LIMBS:
						var mirrored: bool = part == &"idle" and i == 2 and limb == "head"
						var mine: String = _step(model, part, frame, "%s_%s" % [FIGURES[i], limb])
						var lead: String = _step(
							model, part, (frame + i) % count, "a_" + limb, mirrored
						)
						(
							assert_str(mine)
							. override_failure_message(
								"%s %s f%d figure %s %s" % [id, part, frame, FIGURES[i], limb]
							)
							. is_equal(lead)
						)
		# In an idle frame the heads of a and c look opposite ways.
		for frame: int in IDLE_FRAMES:
			var here: String = _step(model, &"idle", frame, "c_head")
			assert_str(here).override_failure_message(id).is_not_equal(
				_step(model, &"idle", frame, "a_head")
			)
		# In a walk frame the three figures stand in three different steps, and a figure's four
		# frames are four different steps.
		for frame: int in WALK_FRAMES:
			var steps: Dictionary[String, bool] = {}
			for figure: String in FIGURES:
				steps[_legs(model, frame, figure)] = true
			assert_int(steps.size()).override_failure_message("%s f%d" % [id, frame]).is_equal(3)
		for figure: String in FIGURES:
			var cycle: Dictionary[String, bool] = {}
			for frame: int in WALK_FRAMES:
				cycle[_legs(model, frame, figure)] = true
			assert_int(cycle.size()).override_failure_message("%s %s" % [id, figure]).is_equal(4)


func test_the_cast_shadow_is_not_posed_and_the_standing_frames_are_as_without_poses() -> void:
	for id: StringName in SQUADS:
		var model: ArtModel = _model(id)
		var plain: ArtModel = model.duplicate() as ArtModel
		plain.poses = PackedStringArray()
		plain.stride_milli = 0
		var posed: Dictionary[String, String] = ArtGen.build(model)
		var rest: Dictionary[String, String] = ArtGen.build(plain)
		assert_int(model.frames(&"shadow")).is_equal(1)
		for dir: int in model.directions(&"hull"):
			for part: StringName in [&"shadow", &"hull"]:
				var path: String = ArtGen.frame_path(model, part, dir)
				assert_bool(posed.has(path)).override_failure_message(path).is_true()
				assert_bool(posed[path] == rest[path]).override_failure_message(path).is_true()
				assert_bool(posed.has(path.replace(".svg", "_f0.svg"))).is_false()
		# The pose frames add files and nothing else: the item card is the standing figure's.
		assert_bool(posed[ArtGen.icon_path(model)] == rest[ArtGen.icon_path(model)]).is_true()


func test_the_feet_stand_on_the_ground_in_every_pose_frame() -> void:
	for id: StringName in SQUADS:
		var model: ArtModel = _model(id)
		for part: StringName in [&"walk", &"idle"]:
			for frame: int in model.frames(part):
				var low: Dictionary[String, float] = {}
				for prim: ArtPrim in model.frame_prims(part, frame):
					var box: AABB = prim.aabb()
					# Nothing sinks into the ground.
					(
						assert_float(box.position.z)
						. override_failure_message("%s %s f%d %s" % [id, part, frame, prim.line])
						. is_greater_equal(-GROUND_TOLERANCE)
					)
					var figure: String = String(prim.group).split("_")[0]
					low[figure] = minf(low.get(figure, INF), box.position.z)
				# Each figure has a foot on it (a walking figure's other foot may be lifted).
				for figure: String in FIGURES:
					(
						assert_float(low[figure])
						. override_failure_message(
							"%s %s f%d figure %s floats" % [id, part, frame, figure]
						)
						. is_less_equal(GROUND_TOLERANCE)
					)


## The note of the P139 row: a turned face must not sit on a light cut of `ArtRender` (the cuts were
## chosen for box faces at 16 yaws), or the figure would band from one frame to the next.
func test_no_turned_face_of_a_pose_sits_on_a_light_cut() -> void:
	var checked: int = 0
	var crossed: int = 0
	for id: StringName in SQUADS:
		var model: ArtModel = _model(id)
		var standing: Array[ArtPrim] = model.primitives(&"hull")
		for part: StringName in [&"walk", &"idle"]:
			for frame: int in model.frames(part):
				var posed: Array[ArtPrim] = model.frame_prims(part, frame)
				for at: int in posed.size():
					var prim: ArtPrim = posed[at]
					if not _turns(prim):
						continue
					# A face that stood on its side and now faces 0.5 or more up crosses the edge cut:
					# it is not a roof (the next test draws it with a dark edge).
					var rest_faces: Array[ArtMesh.Face] = ArtMesh.faces(standing[at])
					var faces: Array[ArtMesh.Face] = ArtMesh.faces(prim)
					for n: int in faces.size():
						if faces[n].normal.z >= 0.5 and rest_faces[n].normal.z < 0.5:
							crossed += 1
					for dir: int in model.directions(part):
						for face: ArtMesh.Face in ArtMesh.faces(prim):
							var normal: Vector3 = ArtRender.rotate(face.normal, ArtGen.yaw(dir))
							if normal.dot(ArtRender.VIEW) < MIN_FACING:
								continue
							var shade: float = ArtRender.LIGHT_BASE + normal.dot(ArtRender.LIGHT)
							var gap: float = minf(
								absf(shade - ArtRender.CUT_TOP), absf(shade - ArtRender.CUT_LEFT)
							)
							(
								assert_float(gap)
								. override_failure_message(
									(
										"%s %s f%d d%02d %s shade %.4f"
										% [id, part, frame, dir, prim.group, shade]
									)
								)
								. is_greater_equal(CUT_MARGIN)
							)
							checked += 1
	assert_int(checked).is_greater(4000)
	assert_int(crossed).is_equal(48)


## A pose frame is drawn in the order of the standing figure (`ArtRender.render` gets the standing
## primitives to order by). A leg that swings or lifts rises into the boxes of its own torso, and
## the centre-depth fallback of the posed boxes drew it over the waist, the pack or the rifle (a
## dark notch a pixel or two wide that came and went). The polygons of a frame come primitive by
## primitive in the order `ArtRender.draw_order` gives the standing ones, and a leg comes before
## every primitive that stands over it on the ground.
func test_a_pose_frame_is_drawn_in_the_order_of_the_standing_figure() -> void:
	var frames: int = 0
	for id: StringName in SQUADS:
		var model: ArtModel = _model(id)
		var standing: Array[ArtPrim] = model.primitives(&"hull")
		var shots: Dictionary[StringName, ArtGen.Shot] = ArtGen.all_shots(model)
		for part: StringName in [&"walk", &"idle"]:
			var shot: ArtGen.Shot = shots[part]
			for i: int in shot.dirs.size():
				var order: Array[int] = ArtRender.draw_order(standing, ArtGen.yaw(shot.dirs[i]))
				for frame: int in shot.frames:
					var drawn: Array[int] = []
					for poly: ArtRender.Poly in shot.polys[i * shot.frames + frame]:
						if drawn.is_empty() or drawn[-1] != poly.prim:
							drawn.append(poly.prim)
					var label: String = "%s %s d%02d f%d" % [id, part, shot.dirs[i], frame]
					var last: int = -1
					for prim: int in drawn:
						var at: int = order.find(prim)
						assert_bool(at > last).override_failure_message(label).is_true()
						last = at
					for leg: int in drawn:
						if not String(standing[leg].group).contains("_leg"):
							continue
						for body: int in drawn:
							if _is_over(standing[body], standing[leg]):
								(
									assert_bool(drawn.find(leg) < drawn.find(body))
									. override_failure_message(label + " leg over its body")
									. is_true()
								)
					frames += 1
	assert_int(frames).is_equal(4 * 8 * (WALK_FRAMES + IDLE_FRAMES))


## A pose changes the shade of a face and never which edge is light: the thin light edge is for the
## top faces of the standing figure. A leg swung 36 degrees has a side face that faces 0.59 up,
## which the posed normal alone would have taken for a roof (a grey edge on the dark leg in every
## contact frame). A primitive has no more light edges in a pose frame than it has top faces at
## rest.
func test_a_pose_never_gives_a_side_face_the_light_edge() -> void:
	var checked: int = 0
	for id: StringName in SQUADS:
		var model: ArtModel = _model(id)
		var standing: Array[ArtPrim] = model.primitives(&"hull")
		var tops: Array[int] = []
		for prim: ArtPrim in standing:
			var count: int = 0
			for face: ArtMesh.Face in ArtMesh.faces(prim):
				count += int(face.normal.z >= 0.5)
			tops.append(count)
		var shots: Dictionary[StringName, ArtGen.Shot] = ArtGen.all_shots(model)
		for part: StringName in [&"walk", &"idle"]:
			var shot: ArtGen.Shot = shots[part]
			for polys: Array in shot.polys:
				var light: Dictionary[int, int] = {}
				for poly: ArtRender.Poly in polys:
					var prim: ArtPrim = standing[poly.prim]
					if poly.stroke == ArtPalette.edge(model.faction, prim.material, true):
						light[poly.prim] = light.get(poly.prim, 0) + 1
				for at: int in light:
					(
						assert_int(light[at])
						. override_failure_message("%s %s: %s" % [id, part, standing[at].line])
						. is_less_equal(tops[at])
					)
					checked += 1
	assert_int(checked).is_greater(1000)


## Only the walk and idle of a squad are drawn at rest: `frame_rest` gives their standing primitives
## and nothing for any other part, an `anim` element above all, which turns all round and is judged
## as posed (a face of a rotor that turns up is a top; `REST_ORDER` is a whole pose part, so a part
## that must move in front of the body, as a raised rifle will, cannot simply join it).
func test_only_the_walk_and_idle_of_a_squad_have_a_rest() -> void:
	var tower: ArtModel = ArtModel.new()
	tower.prims = PackedStringArray(
		["box hull concrete 0 0 0 1.2 1.2 1.0", "box anim steel 0 0 1.0 0.3 0.1 0.6 group=head"]
	)
	tower.poses = PackedStringArray(["anim 2", "anim 1 head turn z 90 0 0 0"])
	assert_array(tower.frame_rest(&"anim")).is_empty()
	assert_array(tower.frame_rest(&"hull")).is_empty()
	for id: StringName in SQUADS:
		var model: ArtModel = _model(id)
		var hull: Array[ArtPrim] = model.primitives(&"hull")
		for part: StringName in [&"walk", &"idle"]:
			var rest: Array[ArtPrim] = model.frame_rest(part)
			assert_int(rest.size()).override_failure_message(id).is_equal(hull.size())
			for at: int in hull.size():
				assert_str(rest[at].line).is_equal(hull[at].line)
		for part: StringName in [&"hull", ArtModel.SHADOW]:
			assert_array(model.frame_rest(part)).is_empty()


func test_the_pose_frames_use_only_the_palette_of_their_faction() -> void:
	var colour: RegEx = RegEx.create_from_string("#[0-9A-F]{6}")
	for id: StringName in SQUADS:
		var model: ArtModel = _model(id)
		var allowed: Dictionary[String, bool] = {}
		for hex: String in ArtPalette.KEYS[model.faction]:
			allowed[hex] = true
		for level: int in 3:
			for material: StringName in ArtPalette.MATERIALS[model.faction]:
				allowed[ArtPalette.tone(model.faction, material, level)] = true
		for material: StringName in ArtPalette.MATERIALS[model.faction]:
			allowed[ArtPalette.edge(model.faction, material, true)] = true
			allowed[ArtPalette.edge(model.faction, material, false)] = true
		var found: int = 0
		for part: StringName in [&"walk", &"idle"]:
			for dir: int in model.directions(part):
				for frame: int in model.frames(part):
					var text: String = FileAccess.get_file_as_string(
						ArtGen.frame_path(model, part, dir, frame)
					)
					for hit: RegExMatch in colour.search_all(text):
						found += 1
						(
							assert_bool(allowed.has(hit.get_string()))
							. override_failure_message(
								"%s %s d%02d f%d %s" % [id, part, dir, frame, hit.get_string()]
							)
							. is_true()
						)
		assert_int(found).is_greater(1000)


## ADR 0027 section 5: the walk frame advances every quarter of `stride_milli`, so a squad at its
## speed (milli-tiles a tick, 15 ticks a second) walks `speed x 15 / stride_milli` cycles a second.
## Every squad of both rosters of `data/units` (the units that have an infantry model) is held to
## 1.5 to 3.5 of them: slower reads as drifting, faster as a flicker.
func test_every_squad_of_both_rosters_walks_1_5_to_3_5_cycles_a_second_at_its_speed() -> void:
	var infantry: Dictionary[StringName, bool] = {}
	for path: String in ArtGen.model_paths():
		var model: ArtModel = load(path) as ArtModel
		if model.category == &"inf":
			infantry[model.art_id] = true
	var seen: Array[String] = []
	for file: String in DirAccess.get_files_at("res://data/units"):
		var unit: UnitDef = load("res://data/units/" + ArtGen.tres_name(file)) as UnitDef
		if unit == null or not infantry.has(unit.type_id):
			continue
		seen.append(String(unit.type_id))
		var sheet: IsoSheetDef = _index.sheet(unit.type_id)
		assert_int(unit.speed).override_failure_message(unit.type_id).is_greater(0)
		assert_int(sheet.stride_milli).override_failure_message(unit.type_id).is_greater(0)
		# The view floors `stride_milli / 4` (P142): a stride that is not a multiple of 4 would
		# make the four walk frames unequal.
		assert_int(sheet.stride_milli % 4).override_failure_message(unit.type_id).is_equal(0)
		var cycles: float = float(unit.speed * Sim.TICK_RATE) / float(sheet.stride_milli)
		(
			assert_float(cycles)
			. override_failure_message(
				(
					"%s walks %.2f cycles a second (speed %d, stride %d)"
					% [unit.type_id, cycles, unit.speed, sheet.stride_milli]
				)
			)
			. is_between(CYCLES_PER_SECOND.x, CYCLES_PER_SECOND.y)
		)
	seen.sort()
	assert_array(seen).is_equal(["renew_rifle", "renew_rocket", "rifle_squad", "rocket_squad"])


func _model(id: StringName) -> ArtModel:
	var faction: String = "renew" if String(id).begins_with("renew_") else "fossil"
	return load("res://assets/art/models/%s/%s.tres" % [faction, id]) as ArtModel


## What the moves of `group` do in a frame, in order: kind and axis, angle (`mirror` takes the
## opposite of it), shift and pivot, the pivot counted from the figure's rest position, so a figure
## turned about a wrong point is not the figure it should be.
func _step(
	model: ArtModel, part: StringName, frame: int, group: String, mirror: bool = false
) -> String:
	var found: PackedStringArray = PackedStringArray()
	var origin: Vector3 = _origin(model, group.split("_")[0])
	for move: ArtMove in model.pose_moves(part, frame):
		if move.group != StringName(group):
			continue
		var pivot: Vector3 = (move.pivot - origin) if move.axis >= 0 else Vector3.ZERO
		found.append(
			(
				"%d %s %s %s"
				% [
					move.axis,
					_fmt(-move.degrees if mirror else move.degrees),
					_fmt3(move.shift),
					_fmt3(pivot)
				]
			)
		)
	return ";".join(found)


## The rest position of a figure on the ground: the centre of the first primitive of its body.
func _origin(model: ArtModel, figure: String) -> Vector3:
	for prim: ArtPrim in model.primitives(&"hull"):
		if prim.group == StringName(figure + "_body"):
			return Vector3(prim.centre.x, prim.centre.y, 0.0)
	return Vector3.ZERO


## A number to four decimals, so that rounding noise and a negative zero compare equal.
func _fmt(value: float) -> String:
	return "%.4f" % (0.0 if absf(value) < 0.00005 else value)


func _fmt3(vector: Vector3) -> String:
	return "%s %s %s" % [_fmt(vector.x), _fmt(vector.y), _fmt(vector.z)]


## The two legs of a figure in a walk frame.
func _legs(model: ArtModel, frame: int, figure: String) -> String:
	return (
		"%s|%s"
		% [
			_step(model, &"walk", frame, figure + "_legl"),
			_step(model, &"walk", frame, figure + "_legr")
		]
	)


## Whether `above` stands over `below` at rest: it starts at the top of `below` or higher, and their
## places on the ground overlap.
func _is_over(above: ArtPrim, below: ArtPrim) -> bool:
	var up: AABB = above.aabb()
	var down: AABB = below.aabb()
	var apart: bool = up.position.x >= down.end.x or down.position.x >= up.end.x
	apart = apart or up.position.y >= down.end.y or down.position.y >= up.end.y
	return up.position.z >= down.end.z - 0.0001 and not apart


## Whether a pose frame turns the primitive (a shift keeps every shade it had).
func _turns(prim: ArtPrim) -> bool:
	for move: ArtMove in prim.moves:
		if move.axis >= 0:
			return true
	return false
