extends GdUnitTestSuite
## PlayerView's rows (plan row P78, ADR 0020 section 1): which rows a player owns and sees, and that
## no getter answers for a row it does not. The crafted World of `view_worlds.gd` (real fog) gives
## each player rows it sees and rows it does not; the vision rule is `Targeting.sees`, which a
## random World checks row by row. Stat, queue, placement and table cases are in
## test_player_view_state.gd.

const ViewWorlds: GDScript = preload("res://tests/sim/support/view_worlds.gd")
const TargetingWorlds: GDScript = preload("res://tests/sim/support/targeting_worlds.gd")
const MISSING: int = PlayerView.MISSING


## The ids of the units in `rows`, in the order given.
func _ids(world: World, rows: PackedInt32Array) -> Array[int]:
	var found: Array[int] = []
	for row: int in rows:
		found.append(world.unit_id[row])
	return found


## Every getter of the view for `row`, as one array: the public columns, the own columns and the
## two parts of the position.
func _answers(view: PlayerView, row: int) -> Array[int]:
	var pos: Vector2i = view.row_pos(row)
	return [
		view.row_id(row),
		view.row_owner(row),
		view.row_type(row),
		pos.x,
		pos.y,
		view.row_hp(row),
		view.row_order(row),
		view.row_harvest_mode(row),
		view.row_home(row),
	]


func _missing_answers() -> Array[int]:
	var answers: Array[int] = []
	answers.resize(9)
	answers.fill(MISSING)
	return answers


func _in(list: PackedInt32Array, row: int) -> bool:
	return list.has(row)


## The rows of both lists, own first.
func _merge(first: PackedInt32Array, second: PackedInt32Array) -> Array[int]:
	var rows: Array[int] = []
	rows.append_array(first)
	rows.append_array(second)
	return rows


func test_player_one_owns_three_rows_and_sees_three_of_the_others() -> void:
	var world: World = ViewWorlds.crafted()
	var view: PlayerView = PlayerView.of(world, 1)
	assert_array(_ids(world, view.own_rows)).is_equal(
		[ViewWorlds.HQ_1, ViewWorlds.RIFLE_1, ViewWorlds.HARVESTER_1]
	)
	assert_array(_ids(world, view.seen_rows)).is_equal(
		[ViewWorlds.NEAR_FOE, ViewWorlds.NEAR_HARVESTER, ViewWorlds.NEAR_NEUTRAL]
	)


func test_player_two_owns_four_rows_and_sees_only_the_far_neutral() -> void:
	var world: World = ViewWorlds.crafted()
	var view: PlayerView = PlayerView.of(world, 2)
	assert_array(_ids(world, view.own_rows)).is_equal(
		[ViewWorlds.HQ_2, ViewWorlds.NEAR_FOE, ViewWorlds.FAR_FOE, ViewWorlds.NEAR_HARVESTER]
	)
	assert_array(_ids(world, view.seen_rows)).is_equal([ViewWorlds.FAR_NEUTRAL])
	assert_int(view.player).is_equal(2)
	assert_int(view.tick).is_equal(world.tick)


func test_no_getter_returns_a_hidden_row() -> void:
	var world: World = ViewWorlds.crafted()
	var hidden: Dictionary[int, Array] = {
		1: [ViewWorlds.HQ_2, ViewWorlds.FAR_FOE, ViewWorlds.FAR_NEUTRAL],
		2: [ViewWorlds.HQ_1, ViewWorlds.RIFLE_1, ViewWorlds.HARVESTER_1, ViewWorlds.NEAR_NEUTRAL],
	}
	for player: int in hidden:
		var view: PlayerView = PlayerView.of(world, player)
		for id: int in hidden[player]:
			var row: int = world.index_of(id)
			assert_bool(_in(view.own_rows, row) or _in(view.seen_rows, row)).is_false()
			assert_array(_answers(view, row)).is_equal(_missing_answers())
			assert_int(view.row_of(id)).is_equal(MISSING)


func test_the_lists_are_ascending_disjoint_and_leave_out_exactly_the_hidden_rows() -> void:
	var world: World = ViewWorlds.crafted()
	for player: int in [1, 2]:
		var view: PlayerView = PlayerView.of(world, player)
		for list: PackedInt32Array in [view.own_rows, view.seen_rows]:
			for at: int in range(1, list.size()):
				assert_bool(list[at - 1] < list[at]).is_true()
		var listed: int = 0
		for row: int in world.unit_count():
			var own: bool = _in(view.own_rows, row)
			var seen: bool = _in(view.seen_rows, row)
			assert_bool(own and seen).is_false()
			assert_bool(own).is_equal(world.owner[row] == player)
			listed += 1 if own or seen else 0
			# The getters agree with the lists: an answer is a row's, or MISSING, never both.
			assert_bool(view.row_id(row) != MISSING).is_equal(own or seen)
		assert_int(listed).is_equal(view.own_rows.size() + view.seen_rows.size())


func test_the_public_columns_of_an_own_or_seen_row_are_the_worlds() -> void:
	var world: World = ViewWorlds.crafted()
	world.hp[world.index_of(ViewWorlds.NEAR_FOE)] = 7
	var view: PlayerView = PlayerView.of(world, 1)
	for row: int in _merge(view.own_rows, view.seen_rows):
		assert_int(view.row_id(row)).is_equal(world.unit_id[row])
		assert_int(view.row_owner(row)).is_equal(world.owner[row])
		assert_int(view.row_type(row)).is_equal(world.type_index[row])
		assert_int(view.row_hp(row)).is_equal(world.hp[row])
		assert_vector(view.row_pos(row)).is_equal(Vector2i(world.pos_x[row], world.pos_y[row]))
	assert_int(view.row_hp(world.index_of(ViewWorlds.NEAR_FOE))).is_equal(7)
	assert_int(view.row_owner(world.index_of(ViewWorlds.NEAR_NEUTRAL))).is_equal(0)
	assert_int(view.row_of(ViewWorlds.NEAR_FOE)).is_equal(world.index_of(ViewWorlds.NEAR_FOE))
	assert_int(view.row_of(ViewWorlds.HQ_1)).is_equal(world.index_of(ViewWorlds.HQ_1))


func test_the_own_columns_are_answered_for_own_rows_only() -> void:
	var world: World = ViewWorlds.crafted()
	var mine: int = world.index_of(ViewWorlds.HARVESTER_1)
	var theirs: int = world.index_of(ViewWorlds.NEAR_HARVESTER)
	world.order[mine] = World.Order.ATTACK_MOVE
	world.harvest_mode[mine] = World.HarvestMode.RETURN
	world.home[mine] = 41
	world.order[theirs] = World.Order.MOVE
	world.harvest_mode[theirs] = World.HarvestMode.MINE
	world.home[theirs] = 42
	var first: PlayerView = PlayerView.of(world, 1)
	assert_int(first.row_order(mine)).is_equal(PlayerView.Order.ATTACK_MOVE)
	assert_int(first.row_harvest_mode(mine)).is_equal(PlayerView.HarvestMode.RETURN)
	assert_int(first.row_home(mine)).is_equal(41)
	# Player 1 sees the enemy harvester, but only its public columns.
	assert_int(first.row_id(theirs)).is_equal(ViewWorlds.NEAR_HARVESTER)
	assert_int(first.row_order(theirs)).is_equal(MISSING)
	assert_int(first.row_harvest_mode(theirs)).is_equal(MISSING)
	assert_int(first.row_home(theirs)).is_equal(MISSING)
	var second: PlayerView = PlayerView.of(world, 2)
	assert_int(second.row_order(theirs)).is_equal(PlayerView.Order.MOVE)
	assert_int(second.row_harvest_mode(theirs)).is_equal(PlayerView.HarvestMode.MINE)
	assert_int(second.row_home(theirs)).is_equal(42)
	assert_int(second.row_order(mine)).is_equal(MISSING)


func test_a_row_index_outside_the_table_answers_missing() -> void:
	var world: World = ViewWorlds.crafted()
	var view: PlayerView = PlayerView.of(world, 1)
	for row: int in [-1, -100, world.unit_count(), world.unit_count() + 1, 1 << 40]:
		assert_array(_answers(view, row)).is_equal(_missing_answers())


func test_row_of_answers_an_id_only_when_the_row_is_the_players() -> void:
	var world: World = ViewWorlds.crafted()
	var view: PlayerView = PlayerView.of(world, 1)
	for id: int in [0, -3, 10, 999, ViewWorlds.HQ_2, ViewWorlds.FAR_FOE, ViewWorlds.FAR_NEUTRAL]:
		assert_int(view.row_of(id)).is_equal(MISSING)
	for id: int in [ViewWorlds.HQ_1, ViewWorlds.NEAR_FOE, ViewWorlds.NEAR_NEUTRAL]:
		var row: int = view.row_of(id)
		assert_int(row).is_equal(world.index_of(id))
		assert_int(view.row_id(row)).is_equal(id)


func test_a_row_is_seen_by_the_cell_it_stands_in_now() -> void:
	var world: World = ViewWorlds.crafted()
	var far: int = world.index_of(ViewWorlds.FAR_FOE)
	var near: int = world.index_of(ViewWorlds.NEAR_FOE)
	assert_bool(_in(PlayerView.of(world, 1).seen_rows, far)).is_false()
	# Into the disc of the headquarters (tile (4, 6), 10 from its centre), and out of it.
	world.pos_x[far] = 4500
	world.pos_y[far] = 6500
	world.pos_x[near] = 16500
	world.pos_y[near] = 12500
	var view: PlayerView = PlayerView.of(world, 1)
	assert_bool(_in(view.seen_rows, far)).is_true()
	assert_bool(_in(view.seen_rows, near)).is_false()
	assert_int(view.row_pos(far).x).is_equal(4500)
	assert_int(view.row_pos(near).x).is_equal(MISSING)


func test_a_position_off_the_map_counts_for_its_nearest_edge_cell() -> void:
	var world: World = ViewWorlds.crafted()
	var far: int = world.index_of(ViewWorlds.FAR_FOE)
	var near: int = world.index_of(ViewWorlds.NEAR_FOE)
	# West of the map at y 2.5 tiles clamps to tile (0, 2), 10 from the headquarters; east of it to
	# tile (19, 2), far from every sight disc of player 1.
	world.pos_x[far] = -500
	world.pos_y[far] = 2500
	world.pos_x[near] = 30000
	world.pos_y[near] = 2500
	var view: PlayerView = PlayerView.of(world, 1)
	assert_bool(_in(view.seen_rows, far)).is_true()
	assert_bool(_in(view.seen_rows, near)).is_false()
	assert_bool(Targeting.sees(world, 1, world.pos_x[far], world.pos_y[far])).is_true()
	assert_bool(Targeting.sees(world, 1, world.pos_x[near], world.pos_y[near])).is_false()


func test_seen_is_targeting_sees_on_random_worlds_for_every_row_and_player() -> void:
	for salt: int in [3, 4]:
		var world: World = TargetingWorlds.short_sighted(salt, 30)
		# Two neutral rows, one anywhere and one in the middle of the map: the rule is the same.
		world.add_unit(0, 0, 3000, 2000)
		world.add_unit(0, 1, 15000, 10000)
		for player: int in [1, 2]:
			var view: PlayerView = PlayerView.of(world, player)
			var seen: int = 0
			for row: int in world.unit_count():
				var other: bool = world.owner[row] != player
				var sees: bool = Targeting.sees(world, player, world.pos_x[row], world.pos_y[row])
				assert_bool(_in(view.seen_rows, row)).is_equal(other and sees)
				assert_bool(_in(view.own_rows, row)).is_equal(not other)
				seen += 1 if other and sees else 0
			assert_int(view.seen_rows.size()).is_equal(seen)
			# A case that never sees, or always sees, would pass the loop above for nothing.
			assert_bool(seen > 0 and seen < world.unit_count() - view.own_rows.size()).is_true()


func test_a_player_the_fog_has_no_block_for_sees_every_row_as_targeting_does() -> void:
	var world: World = ViewWorlds.crafted()
	for player: int in [0, 3]:
		var view: PlayerView = PlayerView.of(world, player)
		var others: int = 0
		for row: int in world.unit_count():
			assert_bool(Targeting.sees(world, player, world.pos_x[row], world.pos_y[row])).is_true()
			if world.owner[row] != player:
				others += 1
				assert_bool(_in(view.seen_rows, row)).is_true()
		assert_int(view.seen_rows.size()).is_equal(others)
	# The neutral player owns the two neutral rows and sees the other seven.
	assert_int(PlayerView.of(world, 0).own_rows.size()).is_equal(2)
	assert_int(PlayerView.of(world, 0).seen_rows.size()).is_equal(7)


func test_making_a_view_writes_nothing_to_the_world() -> void:
	var world: World = ViewWorlds.crafted()
	var hash_before: int = world.state_hash()
	var stats: PackedInt32Array = world.stats.duplicate()
	var rows_version: int = world.rows_version
	var first: PlayerView = PlayerView.of(world, 1)
	var second: PlayerView = PlayerView.of(world, 1)
	PlayerView.of(world, 2)
	assert_int(world.state_hash()).is_equal(hash_before)
	assert_array(Array(world.stats)).is_equal(Array(stats))
	assert_int(world.rows_version).is_equal(rows_version)
	# The same World and player give the same view, row for row.
	assert_array(Array(first.own_rows)).is_equal(Array(second.own_rows))
	assert_array(Array(first.seen_rows)).is_equal(Array(second.seen_rows))
