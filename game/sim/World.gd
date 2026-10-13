class_name World
extends RefCounted
## Simulation state v1 (ADR 0007 section 2): struct-of-arrays, integers only. Positions are
## milli-tiles (1 tile = 1000). Units are rows in the per-unit arrays, ascending by id. Ids come
## from a counter that starts at 1 and are never reused. Removal keeps the rows in id order, so an
## id is found by binary search. The view and input read a World and never write to it. Every array
## and scalar is declared here and listed in one shape list (ADR 0007 section 2); the state hash
## (ADR 0007 section 8) walks those lists.

enum Order { IDLE = 0, ATTACK_MOVE = 1, MOVE = 2, ATTACK = 3 }
enum Armour { INFANTRY = 0, LIGHT = 1, HEAVY = 2, BUILDING = 3 }
enum MoveClass { FOOT = 0, WHEELED = 1, TRACKED = 2 }
enum Event { SPAWNED = 1, DIED = 2, SHOT = 3, IMPACT = 4 }
enum NavMode { NONE = 0, DIRECT = 1, FIELD = 2, HOLD = 3, CHASE = 4 }
## The indexes of `stats`: flow cells settled, line checks, separation pairs tested, targeting
## candidates tested, fog cells stamped, projectile steps and rows moved by a compaction.
enum Stat {
	FLOW_CELLS = 0,
	LINE_CHECKS = 1,
	SEP_PAIRS = 2,
	TARGET_CANDIDATES = 3,
	FOG_CELLS = 4,
	PROJ_STEPS = 5,
	ROWS_COMPACTED = 6,
}

## Same value as Sim.MILLI_PER_TILE, which P3 adds. World cannot read it from Sim (Sim reads World).
const MILLI_PER_TILE: int = 1000
const TILE_CENTRE: int = 500
## Ints per record in `events`.
const EVENT_STRIDE: int = 8
## The layout version of the hashed state.
const STATE_FORMAT: int = 1
## The hash sections that are not a ROW_ARRAYS column: header, map, projectiles and fog.
const HASH_OTHER_SECTIONS: int = 4

## What prepare() fills a type table with for a type that has no entry. A padded type cannot
## fire, sees only its own tile and counts as tracked. These are not balance numbers.
const TYPE_PAD_MAX_HP: int = 1
const TYPE_PAD_ARMOUR: int = Armour.INFANTRY
const TYPE_PAD_MOVE_CLASS: int = MoveClass.TRACKED
const TYPE_PAD_SIGHT: int = 0
const TYPE_PAD_ACQUIRE: int = 0
const TYPE_PAD_WEAPON: int = -1
## For the four Phase 1 tables (speed, radius, selection radius, spacing).
const TYPE_PAD_V0: int = 0
## The cost of open grass for every class, 10 = normal ground (ADR 0008 section 1). It equals the
## default TerrainDef.cost, which a test pins: prepare() may run in the tick and reads no Resource.
const GRASS_COST: int = 10
## The id of open grass, the one terrain of a map without a MapDef. It equals the first terrain of
## data/terrain/standard.tres, which a test pins.
const GRASS_ID: StringName = &"grass"
## The cell sides of the spatial grids (ADR 0008 section 4, ADR 0009): structural, not balance
## numbers, so not in RulesDef. Targeting reads `target_grid.cell_milli`, never a second 4000.
const SEP_CELL_MILLI: int = MILLI_PER_TILE
const TARGET_CELL_MILLI: int = 4 * MILLI_PER_TILE

## The per-unit columns, in this order.
const ROW_ARRAYS: Array[StringName] = [
	&"unit_id",
	&"owner",
	&"type_index",
	&"pos_x",
	&"pos_y",
	&"goal_x",
	&"goal_y",
	&"order",
	&"hp",
	&"order_target",
	&"target",
	&"cooldown",
	&"nav_mode",
	&"field",
	&"nav_cell",
	&"nav_next",
	&"best_dist",
	&"stall",
	&"fog_cell",
]
## The per-type tables, one entry per type_ids entry once prepare() has run.
const TYPE_ARRAYS: Array[StringName] = [
	&"type_speed",
	&"type_radius",
	&"type_selection_radius",
	&"type_spacing",
	&"type_max_hp",
	&"type_armour",
	&"type_move_class",
	&"type_sight",
	&"type_acquire",
	&"type_weapon",
	&"type_names",
]
## The weapon tables, one entry per weapon (weapon_vs_armour has four).
const WEAPON_ARRAYS: Array[StringName] = [
	&"weapon_range",
	&"weapon_min_range",
	&"weapon_damage",
	&"weapon_cooldown",
	&"weapon_projectile_speed",
	&"weapon_vs_armour",
]
## The projectile slots, max_projectiles entries each. proj_free is the stack of free slots.
const PROJECTILE_ARRAYS: Array[StringName] = [
	&"proj_id",
	&"proj_owner",
	&"proj_weapon",
	&"proj_target",
	&"proj_x",
	&"proj_y",
	&"proj_aim_x",
	&"proj_aim_y",
	&"proj_ticks",
	&"proj_free",
]
## The tile grid: the terrain index per cell, the move cost per class and cell, and the cost per
## terrain and class that set_terrain copies into it.
const MAP_ARRAYS: Array[StringName] = [&"terrain", &"move_cost", &"terrain_cost"]
## Per-row working space, max_rows entries each, rewritten every tick. Not state.
const SCRATCH_ARRAYS: Array[StringName] = [&"intent_x", &"intent_y", &"push_x", &"push_y"]
## Rewritten every tick, neither hashed nor compacted.
const RUNTIME_ARRAYS: Array[StringName] = [&"events", &"stats"]

## The int properties that go into the state hash, in hash order: the header ints, then
## map_version (the map grid itself goes in as a cached digest). rng.state() follows them.
const HASHED_SCALARS: Array[StringName] = [
	&"tick",
	&"next_id",
	&"next_projectile_id",
	&"dropped_commands",
	&"projectile_overflow",
	&"spawn_refused",
	&"player_count",
	&"proj_free_top",
	&"map_version",
]
## The rule ints, copied from RulesDef under the same names. defs_hash() covers them.
const RULE_SCALARS: Array[StringName] = [
	&"retarget_period_ticks",
	&"fog_period_ticks",
	&"line_check_period_ticks",
	&"flow_cells_per_tick",
	&"flow_cache_size",
	&"separation_neighbours",
	&"separation_scan",
	&"separation_idle_share",
	&"separation_push_max",
	&"separation_coincident_divisor",
	&"stall_ticks",
	&"stall_range_spacings",
	&"attack_rekey_milli",
	&"max_projectiles",
	&"max_rows",
]
## The other int properties: the map size, the view's rows_version, the map digest cache (it
## follows from map_version and the grid) and the rule ints, which repeat RULE_SCALARS (a literal,
## because `+` on typed constants gives an untyped Array; a test pins the repeat). None is in the
## state hash.
const UNHASHED_SCALARS: Array[StringName] = [
	&"map_w",
	&"map_h",
	&"map_cols",
	&"map_rows",
	&"rows_version",
	&"_map_digest",
	&"_map_digest_version",
	&"retarget_period_ticks",
	&"fog_period_ticks",
	&"line_check_period_ticks",
	&"flow_cells_per_tick",
	&"flow_cache_size",
	&"separation_neighbours",
	&"separation_scan",
	&"separation_idle_share",
	&"separation_push_max",
	&"separation_coincident_divisor",
	&"stall_ticks",
	&"stall_range_spacings",
	&"attack_rekey_milli",
	&"max_projectiles",
	&"max_rows"
]
var tick: int = 0
## Map size in milli-tiles.
var map_w: int = 0
var map_h: int = 0
var next_id: int = 1
## Commands Sim.step rejected (wrong tick, unknown type, no valid unit).
var dropped_commands: int = 0
## Projectile ids start at 1, because projectile id 0 marks a free slot.
var next_projectile_id: int = 1
## Counters since match start: a projectile or a row that did not fit. 0 or more.
var projectile_overflow: int = 0
var spawn_refused: int = 0
## Players are 1..player_count, 0 is neutral.
var player_count: int = 0
## The top of the projectile free stack, 0..max_projectiles.
var proj_free_top: int = 0
## Bumped whenever rows are added or removed, so the view can tell when rows moved.
var rows_version: int = 0
## The sim's random stream (spawn jitter). Never null.
var rng: DetRandom
## The helper objects (ADR 0007 section 2): empty from the start, sized by the first prepare().
## Only `fog` is state; the others are derived. Objects sit in no shape list.
var fog: FogGrid = FogGrid.new()
var flow: FlowCache = FlowCache.new()
var sep_grid: SpatialGrid = SpatialGrid.new()
var target_grid: SpatialGrid = SpatialGrid.new()
## ADR 0007 section 2's one bool check. A bool is neither an int nor a Packed*Array, so no shape
## list holds it and the coverage walk skips it. Not hashed: it follows from the helpers.
var prepared: bool = false

## Rule ints, copied from RulesDef under the same names by _init(). The sim reads these and never
## the Resource.
var retarget_period_ticks: int = 0
var fog_period_ticks: int = 0
var line_check_period_ticks: int = 0
var flow_cells_per_tick: int = 0
var flow_cache_size: int = 0
var separation_neighbours: int = 0
var separation_scan: int = 0
var separation_idle_share: int = 0
var separation_push_max: int = 0
var separation_coincident_divisor: int = 0
var stall_ticks: int = 0
var stall_range_spacings: int = 0
var attack_rekey_milli: int = 0
var max_projectiles: int = 0
var max_rows: int = 0

## Per type. The index is the order of first appearance in the scenario's spawns, then its roster.
## The ranges named on these tables and the weapon tables hold for data that passes test_defs_data;
## from_scenario copies the values and clamps only max hp.
var type_ids: Array[StringName] = []
var type_speed: PackedInt32Array = PackedInt32Array()
var type_radius: PackedInt32Array = PackedInt32Array()
var type_selection_radius: PackedInt32Array = PackedInt32Array()
var type_spacing: PackedInt32Array = PackedInt32Array()
## At least 1.
var type_max_hp: PackedInt32Array = PackedInt32Array()
## A World.Armour.
var type_armour: PackedInt32Array = PackedInt32Array()
## A World.MoveClass.
var type_move_class: PackedInt32Array = PackedInt32Array()
## Sight and acquire range in milli-tiles, 0 or more.
var type_sight: PackedInt32Array = PackedInt32Array()
var type_acquire: PackedInt32Array = PackedInt32Array()
## -1 = unarmed, else a weapon index.
var type_weapon: PackedInt32Array = PackedInt32Array()
## The display name, or the capitalised type id when the definition has none.
var type_names: PackedStringArray = PackedStringArray()

## Per weapon, in the order of first appearance in the unit types. The index is `type_weapon`.
var weapon_ids: Array[StringName] = []
## Milli-tiles, 0 or more. A squared range is made in int64 and never stored.
var weapon_range: PackedInt32Array = PackedInt32Array()
var weapon_min_range: PackedInt32Array = PackedInt32Array()
## At least 1. Damage times a percent is made in int64 and never stored.
var weapon_damage: PackedInt32Array = PackedInt32Array()
## Ticks, at least 1.
var weapon_cooldown: PackedInt32Array = PackedInt32Array()
## Milli-tiles per tick, 0 = hitscan.
var weapon_projectile_speed: PackedInt32Array = PackedInt32Array()
## Percents 0..200, four per weapon: entry `weapon * 4 + Armour`.
var weapon_vs_armour: PackedInt32Array = PackedInt32Array()

## The tile grid. Columns and rows are tiles, 0 until a map is loaded or prepare() derives open
## grass, at most 64 in Phase 2.
var map_cols: int = 0
var map_rows: int = 0
## Bumped by every passability change, 0 or more.
var map_version: int = 0
## Per terrain, in the order of the scenario's terrain set (GRASS_ID alone for open grass).
var terrain_ids: Array[StringName] = []
## Per cell (`(y / 1000) * map_cols + x / 1000`): an index into terrain_ids, 0..255.
var terrain: PackedByteArray = PackedByteArray()
## Entry `class * cells + cell`, 3 classes: 0 = blocked, 10 = normal, up to 40 (ADR 0008).
var move_cost: PackedByteArray = PackedByteArray()
## Entry `terrain * 3 + class` for each terrain index: the numbers move_cost holds, 0 = blocked,
## up to 40 (MapDef.validate keeps them in 0..40). Open grass has the one terrain 0. Only
## from_scenario and prepare() write it, so it is constant during a match.
var terrain_cost: PackedByteArray = PackedByteArray()

## Per unit, ascending by id.
var unit_id: PackedInt32Array = PackedInt32Array()
var owner: PackedInt32Array = PackedInt32Array()
var type_index: PackedInt32Array = PackedInt32Array()
var pos_x: PackedInt32Array = PackedInt32Array()
var pos_y: PackedInt32Array = PackedInt32Array()
var goal_x: PackedInt32Array = PackedInt32Array()
var goal_y: PackedInt32Array = PackedInt32Array()
var order: PackedInt32Array = PackedInt32Array()
## At most the type's max hp. It may go below 0 by at most one hit.
var hp: PackedInt32Array = PackedInt32Array()
## Unit ids, 0 = none.
var order_target: PackedInt32Array = PackedInt32Array()
var target: PackedInt32Array = PackedInt32Array()
## Ticks until the weapon can fire again, 0..the weapon's cooldown_ticks.
var cooldown: PackedInt32Array = PackedInt32Array()
## A World.NavMode.
var nav_mode: PackedInt32Array = PackedInt32Array()
## A flow cache slot, -1 = none.
var field: PackedInt32Array = PackedInt32Array()
## Cells, -1 = none yet.
var nav_cell: PackedInt32Array = PackedInt32Array()
var nav_next: PackedInt32Array = PackedInt32Array()
## A plain distance in milli, 0..0x3FFFFFFF.
var best_dist: PackedInt32Array = PackedInt32Array()
## 0..stall_ticks.
var stall: PackedInt32Array = PackedInt32Array()
## The cell last stamped into the fog, -1 = not stamped.
var fog_cell: PackedInt32Array = PackedInt32Array()

## Projectile slots, max_projectiles entries each. Valid while proj_id is not 0.
## Ids come from next_projectile_id.
var proj_id: PackedInt32Array = PackedInt32Array()
## 1..player_count.
var proj_owner: PackedInt32Array = PackedInt32Array()
## A weapon index.
var proj_weapon: PackedInt32Array = PackedInt32Array()
## A unit id, 0 = none.
var proj_target: PackedInt32Array = PackedInt32Array()
## Milli-tiles inside the map: 0..map_w - 1 and 0..map_h - 1.
var proj_x: PackedInt32Array = PackedInt32Array()
var proj_y: PackedInt32Array = PackedInt32Array()
var proj_aim_x: PackedInt32Array = PackedInt32Array()
var proj_aim_y: PackedInt32Array = PackedInt32Array()
## Ticks to impact: at most max(1, ceil(longest weapon range / slowest projectile speed)),
## 17 with the shipped data, because shots fire only within range.
var proj_ticks: PackedInt32Array = PackedInt32Array()
## Free slot indices 0..max_projectiles - 1, valid below proj_free_top. Filled in descending
## order, so slot 0 is taken first.
var proj_free: PackedInt32Array = PackedInt32Array()

## Per row, max_rows entries, milli-tiles per tick. The intent is -speed..speed (the fastest
## type), the push -separation_push_max..separation_push_max.
var intent_x: PackedInt32Array = PackedInt32Array()
var intent_y: PackedInt32Array = PackedInt32Array()
var push_x: PackedInt32Array = PackedInt32Array()
var push_y: PackedInt32Array = PackedInt32Array()

## Records of EVENT_STRIDE ints for the last tick. Rewritten every tick and not state.
var events: PackedInt32Array = PackedInt32Array()
## This tick's work counts, indexed by Stat. Cleared every tick, each 0 or more and far below the
## int32 limit (one tick's work).
var stats: PackedInt32Array = PackedInt32Array()

## The cache of the map digest (the "map" section of the hash), valid while `_map_digest_version`
## equals `map_version`. Derived, so unhashed.
var _map_digest: int = 0
var _map_digest_version: int = -1


## The rule ints start at the RulesDef script defaults, so a hand-built world is a valid world.
func _init() -> void:
	_copy_rules(RulesDef.new())
	rng = DetRandom.create(0, DetRandom.STREAM_SIM)


## Copies the rule ints from `rules` under the same names.
func _copy_rules(rules: RulesDef) -> void:
	retarget_period_ticks = rules.retarget_period_ticks
	fog_period_ticks = rules.fog_period_ticks
	line_check_period_ticks = rules.line_check_period_ticks
	flow_cells_per_tick = rules.flow_cells_per_tick
	flow_cache_size = rules.flow_cache_size
	separation_neighbours = rules.separation_neighbours
	separation_scan = rules.separation_scan
	separation_idle_share = rules.separation_idle_share
	separation_push_max = rules.separation_push_max
	separation_coincident_divisor = rules.separation_coincident_divisor
	stall_ticks = rules.stall_ticks
	stall_range_spacings = rules.stall_range_spacings
	attack_rekey_milli = rules.attack_rekey_milli
	max_projectiles = rules.max_projectiles
	max_rows = rules.max_rows


## Reads the scenario and its definitions once and returns a prepared world; a null scenario gives
## an empty one. The rules come from `scenario.rules`, else they stay the RulesDef defaults. A null
## `rng` keeps the default stream. The map grid comes from `scenario.map`, which also sets the map
## size; without a map, or with one that fails validate(), the world is open grass of
## `map_size_tiles`. Types come from the spawns (one without a unit is skipped), then the roster.
## `player_count` is the scenario's value, raised to the highest spawn owner. A spawn with a jitter
## draws two values per unit (see _jittered). The SPAWNED events of the setup are dropped. Spawns
## run before prepare(), so no row is refused here: data keeps their total within `max_rows`.
@warning_ignore("shadowed_variable")
static func from_scenario(scenario: ScenarioDef, rng: DetRandom = null) -> World:
	var world: World = World.new()
	if rng != null:
		world.rng = rng
	if scenario == null:
		world.prepare()
		return world
	if scenario.rules != null:
		world._copy_rules(scenario.rules)
	world.player_count = maxi(scenario.player_count, 0)
	var map: MapDef = scenario.map
	if map != null and map.validate().is_empty():
		world._load_map(map)
	else:
		world.map_w = scenario.map_size_tiles.x * MILLI_PER_TILE
		world.map_h = scenario.map_size_tiles.y * MILLI_PER_TILE
		world._derive_open_grass()
	for spawn: SpawnDef in scenario.spawns:
		if spawn == null or spawn.unit == null:
			continue
		var type: int = world._type_for(spawn.unit)
		var move_class: int = world.type_move_class[type]
		var columns: int = maxi(spawn.columns, 1)
		var start_x: int = spawn.origin_tile.x * MILLI_PER_TILE + TILE_CENTRE
		var start_y: int = spawn.origin_tile.y * MILLI_PER_TILE + TILE_CENTRE
		var column: int = 0
		var row: int = 0
		for _slot: int in spawn.count:
			var x: int = start_x + column * spawn.spacing
			var y: int = start_y + row * spawn.spacing
			if spawn.jitter > 0:
				var at: Vector2i = world._jittered(x, y, spawn.jitter, move_class)
				x = at.x
				y = at.y
			world.add_unit(spawn.owner, type, x, y)
			column += 1
			if column == columns:
				column = 0
				row += 1
	for unit: UnitDef in scenario.roster:
		if unit != null:
			world._type_for(unit)
	world.prepare()
	world.events.clear()
	return world


func unit_count() -> int:
	return unit_id.size()


## The row of unit `id`, or -1 when no unit has that id.
func index_of(id: int) -> int:
	var index: int = unit_id.bsearch(id)
	if index < unit_id.size() and unit_id[index] == id:
		return index
	return -1


## Gives every type table one entry per type_ids entry, with the TYPE_PAD_* values (a name is the
## capitalised type id), because Phase 1 code appends only the four Phase 1 tables. It also sizes
## the scratch arrays to max_rows, stats to the Stat count and the projectile slots to
## max_projectiles, and derives open grass from map_w and map_h when no map is loaded. Last it
## configures the helpers, once, because configure() re-creates their arrays, and caches the map
## digest of the hash. Idempotent through `prepared`, so Sim.step calls it every tick. Types,
## players and sizes are fixed before it.
func prepare() -> void:
	if prepared:
		return
	var types: int = type_ids.size()
	_pad(type_speed, types, TYPE_PAD_V0)
	_pad(type_radius, types, TYPE_PAD_V0)
	_pad(type_selection_radius, types, TYPE_PAD_V0)
	_pad(type_spacing, types, TYPE_PAD_V0)
	_pad(type_max_hp, types, TYPE_PAD_MAX_HP)
	_pad(type_armour, types, TYPE_PAD_ARMOUR)
	_pad(type_move_class, types, TYPE_PAD_MOVE_CLASS)
	_pad(type_sight, types, TYPE_PAD_SIGHT)
	_pad(type_acquire, types, TYPE_PAD_ACQUIRE)
	_pad(type_weapon, types, TYPE_PAD_WEAPON)
	var ids: Array[StringName] = type_ids
	var names: PackedStringArray = type_names
	for i: int in range(names.size(), types):
		names.append(String(ids[i]).capitalize())
	# The fixed-capacity arrays. Resizing keeps the contents, so a second call is a no-op.
	intent_x.resize(max_rows)
	intent_y.resize(max_rows)
	push_x.resize(max_rows)
	push_y.resize(max_rows)
	stats.resize(Stat.size())
	if proj_id.size() != max_projectiles:
		_reset_projectile_slots()
	if map_cols == 0:
		_derive_open_grass()
	fog.configure(map_cols, map_rows, player_count)
	flow.configure(map_cols, map_rows, MoveClass.size(), flow_cache_size)
	sep_grid.configure(map_w, map_h, SEP_CELL_MILLI, max_rows)
	target_grid.configure(map_w, map_h, TARGET_CELL_MILLI, max_rows)
	_map_digest_version = -1  # The grid may be new without a map_version bump.
	_map_digest_value()
	prepared = true


## The cell holding the point (x, y) in milli-tiles: `row * map_cols + column`. A point outside
## the map gives the nearest edge cell, so the result is never outside the map (negative values
## divide toward zero and clamp to 0). With no map it is 0.
@warning_ignore("integer_division")
func cell_of(x: int, y: int) -> int:
	if map_cols == 0:
		return 0
	var column: int = clampi(x / MILLI_PER_TILE, 0, map_cols - 1)
	var row: int = clampi(y / MILLI_PER_TILE, 0, map_rows - 1)
	return row * map_cols + column


## Whether a unit of `move_class` may stand on `cell`: its cost there is above 0. True while no
## map is loaded, false for a cell outside the map or a class that does not exist.
func is_passable(cell: int, move_class: int) -> bool:
	if map_cols == 0:
		return true
	var cells: int = map_cols * map_rows
	if cell < 0 or cell >= cells or move_class < 0 or move_class >= MoveClass.size():
		return false
	return move_cost[move_class * cells + cell] > 0


## Makes `cell` the terrain `terrain_index` (an index into terrain_ids) with that terrain's cost
## for each class, and bumps map_version, also when the terrain is the same. A cell outside the
## map or an unknown terrain index changes nothing.
func set_terrain(cell: int, terrain_index: int) -> void:
	var classes: int = MoveClass.size()
	var cells: int = map_cols * map_rows
	if cell < 0 or cell >= cells or terrain_index < 0:
		return
	if (terrain_index + 1) * classes > terrain_cost.size():
		return
	terrain[cell] = terrain_index
	for move_class: int in classes:
		move_cost[move_class * cells + cell] = terrain_cost[terrain_index * classes + move_class]
	map_version += 1
	flow.invalidate(map_version)  # Before any acquire() under the new version.


## Appends an idle unit at (x, y) at its type's max hp (at least 1; 1 for a type with no entry)
## and returns its new id. `type_index` must be an index into type_ids. It writes one SPAWNED
## event and raises player_count to the owner. After prepare() an owner above player_count or a
## row beyond max_rows is refused instead: 0, and spawn_refused counts it. The parameters keep the
## contract's names, so they shadow the arrays of the same name.
@warning_ignore("shadowed_variable")
func add_unit(owner: int, type_index: int, x: int, y: int) -> int:
	if prepared and (owner > player_count or unit_id.size() >= max_rows):
		spawn_refused += 1
		return 0
	var id: int = next_id
	next_id += 1
	unit_id.append(id)
	self.owner.append(owner)
	self.type_index.append(type_index)
	pos_x.append(x)
	pos_y.append(y)
	goal_x.append(x)
	goal_y.append(y)
	order.append(Order.IDLE)
	hp.append(maxi(type_max_hp[type_index], 1) if type_index < type_max_hp.size() else 1)
	order_target.append(0)
	target.append(0)
	cooldown.append(0)
	nav_mode.append(NavMode.NONE)
	field.append(-1)
	nav_cell.append(-1)
	nav_next.append(-1)
	best_dist.append(0x3FFFFFFF)  # No distance yet; equals FlowField.UNREACHED.
	stall.append(0)
	fog_cell.append(-1)
	_push_unit_event(Event.SPAWNED, unit_id.size() - 1)
	rows_version += 1
	player_count = maxi(player_count, owner)
	return id


## Appends the `kind` record (SPAWNED) of row `row` to `events` (ADR 0007 section 10), in place.
func _push_unit_event(kind: int, row: int) -> void:
	var at: int = events.size()
	events.resize(at + EVENT_STRIDE)  # The last two ints of the record stay 0.
	_write_unit_event(at, kind, row)


## Writes the SPAWNED or DIED record of row `row` at `events[at]`, which is already sized.
func _write_unit_event(at: int, kind: int, row: int) -> void:
	events[at] = kind
	events[at + 1] = unit_id[row]
	events[at + 2] = pos_x[row]
	events[at + 3] = pos_y[row]
	events[at + 4] = type_index[row]
	events[at + 5] = owner[row]


## Removes every row with hp of 0 or less, the last step of a tick (ADR 0007 section 3): a DIED
## record per dead row, in row order, then a stable compaction of every ROW_ARRAYS column, so the
## rows stay ascending by id. It bumps rows_version once and adds the rows that changed place to
## stats[ROWS_COMPACTED]. A tick without a death costs one scan. It prepares the world first
## (O(1) once prepared), so a hand-built world works: stats is sized by prepare().
func remove_dead() -> void:
	prepare()
	var count: int = unit_id.size()
	var alive: PackedInt32Array = hp
	var first: int = 0
	while first < count and alive[first] > 0:
		first += 1
	if first == count:
		return
	var dead: int = 0
	for row: int in range(first, count):
		if alive[row] <= 0:
			dead += 1
	# One resize for all the records, then the writes: the loops allocate nothing.
	var at: int = events.size()
	events.resize(at + dead * EVENT_STRIDE)  # The last two ints of each record stay 0.
	for row: int in range(first, count):
		if alive[row] <= 0:
			_write_unit_event(at, Event.DIED, row)
			at += EVENT_STRIDE
	# hp is the test for every column, so it goes last.
	for column_name: StringName in ROW_ARRAYS:
		if column_name != &"hp":
			var column: PackedInt32Array = get(column_name)
			_compact(column, alive, first, count)
	_compact(alive, alive, first, count)
	stats[Stat.ROWS_COMPACTED] += count - first - dead
	rows_version += 1


## The start point of a unit whose grid point is (x, y) and whose spawn has a `jitter` above 0: the
## point moved by -jitter..jitter on each axis (always two draws, x then y), clamped into the map,
## and kept only when its tile is passable for `move_class`. Otherwise the unit starts on the grid
## point. Data keeps every grid point inside the map and passable (test_defs_data), so the unit is
## never more than `jitter` away on an axis; a grid point that is not, is not repaired here.
func _jittered(x: int, y: int, jitter: int, move_class: int) -> Vector2i:
	var moved_x: int = x + rng.range_int(-jitter, jitter)
	var moved_y: int = y + rng.range_int(-jitter, jitter)
	if map_cols > 0:
		moved_x = clampi(moved_x, 0, map_w - 1)
		moved_y = clampi(moved_y, 0, map_h - 1)
		if not is_passable(cell_of(moved_x, moved_y), move_class):
			return Vector2i(x, y)
	return Vector2i(moved_x, moved_y)


## Sizes every projectile slot array to max_projectiles, all slots free. Only the first prepare()
## calls it (the sizes match afterwards). Changing max_projectiles after prepare() is not supported.
func _reset_projectile_slots() -> void:
	var slots: int = max_projectiles
	for column_name: StringName in PROJECTILE_ARRAYS:
		var column: PackedInt32Array = get(column_name)
		column.clear()
		column.resize(slots)
	var stack: PackedInt32Array = proj_free
	for i: int in slots:
		stack[i] = slots - 1 - i
	proj_free_top = slots


## Open grass over map_w x map_h rounded up to whole tiles (ADR 0007 section 2): terrain 0 on
## every cell, normal ground for every class. A size of 0 or less on either axis leaves no map:
## both counts are 0, never a grid with columns and no rows.
@warning_ignore("integer_division")
func _derive_open_grass() -> void:
	map_cols = (map_w + MILLI_PER_TILE - 1) / MILLI_PER_TILE
	map_rows = (map_h + MILLI_PER_TILE - 1) / MILLI_PER_TILE
	if map_cols <= 0 or map_rows <= 0:
		map_cols = 0
		map_rows = 0
	var cells: int = map_cols * map_rows
	var classes: int = MoveClass.size()
	terrain.resize(cells)
	move_cost.resize(classes * cells)
	move_cost.fill(GRASS_COST)
	terrain_cost.resize(classes)
	terrain_cost.fill(GRASS_COST)
	terrain_ids.resize(1)  # In place, so a later prepare() allocates nothing.
	terrain_ids[0] = GRASS_ID


## Copies a map that validate() accepted: its size, the terrain index of each tile and the cost
## per class of each terrain and tile. The terrain index is the position in the terrain set.
func _load_map(map: MapDef) -> void:
	var defs: Array[TerrainDef] = map.terrain.terrains
	var rows: PackedStringArray = map.rows
	var classes: int = MoveClass.size()
	var index_of_symbol: Dictionary[int, int] = {}
	terrain_cost.resize(defs.size() * classes)
	for index: int in defs.size():
		var def: TerrainDef = defs[index]
		terrain_ids.append(def.id)
		if len(def.symbol) == 1:
			index_of_symbol[def.symbol.unicode_at(0)] = index
		for move_class: int in classes:
			terrain_cost[index * classes + move_class] = def.cost[move_class]
	var size: Vector2i = map.size_tiles()
	map_cols = size.x
	map_rows = size.y
	map_w = size.x * MILLI_PER_TILE
	map_h = size.y * MILLI_PER_TILE
	var cells: int = size.x * size.y
	terrain.resize(cells)
	move_cost.resize(classes * cells)
	var kind_at: PackedByteArray = terrain
	var costs: PackedByteArray = terrain_cost
	var cost_at: PackedByteArray = move_cost
	for ty: int in size.y:
		var line: String = rows[ty]
		for tx: int in size.x:
			var cell: int = ty * size.x + tx
			var kind: int = index_of_symbol[line.unicode_at(tx)]
			kind_at[cell] = kind
			for move_class: int in classes:
				cost_at[move_class * cells + cell] = costs[kind * classes + move_class]


## Moves the entries of `col` whose `alive` is above 0 down over the dead ones, in order, and cuts
## it to the survivors. Rows before `first`, the first dead row, stay. `alive` may be `col` itself:
## a write never reaches a row still to be read.
static func _compact(col: PackedInt32Array, alive: PackedInt32Array, first: int, end: int) -> void:
	var to: int = first
	for row: int in range(first + 1, end):
		if alive[row] > 0:
			col[to] = col[row]
			to += 1
	col.resize(to)


## Appends `value` to `table` until it has `size` entries.
static func _pad(table: PackedInt32Array, size: int, value: int) -> void:
	for _i: int in range(table.size(), size):
		table.append(value)


## The type index for `unit`'s type_id. A type seen for the first time is copied in, so each
## definition is read once however many spawns use it.
func _type_for(unit: UnitDef) -> int:
	var found: int = type_ids.find(unit.type_id)
	if found >= 0:
		return found
	type_ids.append(unit.type_id)
	type_speed.append(unit.speed)
	type_radius.append(unit.radius)
	type_selection_radius.append(unit.selection_radius)
	type_spacing.append(unit.formation_spacing)
	type_max_hp.append(maxi(unit.max_hp, 1))
	type_armour.append(unit.armour)
	type_move_class.append(unit.move_class)
	type_sight.append(unit.sight_range)
	type_acquire.append(unit.acquire_range)
	type_weapon.append(_weapon_for(unit.weapon))
	var label: String = unit.display_name
	type_names.append(label if not label.is_empty() else String(unit.type_id).capitalize())
	return type_ids.size() - 1


## The weapon index for `weapon`, -1 for none. A weapon is known by its id like a type by its
## type_id: the first definition of an id is copied in and wins. A definition has four percents
## (a data test pins it for the shipped ones), so each weapon takes four table entries.
func _weapon_for(weapon: WeaponDef) -> int:
	if weapon == null:
		return -1
	var found: int = weapon_ids.find(weapon.id)
	if found >= 0:
		return found
	weapon_ids.append(weapon.id)
	weapon_range.append(weapon.range)
	weapon_min_range.append(weapon.min_range)
	weapon_damage.append(weapon.damage)
	weapon_cooldown.append(weapon.cooldown_ticks)
	weapon_projectile_speed.append(weapon.projectile_speed)
	for armour: int in Armour.size():
		weapon_vs_armour.append(weapon.vs_armour[armour])
	return weapon_ids.size() - 1


## The state hash (ADR 0007 section 8): SHA-256 over the sections of hash_section_names(), in that
## order, each block fed as its tag (the section index), its byte count and its bytes (little
## endian); the first 8 digest bytes as a signed int64. It reads only the hashed lists: the header
## ints and the stream, the map digest, the ROW_ARRAYS columns, the live projectile slots with the
## used free stack, and FogGrid.HASHED. A hand-built world hashes before prepare() too (empty
## helpers and map), to another value than after it.
func state_hash() -> int:
	var ctx: HashingContext = _start_hash()
	for section: int in ROW_ARRAYS.size() + HASH_OTHER_SECTIONS:
		_feed_section(ctx, section)
	return ctx.finish().decode_s64(0)


## One digest prefix per section, in hash_section_names() order, of the bytes state_hash() feeds.
## For the failure message of a test that compares two hashes; it is not called in the tick.
func hash_parts() -> PackedInt64Array:
	var parts: PackedInt64Array = PackedInt64Array()
	for section: int in ROW_ARRAYS.size() + HASH_OTHER_SECTIONS:
		var ctx: HashingContext = _start_hash()
		_feed_section(ctx, section)
		parts.append(ctx.finish().decode_s64(0))
	return parts


## "header", "map", one name per ROW_ARRAYS entry, "projectiles", "fog".
static func hash_section_names() -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray(["header", "map"])
	names.append_array(PackedStringArray(ROW_ARRAYS))
	names.append_array(PackedStringArray(["projectiles", "fog"]))
	return names


## `h` as 16 lower-case hex digits, its 8 bytes least significant first (ADR 0007 section 8).
static func hash_hex(h: int) -> String:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(8)
	bytes.encode_s64(0, h)
	return bytes.hex_encode()


## The hash of the type and weapon tables, their ids and the rule ints: what a replay needs to see
## that it runs on other data. Call it on a prepared world, because prepare() pads the type tables.
func defs_hash() -> int:
	var ctx: HashingContext = _start_hash()
	var tag: int = 0
	for table_name: StringName in TYPE_ARRAYS + WEAPON_ARRAYS:
		_feed(ctx, tag, _bytes_of(get(table_name)))
		tag += 1
	var rules: PackedInt64Array = PackedInt64Array()
	for rule_name: StringName in RULE_SCALARS:
		rules.append(get(rule_name))
	_feed(ctx, tag, rules.to_byte_array())
	_feed(ctx, tag + 1, PackedStringArray(type_ids).to_byte_array())
	_feed(ctx, tag + 2, PackedStringArray(weapon_ids).to_byte_array())
	return ctx.finish().decode_s64(0)


## The digest of MAP_ARRAYS in list order, recomputed only when map_version has changed.
func _map_digest_value() -> int:
	if _map_digest_version != map_version:
		var ctx: HashingContext = _start_hash()
		for index: int in MAP_ARRAYS.size():
			_feed(ctx, index, _bytes_of(get(MAP_ARRAYS[index])))
		_map_digest = ctx.finish().decode_s64(0)
		_map_digest_version = map_version
	return _map_digest


## Feeds the blocks of section `section`, an index into hash_section_names().
func _feed_section(ctx: HashingContext, section: int) -> void:
	var rows_end: int = 2 + ROW_ARRAYS.size()
	if section == 0:
		var header: PackedInt64Array = PackedInt64Array([STATE_FORMAT])
		for scalar_name: StringName in HASHED_SCALARS:
			header.append(get(scalar_name))
		header.append_array(rng.state())
		_feed(ctx, section, header.to_byte_array())
	elif section == 1:
		_feed(ctx, section, PackedInt64Array([_map_digest_value()]).to_byte_array())
	elif section < rows_end:
		_feed(ctx, section, _bytes_of(get(ROW_ARRAYS[section - 2])))
	elif section == rows_end:
		_feed_projectiles(ctx, section)
	else:
		for array_name: StringName in FogGrid.HASHED:
			_feed(ctx, section, _bytes_of(fog.get(array_name)))


## The live slots (index, then the fields in PROJECTILE_ARRAYS order), then the used free stack.
func _feed_projectiles(ctx: HashingContext, section: int) -> void:
	var columns: Array[PackedInt32Array] = []
	for column_name: StringName in PROJECTILE_ARRAYS:
		if column_name != &"proj_free":
			columns.append(get(column_name))
	var ids: PackedInt32Array = proj_id
	var live_count: int = 0
	for slot: int in ids.size():
		if ids[slot] != 0:
			live_count += 1
	var live: PackedInt32Array = PackedInt32Array()
	live.resize(live_count * (columns.size() + 1))  # One resize, then writes by index.
	var at: int = 0
	for slot: int in ids.size():
		if ids[slot] != 0:
			live[at] = slot
			at += 1
			for column: PackedInt32Array in columns:
				live[at] = column[slot]
				at += 1
	_feed(ctx, section, live.to_byte_array())
	_feed(ctx, section, proj_free.slice(0, proj_free_top).to_byte_array())


static func _start_hash() -> HashingContext:
	var ctx: HashingContext = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	return ctx


## One block: the tag and the byte count as two int64, then the bytes (update() refuses none).
static func _feed(ctx: HashingContext, tag: int, bytes: PackedByteArray) -> void:
	ctx.update(PackedInt64Array([tag, bytes.size()]).to_byte_array())
	if not bytes.is_empty():
		ctx.update(bytes)


## A byte array as it is, any other Packed array little-endian (strings as null-terminated UTF-8).
static func _bytes_of(table: Variant) -> PackedByteArray:
	if table is PackedByteArray:
		return table
	return table.to_byte_array()
