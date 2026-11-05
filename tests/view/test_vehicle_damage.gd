extends "res://tests/view/support/vehicle_damage_suite.gd"
## Vehicle damage overlays (plan P161, ADR 0028 sections 4 and 8, ADR 0029 section 12): the stages,
## their write counts, the scales set at dress, the mirror, the pool, the fog and the flags.
## Fixtures: support/vehicle_damage_suite.gd. The budget and the follow writes are in
## test_vehicle_damage_writes.gd.

const TINY: Vector2 = Vector2(0.01, 0.01)


func test_the_stage_is_the_line_the_hp_is_strictly_under() -> void:
	var lines: PackedInt32Array = _life.vehicle_stage_percent
	assert_array(lines).is_equal(PackedInt32Array([50, 25]))
	assert_int(VehicleDamage.stage_of(50, 100, lines)).is_equal(0)
	assert_int(VehicleDamage.stage_of(49, 100, lines)).is_equal(1)
	assert_int(VehicleDamage.stage_of(25, 100, lines)).is_equal(1)
	assert_int(VehicleDamage.stage_of(24, 100, lines)).is_equal(2)
	assert_int(VehicleDamage.stage_of(0, 100, lines)).is_equal(2)


func test_a_stage_change_costs_three_five_or_seven_writes() -> void:
	var writes: int = _layer.life_writes()
	_hit(LIGHT, 40)
	assert_int(_layer.life_writes() - writes).is_equal(3)
	assert_bool(_scar(LIGHT).visible).is_true()
	assert_bool(_loose(LIGHT).visible).is_false()
	writes = _layer.life_writes()
	_hit(LIGHT, 20)
	assert_int(_layer.life_writes() - writes).is_equal(5)
	assert_bool(_loose(LIGHT).visible).is_true()
	writes = _layer.life_writes()
	_hit(HEAVY, 10)  # Straight from intact to the last stage.
	assert_int(_layer.life_writes() - writes).is_equal(7)
	assert_bool(_scar(HEAVY).visible and _loose(HEAVY).visible).is_true()
	_hit(LIGHT, 100)  # The hp is raised by hand to test the down-steps: both overlays go.
	assert_bool(_scar(LIGHT).visible or _loose(LIGHT).visible).is_false()


func test_the_costs_of_the_table_and_the_loose_flag() -> void:
	var table: Array = [[0, 1, 3], [1, 2, 5], [0, 2, 7], [2, 1, 2], [1, 0, 1], [2, 0, 2]]
	for row: Array in table:
		assert_int(VehicleDamage.cost(row[0], row[1], true)).is_equal(row[2])
	assert_int(VehicleDamage.cost(0, 2, false)).is_equal(3)
	assert_int(VehicleDamage.cost(1, 2, false)).is_equal(1)
	_life.damage_loose = false
	var writes: int = _layer.life_writes()
	_hit(LIGHT, 10)
	assert_int(_layer.life_writes() - writes).is_equal(3)
	assert_bool(_scar(LIGHT).visible).is_true()
	assert_bool(_loose(LIGHT).visible).is_false()


func test_each_stage_shows_its_scar_and_the_marks_pick_the_loose_frames() -> void:
	_hit(LIGHT, 40)
	var rig: UnitLayer.Rig = _rig(LIGHT)
	var sort: WorldSort = _layer.world_sort
	var base: int = sort.neutral_base(&"scar1", 1)
	var region: Rect2i = sort.atlas.frame_region(base, rig.damage.scar_look)
	assert_that(_scar(LIGHT).region_rect).is_equal(Rect2(region))
	_hit(LIGHT, 10)
	base = sort.neutral_base(&"scar2", 1)
	region = sort.atlas.frame_region(base, rig.damage.scar_look)
	assert_that(_scar(LIGHT).region_rect).is_equal(Rect2(region))
	base = sort.neutral_base(&"loose", 1)
	region = sort.atlas.frame_region(base, rig.damage.loose_look)
	assert_that(_loose(LIGHT).region_rect).is_equal(Rect2(region))
	var texture: Texture2D = rig.sprites[UnitLayer.HULL].texture
	assert_object(_scar(LIGHT).texture).is_same(texture)  # One batch.
	assert_object(_loose(LIGHT).texture).is_same(texture)


func test_the_looks_are_picked_by_the_id_and_the_marks_and_the_pinned_sums_hold() -> void:
	# The sums are fixed numbers of the integer mix, so they hold on every run and device.
	var scar_ones: int = 0
	var loose_ones: int = 0
	for id: int in range(1, 21):
		var tracks: VehicleDamage.Parts = _dressed(HEAVY, id)
		var wheels: VehicleDamage.Parts = _dressed(LIGHT, id)
		assert_int(tracks.loose_look).is_between(0, 1)  # Track guards: frames 0 and 1.
		assert_int(wheels.loose_look).is_between(2, 3)  # Wheel fenders: frames 2 and 3.
		assert_int(wheels.loose_look - 2).is_equal(tracks.loose_look)
		assert_int(tracks.scar_look).is_equal(wheels.scar_look)
		assert_int(_dressed(HEAVY, id).scar_look).is_equal(tracks.scar_look)
		scar_ones += tracks.scar_look
		loose_ones += tracks.loose_look
	assert_int(scar_ones).is_equal(12)  # Of 20 ids; the other 8 have look 0.
	assert_int(loose_ones).is_equal(6)
	assert_int(_rig(HEAVY).damage.loose_look).is_less(2)  # The heavy tank: tracks.
	assert_int(_rig(LIGHT).damage.loose_look).is_greater_equal(2)


func test_the_two_scars_share_their_canvas_and_anchor_and_the_loose_part_has_both_kinds() -> void:
	var neutral: IsoSheetDef = _layer.world_sort.neutral_sheet()
	assert_that(neutral.frame_size(&"scar1")).is_equal(neutral.frame_size(&"scar2"))
	assert_that(neutral.anchor(&"scar1")).is_equal(neutral.anchor(&"scar2"))
	assert_int(neutral.frame_count(&"loose")).is_equal(4)  # Two track guards, two wheel fenders.


func test_the_overlays_are_children_of_the_hull_after_it_under_the_turret() -> void:
	var rig: UnitLayer.Rig = _rig(LIGHT)
	var hull: Sprite2D = rig.sprites[UnitLayer.HULL]
	assert_array(hull.get_children()).is_equal([rig.damage.scar, rig.damage.loose])
	assert_str(String(rig.damage.scar.name)).is_equal("Scar")
	assert_str(String(rig.damage.loose.name)).is_equal("Loose")
	var order: Array[Node] = rig.get_children()
	assert_int(order.find(hull)).is_less(order.find(rig.sprites[UnitLayer.TURRET]))
	assert_bool(rig.damage.scar.visible or rig.damage.loose.visible).is_false()


func test_a_squad_never_gets_them_and_never_shares_a_rig_with_a_vehicle() -> void:
	var squad: UnitLayer.Rig = _rig(SQUAD)
	assert_object(squad.damage).is_null()
	assert_int(squad.sprites[UnitLayer.HULL].get_child_count()).is_equal(0)
	assert_int(_rig(LIGHT).kind & UnitLayer.DAMAGE_KIND).is_not_equal(0)
	assert_int(squad.kind & UnitLayer.DAMAGE_KIND).is_equal(0)
	_hit(SQUAD, 10)  # Hurt to the last stage, it still shows nothing.
	assert_int(squad.sprites[UnitLayer.HULL].get_child_count()).is_equal(0)


func test_a_scar_and_a_loose_part_draw_at_their_own_scale_and_place_whatever_the_hulls() -> void:
	_check_scale_and_place()


func test_the_same_below_bake_scale_one_where_the_heavy_hull_is_scaled_per_axis() -> void:
	_open(0.75)
	var hull: Vector2 = _rig(HEAVY).sprites[UnitLayer.HULL].scale
	assert_float(absf(hull.x - hull.y)).is_greater(0.001)  # Not uniform: the raster rounds per axis.
	_check_scale_and_place()


func test_a_mirrored_loose_part_draws_about_the_hang_point_on_both_sides() -> void:
	_check_mirror()


func test_a_mirrored_loose_part_below_bake_scale_one() -> void:
	_open(0.75)
	_check_mirror()


func test_a_pooled_rig_taken_for_another_type_gets_the_scales_of_that_type() -> void:
	var light: UnitLayer.Rig = _rig(LIGHT)
	var heavy_scar: Vector2 = _scar(HEAVY).scale
	assert_float(_scar(LIGHT).scale.x).is_not_equal(heavy_scar.x)  # 600 against 800.
	_hit(LIGHT, 10)  # It dies at the last stage, with both overlays shown.
	_kill(LIGHT)
	var id: int = _spawn(&"heavy_tank", 12000, 12000)
	assert_object(_rig(id)).is_same(light)  # The pool gave the light tank's rig.
	assert_vector(light.damage.scar.scale).is_equal_approx(heavy_scar, TINY / 100.0)
	assert_vector(light.damage.loose.scale).is_equal_approx(_loose(HEAVY).scale, TINY / 100.0)
	assert_that(light.sprites[UnitLayer.HULL].scale).is_equal(
		_rig(HEAVY).sprites[UnitLayer.HULL].scale
	)
	assert_int(light.damage.shown).is_equal(0)  # An intact unit on a damaged rig: clean.
	assert_bool(light.damage.scar.visible or light.damage.loose.visible).is_false()
	assert_bool(light.damage.queued).is_false()


func test_the_scales_are_not_written_by_a_stage_change() -> void:
	var scar: Vector2 = _scar(HEAVY).scale
	var loose: Vector2 = _loose(HEAVY).scale
	_hit(HEAVY, 40)
	_hit(HEAVY, 10)
	_hit(HEAVY, 100)
	assert_that(_scar(HEAVY).scale).is_equal(scar)
	assert_float(absf(_loose(HEAVY).scale.x)).is_equal(absf(loose.x))  # Only its side may flip.
	assert_float(_loose(HEAVY).scale.y).is_equal(loose.y)


func test_a_hidden_enemy_writes_nothing_and_shows_its_stage_when_seen() -> void:
	Rig.see(_runner.snapshot, 1, [])
	_layer._process(0.0)
	assert_bool(_layer.is_shown(_row(ENEMY))).is_false()
	var writes: int = _layer.life_writes()
	_hit(ENEMY, 10)
	Rig.see(_runner.snapshot, 1, [])
	_layer._process(0.0)
	assert_int(_layer.life_writes()).is_equal(writes)
	assert_bool(_scar(ENEMY).visible).is_false()
	Rig.see(_runner.snapshot, 1, [Vector2i(28, 28)])
	_layer._process(0.0)
	assert_bool(_scar(ENEMY).visible and _loose(ENEMY).visible).is_true()  # The stage of now.
	assert_int(_layer.life_writes() - writes).is_equal(7)


func test_a_vehicle_out_of_sight_after_it_was_queued_writes_nothing_until_seen() -> void:
	Rig.see(_runner.snapshot, 1, [Vector2i(28, 28)])
	_layer._process(0.0)
	_set_hp(ENEMY, 40)
	_runner.run_ticks(1)
	Rig.see(_runner.snapshot, 1, [Vector2i(28, 28)])
	_layer._sync_rigs()
	assert_int(_layer._damage_queue.size()).is_equal(1)  # Shown, so queued.
	var writes: int = _layer.life_writes()
	Rig.see(_runner.snapshot, 1, [])  # Gone before the frame writes it.
	_layer._process(0.0)
	assert_int(_layer.life_writes()).is_equal(writes)
	assert_bool(_scar(ENEMY).visible).is_false()
	assert_int(_layer._damage_queue.size()).is_equal(0)


func test_a_rig_out_of_the_pool_applies_the_stage_of_now_and_a_new_one_starts_intact() -> void:
	_hit(LIGHT, 10)
	var old: UnitLayer.Rig = _rig(LIGHT)
	var type: int = _runner.world.type_ids.find(&"heavy_tank")
	_runner.world.hp[_runner.world.index_of(LIGHT)] = 0
	_runner.run_ticks(1)
	_layer._process(0.0)
	var id: int = _runner.world.add_unit(1, type, 12000, 12000)
	_runner.world.hp[_runner.world.index_of(id)] = 1  # Born nearly dead.
	_runner.run_ticks(1)
	_layer._process(0.0)
	assert_object(_rig(id)).is_same(old)
	assert_int(old.damage.shown).is_equal(2)
	assert_bool(old.damage.scar.visible and old.damage.loose.visible).is_true()
	var fresh: int = _runner.world.add_unit(1, type, 14000, 12000)
	_runner.run_ticks(1)
	_layer._process(0.0)
	assert_bool(_scar(fresh).visible or _loose(fresh).visible).is_false()
	assert_int(_rig(fresh).damage.shown).is_equal(0)


func test_the_node_count_stays_flat_through_every_stage() -> void:
	var rig: UnitLayer.Rig = _rig(LIGHT)
	var hull: Sprite2D = rig.sprites[UnitLayer.HULL]
	var nodes: int = rig.get_child_count() + hull.get_child_count()
	var made: int = _layer.rigs_made()
	for percent: int in [40, 20, 100, 10, 60]:
		_hit(LIGHT, percent)
	assert_int(rig.get_child_count() + hull.get_child_count()).is_equal(nodes)
	assert_int(_layer.rigs_made()).is_equal(made)


func test_a_turretless_vehicle_has_overlays_and_never_shares_a_rig_with_a_squad() -> void:
	var harvester: UnitLayer.Rig = _rig(HARVESTER)
	assert_int(harvester.kind & UnitLayer.DAMAGE_KIND).is_not_equal(0)
	assert_int(harvester.kind | UnitLayer.DAMAGE_KIND).is_equal(harvester.kind)
	var bits: int = UnitLayer.DAMAGE_KIND | UnitLayer.CARGO_KIND  # A tanker: and the cargo bar.
	assert_int(harvester.kind ^ bits).is_equal(_rig(SQUAD).kind)  # Only the bits.
	_hit(HARVESTER, 10)
	assert_bool(_scar(HARVESTER).visible and _loose(HARVESTER).visible).is_true()
	_kill(HARVESTER)
	var made: int = _layer.rigs_made()
	var squad: int = _spawn(&"rifle_squad", 12000, 12000)
	assert_int(_layer.rigs_made()).is_equal(made + 1)  # The harvester's rig did not serve.
	assert_object(_rig(squad).damage).is_null()
	assert_int(_rig(squad).sprites[UnitLayer.HULL].get_child_count()).is_equal(0)
	_kill(squad)  # And the reverse: the squad's rig waits for a squad.
	var one: int = _spawn(&"harvester", 14000, 12000)
	assert_int(_layer.rigs_made()).is_equal(made + 1)  # The harvester's rig again.
	assert_object(_rig(one)).is_same(harvester)
	var two: int = _spawn(&"harvester", 16000, 12000)
	assert_int(_layer.rigs_made()).is_equal(made + 2)  # Not the squad's rig.
	assert_object(_rig(two).damage).is_not_null()
	var again: int = _spawn(&"rifle_squad", 18000, 12000)
	assert_int(_layer.rigs_made()).is_equal(made + 2)
	assert_object(_rig(again).damage).is_null()


## Checks the scar and the loose part of both tanks against the canvas as drawn: sizes, and where
## the rectangles lie against the sheet's points (the anchor sits on the point), in two hull frames.
func _check_scale_and_place() -> void:
	# The Hull is scaled by `WorldSort.dress`; a child that kept its dress scale would draw twice
	# as large or small, and a position without the hull's texels would be off below scale 1.
	var neutral: IsoSheetDef = _layer.world_sort.neutral_sheet()
	var art: float = WorldSort.ART_SCALE
	for id: int in [LIGHT, HEAVY]:
		_hit(id, 10)
		var sheet: IsoSheetDef = _sheet(id)
		var milli: float = float(sheet.scar_milli) / 1000.0
		var anchor: Vector2 = Vector2(neutral.anchor(&"scar2"))
		var scar: Vector2 = Vector2(neutral.frame_size(&"scar2")) * art * milli
		var loose: Vector2 = Vector2(neutral.frame_size(&"loose")) * art * VehicleDamage.LOOSE_SCALE
		for dir: int in [UnitLayer.D_EAST, 3]:
			_turn(id, dir)
			var point: Vector2 = sheet.emitter_point(sheet.emitters.find("damage"), dir) * art
			var rect: Rect2 = _rect_of(id, _scar(id))
			assert_vector(rect.size).is_equal_approx(scar, TINY)
			assert_vector(rect.position).is_equal_approx(point - anchor * art * milli, TINY)
			assert_vector(_rect_of(id, _loose(id)).size).is_equal_approx(loose, TINY)


func _check_mirror() -> void:
	_hit(HEAVY, 10)
	var sheet: IsoSheetDef = _sheet(HEAVY)
	var neutral: IsoSheetDef = _layer.world_sort.neutral_sheet()
	var anchor: Vector2 = Vector2(neutral.anchor(&"loose"))
	var size: Vector2 = Vector2(neutral.frame_size(&"loose"))
	var k: float = WorldSort.ART_SCALE * VehicleDamage.LOOSE_SCALE
	for right: bool in [true, false]:
		var dir: int = _dir_on(HEAVY, right)
		assert_int(dir).is_greater_equal(0)
		_turn(HEAVY, dir)
		var hang: Vector2 = sheet.emitter_point(sheet.emitters.find("hang"), dir)
		hang *= WorldSort.ART_SCALE
		var from_x: float = hang.x - (anchor.x if right else size.x - anchor.x) * k
		var rect: Rect2 = _rect_of(HEAVY, _loose(HEAVY))
		assert_vector(rect.position).is_equal_approx(Vector2(from_x, hang.y - anchor.y * k), TINY)
		assert_vector(rect.size).is_equal_approx(size * k, TINY)
		assert_bool(_loose(HEAVY).scale.x < 0.0).is_equal(not right)


## The overlays of a vehicle of the type of `like`, dressed afresh for unit id `uid`.
func _dressed(like: int, uid: int) -> VehicleDamage.Parts:
	var hull: Sprite2D = auto_free(Sprite2D.new())
	var sheet: IsoSheetDef = _sheet(like)
	var sort: WorldSort = _layer.world_sort
	sort.dress(hull, sheet, &"hull")
	var parts: VehicleDamage.Parts = VehicleDamage.make(hull)
	VehicleDamage.dress(parts, sort, hull, sheet, uid, 1)
	return parts
