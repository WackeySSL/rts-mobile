class_name World
extends RefCounted
## Simulation state v2 (ADR 0007 section 2, ADR 0017 section 3): struct-of-arrays, integers only.
## Positions are milli-tiles (1 tile = 1000). Units and buildings are rows in the per-unit arrays,
## ascending by id. Ids come from a counter that starts at 1 and are never reused. Removal keeps the
## rows in id order, so an id is found by binary search. The view and input read a World and never
## write to it. Every array and scalar is declared here and listed in one shape list (ADR 0007
## section 2); the state hash (ADR 0007 section 8) walks those lists. The hash code is WorldHash and
## the scenario loader WorldLoad (P70c); the methods of this class that name them are wrappers.

enum Order { IDLE = 0, ATTACK_MOVE = 1, MOVE = 2, ATTACK = 3 }
enum Armour { INFANTRY = 0, LIGHT = 1, HEAVY = 2, BUILDING = 3 }
enum MoveClass { FOOT = 0, WHEELED = 1, TRACKED = 2 }
enum Event { SPAWNED = 1, DIED = 2, SHOT = 3, IMPACT = 4 }
enum NavMode { NONE = 0, DIRECT = 1, FIELD = 2, HOLD = 3, CHASE = 4 }
## The production tabs (ADR 0017 section 3): a queue, a rally point and a buildable type's `tab`.
enum Tab { STRUCTURES = 0, INFANTRY = 1, VEHICLES = 2 }
## What a harvester is doing (ADR 0018 section 3); IDLE is under the player's control.
enum HarvestMode { IDLE = 0, SEEK = 1, MINE = 2, RETURN = 3, UNLOAD = 4 }
## The indexes of `stats`: flow cells settled, line checks, separation pairs tested, targeting
## candidates tested, fog cells stamped, projectile steps, rows moved by a compaction, ore cells
## looked at, exit cells walked and last-seen checks (the last three: Phase 3, ADR 0017 section 3).
## The native kernels check `stats` against this size (`STAT_COUNT` in bind/world_access.h).
enum Stat {
	FLOW_CELLS = 0,
	LINE_CHECKS = 1,
	SEP_PAIRS = 2,
	TARGET_CANDIDATES = 3,
	FOG_CELLS = 4,
	PROJ_STEPS = 5,
	ROWS_COMPACTED = 6,
	ORE_SCANNED = 7,
	EXIT_SCANNED = 8,
	MEMORY_CHECKS = 9,
}

## Same value as Sim.MILLI_PER_TILE, which P3 adds. World cannot read it from Sim (Sim reads World).
const MILLI_PER_TILE: int = 1000
const TILE_CENTRE: int = 500
## Ints per record in `events`.
const EVENT_STRIDE: int = 8
## The production tabs: the second index of the per-tab arrays is `player * TABS + tab`.
const TABS: int = 3
## The layout version of the hashed state. 2: fog.visible left the hash, because the rows it is
## derived from stay in it (ADR 0016). 3: Phase 3's state joined it (ADR 0017 section 7): four row
## columns, the sections players, ore and ghosts, and the scalars match_end_tick and winner.
const STATE_FORMAT: int = 3
## The hash sections that are not a ROW_ARRAYS column: header, map, projectiles, fog, players, ore
## and ghosts.
const HASH_OTHER_SECTIONS: int = 7

## What prepare() fills a type table with for a type that has no entry. A padded type cannot
## fire, sees only its own tile and counts as tracked. These are not balance numbers.
const TYPE_PAD_MAX_HP: int = 1
const TYPE_PAD_ARMOUR: int = Armour.INFANTRY
const TYPE_PAD_MOVE_CLASS: int = MoveClass.TRACKED
const TYPE_PAD_SIGHT: int = 0
const TYPE_PAD_ACQUIRE: int = 0
const TYPE_PAD_WEAPON: int = -1
## For the four Phase 1 tables (speed, radius, selection radius, spacing), and for the Phase 3
## tables whose pad is 0: footprint, cost, build ticks, power, cargo capacity, dock and exit.
const TYPE_PAD_V0: int = 0
## For the Phase 3 tables whose "none" is -1: tab, requirement, produced tab and free unit.
const TYPE_PAD_NONE: int = -1
## The cost of open grass for every class, 10 = normal ground (ADR 0008 section 1). It equals the
## default TerrainDef.cost, which a test pins: prepare() may run in the tick and reads no Resource.
const GRASS_COST: int = 10
## The id of open grass, the one terrain of a map without a MapDef. It equals the first terrain of
## data/terrain/standard.tres, which a test pins.
const GRASS_ID: StringName = &"grass"
## Whether open grass is buildable (1) or not (0), the one terrain of a map without a MapDef. It
## equals the `buildable` flag of the first terrain of data/terrain/standard.tres (a test pins it).
const GRASS_BUILDABLE: int = 1
## The id of the ore terrain (ADR 0018 section 2): WorldLoad lists its cells in `ore_cell`.
const ORE_ID: StringName = &"ore"
## The largest terrain index. `terrain` keeps one byte per cell and the view picks its tile by it,
## so a larger index would be stored as another terrain's and drawn as that one (P48).
const TERRAIN_INDEX_MAX: int = 255
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
	&"group_cell",
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
	&"harvest_mode",
	&"cargo",
	&"harvest_slot",
	&"home",
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
## The per-player state (ADR 0017 section 3), sized by prepare(): the first seven have an entry per
## player (index 0 is neutral and unused), the next four one per player and tab (`player * TABS +
## tab`) and `queue_type` one per queue slot (`(player * TABS + tab) * queue_slots + slot`). Hashed,
## one block per array, in the section `players`.
const PLAYER_ARRAYS: Array[StringName] = [
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
]
## The ore left in each ore cell, one entry per `ore_cell` entry. Hashed, in the section `ore`.
const ORE_ARRAYS: Array[StringName] = [&"ore_amount"]
## The last-seen building records (ADR 0017 section 3): record `i` of player `p` is entry
## `p * ghost_cap + i` of the four record arrays, live below `ghost_count[p]`. Hashed, live records
## only, in the section `ghosts`.
const GHOST_ARRAYS: Array[StringName] = [
	&"ghost_id", &"ghost_type", &"ghost_owner", &"ghost_cell", &"ghost_count"
]
## State that follows from the hashed state (ADR 0016), rebuilt when `rows_version` moves and in
## no hash section: the power totals per player and the ascending rows of buildings and harvesters.
const DERIVED_ARRAYS: Array[StringName] = [
	&"power_made", &"power_used", &"building_rows", &"harvester_rows"
]
## The tile grid: the terrain index per cell, the move cost per class and cell, the cost per
## terrain and class that set_terrain copies into it, the buildable flag per terrain and the
## ascending cells of the ore terrain (fixed at load).
const MAP_ARRAYS: Array[StringName] = [
	&"terrain", &"move_cost", &"terrain_cost", &"terrain_buildable", &"ore_cell"
]
## Per-row working space, max_rows entries each, rewritten every tick. Not state.
const SCRATCH_ARRAYS: Array[StringName] = [&"intent_x", &"intent_y", &"push_x", &"push_y"]
## Rewritten every tick, neither hashed nor compacted.
const RUNTIME_ARRAYS: Array[StringName] = [&"events", &"stats"]

## The int properties that go into the state hash, in hash order: the header ints, then
## map_version (the map grid itself goes in as a cached digest), then the match end. rng.state()
## follows them.
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
	&"match_end_tick",
	&"winner",
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
	&"start_credits",
	&"ore_start",
	&"ore_cell_max",
	&"ore_regrow_ticks",
	&"credits_per_ore",
	&"harvest_ticks_per_ore",
	&"unload_ticks_per_ore",
	&"harvest_reach_milli",
	&"dock_reach_milli",
	&"harvest_retry_ticks",
	&"harvest_resume_ticks",
	&"harvest_pick_milli",
	&"low_power_percent",
	&"queue_slots",
	&"build_reach_tiles",
	&"unit_cap",
	&"building_cap",
	&"ghost_cap",
]
## The other int properties: the map size, the view's rows_version, native_phases (which
## implementation runs a phase is never state, ADR 0013 section 3), the map digest cache (it
## follows from map_version and the grid) and the rule ints, which repeat RULE_SCALARS (a literal,
## because `+` on typed constants gives an untyped Array; a test pins the repeat). None is in the
## state hash.
const UNHASHED_SCALARS: Array[StringName] = [
	&"map_w",
	&"map_h",
	&"map_cols",
	&"map_rows",
	&"rows_version",
	&"native_phases",
	&"_map_digest",
	&"_map_digest_version",
	&"_lists_version",
	&"_power_version",
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
	&"start_credits",
	&"ore_start",
	&"ore_cell_max",
	&"ore_regrow_ticks",
	&"credits_per_ore",
	&"harvest_ticks_per_ore",
	&"unload_ticks_per_ore",
	&"harvest_reach_milli",
	&"dock_reach_milli",
	&"harvest_retry_ticks",
	&"harvest_resume_ticks",
	&"harvest_pick_milli",
	&"low_power_percent",
	&"queue_slots",
	&"build_reach_tiles",
	&"unit_cap",
	&"building_cap",
	&"ghost_cap"
]
## The members that are not state (ADR 0013 section 3): the coverage test, the state hash and the
## reachability walk skip exactly these. `kernels` is the native kernels object, or null.
const NON_STATE_MEMBERS: Array[StringName] = [&"kernels"]
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
## 0 = the match is running; else the tick the ending step produces (`tick + 1`, so an end on the
## first step reads 1, ADR 0018 section 7).
var match_end_tick: int = 0
## The winning player; 0 = none yet, or a draw once `match_end_tick` is set.
var winner: int = 0
## Bumped whenever rows are added or removed, so the view can tell when rows moved.
var rows_version: int = 0
## The sim's random stream (spawn jitter). Never null.
var rng: DetRandom
## The helper objects (ADR 0007 section 2): empty from the start, sized by the first prepare().
## Only `fog` is state (its `explored` bytes; its `visible` counts are derived from the rows); the
## others are derived. Objects sit in no shape list.
var fog: FogGrid = FogGrid.new()
var flow: FlowCache = FlowCache.new()
var sep_grid: SpatialGrid = SpatialGrid.new()
var target_grid: SpatialGrid = SpatialGrid.new()
## ADR 0007 section 2's one bool check. A bool is neither an int nor a Packed*Array, so no shape
## list holds it and the coverage walk skips it. Not hashed: it follows from the helpers.
var prepared: bool = false
## The native kernels (an untyped Object, so no script names the class; null = the GDScript phases)
## and one bit per SimProbe.Phase that runs in them. A phase entry starts with
## `if ((world.native_phases >> SimProbe.Phase.X) & 1) == 1: world.kernels.x(world); return`.
## Neither is hashed (ADR 0013 section 3); callers attach both after prepare().
var kernels: Object = null
var native_phases: int = 0

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
## Phase 3 (ADR 0018 section 9; RulesDef holds the meanings): credits and ore, harvesting, power,
## production, building and the last-seen records.
var start_credits: int = 0
var ore_start: int = 0
var ore_cell_max: int = 0
var ore_regrow_ticks: int = 0
var credits_per_ore: int = 0
var harvest_ticks_per_ore: int = 0
var unload_ticks_per_ore: int = 0
var harvest_reach_milli: int = 0
var dock_reach_milli: int = 0
var harvest_retry_ticks: int = 0
var harvest_resume_ticks: int = 0
var harvest_pick_milli: int = 0
var low_power_percent: int = 0
var queue_slots: int = 0
var build_reach_tiles: int = 0
var unit_cap: int = 0
var building_cap: int = 0
var ghost_cap: int = 0

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
## Phase 3 (ADR 0017 section 3). A building type has a footprint in tiles (`type_foot_w` and
## `type_foot_h` above 0, at most 3), a mobile type has 0 and 0.
var type_foot_w: PackedInt32Array = PackedInt32Array()
var type_foot_h: PackedInt32Array = PackedInt32Array()
## Credits, and ticks to build at 15 Hz; 0 for a type that is not buildable.
var type_cost: PackedInt32Array = PackedInt32Array()
var type_build_ticks: PackedInt32Array = PackedInt32Array()
## The tab whose queue builds the type (a Tab), -1 = not buildable.
var type_tab: PackedInt32Array = PackedInt32Array()
## The type index that must be owned before this one is queued, -1 = none.
var type_requires: PackedInt32Array = PackedInt32Array()
## The tab a building lets its owner queue (a Tab), -1 = none.
var type_produces: PackedInt32Array = PackedInt32Array()
## Power made (above 0) or used (below 0) by a building.
var type_power: PackedInt32Array = PackedInt32Array()
## A harvester's cargo capacity in credits, 0 = not a harvester.
var type_harvest: PackedInt32Array = PackedInt32Array()
## The type index of the unit that comes with a placed building, -1 = none.
var type_free_unit: PackedInt32Array = PackedInt32Array()
## Tile offsets from a building's origin tile: where a harvester unloads and where a unit appears.
var type_dock_x: PackedInt32Array = PackedInt32Array()
var type_dock_y: PackedInt32Array = PackedInt32Array()
var type_exit_x: PackedInt32Array = PackedInt32Array()
var type_exit_y: PackedInt32Array = PackedInt32Array()

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
## Entry `terrain`: 1 if a building may stand on that terrain (TerrainDef.buildable), else 0. Only
## from_scenario and prepare() write it, so it is constant during a match.
var terrain_buildable: PackedByteArray = PackedByteArray()
## The cells of the ore terrain (`ORE_ID`), ascending, listed at load. `set_terrain` does not touch
## it: a cell is an ore cell for the whole match.
var ore_cell: PackedInt32Array = PackedInt32Array()

## Per unit, ascending by id.
var unit_id: PackedInt32Array = PackedInt32Array()
var owner: PackedInt32Array = PackedInt32Array()
var type_index: PackedInt32Array = PackedInt32Array()
var pos_x: PackedInt32Array = PackedInt32Array()
var pos_y: PackedInt32Array = PackedInt32Array()
var goal_x: PackedInt32Array = PackedInt32Array()
var goal_y: PackedInt32Array = PackedInt32Array()
## The cell of the group target of a MOVE or ATTACK_MOVE order (Formation's centre), the key of the
## field its units share; -1 = none (the unit's own goal tile, every ATTACK, every idle unit).
var group_cell: PackedInt32Array = PackedInt32Array()
var order: PackedInt32Array = PackedInt32Array()
## At most the type's max hp. It may go below 0 by the hits of one tick (every shooter hits a unit
## that an earlier shooter has already brought to 0, so one hit per shooter, ADR 0009 section 4).
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
## A cell, -1 = none yet, -2 = looked up and none (Movement.NO_NEXT).
var nav_next: PackedInt32Array = PackedInt32Array()
## A plain distance in milli, 0..0x3FFFFFFF.
var best_dist: PackedInt32Array = PackedInt32Array()
## 0..stall_ticks.
var stall: PackedInt32Array = PackedInt32Array()
## The cell last stamped into the fog, -1 = not stamped.
var fog_cell: PackedInt32Array = PackedInt32Array()
## A HarvestMode (IDLE for every row until the harvest rows), the cargo in credits, the index into
## `ore_cell` of the cell the row works (-1 = none) and the id of the refinery it returns to
## (0 = none). All start at those values, and a row that is no harvester keeps them.
var harvest_mode: PackedInt32Array = PackedInt32Array()
var cargo: PackedInt32Array = PackedInt32Array()
var harvest_slot: PackedInt32Array = PackedInt32Array()
var home: PackedInt32Array = PackedInt32Array()

## Per player (index 0 = neutral, unused; prepare() sizes them to player_count + 1): the credits
## (start_credits), the tick the defeating step produced (0 = still playing), 1 once the player has
## owned a building that produces a tab, and the result-screen counts.
var credits: PackedInt32Array = PackedInt32Array()
var defeated_tick: PackedInt32Array = PackedInt32Array()
var had_producer: PackedInt32Array = PackedInt32Array()
var stat_built: PackedInt32Array = PackedInt32Array()
var stat_lost_units: PackedInt32Array = PackedInt32Array()
var stat_lost_buildings: PackedInt32Array = PackedInt32Array()
var stat_harvested: PackedInt32Array = PackedInt32Array()
## Per player and tab (index `player * TABS + tab`): the items in the queue, the progress of its
## head in hundredths of a tick, and the rally point in milli-tiles (-1 = none).
var queue_count: PackedInt32Array = PackedInt32Array()
var queue_progress: PackedInt32Array = PackedInt32Array()
var rally_x: PackedInt32Array = PackedInt32Array()
var rally_y: PackedInt32Array = PackedInt32Array()
## Per queue slot (index `(player * TABS + tab) * queue_slots + slot`): the queued type index, -1
## for a slot with no item.
var queue_type: PackedInt32Array = PackedInt32Array()
## The ore units left, one per `ore_cell` entry.
var ore_amount: PackedInt32Array = PackedInt32Array()
## The last-seen building records, `ghost_cap` per player (see GHOST_ARRAYS), and the live count per
## player.
var ghost_id: PackedInt32Array = PackedInt32Array()
var ghost_type: PackedInt32Array = PackedInt32Array()
var ghost_owner: PackedInt32Array = PackedInt32Array()
var ghost_cell: PackedInt32Array = PackedInt32Array()
var ghost_count: PackedInt32Array = PackedInt32Array()
## Derived from the rows (ADR 0016), never hashed: the power made and used per player, and the
## ascending rows of the buildings and of the harvesters.
var power_made: PackedInt32Array = PackedInt32Array()
var power_used: PackedInt32Array = PackedInt32Array()
var building_rows: PackedInt32Array = PackedInt32Array()
var harvester_rows: PackedInt32Array = PackedInt32Array()

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
## equals `map_version`. Derived, so unhashed; WorldHash.map_digest() fills it.
var _map_digest: int = 0
var _map_digest_version: int = -1
## The `rows_version` the derived row lists and the power totals were last built at (-1: never);
## unhashed like them. `Power.run` stamps the totals itself: a rebuild of the lists is not one.
var _lists_version: int = -1
var _power_version: int = -1


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
	start_credits = rules.start_credits
	ore_start = rules.ore_start
	ore_cell_max = rules.ore_cell_max
	ore_regrow_ticks = rules.ore_regrow_ticks
	credits_per_ore = rules.credits_per_ore
	harvest_ticks_per_ore = rules.harvest_ticks_per_ore
	unload_ticks_per_ore = rules.unload_ticks_per_ore
	harvest_reach_milli = rules.harvest_reach_milli
	dock_reach_milli = rules.dock_reach_milli
	harvest_retry_ticks = rules.harvest_retry_ticks
	harvest_resume_ticks = rules.harvest_resume_ticks
	harvest_pick_milli = rules.harvest_pick_milli
	low_power_percent = rules.low_power_percent
	queue_slots = rules.queue_slots
	build_reach_tiles = rules.build_reach_tiles
	unit_cap = rules.unit_cap
	building_cap = rules.building_cap
	ghost_cap = rules.ghost_cap


## Reads the scenario and its definitions once and returns a prepared world; a null scenario gives
## an empty one. The rules come from `scenario.rules`, else they stay the RulesDef defaults. A null
## `rng` keeps the default stream. WorldLoad.from_scenario has the rest of the rule: the map grid,
## the types, the spawns and their jitter, and the dropped setup events.
@warning_ignore("shadowed_variable")
static func from_scenario(scenario: ScenarioDef, rng: DetRandom = null) -> World:
	return WorldLoad.from_scenario(scenario, rng)


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
## max_projectiles, sizes the player, ore and ghost state at its start values (_size_match_state),
## and derives open grass from map_w and map_h when no map is loaded. Last it
## configures the helpers, once, because configure() re-creates their arrays, stamps the fog of the
## rows that exist (_stamp_fog) and caches the map digest of the hash. Idempotent through
## `prepared`, so Sim.step calls it every tick. Types, players and sizes are fixed before it.
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
	_pad(type_foot_w, types, TYPE_PAD_V0)
	_pad(type_foot_h, types, TYPE_PAD_V0)
	_pad(type_cost, types, TYPE_PAD_V0)
	_pad(type_build_ticks, types, TYPE_PAD_V0)
	_pad(type_tab, types, TYPE_PAD_NONE)
	_pad(type_requires, types, TYPE_PAD_NONE)
	_pad(type_produces, types, TYPE_PAD_NONE)
	_pad(type_power, types, TYPE_PAD_V0)
	_pad(type_harvest, types, TYPE_PAD_V0)
	_pad(type_free_unit, types, TYPE_PAD_NONE)
	_pad(type_dock_x, types, TYPE_PAD_V0)
	_pad(type_dock_y, types, TYPE_PAD_V0)
	_pad(type_exit_x, types, TYPE_PAD_V0)
	_pad(type_exit_y, types, TYPE_PAD_V0)
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
		WorldLoad.derive_open_grass(self)
	_size_match_state()
	fog.configure(map_cols, map_rows, player_count)
	_stamp_fog()
	flow.configure(map_cols, map_rows, MoveClass.size(), flow_cache_size)
	sep_grid.configure(map_w, map_h, SEP_CELL_MILLI, max_rows)
	target_grid.configure(map_w, map_h, TARGET_CELL_MILLI, max_rows)
	_map_digest_version = -1  # The grid may be new without a map_version bump.
	WorldHash.map_digest(self)
	prepared = true


## Sizes the player, ore and ghost state at its start values (ADR 0017 section 3), from the player
## count and the rule ints, so that no later row moves the hash through a start value: credits at
## start_credits for players 1..player_count, rally points and queue slots at -1 (none), every ore
## cell at ore_start, the rest 0. Entry 0 of a per-player array is the neutral player.
func _size_match_state() -> void:
	var players: int = player_count + 1
	var queues: int = players * TABS
	var ghosts: int = players * ghost_cap
	credits.resize(players)
	for player: int in range(1, players):
		credits[player] = start_credits
	defeated_tick.resize(players)
	had_producer.resize(players)
	stat_built.resize(players)
	stat_lost_units.resize(players)
	stat_lost_buildings.resize(players)
	stat_harvested.resize(players)
	queue_count.resize(queues)
	queue_progress.resize(queues)
	rally_x.resize(queues)
	rally_x.fill(-1)
	rally_y.resize(queues)
	rally_y.fill(-1)
	queue_type.resize(queues * queue_slots)
	queue_type.fill(-1)
	ore_amount.resize(ore_cell.size())
	ore_amount.fill(ore_start)
	ghost_id.resize(ghosts)
	ghost_type.resize(ghosts)
	ghost_owner.resize(ghosts)
	ghost_cell.resize(ghosts)
	ghost_count.resize(players)
	power_made.resize(players)
	power_used.resize(players)


## The cell holding the point (x, y) in milli-tiles: `row * map_cols + column`. A point outside
## the map gives the nearest edge cell, so the result is never outside the map (negative values
## divide toward zero and clamp to 0). With no map it is 0. The INTEGRATE kernel has a C++ twin of
## this (core/integrate.cpp, Pass::cell_of); a change here edits both and passes the kernel's tests
## (tests/sim/native/test_integrate_kernel.gd).
@warning_ignore("integer_division")
func cell_of(x: int, y: int) -> int:
	if map_cols == 0:
		return 0
	var column: int = clampi(x / MILLI_PER_TILE, 0, map_cols - 1)
	var row: int = clampi(y / MILLI_PER_TILE, 0, map_rows - 1)
	return row * map_cols + column


## Whether a unit of `move_class` may stand on `cell`: its cost there is above 0. True while no
## map is loaded, false for a cell outside the map or a class that does not exist. The INTEGRATE
## kernel has a C++ twin of this (core/integrate.cpp, Pass::is_passable): a rule that makes more
## than the terrain block a tile (a building) edits both and passes the kernel's tests.
func is_passable(cell: int, move_class: int) -> bool:
	if map_cols == 0:
		return true
	var cells: int = map_cols * map_rows
	if cell < 0 or cell >= cells or move_class < 0 or move_class >= MoveClass.size():
		return false
	return move_cost[move_class * cells + cell] > 0


## Makes `cell` the terrain `terrain_index` (an index into terrain_ids) with that terrain's cost
## for each class, and bumps map_version, also when the terrain is the same. A cell outside the
## map, an index above TERRAIN_INDEX_MAX (a byte, P48) or an unknown terrain index (one whose
## `terrain_cost` row is missing) changes nothing. It leaves `ore_cell` as the load made it. Any
## other writer of `terrain`, `move_cost`, `terrain_cost`, `terrain_buildable` or `ore_cell` must
## bump map_version itself, because the map digest of the hash follows map_version alone
## (WorldHash.map_digest).
func set_terrain(cell: int, terrain_index: int) -> void:
	var classes: int = MoveClass.size()
	var cells: int = map_cols * map_rows
	if cell < 0 or cell >= cells or terrain_index < 0 or terrain_index > TERRAIN_INDEX_MAX:
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
	group_cell.append(-1)
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
	harvest_mode.append(HarvestMode.IDLE)
	cargo.append(0)
	harvest_slot.append(-1)
	home.append(0)
	_push_unit_event(Event.SPAWNED, unit_id.size() - 1)
	rows_version += 1
	player_count = maxi(player_count, owner)
	return id


## Appends a building with its top-left tile at (origin_col, origin_row); 0 when refused. It blocks
## its tiles (Buildings.add has the rule).
@warning_ignore("shadowed_variable")
func add_building(owner: int, type_index: int, origin_col: int, origin_row: int) -> int:
	return Buildings.add(self, owner, type_index, origin_col, origin_row)


## The top-left tile of row `row`'s footprint, from its position and type.
func footprint_origin(row: int) -> Vector2i:
	return Buildings.footprint_origin(self, row)


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


## Removes every row with hp of 0 or less (ADR 0007 section 3): a DIED record per dead row, in row
## order, and its fog unstamped, then a stable compaction of every ROW_ARRAYS column, so the rows
## stay ascending by id. It bumps rows_version once and adds the rows that changed place to
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
	Buildings.unblock_dead(self)  # Before the compaction: the origin comes from the position.
	var dead: int = 0
	for row: int in range(first, count):
		if alive[row] <= 0:
			dead += 1
	# One resize for all the records, then the writes: the loops allocate nothing. A stamped row's
	# vision ends here (ADR 0010 section 1); `explored` stays.
	var at: int = events.size()
	events.resize(at + dead * EVENT_STRIDE)  # The last two ints of each record stay 0.
	var owners: PackedInt32Array = owner
	var types: PackedInt32Array = type_index
	var stamped: PackedInt32Array = fog_cell
	var pad: int = type_sight.size()
	var has_fog: bool = fog.cells > 0
	for row: int in range(first, count):
		if alive[row] <= 0:
			_write_unit_event(at, Event.DIED, row)
			at += EVENT_STRIDE
			if has_fog and stamped[row] >= 0:
				fog.stamp(owners[row], stamped[row], mini(types[row], pad), -1)
	# hp is the test for every column, so it goes last.
	for column_name: StringName in ROW_ARRAYS:
		if column_name != &"hp":
			var column: PackedInt32Array = get(column_name)
			_compact(column, alive, first, count)
	_compact(alive, alive, first, count)
	stats[Stat.ROWS_COMPACTED] += count - first - dead
	rows_version += 1


## One sight mask per type, in type order, so a mask id is the type index (two types of equal sight
## repeat their mask), and the pad mask of TYPE_PAD_SIGHT after them, id `type_sight.size()`, for a
## row whose type has no entry (the fog code takes the smaller of the type index and that id, so a
## mask added later changes nothing). Then the disc of every row of a player (1..player_count) at
## its cell, so the first frame of a match shows each player's own vision and the tick-0 hash
## includes it (ADR 0010 section 1). No map, no cells: nothing is stamped. It counts nothing in
## `stats`.
func _stamp_fog() -> void:
	for sight: int in type_sight:
		fog.add_mask(sight)
	fog.add_mask(TYPE_PAD_SIGHT)
	if fog.cells == 0:
		return
	var pad: int = type_sight.size()
	var owners: PackedInt32Array = owner
	var types: PackedInt32Array = type_index
	var stamped: PackedInt32Array = fog_cell
	for row: int in owners.size():
		var player: int = owners[row]
		if player >= 1 and player <= player_count:
			var cell: int = cell_of(pos_x[row], pos_y[row])
			fog.stamp(player, cell, mini(types[row], pad), 1)
			stamped[row] = cell


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


## The state hash (ADR 0007 section 8): SHA-256 over the sections of hash_section_names(). The walk
## is WorldHash.state_hash().
func state_hash() -> int:
	return WorldHash.state_hash(self)


## One digest prefix per section, in hash_section_names() order, for the failure message of a test
## that compares two hashes; it is not called in the tick (WorldHash.hash_parts).
func hash_parts() -> PackedInt64Array:
	return WorldHash.hash_parts(self)


## "header", "map", one name per ROW_ARRAYS entry, "projectiles", "fog", "players", "ore", "ghosts"
## (WorldHash.hash_section_names has what each section feeds).
static func hash_section_names() -> PackedStringArray:
	return WorldHash.hash_section_names()


## `h` as 16 lower-case hex digits, its 8 bytes least significant first (ADR 0007 section 8).
static func hash_hex(h: int) -> String:
	return WorldHash.hash_hex(h)


## The hash of the type and weapon tables, their ids and the rule ints: what a replay needs to see
## that it runs on other data. Call it on a prepared world, because prepare() pads the type tables.
func defs_hash() -> int:
	return WorldHash.defs_hash(self)
