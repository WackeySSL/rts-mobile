extends GdUnitTestSuite
## Generator v5a, points and sheets (plan row P163, ADR 0029 sections 3 and 5) on crafted buildings:
## the counts of the damage and ruin points, the ink test for points and emitters, `anim_kritisk`,
## an emitter's `group=` and `emitter_quiet`, the odd-canvas refusal, the vehicles' and squads'
## counts, v4 models that stay as they were, and the key-share raster test.

const Support = preload("res://tests/art/artgen_v5_support.gd")
## A mast that dmg2 raises high above the body, and a stack that dmg2 hides, for the ink tests.
const MAST: String = "box hull iron 0.0 -0.6 1.0 0.1 0.1 1.2 group=mast damage=2"
const TALL_STACK: String = "box hull rust 0.5 -0.2 1.0 0.2 0.2 1.4 group=tall"


func _with(emitters: Array) -> ArtModel:
	return Support.building([], Support.POSES, emitters)


func _problems(model: ArtModel) -> String:
	return "\n".join(model.problems())


func _damage(count: int) -> Array[String]:
	var all: Array[String] = [
		"damage 0.2 0.2 1.0",
		"dmg_spark -0.2 0.3 1.0",
		"dmg_gas 0.0 0.0 1.0",
		"damage -0.3 0.0 1.0",
		"dmg_spark 0.0 0.3 1.0",
		"ruin 0 0 0.12",
	]
	var found: Array[String] = []
	for i: int in count:
		found.append(all[i])
	found.append(all[5])
	return found


func test_two_to_four_typed_damage_points_pass_and_one_and_five_are_refused() -> void:
	for count: int in [2, 3, 4]:
		var model: ArtModel = _with(_damage(count))
		assert_str(_problems(model)).override_failure_message(str(count)).is_equal("")
	for count: int in [0, 1, 5]:
		var model: ArtModel = _with(_damage(count))
		assert_str(_problems(model)).override_failure_message(str(count)).contains(
			"2 to 4 damage points"
		)
	# Each type counts.
	for kinds: Array in [["damage", "damage"], ["dmg_gas", "dmg_spark"], ["damage", "dmg_gas"]]:
		var pair: Array[String] = ["%s 0.2 0.2 1.0" % kinds[0], "%s -0.2 0.3 1.0" % kinds[1]]
		pair.append("ruin 0 0 0.12")
		assert_str(_problems(_with(pair))).is_equal("")


func test_one_to_three_ruin_points_with_ink_pass_and_zero_four_and_bare_ground_are_refused(
) -> void:
	var damage: Array[String] = ["damage 0.2 0.2 1.0", "dmg_spark -0.2 0.3 1.0"]
	var spots: Array[String] = ["ruin 0 0 0.12", "ruin 0.3 0.3 0.12", "ruin -0.3 0.2 0.12"]
	for count: int in [1, 2, 3]:
		assert_str(_problems(_with(damage + spots.slice(0, count)))).is_equal("")
	assert_str(_problems(_with(damage))).contains("1 to 3 ruin points")
	var four: Array = damage + spots + ["ruin 0.1 0.1 0.12"]
	assert_str(_problems(_with(four))).contains("1 to 3 ruin points")
	# A ruin point over empty ground has no ink in the ruin.
	var bare: Array = damage + ["ruin 0 0 0.12", "ruin 0.9 -0.9 0.0"]
	assert_str(_problems(_with(bare))).contains("ruin point (0.9, -0.9, 0.0) has no ink under it")
	# A ruin point without a ruin is refused.
	var no_ruin: ArtModel = Support.with_prims(
		[
			"box hull concrete 0 0 0 1.6 1.6 1.0 group=body",
			"box hull steel 0 0 1 0.2 0.2 0.2 group=c"
		],
		["dmg2 0 c hide"],
		damage + ["ruin 0 0 0.12"]
	)
	assert_str(_problems(no_ruin)).contains("1 to 3 ruin points, no ruin none")


func test_a_point_below_the_cut_or_without_ink_in_dmg1_or_dmg2_is_refused() -> void:
	var ruin: String = "ruin 0 0 0.12"
	# Below dmg1's cut: on the intact body, off any SKADET break.
	var low: Array[String] = ["damage 0.2 0.2 1.0", "damage 0.5 0.5 0.05", ruin]
	assert_str(_problems(_with(low))).contains("below dmg1's cut")
	# High in the air: no ink in either stage.
	var air: Array[String] = ["damage 0.2 0.2 1.0", "dmg_gas 0.2 0.2 3.0", ruin]
	var problems: String = _problems(_with(air))
	assert_str(problems).contains("no ink under it at stage 1")
	assert_str(problems).contains("no ink under it at stage 2")
	# Ink in dmg1 but not in dmg2: the tall stack is hidden by dmg2.
	var stack_model: ArtModel = Support.building(
		[TALL_STACK],
		Support.POSES + ["dmg2 0 tall hide", "ruin 0 tall hide"],
		["damage 0.2 0.2 1.0", "dmg_spark 0.5 -0.2 2.2", ruin]
	)
	var stack: String = _problems(stack_model)
	assert_str(stack).contains("no ink under it at stage 2")
	assert_str(stack).not_contains("at stage 1")
	# Ink in dmg2 but not in dmg1: the mast is drawn from dmg2 on.
	var mast_model: ArtModel = Support.building(
		[MAST],
		Support.POSES + ["ruin 0 mast hide"],
		["damage 0.2 0.2 1.0", "dmg_gas 0.0 -0.6 2.0", ruin]
	)
	var mast: String = _problems(mast_model)
	assert_str(mast).contains("no ink under it at stage 1")
	assert_str(mast).not_contains("at stage 2")
	# A point with ink in both stages, above the cut, passes.
	assert_str(_problems(_with(["damage 0.2 0.2 1.0", "dmg_gas -0.2 0.3 1.0", ruin]))).is_equal("")


func test_an_ambient_emitter_needs_ink_at_each_stage_it_emits_at() -> void:
	var points: Array[String] = ["damage 0.2 0.2 1.0", "dmg_spark -0.2 0.3 1.0", "ruin 0 0 0.12"]
	# On the stack's top, which dmg2 hides: refused unless it names the group.
	var bare: ArtModel = Support.building(
		[TALL_STACK],
		Support.POSES + ["dmg2 0 tall hide", "ruin 0 tall hide"],
		points + ["smoke 0.5 -0.2 2.2"]
	)
	assert_str(_problems(bare)).contains(
		"smoke point (0.5, -0.2, 2.2) has no ink under it at stage 2"
	)
	var named: ArtModel = Support.building(
		[TALL_STACK],
		Support.POSES + ["dmg2 0 tall hide", "ruin 0 tall hide"],
		points + ["smoke 0.5 -0.2 2.2 group=tall"]
	)
	assert_str(_problems(named)).is_equal("")
	# A group that dmg1 moves is quiet from stage 1, and needs ink at no stage.
	var moved: ArtModel = _with(points + ["steam -0.4 -0.4 3.5 group=tower"])
	assert_str(_problems(moved)).is_equal("")
	# A group no hull primitive has is refused.
	assert_str(_problems(_with(points + ["smoke 0 0 1 group=nothing"]))).contains(
		"no hull primitive"
	)
	# Only the ambient kinds take a group.
	assert_int(_with(points + ["damage 0 0 1 group=tower"]).emitter_list().size()).is_equal(3)
	assert_str(_problems(_with(points + ["damage 0 0 1 group=tower"]))).contains("an emitter is")


func test_emitter_quiet_is_the_first_stage_that_moves_or_hides_the_group() -> void:
	var points: Array[String] = ["damage 0.2 0.2 1.0", "dmg_spark -0.2 0.3 1.0", "ruin 0 0 0.12"]
	var emitters: Array = (
		points
		+ [
			"smoke 0.4 0.4 1.4 group=stack",  # dmg2 hides it, dmg1 only chars it
			"steam -0.4 -0.4 3.5 group=tower",  # dmg1 shifts it
			"flame 0.2 0.0 1.0",  # no group
			"smoke 0.0 0.0 1.0 group=body",  # only the ruin hides it
		]
	)
	var model: ArtModel = _with(emitters)
	assert_str(_problems(model)).is_equal("")
	assert_int(ArtDamage.quiet(model, &"stack")).is_equal(2)
	assert_int(ArtDamage.quiet(model, &"tower")).is_equal(1)
	assert_int(ArtDamage.quiet(model, &"")).is_equal(0)
	assert_int(ArtDamage.quiet(model, &"body")).is_equal(0)
	var sheet: IsoSheetDef = ArtSheet.of(model, ArtGen.all_shots(model))
	assert_array(Array(sheet.emitters)).is_equal(
		["damage", "dmg_spark", "ruin", "smoke", "steam", "flame", "smoke"]
	)
	assert_array(Array(sheet.emitter_quiet)).is_equal([0, 0, 0, 2, 1, 0, 0])
	assert_str(ArtSheet.text(sheet)).contains(
		"emitter_quiet = PackedInt32Array(0, 0, 0, 2, 1, 0, 0)"
	)
	# A sheet whose emitters never go quiet writes no `emitter_quiet`.
	var calm: ArtModel = _with(points + ["flame 0.2 0.0 1.0"])
	var calm_sheet: IsoSheetDef = ArtSheet.of(calm, ArtGen.all_shots(calm))
	assert_int(calm_sheet.emitter_quiet.size()).is_equal(0)
	assert_str(ArtSheet.text(calm_sheet)).not_contains("emitter_quiet")
	# And the new fields survive a loaded sheet.
	var path: String = "user://p163_roundtrip_sheet.tres"
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(ArtSheet.text(sheet))
	file.close()
	var loaded: IsoSheetDef = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_array(Array(loaded.emitter_quiet)).is_equal([0, 0, 0, 2, 1, 0, 0])
	DirAccess.remove_absolute(path)


func test_anim_kritisk_run_is_written_and_refused_without_ink_under_the_anim() -> void:
	var model: ArtModel = Support.building()
	model.anim_kritisk = &"run"
	assert_str(_problems(model)).is_equal("")  # the tower still stands in dmg2
	var sheet: IsoSheetDef = ArtSheet.of(model, ArtGen.all_shots(model))
	assert_bool(sheet.anim_kritisk).is_true()
	assert_str(ArtSheet.text(sheet)).contains("anim_kritisk = true")
	# `hide` is written as false, which a sheet leaves out.
	model.anim_kritisk = &"hide"
	assert_str(_problems(model)).is_equal("")
	var hidden: IsoSheetDef = ArtSheet.of(model, ArtGen.all_shots(model))
	assert_bool(hidden.anim_kritisk).is_false()
	assert_str(ArtSheet.text(hidden)).not_contains("anim_kritisk")
	# dmg2 drops the tower that carries the beacon: `run` is refused, `hide` is the answer.
	var fallen: Array[String] = Support.POSES.duplicate()
	fallen[fallen.find("dmg2 0 tower turn y 12 -0.4 -0.4 1.0")] = "dmg2 0 tower hide"
	var carried: ArtModel = Support.building([], fallen)
	carried.anim_kritisk = &"run"
	assert_str(_problems(carried)).contains("nothing stands under the anim in dmg2")
	carried.anim_kritisk = &"hide"
	assert_str(_problems(carried)).is_equal("")
	# Only run or hide, only for a building with an anim and a dmg2.
	carried.anim_kritisk = &"walk"
	assert_str(_problems(carried)).contains("run or hide")
	var plain: ArtModel = Support.with_prims(
		["box hull concrete 0 0 0 1.6 1.6 1.0 group=g"], ["dmg2 0 g shift 0 0 -0.1"], []
	)
	plain.anim_kritisk = &"run"
	assert_str(_problems(plain)).contains("is for a building with an anim and a dmg2")


func test_an_odd_body_canvas_with_damage_parts_is_refused() -> void:
	var model: ArtModel = Support.building()
	var body: ArtGen.Layout = ArtGen.all_shots(model)[&"hull"].layout
	assert_int(body.size.y % 2).is_equal(0)  # the generator's own canvases are even
	assert_array(Array(ArtDamage.canvas_problems(model, body))).is_empty()
	var odd: ArtGen.Layout = ArtGen.Layout.new()
	odd.size = Vector2i(256, 101)
	var problems: PackedStringArray = ArtDamage.canvas_problems(model, odd)
	assert_int(problems.size()).is_equal(1)
	assert_str(problems[0]).contains("101 rows, odd")


func test_vehicles_and_squads_keep_their_counts() -> void:
	var tank: ArtModel = ArtModel.new()
	tank.art_id = &"tank"
	tank.faction = &"fossil"
	tank.category = &"veh"
	tank.prims = PackedStringArray(["box hull steel 0 0 0 1.2 0.8 0.4"])
	tank.emitters = PackedStringArray(["damage 0 0 0.4", "hang 0 0.3 0.2"])
	assert_array(Array(tank.problems())).is_empty()
	tank.emitters = PackedStringArray(["damage 0 0 0.4", "damage 0.1 0 0.4"])
	assert_str(_problems(tank)).contains("a vehicle has one damage point")
	tank.emitters = PackedStringArray(["damage 0 0 0.4", "dmg_gas 0.1 0 0.4"])
	assert_str(_problems(tank)).contains("are a building's")
	tank.emitters = PackedStringArray(["ruin 0 0 0.4"])
	assert_str(_problems(tank)).contains("are a building's")
	var squad: ArtModel = ArtModel.new()
	squad.art_id = &"squad"
	squad.faction = &"fossil"
	squad.category = &"inf"
	squad.prims = PackedStringArray(["box hull steel 0 0 0 0.3 0.3 0.4"])
	squad.emitters = PackedStringArray(["damage 0 0 0.4"])
	assert_str(_problems(squad)).contains("damage and hang points are for buildings and vehicles")
	# A v4 building (no ruin, no typed point) keeps its rule: two damage points at most.
	var v4: ArtModel = (
		Support
		. with_prims(
			[
				"box hull concrete 0 0 0 1.6 1.6 1.0 group=g",
				"box hull steel 0.2 0.2 1.0 0.3 0.3 0.3 group=cap",
			],
			["dmg1 0 cap shift 0 0 -0.05", "dmg2 0 cap hide"],
			["damage 0.2 0.2 1.0"]
		)
	)
	assert_str(_problems(v4)).is_equal("")
	v4.emitters = PackedStringArray(["damage 0 0 1", "damage 0.1 0 1", "damage 0.2 0 1"])
	assert_str(_problems(v4)).contains("a building two at most")
	var sheet: IsoSheetDef = ArtSheet.of(v4, ArtGen.all_shots(v4))
	assert_str(ArtSheet.text(sheet)).not_contains("emitter_quiet")
	assert_str(ArtSheet.text(sheet)).not_contains("anim_kritisk")


func test_the_key_share_passes_the_crafted_model_and_fails_one_outside_the_bands() -> void:
	var model: ArtModel = Support.building()
	assert_array(Array(model.problems())).is_empty()
	var shares: Array[float] = []
	for stage: int in range(1, 4):
		shares.append(Support.key_share(model, stage))
		var band: Vector2 = Support.SHARE_BANDS[stage - 1]
		assert_float(shares[stage - 1]).override_failure_message("stage %d" % stage).is_between(
			band.x, band.y
		)
	assert_array(Array(Support.share_problems(model))).is_empty()
	# The bands are ADR 0029's.
	assert_array(Support.SHARE_BANDS).is_equal(
		[Vector2(0.55, 0.85), Vector2(0.20, 0.50), Vector2(0.01, 0.20)]
	)
	# SKADET that keeps all its team paint (100 %), and a ruin without a remnant (0 %), fail.
	var poses: Array[String] = Support.POSES.duplicate()
	poses.erase("dmg1 0 t1 char 100")
	var prims: Array[String] = Support.PRIMS.duplicate()
	prims.erase("box hull team 0.2 0.85 0 0.15 0.1 0.15 damage=3")
	var wrong: ArtModel = Support.with_prims(prims, poses, Support.EMITTERS)
	wrong.anim_ms = 100
	assert_array(Array(wrong.problems())).is_empty()
	var found: String = "\n".join(Support.share_problems(wrong))
	assert_str(found).contains("stage 1")
	assert_str(found).contains("stage 3")
	assert_str(found).not_contains("stage 2")
