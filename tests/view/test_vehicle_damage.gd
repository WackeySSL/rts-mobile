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
	_hit(LIGHT, 100)  # Repaired: both go.
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
	var tracks: bool = _sheet(LIGHT).marks == &"tracks"
	assert_int(rig.damage.loose_look / 2).is_equal(0 if tracks else 1)
	var texture: Texture2D = rig.sprites[UnitLayer.HULL].texture
	assert_object(_scar(LIGHT).texture).is_same(texture)  # One batch.
	assert_object(_loose(LIGHT).texture).is_same(texture)


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


func test_a_scar_and_a_loose_part_draw_at_their_own_scale_whatever_the_hulls() -> void:
	# The Hull is scaled by `WorldSort.dress`; a child that kept its dress scale would draw twice
	# as large or small. The drawn rectangle is the canvas as drawn, times the scar's milli or 0.8.
	var neutral: IsoSheetDef = _layer.world_sort.neutral_sheet()
	for id: int in [LIGHT, HEAVY]:
		_hit(id, 10)
		var milli: float = float(_sheet(id).scar_milli) / 1000.0
		var scar: Vector2 = Vector2(neutral.frame_size(&"scar2")) * WorldSort.ART_SCALE * milli
		assert_vector(_rect_of(id, _scar(id)).size).is_equal_approx(scar, TINY)
		var loose: Vector2 = Vector2(neutral.frame_size(&"loose")) * WorldSort.ART_SCALE
		loose *= VehicleDamage.LOOSE_SCALE
		assert_vector(_rect_of(id, _loose(id)).size).is_equal_approx(loose, TINY)


func test_a_pooled_rig_taken_for_another_type_gets_the_scales_of_that_type() -> void:
	var light: UnitLayer.Rig = _rig(LIGHT)
	var heavy_scar: Vector2 = _scar(HEAVY).scale
	assert_float(_scar(LIGHT).scale.x).is_not_equal(heavy_scar.x)  # 600 against 800.
	_runner.world.hp[_runner.world.index_of(LIGHT)] = 0
	_runner.run_ticks(1)
	_layer._process(0.0)
	var type: int = _runner.world.type_ids.find(&"heavy_tank")
	var id: int = _runner.world.add_unit(1, type, 12000, 12000)
	_runner.run_ticks(1)
	_layer._process(0.0)
	assert_object(_rig(id)).is_same(light)  # The pool gave the light tank's rig.
	assert_vector(light.damage.scar.scale).is_equal_approx(heavy_scar, TINY / 100.0)
	assert_vector(light.damage.loose.scale).is_equal_approx(_loose(HEAVY).scale, TINY / 100.0)
	assert_that(light.sprites[UnitLayer.HULL].scale).is_equal(
		_rig(HEAVY).sprites[UnitLayer.HULL].scale
	)
	assert_int(light.damage.shown).is_equal(0)


func test_the_scales_are_not_written_by_a_stage_change() -> void:
	var scar: Vector2 = _scar(HEAVY).scale
	var loose: Vector2 = _loose(HEAVY).scale
	_hit(HEAVY, 40)
	_hit(HEAVY, 10)
	_hit(HEAVY, 100)
	assert_that(_scar(HEAVY).scale).is_equal(scar)
	assert_float(absf(_loose(HEAVY).scale.x)).is_equal(absf(loose.x))  # Only its side may flip.
	assert_float(_loose(HEAVY).scale.y).is_equal(loose.y)


func test_a_mirrored_loose_part_draws_about_the_hang_point_on_both_sides() -> void:
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
