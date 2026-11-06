extends GdUnitTestSuite
## The Derrick League's eight buildings in three damage stages (plan row P158a, ADR 0029 sections 3
## to 5 and 11): each has `dmg1` (SKADET) and `dmg2` (KRITISK) from its model, no ruin, 2 to 4 typed
## damage points, `anim_kritisk` where it has an `anim`, the emitter groups that a stage breaks, and
## the key shares of the bands of P163. The intact body, its shadow and its card are as they were.

const IDS: Array[StringName] = [
	&"barracks",
	&"defence_turret",
	&"fossil_radar",
	&"fossil_strike",
	&"headquarters",
	&"power_plant",
	&"refinery",
	&"vehicle_factory",
]
const MODELS: String = "res://assets/art/models/fossil/%s.tres"
## SKADET changes the top of the body (ADR 0029 section 4 asks for its top half). Where the team
## colour of a building sits low (the Redoubt's band, the Rigworks' crane beam, the Vehicle Works'
## lintel, the Deep Bore's ring girders and the Oil Works' column ring) the key share of
## SKADET needs a change that reaches further down, so the bound is 0.80 of the rows (the Redoubt
## is at 76 %); the Barracks, the Signal Mast and the Turbine Hall keep to the half.
const SKADET_MAX: float = 0.80
const HALF: Array[StringName] = [&"barracks", &"fossil_radar", &"power_plant"]
const FOOT_TOP: float = 0.06  ## The foot slab is 0.06 tile tall.
const KRITISK_FOOT_ROWS: int = 4  ## The overlap a patch needs above the foot of the body.
## The first stage that moves, turns or hides the group of each ambient emitter (0: never), parallel
## to the sheet's emitters, which list the ambient ones first.
const QUIET: Dictionary[StringName, Array] = {
	&"headquarters": [1, 0, 0, 0],
	&"power_plant": [1, 0, 0, 0, 0],
	&"refinery": [2, 1, 0, 0, 0],
}
## Which buildings with an `anim` keep it running in KRITISK (ADR 0029 section 3): the Turbine
## Hall's fans stand on their platform, the Signal Mast and the Deep Bore have fallen.
const ANIM_KRITISK: Dictionary[StringName, bool] = {
	&"fossil_radar": false, &"fossil_strike": false, &"power_plant": true
}
const SUPPORT: String = "res://tests/art/artgen_v5_support.gd"
const HOW_TO_PLAY: String = "res://docs/HOW_TO_PLAY.md"


func test_each_building_has_both_patches_from_its_model_and_no_ruin() -> void:
	var index: IsoIndex = load(IsoIndex.PATH) as IsoIndex
	for id: StringName in IDS:
		var model: ArtModel = load(MODELS % id) as ArtModel
		(
			assert_array(Array(model.problems()))
			. override_failure_message("%s: %s" % [id, "; ".join(model.problems())])
			. is_empty()
		)
		assert_array(model.damage_parts()).is_equal([&"dmg1", &"dmg2"])
		var sheet: IsoSheetDef = index.sheet(id)
		var parts: Array = Array(sheet.parts)
		assert_array(parts).override_failure_message(String(id)).contains(["dmg1", "dmg2"])
		assert_array(parts).override_failure_message(String(id)).not_contains(["ruin"])
		assert_str(parts[-1]).is_equal("shadow")
		for part: String in ["dmg1", "dmg2"]:
			var file: String = ArtGen.frame_path(model, StringName(part), -1)
			assert_bool(FileAccess.file_exists(file)).override_failure_message(file).is_true()
			assert_int(FileAccess.get_file_as_string(file).length()).is_less(28 * 1024)


func test_the_cuts_run_down_the_body_and_skadet_stays_in_the_upper_part() -> void:
	var index: IsoIndex = load(IsoIndex.PATH) as IsoIndex
	for id: StringName in IDS:
		var sheet: IsoSheetDef = index.sheet(id)
		var rows: int = sheet.frame_size(&"hull").y
		assert_int(sheet.cuts.size()).override_failure_message(String(id)).is_equal(2)
		var skadet: int = sheet.cuts[0]
		var kritisk: int = sheet.cuts[1]
		assert_int(skadet).override_failure_message(String(id)).is_greater(0)
		# KRITISK changes more than SKADET and stops just above the foot, never at it.
		assert_int(kritisk).override_failure_message(String(id)).is_greater(skadet)
		assert_int(kritisk + KRITISK_FOOT_ROWS).override_failure_message(String(id)).is_less_equal(
			rows
		)
		assert_float(float(skadet) / rows).override_failure_message(String(id)).is_less_equal(
			SKADET_MAX
		)
		if id in HALF:
			assert_int(skadet * 2).override_failure_message(String(id)).is_less_equal(rows)


## Nothing of KRITISK but the foot slab stands on the ground: no `damage=2` primitive and no moved
## one reaches below the top of the foot slab (an independent check; the generator's own refusal is
## the cut's).
func test_nothing_of_kritisk_lies_on_the_ground_but_the_foot() -> void:
	for id: StringName in IDS:
		var model: ArtModel = load(MODELS % id) as ArtModel
		for prim: ArtPrim in model.damage_prims(2):
			if prim.index == 0:  # The foot slab.
				continue
			var low: float = prim.aabb().position.z
			if prim.shape == &"rod":
				low = minf(prim.place(prim.rod_a).z, prim.place(prim.rod_b).z)
			(
				assert_float(low)
				. override_failure_message("%s: %s lies on the ground" % [id, prim.line])
				. is_greater_equal(FOOT_TOP - 0.001)
			)


func test_each_building_has_two_to_four_typed_damage_points_and_the_defence_a_second() -> void:
	var index: IsoIndex = load(IsoIndex.PATH) as IsoIndex
	for id: StringName in IDS:
		var sheet: IsoSheetDef = index.sheet(id)
		var typed: int = 0
		for kind: String in sheet.emitters:
			typed += 1 if StringName(kind) in ArtModel.DAMAGE_POINTS else 0
		assert_int(typed).override_failure_message(String(id)).is_between(2, 4)
		assert_int(sheet.emitter_points.size()).is_equal(sheet.emitters.size())
	var defence: IsoSheetDef = index.sheet(&"defence_turret")
	assert_array(Array(defence.emitters)).is_equal(["damage", "dmg_spark"])
	# The refinery's tanks burn as gas jets, the others as fire and sparks.
	var refinery: IsoSheetDef = index.sheet(&"refinery")
	assert_int(Array(refinery.emitters).count("dmg_gas")).is_equal(2)


func test_a_building_with_an_anim_says_whether_it_runs_in_kritisk() -> void:
	var index: IsoIndex = load(IsoIndex.PATH) as IsoIndex
	for id: StringName in IDS:
		var model: ArtModel = load(MODELS % id) as ArtModel
		var sheet: IsoSheetDef = index.sheet(id)
		var animated: bool = sheet.has_part(&"anim")
		assert_bool(ANIM_KRITISK.has(id)).override_failure_message(String(id)).is_equal(animated)
		if animated:
			assert_str(model.anim_kritisk).is_equal(&"run" if ANIM_KRITISK[id] else &"hide")
			assert_bool(sheet.anim_kritisk).override_failure_message(String(id)).is_equal(
				ANIM_KRITISK[id]
			)
		else:
			assert_str(model.anim_kritisk).is_equal(&"")
			assert_bool(sheet.anim_kritisk).is_false()


func test_the_ambient_emitters_of_a_chimney_a_flare_and_a_stack_name_their_groups() -> void:
	var index: IsoIndex = load(IsoIndex.PATH) as IsoIndex
	for id: StringName in IDS:
		var sheet: IsoSheetDef = index.sheet(id)
		var want: Array = QUIET.get(id, [])
		assert_array(Array(sheet.emitter_quiet)).override_failure_message(String(id)).is_equal(want)
	var model: ArtModel = load(MODELS % &"refinery") as ArtModel
	var groups: Array[String] = []
	for emitter: Array in model.emitter_list():
		groups.append(String(emitter[2]))
	assert_array(groups).is_equal(["coltop", "flare", "", "", ""])


func test_the_key_share_of_each_stage_is_in_its_band() -> void:
	var support: GDScript = load(SUPPORT) as GDScript
	for id: StringName in IDS:
		var model: ArtModel = load(MODELS % id) as ArtModel
		var problems: PackedStringArray = support.share_problems(model)
		(
			assert_array(Array(problems))
			. override_failure_message("%s: %s" % [id, "; ".join(problems)])
			. is_empty()
		)


func test_the_damage_changes_only_the_patches_the_body_shadow_and_card_are_as_before() -> void:
	for id: StringName in IDS:
		var model: ArtModel = load(MODELS % id) as ArtModel
		var plain: ArtModel = model.duplicate() as ArtModel
		var kept: PackedStringArray = PackedStringArray()
		for line: String in model.prims:
			if not line.contains("damage="):
				kept.append(line)
		plain.prims = kept
		plain.poses = PackedStringArray(
			Array(model.poses).filter(
				func(line: String) -> bool: return not line.begins_with("dmg")
			)
		)
		plain.anim_kritisk = &""
		var with: Dictionary[String, String] = ArtGen.build(model)
		var without: Dictionary[String, String] = ArtGen.build(plain)
		for path: String in [
			ArtGen.frame_path(model, &"hull", -1),
			ArtGen.frame_path(model, ArtModel.SHADOW, -1),
			ArtGen.icon_path(model),
		]:
			assert_bool(with.has(path)).override_failure_message(path).is_true()
			assert_str(with[path]).override_failure_message(path).is_equal(without[path])
		# The anim frames are the intact ones too.
		for path: String in without:
			if path.contains("_anim_f"):
				assert_str(with[path]).override_failure_message(path).is_equal(without[path])


## ADR 0029 section 4: every building has rebar or beams and dark rooms in KRITISK and something in
## SKADET, and every rod bends (a straight rod would be a plain stick, not bent steel).
func test_the_stages_follow_the_material_rules() -> void:
	for id: StringName in IDS:
		var model: ArtModel = load(MODELS % id) as ArtModel
		var interior: int = 0
		var rods: int = 0
		var stage1: int = 0
		for line: String in model.prims:
			if line.contains("damage=2"):
				interior += 1 if line.contains(" interior ") else 0
				rods += (
					1
					if (
						line.begins_with("rod ")
						and (line.contains(" rebar ") or line.contains(" beam "))
					)
					else 0
				)
			if line.contains("damage=1"):
				stage1 += 1
		assert_int(interior).override_failure_message("%s: dark rooms" % id).is_greater(0)
		assert_int(rods).override_failure_message("%s: rebar or beams" % id).is_greater(0)
		assert_int(stage1).override_failure_message("%s: SKADET" % id).is_greater(0)
		for rod: String in model.prims:
			if rod.begins_with("rod "):
				assert_bool(rod.contains("bend=")).override_failure_message(rod).is_true()
	# The barracks: the team paint burns off from the top down, the ridge cap in SKADET, the eave
	# band's rear in KRITISK.
	var barracks: ArtModel = load(MODELS % &"barracks") as ArtModel
	assert_array(_charred(barracks, &"dmg1")).is_equal([&"p1r"])
	assert_array(_charred(barracks, &"dmg2")).contains([&"k2b"])
	# The refinery: the flare is never hidden in pieces, it is replaced by one bent iron rod from its
	# base at each stage; the pipe run is cut at the break; the sphere is torn open in plates.
	var refinery: ArtModel = load(MODELS % &"refinery") as ArtModel
	for part: StringName in [&"dmg1", &"dmg2"]:
		var hidden: Array[StringName] = []
		for move: ArtMove in refinery.pose_moves(part, 0):
			if move.kind == &"hide":
				hidden.append(move.group)
		assert_array(hidden).override_failure_message("%s hides the flare" % part).contains(
			[&"flare"]
		)
	for tag: String in ["damage=1", "damage=2"]:
		var flare_rods: int = 0
		for line: String in refinery.prims:
			flare_rods += (
				1
				if (
					line.begins_with("rod hull iron 0.1 -1.25 0.06 ")
					and line.contains("bend=")
					and line.contains(tag)
				)
				else 0
			)
		assert_int(flare_rods).override_failure_message("flare rod at %s" % tag).is_equal(1)
	var petals: int = 0
	for line: String in refinery.prims:
		petals += 1 if line.begins_with("petals ") else 0
	assert_int(petals).is_equal(1)
	# The headquarters' chimney snaps and topples: a group that turns about its break in KRITISK.
	var works: ArtModel = load(MODELS % &"headquarters") as ArtModel
	var turned: Array[StringName] = []
	for move: ArtMove in works.pose_moves(&"dmg2", 0):
		if move.kind == &"turn":
			turned.append(move.group)
	assert_array(turned).contains([&"chtop", &"chmid"])


func test_the_how_to_play_row_says_what_a_damaged_building_looks_like() -> void:
	var text: String = FileAccess.get_file_as_string(HOW_TO_PLAY)
	(
		assert_str(text)
		. contains(
			(
				"| A building is badly damaged | Under two thirds of its health a building shows blown "
				+ "windows, soot and a broken corner, mast or wing; under a third part of it has "
				+ "collapsed, you can see inside, and it burns from inside. A building under "
				+ "construction does not show it. An enemy building shows its damage only while you see "
				+ "it; its dimmed picture in the fog shows the damage you last saw "
				+ "(`building_stage_percent` in `data/life_settings.tres`)."
			)
		)
	)


## The groups a stage chars, in order.
func _charred(model: ArtModel, part: StringName) -> Array[StringName]:
	var found: Array[StringName] = []
	for move: ArtMove in model.pose_moves(part, 0):
		if move.kind == &"char":
			found.append(move.group)
	return found
