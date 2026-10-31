extends GdUnitTestSuite
## What the minimap's picture shows and when it is painted (plan P88, ADR 0019 section 4, ADR 0023
## section 4): one RGBA8 texel per cell read from `MinimapImage.image()`, never from the texture.
## The terrain is MapView's colour, black where the player never was and dimmed where it was and is
## not now; own rows are always drawn, in their team's tones (a building its footprint in the mid
## tone, a unit one cell in the light one); an enemy row only where the player sees it now, a unit
## by its cell and a building by any cell of its footprint; a last-seen record dimmed where no cell
## of its footprint is seen. A hidden enemy is never written. An own mark is exactly its cells
## and an enemy one (a last-seen one too) those cells grown by one on every side without the four
## corners, a plus for a unit: own and enemy differ in shape, not in colour alone. The fog part is
## patched from the dirty list and the rows are painted at the fog's cadence, so the picture of a
## march equals a fresh one at every paint and the paints stay at one per fog update.
## Cases on a 32 x 32 map, player 1 the local one: its Headquarters (3x3) at tile (4, 4) and a light
## tank at (10, 4); player 2's Headquarters (3x3, id 3, tiles 4-6 by 12-14) and a tank at (20, 20).
## The marches run on controls_test (48 x 48, blue tanks from tile (8, 18), red ones from (34, 10)).

const Rig: GDScript = preload("res://tests/view/support/building_rig.gd")
const Ghosts: GDScript = preload("res://tests/view/support/ghost_rig.gd")
const FogRig: GDScript = preload("res://tests/view/support/fog_rig.gd")
const KEEP: int = 255 - 140  ## What the explored shade leaves of a colour, of 255.
const UNEXPLORED: Vector3i = Vector3i(11, 13, 16)  ## #0B0D10.
const FIRST_HQ: Vector2i = Vector2i(4, 4)  ## The tile of player 1's Headquarters (3x3).
const ENEMY_HQ: Vector2i = Vector2i(4, 12)  ## The tile of player 2's Headquarters (3x3).
const ENEMY_HQ_ID: int = 3

var _runner: MatchRunner
var _snap: MatchSnapshot
var _colours: Dictionary[StringName, Color]
var _picture: MinimapImage


func before_test() -> void:
	CommandQueue.clear()
	_colours = auto_free(MapView.new()).colors
	var spawns: Array[SpawnDef] = [
		Rig.spawn(1, "headquarters", FIRST_HQ.x, FIRST_HQ.y),
		Rig.spawn(1, "light_tank", 10, 4),
		Rig.spawn(2, "renew_hq", ENEMY_HQ.x, ENEMY_HQ.y),
		Rig.spawn(2, "renew_tank", 20, 20),
	]
	_runner = auto_free(Rig.runner(Rig.scenario(spawns)))
	_snap = _runner.snapshot
	_picture = _new_picture()


func after_test() -> void:
	CommandQueue.clear()


func test_the_picture_is_the_map_with_the_fog_over_it_one_texel_per_cell() -> void:
	_clear_fog(1)
	_see(1, _block(Vector2i(14, 14), 8, 4), true)
	_see(1, _block(Vector2i(18, 14), 4, 4), false)  # Seen before: the block's east half.
	assert_bool(_picture.update(_snap, 1)).is_true()
	var image: Image = _picture.image()
	assert_that(image.get_size()).is_equal(Vector2i(32, 32))
	assert_int(image.get_format()).is_equal(Image.FORMAT_RGBA8)
	var covered: Dictionary[int, bool] = _row_cells()
	var fog: FogGrid = _snap.fog
	var counts: Vector3i = Vector3i.ZERO
	for cell: int in fog.cells:
		if covered.has(cell):
			continue
		var tone: Color = _colours[_snap.terrain_ids[_snap.terrain[cell]]]
		var expected: Vector3i = UNEXPLORED
		if fog.is_visible(1, cell):
			expected = _rgb(tone)
			counts.x += 1
		elif fog.is_explored(1, cell):
			expected = _rgb(tone, KEEP)
			counts.y += 1
		else:
			counts.z += 1
		var shown: Vector3i = _px(cell % 32, cell / 32)
		assert_vector(shown).override_failure_message("cell %d" % cell).is_equal(expected)
		assert_int(image.get_pixel(cell % 32, cell / 32).a8).is_equal(255)
	assert_int(counts.x).is_greater(0)  # All three states were looked at.
	assert_int(counts.y).is_greater(0)
	assert_int(counts.z).is_greater(0)


func test_own_rows_are_drawn_in_their_teams_tones_a_building_by_its_footprint() -> void:
	_clear_fog(1)
	assert_bool(_picture.update(_snap, 1)).is_true()
	var first: Array = WorldSort.TRIADS[0]
	for line: int in range(FIRST_HQ.y, FIRST_HQ.y + 3):
		for col: int in range(FIRST_HQ.x, FIRST_HQ.x + 3):
			assert_vector(_px(col, line)).is_equal(_rgb(Color(first[1])))
	var tank: int = _row_of(&"light_tank")
	assert_vector(_px(_snap.pos_x[tank] / 1000, _snap.pos_y[tank] / 1000)).is_equal(
		_rgb(Color(first[0]))
	)
	assert_vector(_px(_snap.pos_x[tank] / 1000 + 1, _snap.pos_y[tank] / 1000)).is_equal(UNEXPLORED)
	# Beside the footprint it is the unseen ground: the Headquarters sees nothing here (fog cleared).
	assert_vector(_px(FIRST_HQ.x + 3, FIRST_HQ.y)).is_equal(UNEXPLORED)


func test_a_hidden_enemy_is_never_drawn_and_shows_only_while_a_cell_of_it_is_seen() -> void:
	_clear_fog(1)
	assert_bool(_picture.update(_snap, 1)).is_true()
	assert_int(_count_team(2)).is_equal(0)
	var tank: int = _row_of(&"renew_tank")
	var at: Vector2i = Vector2i(_snap.pos_x[tank] / 1000, _snap.pos_y[tank] / 1000)
	# The enemy tank's cell comes into sight: one light cell of player 2.
	_see(1, [at], true)
	assert_bool(_picture.update(_snap, 1)).is_true()
	assert_vector(_px(at.x, at.y)).is_equal(_rgb(Color(WorldSort.TRIADS[1][0])))
	assert_int(_count_team(2)).is_equal(5)  # A plus: its cell and the four beside it.
	# It leaves sight again: gone, over the ground seen before.
	_see(1, [at], false)
	assert_bool(_picture.update(_snap, 1)).is_true()
	assert_int(_count_team(2)).is_equal(0)
	var tone: Color = _colours[_snap.terrain_ids[_snap.terrain[at.y * 32 + at.x]]]
	assert_vector(_px(at.x, at.y)).is_equal(_rgb(tone, KEEP))
	# One corner cell of the Headquarters is seen: the whole footprint is drawn, as the view draws it.
	_see(1, [ENEMY_HQ + Vector2i(2, 2)], true)
	assert_bool(_picture.update(_snap, 1)).is_true()
	assert_int(_count_team(2)).is_equal(21)  # 5 x 5 without the corners.
	assert_vector(_px(ENEMY_HQ.x, ENEMY_HQ.y)).is_equal(_rgb(Color(WorldSort.TRIADS[1][1])))
	_see(1, [ENEMY_HQ + Vector2i(2, 2)], false)
	assert_bool(_picture.update(_snap, 1)).is_true()
	assert_int(_count_team(2)).is_equal(0)


func test_a_last_seen_building_is_drawn_dimmed_where_no_cell_of_it_is_seen() -> void:
	_clear_fog(1)
	var cell: int = Ghosts.centre_cell(_snap, ENEMY_HQ, 3, 3)
	Ghosts.remember(_snap, 1, [Ghosts.record(ENEMY_HQ_ID, &"renew_hq", 2, cell)])
	assert_bool(_picture.update(_snap, 1)).is_true()
	var ghost: Vector3i = _rgb(Color(WorldSort.TRIADS[1][1]), KEEP)
	assert_int(_count_team(2)).is_equal(21)  # The memory alone: no live row is drawn.
	for line: int in range(ENEMY_HQ.y, ENEMY_HQ.y + 3):
		for col: int in range(ENEMY_HQ.x, ENEMY_HQ.x + 3):
			assert_vector(_px(col, line)).is_equal(ghost)
	# A cell of it comes into sight: the live building replaces the memory on the whole footprint.
	_see(1, [ENEMY_HQ], true)
	assert_bool(_picture.update(_snap, 1)).is_true()
	assert_vector(_px(ENEMY_HQ.x + 2, ENEMY_HQ.y + 2)).is_equal(_rgb(Color(WorldSort.TRIADS[1][1])))
	# A record of another player's block is not this player's memory.
	_see(1, [ENEMY_HQ], false)
	Ghosts.remember(_snap, 1, [])
	Ghosts.remember(_snap, 2, [Ghosts.record(ENEMY_HQ_ID, &"renew_hq", 2, cell)])
	assert_bool(_picture.update(_snap, 1)).is_true()
	assert_int(_count_team(2)).is_equal(0)


func test_an_enemy_mark_differs_from_an_own_one_in_shape_not_only_in_colour() -> void:
	# Each team once as the player: its own marks are exactly their cells, the other team's are
	# grown into a plus (a unit) or a rounded blob (a building), so the same shapes follow the
	# role and not the colour, and a greyscale picture tells them apart.
	var tank_of: Dictionary[int, StringName] = {1: &"light_tank", 2: &"renew_tank"}
	var hq_of: Dictionary[int, Vector2i] = {1: FIRST_HQ, 2: ENEMY_HQ}
	for player: int in [1, 2]:
		var other: int = 3 - player
		var own_tank: Vector2i = _cell_of(tank_of[player])
		var enemy_tank: Vector2i = _cell_of(tank_of[other])
		var seen: Array[Vector2i] = [enemy_tank, hq_of[other] + Vector2i(1, 1)]
		_picture = _new_picture()
		Rig.see(_snap, player, seen)
		assert_bool(_picture.update(_snap, player)).is_true()
		var why: String = "player %d" % player
		(
			assert_array(_marks(Rect2i(own_tank, Vector2i.ONE).grow(2)))
			. override_failure_message(why)
			. contains_exactly_in_any_order([own_tank])
		)
		(
			assert_array(_marks(Rect2i(enemy_tank, Vector2i.ONE).grow(2)))
			. override_failure_message(why)
			. contains_exactly_in_any_order(
				[
					enemy_tank,
					enemy_tank + Vector2i.LEFT,
					enemy_tank + Vector2i.RIGHT,
					enemy_tank + Vector2i.UP,
					enemy_tank + Vector2i.DOWN
				]
			)
		)
		var own_foot: Rect2i = Rect2i(hq_of[player], Vector2i(3, 3))
		(
			assert_array(_marks(own_foot.grow(2)))
			. override_failure_message(why)
			. contains_exactly_in_any_order(_cells(own_foot, 0))
		)
		var enemy_foot: Rect2i = Rect2i(hq_of[other], Vector2i(3, 3))
		(
			assert_array(_marks(enemy_foot.grow(2)))
			. override_failure_message(why)
			. contains_exactly_in_any_order(_cells(enemy_foot, 1))
		)


func test_an_own_mark_is_never_covered_by_the_arms_of_an_enemy_next_to_it() -> void:
	_clear_fog(1)
	var own: Vector2i = _cell_of(&"light_tank")
	var next_to: Vector2i = own + Vector2i.RIGHT  # The enemy's left arm would be on `own`.
	_snap.pos_x[_row_of(&"renew_tank")] = next_to.x * 1000 + 500
	_snap.pos_y[_row_of(&"renew_tank")] = next_to.y * 1000 + 500
	_see(1, [next_to], true)
	assert_bool(_picture.update(_snap, 1)).is_true()
	assert_vector(_px(own.x, own.y)).is_equal(_rgb(Color(WorldSort.TRIADS[0][0])))
	assert_vector(_px(next_to.x, next_to.y)).is_equal(_rgb(Color(WorldSort.TRIADS[1][0])))
	# Its right arm.
	assert_vector(_px(own.x + 2, own.y)).is_equal(_rgb(Color(WorldSort.TRIADS[1][0])))


func test_a_remembered_building_whose_footprint_is_seen_is_not_drawn_when_nothing_stands_there(
) -> void:
	_clear_fog(1)
	var spot: Vector2i = Vector2i(20, 6)  # Empty ground: no live row, only the record.
	var cell: int = Ghosts.centre_cell(_snap, spot, 3, 3)
	Ghosts.remember(_snap, 1, [Ghosts.record(99, &"renew_hq", 2, cell)])
	assert_bool(_picture.update(_snap, 1)).is_true()
	assert_int(_count_team(2)).is_equal(21)  # Unseen: the memory is drawn.
	_see(1, [spot + Vector2i(1, 1)], true)  # One cell of the spot is seen, and nothing is there.
	assert_bool(_picture.update(_snap, 1)).is_true()
	assert_int(_count_team(2)).is_equal(0)


func test_a_building_placed_or_lost_does_not_shade_the_ground_again_but_another_terrain_does(
) -> void:
	_start_march(1)
	var cells: int = _snap.fog.cells
	_snap.tick += 3  # The fog stands: only the period is due.
	_snap.map_version += 1  # A building was placed: the move costs changed, the terrain did not.
	assert_bool(_picture.update(_snap, 1)).is_true()
	assert_int(_picture.shaded_count()).is_equal(0)  # The rows were painted, the ground not.
	assert_int(_snap.terrain_ids.size()).is_greater(1)
	var changed: PackedByteArray = _snap.terrain.duplicate()
	changed[0] = (changed[0] + 1) % _snap.terrain_ids.size()
	_snap.terrain = changed
	_snap.map_version += 1
	assert_bool(_picture.update(_snap, 1)).is_true()
	assert_int(_picture.shaded_count()).is_equal(cells)
	var fresh: MinimapImage = _new_picture()
	assert_bool(fresh.update(_snap, 1)).is_true()
	assert_bool(_picture.image().get_data() == fresh.image().get_data()).is_true()


func test_a_gap_in_the_ticks_or_an_overflowed_dirty_list_shades_the_whole_ground() -> void:
	_clear_fog(1)
	assert_bool(_picture.update(_snap, 1)).is_true()
	var cells: int = _snap.fog.cells
	var spot: Array[Vector2i] = [Vector2i(14, 14), Vector2i(15, 14)]
	_see(1, spot, true)  # The next tick, listed: a patch of the two cells.
	assert_bool(_picture.update(_snap, 1)).is_true()
	assert_int(_picture.shaded_count()).is_equal(2)
	_assert_equals_fresh("a patch")
	var later: Array[Vector2i] = [Vector2i(16, 14)]
	FogRig.flip(_snap, 1, later, true, 2)  # Two ticks on: a tick was not seen.
	assert_bool(_picture.update(_snap, 1)).is_true()
	assert_int(_picture.shaded_count()).is_equal(cells)
	_assert_equals_fresh("a gap")
	var last: Array[Vector2i] = [Vector2i(17, 14)]
	FogRig.flip(_snap, 1, last, true)  # The next tick, but the list is only a prefix.
	_snap.fog.dirty_full[0] = 1
	assert_bool(_picture.update(_snap, 1)).is_true()
	assert_int(_picture.shaded_count()).is_equal(cells)
	_assert_equals_fresh("an overflow")


func test_the_period_is_at_least_one_tick_so_a_tick_is_never_painted_twice() -> void:
	_start_march(1)
	_picture.period_ticks = 0
	assert_bool(_picture.update(_snap, 1)).is_false()  # The same snapshot again.
	_runner.run_ticks(1)
	_snap = _runner.snapshot
	assert_bool(_picture.update(_snap, 1)).is_true()  # The next tick: one paint.
	assert_bool(_picture.update(_snap, 1)).is_false()


func test_a_team_takes_the_slot_the_atlas_gives_its_player() -> void:
	# WorldSort gives players 1..N the triads in order, wrapping after eight; owner 0 is the first.
	assert_int(MinimapImage.team_slot(0)).is_equal(0)
	for owner_id: int in range(1, 25):
		assert_int(MinimapImage.team_slot(owner_id)).is_equal(
			(owner_id - 1) % WorldSort.TRIADS.size()
		)


func test_a_march_is_painted_at_the_fog_cadence_and_equals_a_fresh_picture_at_every_paint() -> void:
	_start_march(1)
	var cells: int = _snap.fog.cells
	var paints: int = 0
	var patches: int = 0
	CommandQueue.submit(Command.move(1, PackedInt32Array(range(1, 31)), 24000, 21500))
	for tick: int in 60:
		_runner.run_ticks(1)
		_snap = _runner.snapshot
		if _picture.update(_snap, 1):
			paints += 1
			patches += 1 if _picture.shaded_count() > 0 and _picture.shaded_count() < cells else 0
			var fresh: MinimapImage = _new_picture()
			assert_bool(fresh.update(_snap, 1)).is_true()
			(
				assert_bool(_picture.image().get_data() == fresh.image().get_data())
				. override_failure_message("tick %d" % _snap.tick)
				. is_true()
			)
		else:
			assert_int(_picture.shaded_count()).is_equal(0)
	assert_int(_picture.redraw_count()).is_equal(paints + 1)  # The first, at the start, too.
	assert_int(paints).is_less_equal(20)  # One in three ticks.
	assert_int(paints).is_greater(10)  # The fog moves with the march.
	assert_int(patches).is_greater(10)  # Almost every paint was a patch of the dirty cells.


func test_with_the_fog_standing_a_paint_comes_every_period_ticks_and_never_twice_for_a_tick(
) -> void:
	_start_march(1)
	assert_int(_picture.redraw_count()).is_equal(1)
	assert_bool(_picture.update(_snap, 1)).is_false()  # The same snapshot again.
	for tick: int in 30:
		_runner.run_ticks(1)
		_snap = _runner.snapshot
		var paints: int = _picture.redraw_count()
		var painted: bool = _picture.update(_snap, 1)
		assert_bool(painted).is_equal(_snap.tick % 3 == 0)
		assert_bool(_picture.update(_snap, 1)).is_false()
		assert_int(_picture.redraw_count()).is_equal(paints + (1 if painted else 0))
	assert_int(_picture.redraw_count()).is_equal(11)


func test_another_player_or_match_paints_afresh_and_each_side_sees_only_its_own() -> void:
	_start_march(1)
	assert_int(_count_team(1)).is_greater(0)
	assert_int(_count_team(2)).is_equal(0)  # The red tanks are out of the blue tanks' sight.
	assert_bool(_picture.update(_snap, 2)).is_true()  # Another player: all new.
	assert_int(_count_team(2)).is_greater(0)
	assert_int(_count_team(1)).is_equal(0)
	_snap.match_serial += 1
	assert_bool(_picture.update(_snap, 2)).is_true()  # Another match: all new.
	assert_int(_picture.shaded_count()).is_equal(48 * 48)


func test_a_player_the_fog_has_no_grid_for_has_nothing_hidden() -> void:
	assert_bool(_picture.update(_snap, 3)).is_true()
	assert_int(_count_team(2)).is_equal(26)  # Player 2's Headquarters (21) and tank (5), in sight.
	assert_int(_count_color(UNEXPLORED)).is_equal(0)


func test_a_map_with_no_area_has_no_picture() -> void:
	var empty: MatchSnapshot = MatchSnapshot.new()
	assert_bool(_picture.update(empty, 1)).is_false()
	assert_object(_picture.texture()).is_null()
	assert_int(_picture.cols()).is_equal(0)


## A picture with MapView's colours, the fog's shade and period.
func _new_picture() -> MinimapImage:
	var made: MinimapImage = MinimapImage.new()
	made.terrain_colours = _colours
	return made


## The march: controls_test, started, and the picture painted once from tick 0.
func _start_march(player: int) -> void:
	_runner = auto_free(MatchRunner.new())
	_runner.scenario = FogRig.scenario(player)
	_runner.start()
	_snap = _runner.snapshot
	_picture = _new_picture()
	assert_bool(_picture.update(_snap, player)).is_true()


## Player `player` sees and has seen nothing, and the picture starts again from that.
func _clear_fog(player: int) -> void:
	var fog: FogGrid = _snap.fog
	for cell: int in fog.cells:
		fog.visible[(player - 1) * fog.cells + cell] = 0
		fog.explored[(player - 1) * fog.cells + cell] = 0
	fog.version[player - 1] += 1
	_snap.tick += 2


## One update of the player's fog as the sim leaves it (`FogRig.flip`): `tiles` turn seen or not.
func _see(player: int, tiles: Array[Vector2i], seen: bool) -> void:
	FogRig.flip(_snap, player, tiles, seen)


func _block(origin: Vector2i, width: int, height: int) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for line: int in height:
		for col: int in width:
			tiles.append(origin + Vector2i(col, line))
	return tiles


func _px(col: int, line: int) -> Vector3i:
	var pixel: Color = _picture.image().get_pixel(col, line)
	return Vector3i(pixel.r8, pixel.g8, pixel.b8)


## The bytes of `colour` times `share` / 255, as the picture stores a tone.
@warning_ignore("integer_division")
func _rgb(colour: Color, share: int = 255) -> Vector3i:
	return Vector3i(colour.r8 * share / 255, colour.g8 * share / 255, colour.b8 * share / 255)


## The row of the first unit of type `type_id`.
func _row_of(type_id: StringName) -> int:
	return Rig.row_of(_snap, type_id)


## The cells a row stands on: a unit's cell and a building's footprint.
@warning_ignore("integer_division")
func _row_cells() -> Dictionary[int, bool]:
	var cells: Dictionary[int, bool] = {}
	for row: int in _snap.unit_count():
		var type: int = _snap.type_index[row]
		var foot: Rect2i = Rect2i(_snap.pos_x[row] / 1000, _snap.pos_y[row] / 1000, 1, 1)
		if _snap.type_foot_w[type] > 0:
			foot = BuildingLayer.footprint_of(_snap, row)
		for line: int in range(foot.position.y, foot.end.y):
			for col: int in range(foot.position.x, foot.end.x):
				cells[line * _snap.map_cols + col] = true
	return cells


## The tile of the first row of type `type_id`.
@warning_ignore("integer_division")
func _cell_of(type_id: StringName) -> Vector2i:
	var row: int = _row_of(type_id)
	return Vector2i(_snap.pos_x[row] / 1000, _snap.pos_y[row] / 1000)


## The cells of `foot`, grown by `grow` on every side without its four corners when it is grown.
func _cells(foot: Rect2i, grow: int) -> Array[Vector2i]:
	var area: Rect2i = foot.grow(grow)
	var out: Array[Vector2i] = []
	for line: int in range(area.position.y, area.end.y):
		for col: int in range(area.position.x, area.end.x):
			var corner: bool = line in [area.position.y, area.end.y - 1]
			if grow > 0 and corner and col in [area.position.x, area.end.x - 1]:
				continue
			out.append(Vector2i(col, line))
	return out


## The cells of `window` whose texel is a mark of any team, whichever: the shape without the colour.
func _marks(window: Rect2i) -> Array[Vector2i]:
	var tones: Array[Vector3i] = []
	for triad: Array in WorldSort.TRIADS:
		tones.append_array(
			[_rgb(Color(triad[0])), _rgb(Color(triad[1])), _rgb(Color(triad[1]), KEEP)]
		)
	var out: Array[Vector2i] = []
	for cell: Vector2i in _cells(window, 0):
		if _px(cell.x, cell.y) in tones:
			out.append(cell)
	return out


## The picture is what a fresh one makes of the same snapshot.
func _assert_equals_fresh(why: String) -> void:
	var fresh: MinimapImage = _new_picture()
	assert_bool(fresh.update(_snap, 1)).is_true()
	(
		assert_bool(_picture.image().get_data() == fresh.image().get_data())
		. override_failure_message(why)
		. is_true()
	)


## How many texels of the image are a tone of the team of `player` (light, mid or dimmed mid).
func _count_team(player: int) -> int:
	var triad: Array = WorldSort.TRIADS[player - 1]
	var tones: Array[Vector3i] = [
		_rgb(Color(triad[0])), _rgb(Color(triad[1])), _rgb(Color(triad[1]), KEEP)
	]
	var found: int = 0
	for line: int in _picture.rows():
		for col: int in _picture.cols():
			found += 1 if _px(col, line) in tones else 0
	return found


## How many texels of the image are exactly `colour`.
func _count_color(colour: Vector3i) -> int:
	var found: int = 0
	for line: int in _picture.rows():
		for col: int in _picture.cols():
			found += 1 if _px(col, line) == colour else 0
	return found
