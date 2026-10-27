class_name MatchSnapshot
extends RefCounted
## The view's copy of one tick (ADR 0012 section 3, plan P38s; v2: ADR 0017 section 6, plan P81).
## capture() fills it from the World: every COPIED array and every ID_LISTS list by duplicate()
## (O(1); the World's next write copies the buffer), the COPIED_SCALARS, the fog by
## FogGrid.copy_into, plus the prev positions the view interpolates from (ADR 0011 section 2). One
## new snapshot per publish: nobody writes a published one, so its arrays may be shared with the
## next snapshot. Pure: no Node, no clock, no engine singleton.
##
## The header order is fixed (ADR 0012 section 3): the creator sets `match_serial` before
## capture(), which compares it with `previous.match_serial`; `last_hash` is set by the creator
## (TickJob, plan P38j) from the loop. capture() sets neither, because the World holds neither.

## The World columns the snapshot carries, under their World names: rows, with the four harvest
## columns; the type and weapon tables the view reads (ADR 0011 section 1, with `type_armour`, ADR
## 0012's amendment), `type_radius` and every Phase 3 type table; the projectile slots it draws;
## the map, with `move_cost` and `terrain_buildable` (the ghost's Placement.reason, ADR 0017 section
## 2) and `ore_cell`; and, from ADR 0017 section 6, every PLAYER_ARRAYS, ORE_ARRAYS and GHOST_ARRAYS
## array and the derived power totals, which ECONOMY has rebuilt by the end of the step.
const COPIED: Array[StringName] = [
	&"unit_id",
	&"owner",
	&"type_index",
	&"pos_x",
	&"pos_y",
	&"order",
	&"hp",
	&"target",
	&"harvest_mode",
	&"cargo",
	&"harvest_slot",
	&"home",
	&"ready_tick",
	&"offline_until",
	&"type_speed",
	&"type_radius",
	&"type_selection_radius",
	&"type_max_hp",
	&"type_armour",
	&"type_weapon",
	&"type_names",
	&"type_foot_w",
	&"type_foot_h",
	&"type_cost",
	&"type_build_ticks",
	&"type_tab",
	&"type_requires",
	&"type_produces",
	&"type_power",
	&"type_harvest",
	&"type_free_unit",
	&"type_dock_x",
	&"type_dock_y",
	&"type_exit_x",
	&"type_exit_y",
	&"type_faction",
	&"type_strike_kind",
	&"type_charge_ticks",
	&"type_strike_radius",
	&"weapon_projectile_speed",
	&"proj_id",
	&"proj_owner",
	&"proj_weapon",
	&"proj_x",
	&"proj_y",
	&"terrain",
	&"move_cost",
	&"terrain_buildable",
	&"ore_cell",
	&"credits",
	&"defeated_tick",
	&"had_producer",
	&"stat_built",
	&"stat_lost_units",
	&"stat_lost_buildings",
	&"stat_harvested",
	&"queue_count",
	&"queue_progress",
	&"rally_x",
	&"rally_y",
	&"queue_type",
	&"strike_x",
	&"strike_y",
	&"strike_tick",
	&"ore_amount",
	&"ghost_id",
	&"ghost_type",
	&"ghost_owner",
	&"ghost_cell",
	&"ghost_count",
	&"power_made",
	&"power_used",
]
## Every other array of the World's ROW_ARRAYS, TYPE_ARRAYS, WEAPON_ARRAYS, PROJECTILE_ARRAYS,
## MAP_ARRAYS, PLAYER_ARRAYS, ORE_ARRAYS, GHOST_ARRAYS and DERIVED_ARRAYS: the sim's working state,
## which no view reads. With COPIED it covers those nine lists exactly once (a coverage test), so a
## new World array fails until it is classified. `terrain_cost` is here (the view needs `terrain`,
## `terrain_ids` and `move_cost`), and so are the derived `building_rows` and `harvester_rows`
## (ADR 0016: row indexes the sim rebuilds when `rows_version` moves; a view finds buildings by
## `type_foot_w` and harvesters by `type_harvest`).
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
	&"type_spacing",
	&"type_move_class",
	&"type_sight",
	&"type_acquire",
	&"type_strike_delay",
	&"type_strike_ticks",
	&"type_strike_weapon",
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
	&"terrain_cost",
	&"building_rows",
	&"harvester_rows",
]
## The World ints the snapshot carries besides its header: the end of the match (ADR 0018 section
## 7; 0 while it runs) and the two rule ints Placement.reason reads (PlacementInput).
const COPIED_SCALARS: Array[StringName] = [
	&"match_end_tick", &"winner", &"build_reach_tiles", &"building_cap"
]
## The World's Array[StringName] id lists, in no World shape list (ADR 0012's amendment). Each is
## copied by duplicate(): a shallow copy of a few immutable StringNames.
const ID_LISTS: Array[StringName] = [&"type_ids", &"weapon_ids", &"terrain_ids", &"faction_ids"]

## Header. `match_serial` and `last_hash` come from the creator; capture() sets the rest.
var match_serial: int = 0
var tick: int = 0
var rows_version: int = 0
var map_version: int = 0
var last_hash: int = 0
## The end of the match (World meanings, ADR 0018 section 7): 0 while it runs, else the tick the
## ending step produced; the winning player, 0 for none yet or a draw. The runner ticks no more
## once a published snapshot shows the end.
var match_end_tick: int = 0
var winner: int = 0

## Rows, unit_count() entries each, ascending by id (World column meanings).
var unit_id: PackedInt32Array = PackedInt32Array()
var owner: PackedInt32Array = PackedInt32Array()
var type_index: PackedInt32Array = PackedInt32Array()
var pos_x: PackedInt32Array = PackedInt32Array()
var pos_y: PackedInt32Array = PackedInt32Array()
var order: PackedInt32Array = PackedInt32Array()
var hp: PackedInt32Array = PackedInt32Array()
var target: PackedInt32Array = PackedInt32Array()
var harvest_mode: PackedInt32Array = PackedInt32Array()
var cargo: PackedInt32Array = PackedInt32Array()
var harvest_slot: PackedInt32Array = PackedInt32Array()
var home: PackedInt32Array = PackedInt32Array()
## The tick a strike building may fire and the tick a blacked-out building comes back (0 = none).
var ready_tick: PackedInt32Array = PackedInt32Array()
var offline_until: PackedInt32Array = PackedInt32Array()
## The row of `target` in this snapshot, -1 for no target (0) or one that is gone.
var target_row: PackedInt32Array = PackedInt32Array()
## The positions one tick before, aligned to these rows (a new row starts at its position).
var prev_pos_x: PackedInt32Array = PackedInt32Array()
var prev_pos_y: PackedInt32Array = PackedInt32Array()

## The type and weapon tables and the id lists, indexed like the World's.
var type_ids: Array[StringName] = []
var type_speed: PackedInt32Array = PackedInt32Array()
var type_radius: PackedInt32Array = PackedInt32Array()
var type_selection_radius: PackedInt32Array = PackedInt32Array()
var type_max_hp: PackedInt32Array = PackedInt32Array()
var type_armour: PackedInt32Array = PackedInt32Array()
var type_weapon: PackedInt32Array = PackedInt32Array()
var type_names: PackedStringArray = PackedStringArray()
var type_foot_w: PackedInt32Array = PackedInt32Array()
var type_foot_h: PackedInt32Array = PackedInt32Array()
var type_cost: PackedInt32Array = PackedInt32Array()
var type_build_ticks: PackedInt32Array = PackedInt32Array()
var type_tab: PackedInt32Array = PackedInt32Array()
var type_requires: PackedInt32Array = PackedInt32Array()
var type_produces: PackedInt32Array = PackedInt32Array()
var type_power: PackedInt32Array = PackedInt32Array()
var type_harvest: PackedInt32Array = PackedInt32Array()
var type_free_unit: PackedInt32Array = PackedInt32Array()
var type_dock_x: PackedInt32Array = PackedInt32Array()
var type_dock_y: PackedInt32Array = PackedInt32Array()
var type_exit_x: PackedInt32Array = PackedInt32Array()
var type_exit_y: PackedInt32Array = PackedInt32Array()
var type_faction: PackedInt32Array = PackedInt32Array()
## What the strike button, its charge ring and its targeting circle read (ADR 0023 section 10).
var type_strike_kind: PackedInt32Array = PackedInt32Array()
var type_charge_ticks: PackedInt32Array = PackedInt32Array()
var type_strike_radius: PackedInt32Array = PackedInt32Array()
var weapon_ids: Array[StringName] = []
var faction_ids: Array[StringName] = []
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

## The map: 0 x 0 with no map. `terrain` holds an index into `terrain_ids` per cell; the move
## cost per class and cell (0 under a building), the buildable flag per terrain index and the ore
## cells, ascending.
var map_cols: int = 0
var map_rows: int = 0
var terrain: PackedByteArray = PackedByteArray()
var terrain_ids: Array[StringName] = []
var move_cost: PackedByteArray = PackedByteArray()
var terrain_buildable: PackedByteArray = PackedByteArray()
var ore_cell: PackedInt32Array = PackedInt32Array()
## An independent copy of the World's fog; it answers every FogGrid read method.
var fog: FogGrid = FogGrid.new()

## The players (World layouts, ADR 0017 section 3): per player, index 0 neutral; per player and
## tab, `player * World.TABS + tab`; per queue slot, `(player * World.TABS + tab) * queue_slots +
## slot`. Then the ore left per `ore_cell` entry, the last-seen records (`player * ghost_cap + i`,
## live below `ghost_count[player]`) and the power totals per player.
var credits: PackedInt32Array = PackedInt32Array()
var defeated_tick: PackedInt32Array = PackedInt32Array()
var had_producer: PackedInt32Array = PackedInt32Array()
var stat_built: PackedInt32Array = PackedInt32Array()
var stat_lost_units: PackedInt32Array = PackedInt32Array()
var stat_lost_buildings: PackedInt32Array = PackedInt32Array()
var stat_harvested: PackedInt32Array = PackedInt32Array()
var queue_count: PackedInt32Array = PackedInt32Array()
var queue_progress: PackedInt32Array = PackedInt32Array()
var rally_x: PackedInt32Array = PackedInt32Array()
var rally_y: PackedInt32Array = PackedInt32Array()
var queue_type: PackedInt32Array = PackedInt32Array()
## The pending rupture per player, 0 = none: its point and the tick it lands (the warning marker).
var strike_x: PackedInt32Array = PackedInt32Array()
var strike_y: PackedInt32Array = PackedInt32Array()
var strike_tick: PackedInt32Array = PackedInt32Array()
var ore_amount: PackedInt32Array = PackedInt32Array()
var ghost_id: PackedInt32Array = PackedInt32Array()
var ghost_type: PackedInt32Array = PackedInt32Array()
var ghost_owner: PackedInt32Array = PackedInt32Array()
var ghost_cell: PackedInt32Array = PackedInt32Array()
var ghost_count: PackedInt32Array = PackedInt32Array()
var power_made: PackedInt32Array = PackedInt32Array()
var power_used: PackedInt32Array = PackedInt32Array()
## The rule ints Placement.reason reads (RulesDef).
var build_reach_tiles: int = 0
var building_cap: int = 0

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


## The input Placement.reason reads, over this snapshot's arrays (ADR 0017 section 2): the view
## judges a ghost with the code the sim runs on PlacementInput.of_world. Its arrays are this
## snapshot's, which nobody writes after the publish, so it answers as the World did at this tick.
func placement_input() -> PlacementInput:
	var input: PlacementInput = PlacementInput.new()
	input.map_cols = map_cols
	input.map_rows = map_rows
	input.terrain = terrain
	input.terrain_buildable = terrain_buildable
	input.move_cost = move_cost
	input.explored = fog.explored
	input.fog_cells = fog.cells
	input.fog_player_count = fog.player_count
	input.owner = owner
	input.type_index = type_index
	input.pos_x = pos_x
	input.pos_y = pos_y
	input.type_speed = type_speed
	input.type_radius = type_radius
	input.type_foot_w = type_foot_w
	input.type_foot_h = type_foot_h
	input.build_reach_tiles = build_reach_tiles
	input.building_cap = building_cap
	return input


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
	match_end_tick = world.match_end_tick
	winner = world.winner
	build_reach_tiles = world.build_reach_tiles
	building_cap = world.building_cap
	unit_id = world.unit_id.duplicate()
	owner = world.owner.duplicate()
	type_index = world.type_index.duplicate()
	pos_x = world.pos_x.duplicate()
	pos_y = world.pos_y.duplicate()
	order = world.order.duplicate()
	hp = world.hp.duplicate()
	target = world.target.duplicate()
	harvest_mode = world.harvest_mode.duplicate()
	cargo = world.cargo.duplicate()
	harvest_slot = world.harvest_slot.duplicate()
	home = world.home.duplicate()
	ready_tick = world.ready_tick.duplicate()
	offline_until = world.offline_until.duplicate()
	type_speed = world.type_speed.duplicate()
	type_radius = world.type_radius.duplicate()
	type_selection_radius = world.type_selection_radius.duplicate()
	type_max_hp = world.type_max_hp.duplicate()
	type_armour = world.type_armour.duplicate()
	type_weapon = world.type_weapon.duplicate()
	type_names = world.type_names.duplicate()
	type_foot_w = world.type_foot_w.duplicate()
	type_foot_h = world.type_foot_h.duplicate()
	type_cost = world.type_cost.duplicate()
	type_build_ticks = world.type_build_ticks.duplicate()
	type_tab = world.type_tab.duplicate()
	type_requires = world.type_requires.duplicate()
	type_produces = world.type_produces.duplicate()
	type_power = world.type_power.duplicate()
	type_harvest = world.type_harvest.duplicate()
	type_free_unit = world.type_free_unit.duplicate()
	type_dock_x = world.type_dock_x.duplicate()
	type_dock_y = world.type_dock_y.duplicate()
	type_exit_x = world.type_exit_x.duplicate()
	type_exit_y = world.type_exit_y.duplicate()
	type_faction = world.type_faction.duplicate()
	type_strike_kind = world.type_strike_kind.duplicate()
	type_charge_ticks = world.type_charge_ticks.duplicate()
	type_strike_radius = world.type_strike_radius.duplicate()
	weapon_projectile_speed = world.weapon_projectile_speed.duplicate()
	proj_id = world.proj_id.duplicate()
	proj_owner = world.proj_owner.duplicate()
	proj_weapon = world.proj_weapon.duplicate()
	proj_x = world.proj_x.duplicate()
	proj_y = world.proj_y.duplicate()
	terrain = world.terrain.duplicate()
	move_cost = world.move_cost.duplicate()
	terrain_buildable = world.terrain_buildable.duplicate()
	ore_cell = world.ore_cell.duplicate()
	_capture_players(world)
	type_ids = world.type_ids.duplicate()
	faction_ids = world.faction_ids.duplicate()
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


## The player, ore and ghost arrays and the power totals (ADR 0017 section 6), by duplicate().
func _capture_players(world: World) -> void:
	credits = world.credits.duplicate()
	defeated_tick = world.defeated_tick.duplicate()
	had_producer = world.had_producer.duplicate()
	stat_built = world.stat_built.duplicate()
	stat_lost_units = world.stat_lost_units.duplicate()
	stat_lost_buildings = world.stat_lost_buildings.duplicate()
	stat_harvested = world.stat_harvested.duplicate()
	queue_count = world.queue_count.duplicate()
	queue_progress = world.queue_progress.duplicate()
	rally_x = world.rally_x.duplicate()
	rally_y = world.rally_y.duplicate()
	queue_type = world.queue_type.duplicate()
	strike_x = world.strike_x.duplicate()
	strike_y = world.strike_y.duplicate()
	strike_tick = world.strike_tick.duplicate()
	ore_amount = world.ore_amount.duplicate()
	ghost_id = world.ghost_id.duplicate()
	ghost_type = world.ghost_type.duplicate()
	ghost_owner = world.ghost_owner.duplicate()
	ghost_cell = world.ghost_cell.duplicate()
	ghost_count = world.ghost_count.duplicate()
	power_made = world.power_made.duplicate()
	power_used = world.power_used.duplicate()


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
