extends GdUnitTestSuite
## The one pass of `PlayerView._take_rows` against a plain reference pass (plan row P198c). On random
## Worlds with a real fog, rows on tile borders and rows off the map, for every player (the neutral
## 0 and one past the fog's players see all), the two lists, the level of each row (own, seen,
## hidden, as the getters answer it) and the seven columns are exactly what a row-by-row reading of
## the World gives. The reference is written for clarity: it owns a row when the owner is the
## player, and sees another owner's row by `Targeting.sees`, the rule that the pass inlines.

const TargetingWorlds: GDScript = preload("res://tests/sim/support/targeting_worlds.gd")
const ViewWorlds: GDScript = preload("res://tests/sim/support/view_worlds.gd")
## Positions that sit on or next to tile borders and off the map, on the 30 x 20 map of
## `short_sighted`: the far-half border rule and the clamp both apply.
const EDGES: Array[int] = [
	-500, 0, 999, 1000, 14999, 15000, 15001, 19000, 20000, 29000, 30000, 31000
]


## A World of 60 random rows plus a neutral row, a row on each border value and rows off the map.
func _world(salt: int) -> World:
	var world: World = TargetingWorlds.short_sighted(salt, 30)
	var rng: DetRandom = DetRandom.create(salt, 198)
	for _row: int in 12:
		world.add_unit(0, rng.next_int(2), rng.next_int(30000), rng.next_int(20000))
	for x: int in EDGES:
		for y: int in EDGES:
			world.add_unit(rng.next_int(3), rng.next_int(2), x, y)
	return world


## The rows `player` owns and the rows of other owners it sees, ascending, by the plain rule.
func _reference(world: World, player: int) -> Array[PackedInt32Array]:
	var own: PackedInt32Array = PackedInt32Array()
	var seen: PackedInt32Array = PackedInt32Array()
	for row: int in world.unit_count():
		if world.owner[row] == player:
			own.append(row)
		elif Targeting.sees(world, player, world.pos_x[row], world.pos_y[row]):
			seen.append(row)
	return [own, seen]


func _check(world: World, player: int, tag: String) -> void:
	var view: PlayerView = PlayerView.of(world, player)
	var want: Array[PackedInt32Array] = _reference(world, player)
	assert_array(view.own_rows).override_failure_message(tag + " own").is_equal(want[0])
	assert_array(view.seen_rows).override_failure_message(tag + " seen").is_equal(want[1])
	var rows: int = world.unit_count()
	for row: int in rows:
		var level: int = view._level(row)
		var expected: int = 1 if want[0].has(row) else (2 if want[1].has(row) else 0)
		assert_int(level).override_failure_message("%s row %d" % [tag, row]).is_equal(expected)
		# The getters agree: a hidden row answers MISSING, a seen row has no own columns.
		assert_bool(view.row_id(row) == PlayerView.MISSING).is_equal(expected == 0)
		assert_bool(view.row_order(row) == PlayerView.MISSING).is_equal(expected != 1)
	assert_int(view._level(rows)).is_equal(0)
	assert_int(view._level(-1)).is_equal(0)
	assert_int(view._shown.size()).is_equal(rows)
	var columns: Array[PackedInt32Array] = view.columns()
	var origin: Array[PackedInt32Array] = [
		world.unit_id,
		world.owner,
		world.type_index,
		world.pos_x,
		world.pos_y,
		world.hp,
		world.build_left,
	]
	assert_int(columns.size()).is_equal(origin.size())
	for at: int in origin.size():
		assert_array(columns[at]).override_failure_message("%s column %d" % [tag, at]).is_equal(
			origin[at]
		)


func test_the_pass_gives_the_reference_lists_levels_and_columns_on_random_worlds() -> void:
	for salt: int in [5, 6, 7]:
		var world: World = _world(salt)
		for player: int in [0, 1, 2, 3]:
			_check(world, player, "salt %d player %d" % [salt, player])
		# The lists are not trivial: some own, some seen, some hidden, for the fogged players.
		var view: PlayerView = PlayerView.of(world, 1)
		assert_bool(view.own_rows.size() > 0 and view.seen_rows.size() > 0).is_true()
		assert_bool(view.own_rows.size() + view.seen_rows.size() < world.unit_count()).is_true()


func test_the_pass_gives_the_reference_on_the_crafted_world_and_an_empty_one() -> void:
	var crafted: World = ViewWorlds.crafted()
	for player: int in [0, 1, 2, 3]:
		_check(crafted, player, "crafted player %d" % player)
	var empty: World = TargetingWorlds.short_sighted(5, 0)
	for player: int in [0, 1, 2]:
		_check(empty, player, "empty player %d" % player)
