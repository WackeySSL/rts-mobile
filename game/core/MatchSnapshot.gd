class_name MatchSnapshot
extends RefCounted
## The view's copy of one tick (ADR 0012 section 3, plan P38s). capture() fills it from the World:
## every COPIED array and every ID_LISTS list by duplicate() (O(1); the World's next write copies
## the buffer), the fog by FogGrid.copy_into, plus the prev positions the view interpolates from
## (ADR 0011 section 2). One new snapshot per publish: nobody writes a published one, so its
## arrays may be shared with the next snapshot. Pure: no Node, no clock, no engine singleton.
##
## The header order is fixed (ADR 0012 section 3): the creator sets `match_serial` before
## capture(), which compares it with `previous.match_serial`; `last_hash` is set by the creator
## (TickJob, plan P38j) from the loop. capture() sets neither, because the World holds neither.

## The World columns the snapshot carries, under their World names: rows, the type and weapon
## tables the view reads (ADR 0011 section 1, with `type_armour`, ADR 0012's amendment), the
## projectile slots it draws and the terrain.
const COPIED: Array[StringName] = [
	&"unit_id",
	&"owner",
	&"type_index",
	&"pos_x",
	&"pos_y",
	&"order",
	&"hp",
	&"target",
	&"type_speed",
	&"type_selection_radius",
	&"type_max_hp",
	&"type_armour",
	&"type_weapon",
	&"type_names",
	&"weapon_projectile_speed",
	&"proj_id",
	&"proj_owner",
	&"proj_weapon",
	&"proj_x",
	&"proj_y",
	&"terrain",
]
## Every other column of the World's ROW_ARRAYS, TYPE_ARRAYS, WEAPON_ARRAYS, PROJECTILE_ARRAYS
## and MAP_ARRAYS: the sim's working state, which no view reads. With COPIED it covers those five
## lists exactly once (a coverage test), so a new World column fails until it is classified.
## `move_cost` and `terrain_cost` are here: the view needs only `terrain` and `terrain_ids`.
const NOT_COPIED: Array[StringName] = [
	&"goal_x",
	&"goal_y",
	&"group_cell",
	&"order_target",
	&"cooldown",
	&"nav_mode",
	&"field",
	&"nav_cell",
	&"nav_next",
	&"best_dist",
	&"stall",
	&"fog_cell",
	&"type_radius",
	&"type_spacing",
	&"type_move_class",
	&"type_sight",
	&"type_acquire",
	&"weapon_range",
	&"weapon_min_range",
	&"weapon_damage",
	&"weapon_cooldown",
	&"weapon_vs_armour",
	&"proj_target",
	&"proj_aim_x",
	&"proj_aim_y",
	&"proj_ticks",
	&"proj_free",
	&"move_cost",
	&"terrain_cost",
]
## The World's Array[StringName] id lists, in no World shape list (ADR 0012's amendment). Each is
## copied by duplicate(): a shallow copy of a few immutable StringNames.
const ID_LISTS: Array[StringName] = [&"type_ids", &"weapon_ids", &"terrain_ids"]

## Header. `match_serial` and `last_hash` come from the creator; capture() sets the rest.
var match_serial: int = 0
var tick: int = 0
var rows_version: int = 0
var map_version: int = 0
var last_hash: int = 0

## Rows, unit_count() entries each, ascending by id (World column meanings).
var unit_id: PackedInt32Array = PackedInt32Array()
var owner: PackedInt32Array = PackedInt32Array()
var type_index: PackedInt32Array = PackedInt32Array()
var pos_x: PackedInt32Array = PackedInt32Array()
var pos_y: PackedInt32Array = PackedInt32Array()
var order: PackedInt32Array = PackedInt32Array()
var hp: PackedInt32Array = PackedInt32Array()
var target: PackedInt32Array = PackedInt32Array()
## The row of `target` in this snapshot, -1 for no target (0) or one that is gone.
var target_row: PackedInt32Array = PackedInt32Array()
## The positions one tick before, aligned to these rows (a new row starts at its position).
var prev_pos_x: PackedInt32Array = PackedInt32Array()
var prev_pos_y: PackedInt32Array = PackedInt32Array()

## The type and weapon tables and the id lists, indexed like the World's.
var type_ids: Array[StringName] = []
var type_speed: PackedInt32Array = PackedInt32Array()
var type_selection_radius: PackedInt32Array = PackedInt32Array()
var type_max_hp: PackedInt32Array = PackedInt32Array()
var type_armour: PackedInt32Array = PackedInt32Array()
var type_weapon: PackedInt32Array = PackedInt32Array()
var type_names: PackedStringArray = PackedStringArray()
var weapon_ids: Array[StringName] = []
var weapon_projectile_speed: PackedInt32Array = PackedInt32Array()

## Projectile slots (proj_id 0 = free) and the previous snapshot's slots. A slot whose `proj_id`
## differs from `prev_proj_id` is new in this tick.
var proj_id: PackedInt32Array = PackedInt32Array()
var proj_owner: PackedInt32Array = PackedInt32Array()
var proj_weapon: PackedInt32Array = PackedInt32Array()
var proj_x: PackedInt32Array = PackedInt32Array()
var proj_y: PackedInt32Array = PackedInt32Array()
var prev_proj_id: PackedInt32Array = PackedInt32Array()
var prev_proj_x: PackedInt32Array = PackedInt32Array()
var prev_proj_y: PackedInt32Array = PackedInt32Array()

## The map: 0 x 0 with no map. `terrain` holds an index into `terrain_ids` per cell.
var map_cols: int = 0
var map_rows: int = 0
var terrain: PackedByteArray = PackedByteArray()
var terrain_ids: Array[StringName] = []
## An independent copy of the World's fog; it answers every FogGrid read method.
var fog: FogGrid = FogGrid.new()

## This tick's events (World.EVENT_STRIDE ints each) and work counts (World.Stat).
var events: PackedInt32Array = PackedInt32Array()
var stats: PackedInt32Array = PackedInt32Array()

## Timings in microseconds, set by the tick job (plan P38j): the probe's per-phase split (empty
## without a probe), Sim.step, the whole job, its post and its end.
var phase_usec: PackedInt64Array = PackedInt64Array()
var step_usec: int = 0
var job_usec: int = 0
var post_usec: int = 0
var end_usec: int = 0


func unit_count() -> int:
	return unit_id.size()


## The row of unit `id` (binary search over the ascending ids), or -1 when it is not here.
func index_of(id: int) -> int:
	var ids: PackedInt32Array = unit_id
	var at: int = ids.bsearch(id)
	if at < ids.size() and ids[at] == id:
		return at
	return -1


## The cell of the point (x, y) in milli-tiles, by World.cell_of's formula: clamped into the map,
## so a point outside it gives the nearest edge cell; 0 with no map.
@warning_ignore("integer_division")
func cell_of(x: int, y: int) -> int:
	if map_cols == 0:
		return 0
	var column: int = clampi(x / World.MILLI_PER_TILE, 0, map_cols - 1)
	var row: int = clampi(y / World.MILLI_PER_TILE, 0, map_rows - 1)
	return row * map_cols + column


## Copies the World's tick into this snapshot, whose `match_serial` the caller has set. `previous`
## is the last published snapshot, or null: when it is null or of another match, prev = current,
## as copies (O(1)), so a test that writes this snapshot's pos_* or proj_* to set up a view case
## (ADR 0012 section 3) leaves its prev_* alone. Otherwise prev_proj_* are its proj_*, and
## prev_pos_* are its pos_* while the rows are the same (`rows_version` unchanged, no copy), else
## aligned by id.
func capture(world: World, previous: MatchSnapshot) -> void:
	tick = world.tick
	rows_version = world.rows_version
	map_version = world.map_version
	map_cols = world.map_cols
	map_rows = world.map_rows
	unit_id = world.unit_id.duplicate()
	owner = world.owner.duplicate()
	type_index = world.type_index.duplicate()
	pos_x = world.pos_x.duplicate()
	pos_y = world.pos_y.duplicate()
	order = world.order.duplicate()
	hp = world.hp.duplicate()
	target = world.target.duplicate()
	type_speed = world.type_speed.duplicate()
	type_selection_radius = world.type_selection_radius.duplicate()
	type_max_hp = world.type_max_hp.duplicate()
	type_armour = world.type_armour.duplicate()
	type_weapon = world.type_weapon.duplicate()
	type_names = world.type_names.duplicate()
	weapon_projectile_speed = world.weapon_projectile_speed.duplicate()
	proj_id = world.proj_id.duplicate()
	proj_owner = world.proj_owner.duplicate()
	proj_weapon = world.proj_weapon.duplicate()
	proj_x = world.proj_x.duplicate()
	proj_y = world.proj_y.duplicate()
	terrain = world.terrain.duplicate()
	type_ids = world.type_ids.duplicate()
	weapon_ids = world.weapon_ids.duplicate()
	terrain_ids = world.terrain_ids.duplicate()
	events = world.events.duplicate()
	stats = world.stats.duplicate()
	world.fog.copy_into(fog)
	_fill_target_rows()
	if previous == null or previous.match_serial != match_serial:
		prev_pos_x = pos_x.duplicate()
		prev_pos_y = pos_y.duplicate()
		prev_proj_id = proj_id.duplicate()
		prev_proj_x = proj_x.duplicate()
		prev_proj_y = proj_y.duplicate()
		return
	prev_proj_id = previous.proj_id
	prev_proj_x = previous.proj_x
	prev_proj_y = previous.proj_y
	if previous.rows_version == rows_version:
		prev_pos_x = previous.pos_x
		prev_pos_y = previous.pos_y
	else:
		_align_prev(previous.unit_id, previous.pos_x, previous.pos_y)


## target_row in one walk over the rows: each target id found by binary search over the ascending
## ids, -1 for an id that is not here. Ids start at 1, so a target of 0 (none) is never found.
func _fill_target_rows() -> void:
	var ids: PackedInt32Array = unit_id
	var targets: PackedInt32Array = target
	var count: int = ids.size()
	var rows: PackedInt32Array = PackedInt32Array()
	rows.resize(count)
	for row: int in count:
		var id: int = targets[row]
		var at: int = ids.bsearch(id)
		rows[row] = at if at < count and ids[at] == id else -1
	target_row = rows


## The merge walk of ADR 0011 section 2 over two ascending id lists: a row whose id was in the
## previous snapshot keeps that position as its prev, a new row starts at its position, and the
## previous rows that are gone are skipped.
func _align_prev(
	old_ids: PackedInt32Array, old_x: PackedInt32Array, old_y: PackedInt32Array
) -> void:
	var ids: PackedInt32Array = unit_id
	var xs: PackedInt32Array = pos_x
	var ys: PackedInt32Array = pos_y
	var count: int = ids.size()
	var old_count: int = old_ids.size()
	var out_x: PackedInt32Array = PackedInt32Array()
	var out_y: PackedInt32Array = PackedInt32Array()
	out_x.resize(count)
	out_y.resize(count)
	var old: int = 0
	for row: int in count:
		var id: int = ids[row]
		while old < old_count and old_ids[old] < id:
			old += 1
		if old < old_count and old_ids[old] == id:
			out_x[row] = old_x[old]
			out_y[row] = old_y[old]
		else:
			out_x[row] = xs[row]
			out_y[row] = ys[row]
	prev_pos_x = out_x
	prev_pos_y = out_y
