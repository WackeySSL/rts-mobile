class_name World
extends RefCounted
## Simulation state v1 (ADR 0007 section 2): struct-of-arrays, integers only. Positions are
## milli-tiles (1 tile = 1000). Units are rows in the per-unit arrays, ascending by id. Ids come
## from a counter that starts at 1 and are never reused. Phase 1 never removes a unit, so an id
## is found by binary search. The view and input read a World and never write to it. This part
## declares the enums, header, rule ints, row columns and type tables; the weapon, map,
## projectile and scratch arrays follow in the next World change.

enum Order { IDLE = 0, ATTACK_MOVE = 1, MOVE = 2, ATTACK = 3 }
enum Armour { INFANTRY = 0, LIGHT = 1, HEAVY = 2, BUILDING = 3 }
enum MoveClass { FOOT = 0, WHEELED = 1, TRACKED = 2 }
enum Event { SPAWNED = 1, DIED = 2, SHOT = 3, IMPACT = 4 }
enum NavMode { NONE = 0, DIRECT = 1, FIELD = 2, HOLD = 3, CHASE = 4 }

## Same value as Sim.MILLI_PER_TILE, which P3 adds. World cannot read it from Sim (Sim reads World).
const MILLI_PER_TILE: int = 1000
const TILE_CENTRE: int = 500
## Ints per record in `events`.
const EVENT_STRIDE: int = 8
## The layout version of the hashed state.
const STATE_FORMAT: int = 1

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

## Per type. The index is the order of first appearance in the scenario's spawns.
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
var type_names: PackedStringArray = PackedStringArray()

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

## Records of EVENT_STRIDE ints for the last tick. Rewritten every tick and not state.
var events: PackedInt32Array = PackedInt32Array()


## The rule ints start at the RulesDef script defaults, so a hand-built world is a valid world.
func _init() -> void:
	var rules: RulesDef = RulesDef.new()
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
	rng = DetRandom.create(0, DetRandom.STREAM_SIM)


## Reads the scenario and its unit definitions once. A null scenario gives an empty world.
## A spawn without a unit is skipped. A null `rng` keeps the default stream.
@warning_ignore("shadowed_variable")
static func from_scenario(scenario: ScenarioDef, rng: DetRandom = null) -> World:
	var world: World = World.new()
	if rng != null:
		world.rng = rng
	if scenario == null:
		return world
	world.map_w = scenario.map_size_tiles.x * MILLI_PER_TILE
	world.map_h = scenario.map_size_tiles.y * MILLI_PER_TILE
	for spawn: SpawnDef in scenario.spawns:
		if spawn == null or spawn.unit == null:
			continue
		var type: int = world._type_for(spawn.unit)
		var columns: int = maxi(spawn.columns, 1)
		var start_x: int = spawn.origin_tile.x * MILLI_PER_TILE + TILE_CENTRE
		var start_y: int = spawn.origin_tile.y * MILLI_PER_TILE + TILE_CENTRE
		var column: int = 0
		var row: int = 0
		for _slot: int in spawn.count:
			var x: int = start_x + column * spawn.spacing
			var y: int = start_y + row * spawn.spacing
			world.add_unit(spawn.owner, type, x, y)
			column += 1
			if column == columns:
				column = 0
				row += 1
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
## capitalised type id), because Phase 1 code appends only the four Phase 1 tables. Idempotent.
## Types are appended before the first step.
func prepare() -> void:
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


## Appends an idle unit at (x, y) at its type's max hp (at least 1; 1 for a type with no entry)
## and returns its new id. `type_index` must be an index into type_ids. It writes one SPAWNED
## event and raises player_count to the owner. The parameters keep the contract's names, so
## they shadow the arrays of the same name.
@warning_ignore("shadowed_variable")
func add_unit(owner: int, type_index: int, x: int, y: int) -> int:
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
	var at: int = events.size()
	events.resize(at + EVENT_STRIDE)  # In place, no allocation. The last two ints stay 0.
	events[at] = Event.SPAWNED
	events[at + 1] = id
	events[at + 2] = x
	events[at + 3] = y
	events[at + 4] = type_index
	events[at + 5] = owner
	rows_version += 1
	player_count = maxi(player_count, owner)
	return id


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
	return type_ids.size() - 1
