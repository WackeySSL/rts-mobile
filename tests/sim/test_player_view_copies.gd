extends GdUnitTestSuite
## PlayerView holds no World array (ADR 0038 section 4, plan row P302): after `PlayerView.of`, an
## in-place write to every packed array of the World (and of its fog) changes no answer of the view.

const ViewWorlds: GDScript = preload("res://tests/sim/support/view_worlds.gd")


## Every in-place writable packed array of `world` and its fog: the arrays are shared by reference,
## so a write through the returned handle is a write to the World's own array.
func _sources(world: World) -> Array:
	var found: Array = []
	for holder: Object in [world, world.fog]:
		for info: Dictionary in holder.get_property_list():
			var kind: int = info["type"]
			if kind == TYPE_PACKED_INT32_ARRAY or kind == TYPE_PACKED_BYTE_ARRAY:
				found.append(holder.get(info["name"]))
	return found


## Overwrites every entry of every source array with a value that no answer was built from.
func _scribble(sources: Array) -> int:
	var written: int = 0
	for source: Variant in sources:
		if source is PackedInt32Array:
			var ints: PackedInt32Array = source
			for at: int in ints.size():
				ints[at] = 7777 + at
			written += ints.size()
		else:
			var bytes: PackedByteArray = source
			for at: int in bytes.size():
				bytes[at] = 1 + at % 3
			written += bytes.size()
	return written


## Every answer of `view`: the getters of each World row, `columns()`, `placement`, `is_explored`.
func _answers(view: PlayerView, world: World, rows: int) -> Array:
	var out: Array = []
	for row: int in range(-1, rows + 1):
		(
			out
			. append(
				[
					view.row_id(row),
					view.row_owner(row),
					view.row_type(row),
					view.row_pos(row),
					view.row_hp(row),
					view.row_build_left(row),
					view.row_order(row),
					view._row_harvest_mode(row),
					view.row_home(row),
					view.row_ready_tick(row),
					view.row_offline_until(row),
					view.row_mend(row),
				]
			)
		)
	for column: PackedInt32Array in view.columns():
		out.append(column.duplicate())
	for type: int in view.type_cost.size():
		for line: int in range(-1, world.map_rows + 1):
			for col: int in range(-1, world.map_cols + 1):
				out.append(view.placement(type, col, line))
	for cell: int in world.map_cols * world.map_rows:
		out.append(view.is_explored(cell))
	out.append([view.own_rows, view.seen_rows, view.own_stance, view.credits, view.ore_cells])
	return out


func test_a_write_to_every_world_array_changes_no_answer_of_the_view() -> void:
	for player: int in [1, 2]:
		var world: World = ViewWorlds.crafted()
		var rows: int = world.unit_count()
		var view: PlayerView = PlayerView.of(world, player)
		var before: Array = _answers(view, world, rows)
		assert_int(_scribble(_sources(world))).is_greater(1000)
		assert_array(_answers(view, world, rows)).is_equal(before)
