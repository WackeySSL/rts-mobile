extends RefCounted
## Maps built in code for the sim tests (P37a): a prepared World from one string per tile row, one
## character per tile. Not a test suite.

## The terrain of each character, in the order of GROUND_COST (foot, wheeled, tracked per terrain):
## open grass, scrub that only foot units cross, and rock that nothing crosses.
const GROUND: String = ".^#"
const GROUND_COST: Array[int] = [10, 10, 10, 10, 0, 0, 0, 0, 0]

## A prepared World of the map `rows`, with one unit type per entry of `move_classes` (type 0 is
## `move_classes[0]`). Every type has speed 120, radius 400, selection radius 500 and formation
## spacing 1200; a test may change those tables. `player_count` is 1, so units of player 1 can be
## added after the call. Units are the test's to add.
@warning_ignore("integer_division")
static func from_rows(
	rows: PackedStringArray, move_classes: Array = [World.MoveClass.TRACKED]
) -> World:
	var cols: int = len(rows[0])
	var world: World = World.new()
	world.map_w = cols * World.MILLI_PER_TILE
	world.map_h = rows.size() * World.MILLI_PER_TILE
	world.player_count = 1
	for kind: int in move_classes.size():
		world.type_ids.append(StringName("type%d" % kind))
		world.type_speed.append(120)
		world.type_radius.append(400)
		world.type_selection_radius.append(500)
		world.type_spacing.append(1200)
	world.prepare()
	for kind: int in move_classes.size():
		world.type_move_class[kind] = int(move_classes[kind])
	world.terrain_cost = PackedByteArray(GROUND_COST)
	for cell: int in cols * rows.size():
		world.set_terrain(cell, GROUND.find(rows[cell / cols][cell % cols]))
	return world


## The rows of an all-grass map of `cols` x `rows` tiles, with the `rock` tiles (x, y) set to '#'.
static func grass(cols: int, rows: int, rock: Array = []) -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	for _row: int in rows:
		lines.append(".".repeat(cols))
	for tile: Vector2i in rock:
		lines[tile.y] = lines[tile.y].left(tile.x) + "#" + lines[tile.y].substr(tile.x + 1)
	return lines


## Tiles from [x, y] pairs.
static func tiles(pairs: Array) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	for pair: Array in pairs:
		found.append(Vector2i(int(pair[0]), int(pair[1])))
	return found


## `count` units of player 1 and type `type` on a grid `columns` wide, from (x, y) in steps of
## `step`. Returns their rows.
@warning_ignore("integer_division")
static func add_block(
	world: World, count: int, columns: int, x: int, y: int, step: int, type: int
) -> PackedInt32Array:
	var rows: PackedInt32Array = PackedInt32Array()
	for k: int in count:
		world.add_unit(1, type, x + (k % columns) * step, y + (k / columns) * step)
		rows.append(world.unit_count() - 1)
	return rows


## The goals of `rows`, in row order.
static func goals(world: World, rows: PackedInt32Array) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	for row: int in rows:
		found.append(Vector2i(world.goal_x[row], world.goal_y[row]))
	return found
