class_name FogGrid
extends RefCounted
## The fog of war of every player (ADR 0010 section 1); players are 1..player_count, blocks are
## indexed player - 1. All state stamp() changes lives in Packed arrays or int members, sized by
## configure() and add_mask(), so a C++ kernel can write it in place (ADR 0013 section 2).
## stamp() has a C++ twin in the FOG kernel (core/fog.cpp, P46n), which FogUpdate.run calls when
## the World runs that phase natively; the GDScript stamp stays for World.prepare(), the unstamp of
## World.remove_dead and the web path, and a change to it edits both and passes the kernel's tests.

## Same value as World.MILLI_PER_TILE (a test pins the pair).
const MILLI_PER_TILE: int = 1000
## The arrays the state hash covers.
const HASHED: Array[StringName] = [&"visible", &"explored"]
## Every other int and Packed array of the class: the sizes, the version, the dirty-list blocks
## and the masks (ADR 0007 section 8 lists each one exactly once).
const UNHASHED: Array[StringName] = [
	&"cols",
	&"rows",
	&"cells",
	&"player_count",
	&"dirty_capacity",
	&"version",
	&"dirty",
	&"dirty_count",
	&"dirty_full",
	&"listed",
	&"mask_start",
	&"mask_radius",
	&"mask_half",
]

var cols: int = 0
var rows: int = 0
## cols * rows, the length of one player's block of visible and explored.
var cells: int = 0
var player_count: int = 0
## Entries in one player's dirty block: a quarter of the cells (ADR 0010 section 1).
var dirty_capacity: int = 0

## The number of sight discs covering each cell, at (player - 1) * cells + cell.
var visible: PackedInt32Array = PackedInt32Array()
## 1 once any disc of the player has covered the cell, same layout. Never cleared.
var explored: PackedByteArray = PackedByteArray()
var version: PackedInt32Array = PackedInt32Array()
## The dirty lists: one flat array of player_count blocks of dirty_capacity cells each.
var dirty: PackedInt32Array = PackedInt32Array()
## Per player, how many entries of its block are used (never above dirty_capacity).
var dirty_count: PackedInt32Array = PackedInt32Array()
## Per player, 1 when a flip found its block full since the last begin_update.
var dirty_full: PackedInt32Array = PackedInt32Array()
## 1 while the cell is in the player's dirty list, same layout as visible: a cell is listed once.
var listed: PackedByteArray = PackedByteArray()
## Per mask: where its rows start in mask_half, and how many rows it reaches above and below
## its centre. mask_half holds each row's half-width in tiles, from dy = -radius down.
var mask_start: PackedInt32Array = PackedInt32Array()
var mask_radius: PackedInt32Array = PackedInt32Array()
var mask_half: PackedInt32Array = PackedInt32Array()

## Sizes every grid for `cols` x `rows` cells and `player_count` players and clears them. The
## masks are kept. The parameters keep the contract's names, so they shadow the members.
@warning_ignore("shadowed_variable", "integer_division")
func configure(cols: int, rows: int, player_count: int) -> void:
	self.cols = cols
	self.rows = rows
	self.player_count = player_count
	cells = cols * rows
	dirty_capacity = cells / 4
	visible = _zeros(player_count * cells)
	explored = PackedByteArray()
	explored.resize(player_count * cells)
	listed = explored.duplicate()
	version = _zeros(player_count)
	dirty = _zeros(player_count * dirty_capacity)
	dirty_count = _zeros(player_count)
	dirty_full = _zeros(player_count)


## Adds the sight disc of `sight_milli` (>= 0) and returns its id, 0, 1, 2 in call order. The
## disc covers the tiles with (dx * 1000)^2 + (dy * 1000)^2 <= sight_milli^2, centre to centre.
@warning_ignore("integer_division")
func add_mask(sight_milli: int) -> int:
	var radius: int = sight_milli / MILLI_PER_TILE
	mask_start.append(mask_half.size())
	mask_radius.append(radius)
	var squared: int = sight_milli * sight_milli
	for dy: int in range(-radius, radius + 1):
		var left: int = squared - dy * dy * MILLI_PER_TILE * MILLI_PER_TILE
		mask_half.append(FixedMath.isqrt(left) / MILLI_PER_TILE)
	return mask_start.size() - 1


## Adds `delta` (+1 stamps, -1 unstamps) to the visible count of every cell of the mask's disc
## centred on `cell`, clipped to the map, and marks the cells it leaves visible as explored. A
## cell turns explored only as it turns visible, so a flip is a count crossing 0. A cell that
## flips goes into the player's dirty block once per update, however often it flips (so a
## re-stamp lists the cells of both discs when the old one is unstamped first, and only the
## cells that change when the new one is stamped first); a cell that finds the block full sets
## its flag instead. The version grows by one if any cell flipped. `cell` must be in the map,
## `player` and `mask` valid. It allocates nothing.
@warning_ignore("integer_division")
func stamp(player: int, cell: int, mask: int, delta: int) -> void:
	var block: int = player - 1
	var base: int = block * cells
	var width: int = cols
	var centre_x: int = cell % width
	var centre_y: int = cell / width
	var radius: int = mask_radius[mask]
	var spans: int = mask_start[mask] + radius - centre_y
	var half: PackedInt32Array = mask_half
	var counts: PackedInt32Array = visible
	var seen: PackedByteArray = explored
	var marks: PackedByteArray = listed
	var list: PackedInt32Array = dirty
	var list_at: int = block * dirty_capacity
	var capacity: int = dirty_capacity
	var used: int = dirty_count[block]
	var flipped: bool = false
	var overflowed: bool = false
	for y: int in range(maxi(centre_y - radius, 0), mini(centre_y + radius, rows - 1) + 1):
		var reach: int = half[spans + y]
		var row_at: int = y * width
		for x: int in range(maxi(centre_x - reach, 0), mini(centre_x + reach, width - 1) + 1):
			var at: int = row_at + x
			var before: int = counts[base + at]
			var after: int = before + delta
			counts[base + at] = after
			if after > 0:
				seen[base + at] = 1
			if (before > 0) == (after > 0):
				continue
			flipped = true
			if marks[base + at] != 0:
				continue
			if used < capacity:
				list[list_at + used] = at
				used += 1
				marks[base + at] = 1
			else:
				overflowed = true
	dirty_count[block] = used
	if overflowed:
		dirty_full[block] = 1
	if flipped:
		version[block] += 1


func is_visible(player: int, cell: int) -> bool:
	return visible[(player - 1) * cells + cell] > 0


func is_explored(player: int, cell: int) -> bool:
	return explored[(player - 1) * cells + cell] != 0


## The number of stamps that flipped a cell of the player; a changed value means cells to patch.
func version_of(player: int) -> int:
	return version[player - 1]


## The used part of the player's dirty block: the cells that flipped since its last
## begin_update, each once, in the order of its first flip. A copy, for the view; the sim never
## calls it.
func dirty_cells(player: int) -> PackedInt32Array:
	var at: int = (player - 1) * dirty_capacity
	return dirty.slice(at, at + dirty_count[player - 1])


## Whether the player's block overflowed, so dirty_cells() is only a prefix.
func dirty_overflowed(player: int) -> bool:
	return dirty_full[player - 1] != 0


## Empties the player's dirty list and clears its flag and the marks of its cells. Nothing is
## resized.
func begin_update(player: int) -> void:
	var block: int = player - 1
	var marks: PackedByteArray = listed
	var list: PackedInt32Array = dirty
	var base: int = block * cells
	var list_at: int = block * dirty_capacity
	for entry: int in dirty_count[block]:
		marks[base + list[list_at + entry]] = 0
	dirty_count[block] = 0
	dirty_full[block] = 0


## Makes `dst` an independent copy (ADR 0012 section 3): every Packed array of HASHED and
## UNHASHED is a duplicate() and every int is copied, so a later write here never reaches `dst`.
func copy_into(dst: FogGrid) -> void:
	dst.cols = cols
	dst.rows = rows
	dst.cells = cells
	dst.player_count = player_count
	dst.dirty_capacity = dirty_capacity
	dst.visible = visible.duplicate()
	dst.explored = explored.duplicate()
	dst.version = version.duplicate()
	dst.dirty = dirty.duplicate()
	dst.dirty_count = dirty_count.duplicate()
	dst.dirty_full = dirty_full.duplicate()
	dst.listed = listed.duplicate()
	dst.mask_start = mask_start.duplicate()
	dst.mask_radius = mask_radius.duplicate()
	dst.mask_half = mask_half.duplicate()


static func _zeros(count: int) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	out.resize(count)
	return out
