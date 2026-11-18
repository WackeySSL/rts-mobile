extends GdUnitTestSuite
## The mine layer (plan P293, ADR 0037 section 8): at z 3 between `DecalLayer` and `LifeFx` in
## main.tscn, the marks of the local player's own mines (half alpha until armed) and of its records
## (dimmed on a cell it does not see), an unknown enemy mine never drawn, the burst and the scorch
## of a blast only where the cell is seen, in rings of fixed size, and the whole layer one `_draw`
## of one texture. The marks are read from `MatchSnapshot.mines_for`; the cases write the published
## snapshot's mine columns the way the sim leaves them, on the building scenario of the ghost
## suite: player 1 the local one (the Derrick League), player 2 the Lumen Accord.

const Rig: GDScript = preload("res://tests/view/support/building_rig.gd")
const SourceScan: GDScript = preload("res://tests/view/support/source_scan.gd")
const MAIN_SCENE: String = "res://scenes/main.tscn"
const LAYER: String = "res://game/view/MineLayer.gd"
const CAP: int = 4
const TOL: Vector2 = Vector2(0.01, 0.01)

var _runner: MatchRunner
var _sort: WorldSort
var _layer: MineLayer


func before_test() -> void:
	var spawns: Array[SpawnDef] = [
		Rig.spawn(1, "headquarters", 4, 4),
		Rig.spawn(2, "renew_hq", 4, 12),
	]
	_runner = auto_free(Rig.runner(Rig.scenario(spawns)))
	_sort = auto_free(WorldSort.new())
	_sort.runner = _runner
	add_child(_sort)
	_layer = auto_free(MineLayer.new())
	_layer.runner = _runner
	_layer.world_sort = _sort
	add_child(_layer)
	_layer.set_process(false)
	var snap: MatchSnapshot = _runner.snapshot
	snap.weapon_blast_milli = PackedInt32Array([1000])
	_set_mines([], [])
	_layer._process(0.0)


func after_test() -> void:
	CommandQueue.clear()


## The table: `laid` is [owner, cell, armed tick] of each live mine, `found` [owner, cell] of each
## record player 1 holds.
func _set_mines(laid: Array, found: Array) -> void:
	var snap: MatchSnapshot = _runner.snapshot
	snap.mine_count = laid.size()
	snap.mine_known_cap = CAP
	snap.mine_id = PackedInt32Array()
	snap.mine_owner = PackedInt32Array()
	snap.mine_cell = PackedInt32Array()
	snap.mine_armed_tick = PackedInt32Array()
	for index: int in laid.size():
		snap.mine_id.append(index + 1)
		snap.mine_owner.append(laid[index][0])
		snap.mine_cell.append(laid[index][1])
		snap.mine_armed_tick.append(laid[index][2])
	snap.mine_seen_id = PackedInt32Array()
	snap.mine_seen_owner = PackedInt32Array()
	snap.mine_seen_cell = PackedInt32Array()
	snap.mine_seen_id.resize(3 * CAP)
	snap.mine_seen_owner.resize(3 * CAP)
	snap.mine_seen_cell.resize(3 * CAP)
	for index: int in found.size():
		snap.mine_seen_id[CAP + index] = 100 + index
		snap.mine_seen_owner[CAP + index] = found[index][0]
		snap.mine_seen_cell[CAP + index] = found[index][1]
	snap.mine_seen_count = PackedInt32Array([0, found.size(), 0])
	snap.tick += 1


func _cell(x: int, y: int) -> int:
	return y * _runner.snapshot.map_cols + x


func _centre(x: int, y: int) -> Vector2:
	return IsoProjection.ground_to_px(x * 1000 + 500, y * 1000 + 500)


func _blast(x: int, y: int, weapon: int = 0) -> void:
	var snap: MatchSnapshot = _runner.snapshot
	snap.tick += 1
	snap.events = PackedInt32Array(
		[World.Event.MINE_BLAST, 1, x * 1000 + 500, y * 1000 + 500, weapon, 2, 0, 0]
	)
	_runner.ticked.emit(snap.tick)
	snap.events = PackedInt32Array()


func test_the_layer_is_at_z_3_between_the_decals_and_the_life_fx_in_the_main_scene() -> void:
	assert_int(_layer.z_index).is_equal(3)
	assert_bool(_layer.z_as_relative).is_false()
	var text: String = FileAccess.get_file_as_string(MAIN_SCENE)
	var decals: int = text.find('[node name="DecalLayer"')
	var mines: int = text.find('[node name="MineLayer"')
	var life: int = text.find('[node name="LifeFx"')
	assert_bool(decals >= 0 and decals < mines and mines < life).is_true()


func test_an_own_mine_is_a_mark_at_half_alpha_until_it_arms() -> void:
	var snap: MatchSnapshot = _runner.snapshot
	_set_mines([[1, _cell(5, 5), snap.tick - 1], [1, _cell(9, 9), snap.tick + 20]], [])
	_layer._process(0.0)
	assert_int(_layer.mark_count()).is_equal(2)
	assert_vector(_layer.mark_at(0)).is_equal_approx(_centre(5, 5), TOL)
	assert_float(_layer.mark_alpha(0)).is_equal(1.0)
	assert_vector(_layer.mark_at(1)).is_equal_approx(_centre(9, 9), TOL)
	assert_float(_layer.mark_alpha(1)).is_equal(MineLayer.UNARMED_ALPHA)
	for index: int in 2:
		assert_int(_layer.mark_kind(index)).is_equal(MineLayer.OWN)
		assert_int(_layer.mark_owner(index)).is_equal(1)
		assert_bool(_layer.mark_dimmed(index)).is_false()


func test_an_own_mine_in_the_dark_is_drawn_at_full_strength() -> void:
	var snap: MatchSnapshot = _runner.snapshot
	Rig.see(snap, 1, [Vector2i(0, 0)])
	_set_mines([[1, _cell(20, 20), snap.tick - 1]], [])
	_layer._process(0.0)
	assert_int(_layer.mark_count()).is_equal(1)
	assert_bool(_layer.mark_dimmed(0)).is_false()


func test_an_unknown_enemy_mine_is_never_drawn_and_a_found_one_is_the_enemys_known_mark() -> void:
	var snap: MatchSnapshot = _runner.snapshot
	_set_mines([[2, _cell(12, 12), snap.tick - 1], [2, _cell(14, 14), snap.tick - 1]], [])
	Rig.see(snap, 1, [Vector2i(12, 12), Vector2i(14, 14)])
	_layer._process(0.0)
	assert_int(_layer.mark_count()).is_equal(0)  # In sight, and still nothing: it is not found.
	_set_mines(
		[[2, _cell(12, 12), snap.tick - 1], [2, _cell(14, 14), snap.tick - 1]], [[2, _cell(14, 14)]]
	)
	_layer._process(0.0)
	assert_int(_layer.mark_count()).is_equal(1)
	assert_vector(_layer.mark_at(0)).is_equal_approx(_centre(14, 14), TOL)
	assert_int(_layer.mark_kind(0)).is_equal(MineLayer.KNOWN)
	assert_int(_layer.mark_owner(0)).is_equal(2)
	assert_float(_layer.mark_alpha(0)).is_equal(1.0)


func test_a_record_is_dimmed_while_its_cell_is_not_seen_and_goes_with_the_record() -> void:
	var snap: MatchSnapshot = _runner.snapshot
	Rig.see(snap, 1, [Vector2i(14, 14)])
	_set_mines([], [[2, _cell(14, 14)]])
	_layer._process(0.0)
	assert_bool(_layer.mark_dimmed(0)).is_false()
	Rig.see(snap, 1, [Vector2i(1, 1)])  # The fog version moves; the tick does not.
	_layer._process(0.0)
	assert_int(_layer.mark_count()).is_equal(1)
	assert_bool(_layer.mark_dimmed(0)).is_true()
	assert_float(_layer.dim_keep()).is_equal_approx(1.0 - 140.0 / 255.0, 0.0001)
	_set_mines([], [])
	_layer._process(0.0)
	assert_int(_layer.mark_count()).is_equal(0)


func test_the_marks_are_in_draw_order_with_the_southern_one_last() -> void:
	var snap: MatchSnapshot = _runner.snapshot
	var armed: int = snap.tick - 1
	_set_mines([[1, _cell(9, 9), armed], [1, _cell(5, 5), armed], [1, _cell(7, 7), armed]], [])
	_layer._process(0.0)
	assert_vector(_layer.mark_at(0)).is_equal_approx(_centre(5, 5), TOL)
	assert_vector(_layer.mark_at(1)).is_equal_approx(_centre(7, 7), TOL)
	assert_vector(_layer.mark_at(2)).is_equal_approx(_centre(9, 9), TOL)


func test_both_players_marks_are_on_one_texture_in_the_regions_the_bake_made() -> void:
	assert_object(_layer.texture()).is_not_null()
	for owner: int in [1, 2]:
		for kind: int in [MineLayer.OWN, MineLayer.KNOWN]:
			var region: Rect2 = _layer.region_of(owner, kind)
			(
				assert_bool(region.size.x >= MineMarkArt.SIZE_PX.x)
				. override_failure_message("%d %d %s" % [owner, kind, region])
				. is_true()
			)
	assert_vector(_layer.region_of(1, MineLayer.OWN).size).is_equal(
		_layer.region_of(2, MineLayer.KNOWN).size
	)


func test_a_blast_in_sight_leaves_a_burst_and_a_scorch() -> void:
	Rig.see(_runner.snapshot, 1, [Vector2i(14, 14)])
	_blast(14, 14)
	assert_int(_layer.burst_count()).is_equal(1)
	assert_int(_layer.scorch_count()).is_equal(1)
	assert_vector(_layer.scorch_at(0)).is_equal_approx(_centre(14, 14), TOL)


func test_a_blast_on_a_cell_the_player_does_not_see_leaves_nothing() -> void:
	Rig.see(_runner.snapshot, 1, [Vector2i(1, 1)])
	_blast(14, 14)
	assert_int(_layer.burst_count()).is_equal(0)
	assert_int(_layer.scorch_count()).is_equal(0)


func test_a_weapon_with_no_blast_radius_leaves_nothing() -> void:
	_runner.snapshot.weapon_blast_milli = PackedInt32Array([0])
	Rig.see(_runner.snapshot, 1, [Vector2i(14, 14)])
	_blast(14, 14)
	_blast(14, 14, 7)  # A weapon the table does not have.
	assert_int(_layer.burst_count()).is_equal(0)


func test_the_burst_ends_before_the_scorch_and_the_scorch_fades_out() -> void:
	var snap: MatchSnapshot = _runner.snapshot
	Rig.see(snap, 1, [Vector2i(14, 14)])
	_blast(14, 14)
	snap.tick += 60  # 4 s: the burst is over, the scorch has not begun to fade.
	_layer._process(0.0)
	assert_int(_layer.burst_count()).is_equal(0)
	assert_int(_layer.scorch_count()).is_equal(1)
	snap.tick += 200  # 17 s in all: gone.
	_layer._process(0.0)
	assert_int(_layer.scorch_count()).is_equal(0)


func test_the_rings_hold_a_fixed_number_and_overwrite_the_oldest() -> void:
	var snap: MatchSnapshot = _runner.snapshot
	Rig.see(snap, 1, [Vector2i(14, 14)])
	for _blast_no: int in MineLayer.SCORCH_SLOTS + 6:
		_blast(14, 14)
	assert_int(_layer.burst_count()).is_equal(MineLayer.BURST_SLOTS)
	assert_int(_layer.scorch_count()).is_equal(MineLayer.SCORCH_SLOTS)


func test_a_new_match_empties_the_layer() -> void:
	var snap: MatchSnapshot = _runner.snapshot
	Rig.see(snap, 1, [Vector2i(14, 14)])
	_set_mines([[1, _cell(5, 5), snap.tick - 1]], [])
	_layer._process(0.0)
	_blast(14, 14)
	snap.match_serial += 1
	snap.mine_count = 0
	_layer._process(0.0)
	assert_int(_layer.mark_count()).is_equal(0)
	assert_int(_layer.burst_count()).is_equal(0)
	assert_int(_layer.scorch_count()).is_equal(0)


func test_a_still_frame_redraws_nothing() -> void:
	var snap: MatchSnapshot = _runner.snapshot
	_set_mines([[1, _cell(5, 5), snap.tick - 1]], [])
	_layer._process(0.0)
	var before: int = _layer.redraw_count()
	for _frame: int in 5:
		_layer._process(0.0)
	assert_int(_layer.redraw_count()).is_equal(before)


func test_the_layer_is_one_draw_of_one_texture() -> void:
	# The +1 of the draw-call forecast: one `_draw`, and every call it makes is a region of the one
	# atlas, so the engine batches the marks, the scorches and the bursts into one call.
	var source: String = FileAccess.get_file_as_string(LAYER)
	assert_int(source.count("func _draw()")).is_equal(1)
	var calls: Array[String] = []
	var at: int = source.find("draw_")
	while at >= 0:
		var open: int = source.find("(", at)
		var name: String = source.substr(at, open - at)
		if name.is_valid_ascii_identifier() and not calls.has(name):
			calls.append(name)
		at = source.find("draw_", open)
	calls.erase("draw_count")
	assert_array(calls).is_equal(["draw_texture_rect_region"])
	assert_int(source.count("draw_texture_rect_region(")).is_equal(2)
	assert_str(SourceScan.function(LAYER, "_draw")).contains("_texture")
