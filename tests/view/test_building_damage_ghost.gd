extends "res://tests/view/support/damage_suite.gd"
## Ghosts at their remembered stage (plan P159, ADR 0028 section 5, ADR 0029 sections 9 and 12):
## the dimmed picture of an enemy building out of sight is the trimmed body and a `Damage` child
## before the `Anim`, at the stage the player last saw. Fixtures: support/damage_suite.gd;
## building 2 is the enemy's, standing on tiles (14, 14) to (15, 15).

const GhostRig: GDScript = preload("res://tests/view/support/ghost_rig.gd")
const ENEMY: int = 2

var _ghosts: GhostMemoryLayer


## The enemy building seen at `percent` of its hp, then out of sight and remembered.
func _remember(percent: int, extras: Dictionary = {}, anim_runs: bool = true) -> void:
	var given: Dictionary = extras.duplicate()
	given["anim_kritisk"] = anim_runs
	_open(_pair(), given, 1.0, false)
	Dmg.Rig.see(_runner.snapshot, 1, [Vector2i(14, 14)])
	_layer._process(0.0)
	Dmg.hit(_runner, ENEMY, percent)  # The sim's fog is not the fixture's: the next lines write it.
	Dmg.Rig.see(_runner.snapshot, 1, [Vector2i(14, 14)])
	_runner.ticked.emit(_runner.snapshot.tick)
	_ghost_layer()
	_look_away()


func _ghost_layer() -> void:
	_ghosts = auto_free(GhostMemoryLayer.new())
	_ghosts.runner = _runner
	_ghosts.world_sort = _sort
	_ghosts.building_layer = _layer
	add_child(_ghosts)


func _look_away() -> void:
	var snap: MatchSnapshot = _runner.snapshot
	var cell: int = GhostRig.centre_cell(snap, Vector2i(14, 14), 2, 2)
	GhostRig.remember(snap, 1, [GhostRig.record(ENEMY, Dmg.ART_ID, 2, cell)])
	Dmg.Rig.see(snap, 1, [])
	_ghosts._process(0.0)


func test_a_ghost_shows_the_stage_last_seen_trimmed_with_its_patch_child_first() -> void:
	for stage: int in [1, 2]:
		_remember(66 if stage == 1 else 10, {"anim": true})
		var ghost: Sprite2D = _ghosts.ghost(ENEMY)
		assert_object(ghost).is_not_null()
		var full: Rect2i = _region(&"hull")
		var cut: int = IsoAtlas.body_cut_row(Dmg.CUTS[stage - 1], Dmg.BODY_PX, full.size.y)
		assert_that(ghost.region_rect).is_equal(
			Rect2(full.position.x, full.position.y + cut, full.size.x, full.size.y - cut)
		)
		assert_bool(ghost.region_filter_clip_enabled).is_true()
		var patch: Sprite2D = ghost.get_node("Damage")
		var anim: Sprite2D = ghost.get_node("Anim")
		assert_int(patch.get_index()).is_less(anim.get_index())  # Under the moving element.
		assert_bool(patch.visible).is_true()
		assert_that(patch.region_rect).is_equal(Rect2(_region(StringName("dmg%d" % stage))))
		# The child's scale is body texels over patch texels, as the ghost's Anim is.
		var part: StringName = StringName("dmg%d" % stage)
		var body_texels: Vector2 = _sort.texels(_def, &"hull")
		var patch_texels: Vector2 = _sort.texels(_def, part)
		assert_vector(patch.scale).is_equal_approx(body_texels / patch_texels, Vector2(1e-4, 1e-4))
		assert_vector(patch.offset).is_equal_approx(
			-Vector2(_def.origin(part)) * patch_texels, Vector2(1e-3, 1e-3)
		)
		# The rest frame is on the Anim, not on the patch.
		var base: int = _sort.base_of(_def, &"anim", BuildingLayer.NO_FRAME, 2)
		assert_that(anim.region_rect).is_equal(Rect2(_sort.atlas.frame_region(base, 0)))
		assert_that(patch.region_rect).is_not_equal(anim.region_rect)
		_layer.queue_free()
		_sort.queue_free()
		_ghosts.queue_free()


func test_a_ghost_of_an_unknown_building_or_an_intact_one_is_whole() -> void:
	_remember(100, {"anim": true})
	var ghost: Sprite2D = _ghosts.ghost(ENEMY)
	assert_that(ghost.region_rect).is_equal(Rect2(_region(&"hull")))
	assert_bool(ghost.region_filter_clip_enabled).is_false()
	var patch: Sprite2D = ghost.get_node_or_null("Damage") as Sprite2D
	assert_bool(patch == null or not patch.visible).is_true()
	assert_int(_layer.remembered_stage(77)).is_equal(0)


func test_a_pooled_ghost_sprite_is_whole_again_for_a_building_not_damaged() -> void:
	_remember(10, {"anim": true})
	var ghost: Sprite2D = _ghosts.ghost(ENEMY)
	assert_bool(ghost.get_node("Damage").visible).is_true()
	# Another building takes the slot: its id has no remembered stage.
	var snap: MatchSnapshot = _runner.snapshot
	var cell: int = GhostRig.centre_cell(snap, Vector2i(14, 14), 2, 2)
	GhostRig.remember(snap, 1, [GhostRig.record(88, Dmg.ART_ID, 2, cell)])
	snap.fog.version[0] += 1
	_ghosts._process(0.0)
	var again: Sprite2D = _ghosts.ghost(88)
	assert_object(again).is_same(ghost)
	assert_that(again.region_rect).is_equal(Rect2(_region(&"hull")))
	assert_bool(again.region_filter_clip_enabled).is_false()
	assert_bool(again.get_node("Damage").visible).is_false()
	assert_bool(again.get_node("Anim").visible).is_true()


func test_a_ghost_anim_is_hidden_at_kritisk_when_the_sheet_says_hide() -> void:
	for percent: int in [66, 10]:
		_remember(percent, {"anim": true}, false)
		var anim: Sprite2D = _ghosts.ghost(ENEMY).get_node("Anim")
		assert_bool(anim.visible).is_equal(percent == 66)  # Shown at SKADET, hidden at KRITISK.
		_layer.queue_free()
		_sort.queue_free()
		_ghosts.queue_free()


func test_dress_ghost_finds_the_anim_by_name_not_by_position() -> void:
	_open(_pair(), {"anim": true})
	var parent: Sprite2D = auto_free(Sprite2D.new())
	_sort.dress(parent, _def, &"hull")
	_sort.show_frame(parent, _def, &"hull", BuildingLayer.NO_FRAME, 2)
	BuildingDamage.dress_ghost(parent, _sort, _def, 2, 2)  # A Damage child first.
	BuildingAnims.dress_ghost(parent, _sort, _def, 2)
	assert_int(parent.get_child_count()).is_equal(2)
	assert_str(parent.get_child(0).name).is_equal("Damage")
	assert_str(parent.get_child(1).name).is_equal("Anim")
	var base: int = _sort.base_of(_def, &"anim", BuildingLayer.NO_FRAME, 2)
	assert_that((parent.get_child(1) as Sprite2D).region_rect).is_equal(
		Rect2(_sort.atlas.frame_region(base, 0))
	)
	# Dressed again (a redraw), no child is added.
	BuildingDamage.dress_ghost(parent, _sort, _def, 2, 2)
	BuildingAnims.dress_ghost(parent, _sort, _def, 2)
	assert_int(parent.get_child_count()).is_equal(2)
	# The order also holds when the Anim came first (a pooled sprite).
	var late: Sprite2D = auto_free(Sprite2D.new())
	_sort.dress(late, _def, &"hull")
	_sort.show_frame(late, _def, &"hull", BuildingLayer.NO_FRAME, 2)
	BuildingAnims.dress_ghost(late, _sort, _def, 2)
	BuildingDamage.dress_ghost(late, _sort, _def, 2, 1)
	assert_str(late.get_child(0).name).is_equal("Damage")
	assert_str(late.get_child(1).name).is_equal("Anim")
