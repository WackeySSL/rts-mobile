extends GdUnitTestSuite
## The mine layer (plan P293, ADR 0037 section 8): at z 3 between `DecalLayer` and `LifeFx` in
## main.tscn, the marks of the local player's own mines (half alpha until armed) and of its records
## (kept on a cell it does not see, where the fog layer above dims them), an unknown enemy mine
## never drawn, the scorch of a blast only where the cell is seen, in a ring of fixed size, and the
## whole layer one `_draw` of one texture. The burst is `EffectsLayer`'s (test_effects_layer.gd).
## The marks are read from `MatchSnapshot.mines_for`; the cases write the published
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


func _scene_value(node_name: String, property: StringName) -> Variant:
	var state: SceneState = (load(MAIN_SCENE) as PackedScene).get_state()
	for index: int in state.get_node_count():
		if state.get_node_name(index) != node_name:
			continue
		for at: int in state.get_node_property_count(index):
			if state.get_node_property_name(index, at) == property:
				return state.get_node_property_value(index, at)
	return null


func test_the_layer_is_at_z_3_between_the_decals_and_the_life_fx_in_the_main_scene() -> void:
	assert_int(_layer.z_index).is_equal(3)
	assert_bool(_layer.z_as_relative).is_false()
	var text: String = FileAccess.get_file_as_string(MAIN_SCENE)
	var decals: int = text.find('[node name="DecalLayer"')
	var mines: int = text.find('[node name="MineLayer"')
	var life: int = text.find('[node name="LifeFx"')
	assert_bool(decals >= 0 and decals < mines and mines < life).is_true()
	# The fog is above it, which is what dims a record on a cell the player does not see.
	assert_int(_scene_value("FogLayer", &"z_index")).is_greater(
		_scene_value("MineLayer", &"z_index")
	)


func test_the_main_scene_wires_the_layer_to_the_runner_and_the_sorted_world() -> void:
	assert_that(_scene_value("MineLayer", &"runner")).is_equal(NodePath("../MatchRunner"))
	assert_that(_scene_value("MineLayer", &"world_sort")).is_equal(NodePath("../WorldSort"))
	assert_that(_scene_value("MineLayer", &"z_as_relative")).is_equal(false)


func test_an_own_mine_is_a_mark_at_half_alpha_until_it_arms() -> void:
	var snap: MatchSnapshot = _runner.snapshot
	_set_mines([[1, _cell(5, 5), snap.tick - 1], [1, _cell(9, 9), snap.tick + 20]], [])
	_layer._process(0.0)
	assert_int(_layer.mark_count()).is_equal(2)
	assert_vector(_layer.mark_at(0)).is_equal_approx(_centre(5, 5), TOL)
	assert_float(_layer.mark_alpha(0)).is_equal(1.0)
	assert_vector(_layer.mark_at(1)).is_equal_approx(_centre(9, 9), TOL)
	assert_float(_layer.mark_alpha(1)).is_equal(0.5)
	assert_float(_layer.mark_alpha(1)).is_less(1.0)
	for index: int in 2:
		assert_int(_layer.mark_region(index)).is_equal(MineLayer.OWN)  # Owner 1, kind own.


func test_an_unknown_enemy_mine_is_never_drawn_and_a_found_one_is_the_enemys_known_mark() -> void:
	var snap: MatchSnapshot = _runner.snapshot
	var table: Array = [[2, _cell(12, 12), snap.tick - 1], [2, _cell(14, 14), snap.tick - 1]]
	_set_mines(table, [])
	Rig.see(snap, 1, [Vector2i(12, 12), Vector2i(14, 14)])
	_layer._process(0.0)
	assert_int(_layer.mark_count()).is_equal(0)  # In sight, and still nothing: it is not found.
	_set_mines(table, [[2, _cell(14, 14)]])
	_layer._process(0.0)
	assert_int(_layer.mark_count()).is_equal(1)
	assert_vector(_layer.mark_at(0)).is_equal_approx(_centre(14, 14), TOL)
	# Owner 2, kind known.
	assert_int(_layer.mark_region(0)).is_equal(MineLayer.KINDS_PER_OWNER + MineLayer.KNOWN)
	assert_float(_layer.mark_alpha(0)).is_equal(1.0)


func test_a_record_stays_in_the_plan_at_full_tint_when_its_cell_is_not_seen() -> void:
	# The fog layer above dims the cell; the mark must not be dimmed twice.
	var snap: MatchSnapshot = _runner.snapshot
	Rig.see(snap, 1, [Vector2i(14, 14)])
	_set_mines([], [[2, _cell(14, 14)]])
	_layer._process(0.0)
	Rig.see(snap, 1, [Vector2i(1, 1)])  # The fog version moves; the tick does not.
	_layer._process(0.0)
	assert_int(_layer.mark_count()).is_equal(1)
	assert_float(_layer.mark_alpha(0)).is_equal(1.0)
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


func test_the_plan_is_not_made_again_without_a_tick_or_a_fog_change() -> void:
	var snap: MatchSnapshot = _runner.snapshot
	_set_mines([[1, _cell(5, 5), snap.tick - 1]], [])
	_layer._process(0.0)
	snap.mine_cell[0] = _cell(9, 9)  # Only a column moves.
	_layer._process(0.0)
	assert_vector(_layer.mark_at(0)).is_equal_approx(_centre(5, 5), TOL)
	snap.tick += 1
	_layer._process(0.0)
	assert_vector(_layer.mark_at(0)).is_equal_approx(_centre(9, 9), TOL)


func test_the_local_players_own_mark_and_the_others_known_marks_are_on_one_texture() -> void:
	assert_object(_layer.texture()).is_not_null()
	var own: Rect2 = _layer.region_of(1, MineLayer.OWN)
	var known: Rect2 = _layer.region_of(2, MineLayer.KNOWN)
	(
		assert_bool(own.size.x >= MineMarkArt.SIZE_PX.x and known.size.x >= MineMarkArt.SIZE_PX.x)
		. is_true()
	)
	assert_vector(own.size).is_equal(known.size)
	assert_vector(_layer.region_of(1, MineLayer.KNOWN).size).is_equal(Vector2.ZERO)
	assert_vector(_layer.region_of(2, MineLayer.OWN).size).is_equal(Vector2.ZERO)
	assert_float(_layer.bake_ms).is_greater(0.0)
	print("mine_layer_bake_ms %.1f" % _layer.bake_ms)


func test_a_blast_in_sight_leaves_a_scorch_as_wide_as_the_blast_scaled_down() -> void:
	Rig.see(_runner.snapshot, 1, [Vector2i(14, 14)])
	_blast(14, 14)
	assert_int(_layer.scorch_count()).is_equal(1)
	assert_vector(_layer.scorch_at(0)).is_equal_approx(_centre(14, 14), TOL)


func test_a_blast_on_a_cell_the_player_does_not_see_leaves_nothing() -> void:
	Rig.see(_runner.snapshot, 1, [Vector2i(1, 1)])
	_blast(14, 14)
	assert_int(_layer.scorch_count()).is_equal(0)


func test_a_weapon_with_no_blast_radius_leaves_nothing() -> void:
	_runner.snapshot.weapon_blast_milli = PackedInt32Array([0])
	Rig.see(_runner.snapshot, 1, [Vector2i(14, 14)])
	_blast(14, 14)
	_blast(14, 14, 7)  # A weapon the table does not have.
	assert_int(_layer.scorch_count()).is_equal(0)


func test_the_scorch_holds_flat_for_eight_seconds_then_fades_and_goes_at_twelve() -> void:
	var snap: MatchSnapshot = _runner.snapshot
	Rig.see(snap, 1, [Vector2i(14, 14)])
	_blast(14, 14)
	snap.tick += 60  # 4 s.
	_layer._process(0.0)
	assert_float(_layer.scorch_alpha(0)).is_equal(MineLayer.SCORCH_ALPHA)
	var flat: int = _layer.redraw_count()
	for _frame: int in 3:
		_layer._process(0.0)
	assert_int(_layer.redraw_count()).is_equal(flat)  # Nothing changes, nothing is drawn.
	snap.tick += 90  # 10 s: inside the fade.
	_layer._process(0.0)
	var early: float = _layer.scorch_alpha(0)
	assert_float(early).is_less(MineLayer.SCORCH_ALPHA)
	assert_float(early).is_greater(0.0)
	var fading: int = _layer.redraw_count()
	snap.tick += 15  # 11 s.
	_layer._process(0.0)
	assert_float(_layer.scorch_alpha(0)).is_less(early)
	_layer._process(0.0)
	assert_int(_layer.redraw_count()).is_greater(fading + 1)  # Every frame while it fades.
	snap.tick += 30  # 13 s: gone.
	_layer._process(0.0)
	assert_int(_layer.scorch_count()).is_equal(0)


func test_the_ring_holds_a_fixed_number_and_drops_the_first_blast_first() -> void:
	var snap: MatchSnapshot = _runner.snapshot
	var tiles: Array = []
	for x: int in MineLayer.SCORCH_SLOTS + 2:
		tiles.append(Vector2i(x % 30, 10 + x / 30))
	Rig.see(snap, 1, tiles)
	for tile: Vector2i in tiles:
		_blast(tile.x, tile.y)
	assert_int(_layer.scorch_count()).is_equal(MineLayer.SCORCH_SLOTS)
	var centres: Array[Vector2] = []
	for slot: int in MineLayer.SCORCH_SLOTS:
		centres.append(_layer.scorch_at(slot))
	var first: Vector2 = _centre(tiles[0].x, tiles[0].y)
	var second: Vector2 = _centre(tiles[1].x, tiles[1].y)
	var newest: Vector2 = _centre(tiles[-1].x, tiles[-1].y)
	assert_bool(_has(centres, first)).is_false()
	assert_bool(_has(centres, second)).is_false()
	assert_bool(_has(centres, newest)).is_true()
	assert_bool(_has(centres, _centre(tiles[2].x, tiles[2].y))).is_true()


func _has(points: Array[Vector2], point: Vector2) -> bool:
	for candidate: Vector2 in points:
		if candidate.is_equal_approx(point):
			return true
	return false


func test_a_new_match_empties_the_layer_and_plans_again_on_the_same_tick() -> void:
	var snap: MatchSnapshot = _runner.snapshot
	Rig.see(snap, 1, [Vector2i(14, 14)])
	_set_mines([[1, _cell(5, 5), snap.tick - 1]], [])
	_layer._process(0.0)
	_blast(14, 14)
	snap.match_serial += 1
	snap.mine_cell[0] = _cell(9, 9)  # The new match's table, on the same tick and fog version.
	_layer._process(0.0)
	assert_int(_layer.scorch_count()).is_equal(0)
	assert_int(_layer.mark_count()).is_equal(1)
	assert_vector(_layer.mark_at(0)).is_equal_approx(_centre(9, 9), TOL)


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
	# atlas, so the engine batches the marks and the scorches into one call.
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
	var texture_calls: RegEx = RegEx.create_from_string("draw_texture_rect_region\\(\\s*_texture,")
	assert_int(texture_calls.search_all(source).size()).is_equal(2)  # The scorches and the marks.
	assert_int(source.count("draw_texture_rect_region(")).is_equal(2)
	assert_str(SourceScan.function(LAYER, "_draw")).contains("_texture")
