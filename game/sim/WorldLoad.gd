class_name WorldLoad
extends RefCounted
## The scenario loader of a World, split out of World.gd (P70c) so that file stays under gdlint's
## 1,000 lines. Pure static helpers: they read the scenario, the map and the definitions passed in
## and write the World passed in, and they keep nothing. World.from_scenario() is a thin wrapper
## over from_scenario() here, World.prepare() over prepare_world() (P246a moved its body), and
## World._init() calls copy_rules(), so most callers reach this class through World. The code is
## World.gd's own, moved (P109 moved copy_rules and size_match_state, P232 stamp_fog and
## reset_projectile_slots, with no change; P232 pad_types too,
## but it pads the sight, acquire, weapon and repair period tables by named constants; P285
## set_terrain, which only tests call) or the copy of a definition into a table (the loader, with
## the layer bit derived from the move class and `low_flying`); ADR 0007 section 2 and ADR 0017
## section 3 keep every column, list and rule int in World itself.

## The percent of an unchanged income, and the divisor of every percent: a human's income.
const PERCENT: int = 100


## Reads the scenario and its definitions once and returns a prepared world; a null scenario gives
## an empty one. The rules come from `scenario.rules`, else they stay the RulesDef defaults. A null
## `rng` keeps the default stream. The map grid comes from `scenario.map`, which also sets the map
## size; without a map, or with one that fails validate(), the world is open grass of
## `map_size_tiles`. Types come from the spawns (one without a unit is skipped), then the roster,
## then the roster of each listed faction by player. `player_count` is the scenario's value, raised
## to the highest spawn owner. A spawn with a jitter draws two values per unit (see _jittered). The
## SPAWNED events of the setup are dropped. Spawns run before prepare(), so no row is refused here:
## data keeps their total within `max_rows`.
static func from_scenario(scenario: ScenarioDef, rng: DetRandom = null) -> World:
	var world: World = World.new()
	if rng != null:
		world.rng = rng
	if scenario == null:
		world.prepare()
		return world
	if scenario.rules != null:
		copy_rules(world, scenario.rules)
	world.player_count = maxi(scenario.player_count, 0)
	var map: MapDef = scenario.map
	if map != null and map.validate().is_empty():
		_load_map(world, map)
	else:
		world.map_w = scenario.map_size_tiles.x * World.MILLI_PER_TILE
		world.map_h = scenario.map_size_tiles.y * World.MILLI_PER_TILE
		derive_open_grass(world)
	for spawn: SpawnDef in scenario.spawns:
		if spawn == null or spawn.unit == null:
			continue
		var type: int = _type_for(world, spawn.unit)
		if spawn.unit is BuildingDef:
			_place_buildings(world, spawn, type)
			continue
		var move_class: int = world.type_move_class[type]
		var columns: int = maxi(spawn.columns, 1)
		var start_x: int = spawn.origin_tile.x * World.MILLI_PER_TILE + World.TILE_CENTRE
		var start_y: int = spawn.origin_tile.y * World.MILLI_PER_TILE + World.TILE_CENTRE
		var column: int = 0
		var row: int = 0
		for _slot: int in spawn.count:
			var x: int = start_x + column * spawn.spacing
			var y: int = start_y + row * spawn.spacing
			if spawn.jitter > 0:
				var at: Vector2i = _jittered(world, x, y, spawn.jitter, move_class)
				x = at.x
				y = at.y
			world.add_unit(spawn.owner, type, x, y)
			# A harvester that a scenario spawns starts in SEEK, with no home (ADR 0018 section 3).
			if world.type_harvest[type] > 0:
				world.harvest_mode[world.unit_count() - 1] = World.HarvestMode.SEEK
			column += 1
			if column == columns:
				column = 0
				row += 1
	for unit: UnitDef in scenario.roster:
		if unit != null:
			_type_for(world, unit)
	# The listed factions' rosters last, by player (ADR 0023 section 6).
	for faction: FactionDef in scenario.factions:
		if faction == null:
			continue
		for unit: UnitDef in faction.roster:
			if unit != null:
				_type_for(world, unit)
	# Then the upgrades of the listed factions, after every type they may change (ADR 0036 section 2).
	for faction: FactionDef in scenario.factions:
		if faction != null:
			for upgrade: UpgradeDef in faction.upgrades:
				_upgrade_for(world, upgrade)
	world.prepare()
	world.events.clear()
	return world


## The buildings of a spawn whose unit is a BuildingDef (ADR 0017 section 1): `count` of them
## through World.add_building from `origin_tile`, in rows of `columns`, one footprint apart. Nothing
## is drawn: `spacing` and `jitter` are for units. A strike building starts `charge_elapsed_ticks`
## into its charge (Strike.age_charge).
@warning_ignore("integer_division")
static func _place_buildings(world: World, spawn: SpawnDef, type: int) -> void:
	var columns: int = maxi(spawn.columns, 1)
	var width: int = world.type_foot_w[type]
	var height: int = world.type_foot_h[type]
	for slot: int in spawn.count:
		var col: int = spawn.origin_tile.x + slot % columns * width
		var line: int = spawn.origin_tile.y + slot / columns * height
		if world.add_building(spawn.owner, type, col, line) != 0:
			Strike.age_charge(world, world.unit_count() - 1, spawn.charge_elapsed_ticks)


## Open grass over map_w x map_h rounded up to whole tiles (ADR 0007 section 2): terrain 0 on
## every cell, normal ground for every class. A size of 0 or less on either axis leaves no map:
## both counts are 0, never a grid with columns and no rows.
@warning_ignore("integer_division")
static func derive_open_grass(world: World) -> void:
	world.map_cols = (world.map_w + World.MILLI_PER_TILE - 1) / World.MILLI_PER_TILE
	world.map_rows = (world.map_h + World.MILLI_PER_TILE - 1) / World.MILLI_PER_TILE
	if world.map_cols <= 0 or world.map_rows <= 0:
		world.map_cols = 0
		world.map_rows = 0
	var cells: int = world.map_cols * world.map_rows
	world.terrain.resize(cells)
	world.move_cost.resize(World.MoveClass.size() * cells)
	world.move_cost.fill(World.GRASS_COST)
	world.terrain_cost.resize(World.GROUND_CLASSES)
	world.terrain_cost.fill(World.GRASS_COST)
	world.terrain_ids.resize(1)  # In place, so a later prepare() allocates nothing.
	world.terrain_ids[0] = World.GRASS_ID
	world.terrain_buildable.resize(1)
	world.terrain_buildable[0] = World.GRASS_BUILDABLE
	world.ore_cell.clear()


## Copies a map that validate() accepted: its size, the terrain index of each tile and the cost
## per class and the buildable flag of each terrain and tile, and lists the cells of the first
## terrain with the id ORE_ID, ascending. The terrain index is the position in the terrain set.
static func _load_map(world: World, map: MapDef) -> void:
	var defs: Array[TerrainDef] = map.terrain.terrains
	var rows: PackedStringArray = map.rows
	var classes: int = World.GROUND_CLASSES  # The stride of terrain_cost; AIR has no terrain cost.
	var index_of_symbol: Dictionary[int, int] = {}
	world.terrain_cost.resize(defs.size() * classes)
	world.terrain_buildable.resize(defs.size())
	var ore_index: int = -1
	for index: int in defs.size():
		var def: TerrainDef = defs[index]
		world.terrain_ids.append(def.id)
		world.terrain_buildable[index] = 1 if def.buildable else 0
		if def.id == World.ORE_ID and ore_index < 0:
			ore_index = index
		if len(def.symbol) == 1:
			index_of_symbol[def.symbol.unicode_at(0)] = index
		for move_class: int in classes:
			world.terrain_cost[index * classes + move_class] = def.cost[move_class]
	var size: Vector2i = map.size_tiles()
	world.map_cols = size.x
	world.map_rows = size.y
	world.map_w = size.x * World.MILLI_PER_TILE
	world.map_h = size.y * World.MILLI_PER_TILE
	var cells: int = size.x * size.y
	world.terrain.resize(cells)
	world.move_cost.resize(World.MoveClass.size() * cells)
	world.move_cost.fill(World.GRASS_COST)  # The AIR plane; the ground planes follow below.
	var kind_at: PackedByteArray = world.terrain
	var costs: PackedByteArray = world.terrain_cost
	var cost_at: PackedByteArray = world.move_cost
	var ore_at: PackedInt32Array = world.ore_cell
	for ty: int in size.y:
		var line: String = rows[ty]
		for tx: int in size.x:
			var cell: int = ty * size.x + tx
			var kind: int = index_of_symbol[line.unicode_at(tx)]
			kind_at[cell] = kind
			if kind == ore_index:
				ore_at.append(cell)
			for move_class: int in classes:
				cost_at[move_class * cells + cell] = costs[kind * classes + move_class]


## The type index for `unit`'s type_id. A type seen for the first time is copied in, so each
## definition is read once however many spawns use it. The faction table takes the index of
## `unit.faction` (_faction_for). A BuildingDef also fills the footprint, power, produced tab, free
## unit, dock and exit tables (a UnitDef pads them); the type it `requires` and the `free_unit` of a
## building are copied in too, after it, when no earlier type was theirs.
static func _type_for(world: World, unit: UnitDef) -> int:
	var found: int = world.type_ids.find(unit.type_id)
	if found >= 0:
		return found
	world.type_ids.append(unit.type_id)
	world.type_speed.append(unit.speed)
	world.type_radius.append(unit.radius)
	world.type_selection_radius.append(unit.selection_radius)
	world.type_spacing.append(unit.formation_spacing)
	world.type_max_hp.append(maxi(unit.max_hp, 1))
	world.type_armour.append(unit.armour)
	world.type_move_class.append(unit.move_class)
	world.type_sight.append(unit.sight_range)
	world.type_acquire.append(unit.acquire_range)
	world.type_weapon.append(_weapon_for(world, unit.weapon))
	var label: String = unit.display_name
	world.type_names.append(label if not label.is_empty() else String(unit.type_id).capitalize())
	world.type_cost.append(unit.cost)
	world.type_build_ticks.append(unit.build_ticks)
	world.type_tab.append(unit.tab)
	world.type_requires.append(World.TYPE_PAD_NONE)
	world.type_harvest.append(unit.harvest_capacity)
	world.type_faction.append(_faction_for(world, unit.faction))
	var building: BuildingDef = unit as BuildingDef
	world.type_foot_w.append(building.footprint.x if building != null else World.TYPE_PAD_V0)
	world.type_foot_h.append(building.footprint.y if building != null else World.TYPE_PAD_V0)
	world.type_produces.append(building.produces if building != null else World.TYPE_PAD_NONE)
	world.type_power.append(building.power if building != null else World.TYPE_PAD_V0)
	world.type_free_unit.append(World.TYPE_PAD_NONE)
	world.type_dock_x.append(building.dock.x if building != null else World.TYPE_PAD_V0)
	world.type_dock_y.append(building.dock.y if building != null else World.TYPE_PAD_V0)
	world.type_exit_x.append(building.exit.x if building != null else World.TYPE_PAD_V0)
	world.type_exit_y.append(building.exit.y if building != null else World.TYPE_PAD_V0)
	_strike_for(world, building)
	_air_for(world, unit, building)
	# The other types last, so that this type is complete before they are read.
	var index: int = world.type_ids.size() - 1
	if unit.requires != null:
		world.type_requires[index] = _type_for(world, unit.requires)
	if building != null and building.free_unit != null:
		world.type_free_unit[index] = _type_for(world, building.free_unit)
	return index


## Appends the air and repair entries of a type (ADR 0036 sections 2 and 3): the layer bit derived
## from the move class and `low_flying`, the ammo, the pads and their offsets (a BuildingDef's), the
## upgrade a research item gives (-1: P246 makes those types), the repair role and the carrier role.
static func _air_for(world: World, unit: UnitDef, building: BuildingDef) -> void:
	var layer: int = World.Layer.GROUND
	if unit.move_class == World.MoveClass.AIR:
		layer = World.Layer.LOW_AIR if unit.low_flying else World.Layer.AIR
	world.type_layer_bit.append(layer)
	world.type_ammo.append(unit.ammo)
	world.type_rearm_ticks.append(unit.rearm_ticks)
	world.type_pads.append(building.pads if building != null else World.TYPE_PAD_V0)
	world.type_pad_first.append(world.pad_offset_x.size())
	if building != null:
		for offset: Vector2i in building.pad_offsets:
			world.pad_offset_x.append(offset.x)
			world.pad_offset_y.append(offset.y)
	world.type_upgrade.append(World.TYPE_PAD_NONE)  # `_upgrade_for` sets a research item's.
	world.type_repair_classes.append(unit.repair_classes)
	world.type_repair_hp.append(unit.repair_hp)
	world.type_repair_period.append(unit.repair_period_ticks)
	world.type_repair_cost_percent.append(unit.repair_cost_percent)
	world.type_repair_reach.append(unit.repair_reach_milli)
	world.type_repair_slots.append(unit.repair_slots)
	world.type_repair_seek.append(unit.repair_seek_milli)
	world.type_carry_slots.append(unit.carry_slots)
	world.type_carry_classes.append(unit.carry_classes)
	world.type_carry_eject_percent.append(unit.carry_eject_percent)
	world.type_mine_weapon.append(_weapon_for(world, unit.mine_weapon))
	world.type_mine_cost.append(unit.mine_cost)
	world.type_mine_aware.append(1 if unit.mine_aware else 0)
	world.type_detect_milli.append(unit.detect_milli)


## Appends an upgrade (ADR 0036 sections 2 and 3) once per id, up to World.UPGRADES_MAX: its stat
## and value, and the type indexes it changes, flat in `upgrade_types` from `upgrade_type_first`.
static func _upgrade_for(world: World, upgrade: UpgradeDef) -> void:
	if (
		upgrade == null
		or world.upgrade_ids.has(upgrade.id)
		or world.upgrade_ids.size() >= World.UPGRADES_MAX
	):
		return
	if world.type_ids.has(upgrade.id):
		push_error("upgrade id %s is also a type id; skipped" % upgrade.id)
		return
	world.upgrade_ids.append(upgrade.id)
	world.upgrade_stat.append(upgrade.stat)
	world.upgrade_value.append(upgrade.value)
	var first: int = world.upgrade_types.size()
	world.upgrade_type_first.append(first)
	for unit: UnitDef in upgrade.applies_to:
		if unit != null:  # A null entry names no type: it is left out of the count too.
			world.upgrade_types.append(_type_for(world, unit))
	world.upgrade_type_count.append(world.upgrade_types.size() - first)
	# The research item (ADR 0036 section 3): a queue-only type of the RESEARCH tab, named by the id.
	var item: UnitDef = UnitDef.new()
	item.type_id = upgrade.id
	item.display_name = upgrade.display_name
	item.faction = upgrade.faction
	item.cost = upgrade.cost
	item.build_ticks = upgrade.research_ticks
	item.tab = World.Tab.RESEARCH
	item.requires = upgrade.requires
	world.type_upgrade[_type_for(world, item)] = world.upgrade_ids.size() - 1


## Appends the six strike table entries of a type (ADR 0023 section 10): a BuildingDef's exports,
## else the pads (kind 0, no lengths, no weapon). The strike weapon is a weapon of the weapon tables
## (_weapon_for), so a rupture's damage goes through the armour percents like a shot's.
static func _strike_for(world: World, building: BuildingDef) -> void:
	var pad: int = World.TYPE_PAD_V0
	world.type_strike_kind.append(building.strike_kind if building != null else pad)
	world.type_charge_ticks.append(building.charge_ticks if building != null else pad)
	world.type_strike_radius.append(building.strike_radius if building != null else pad)
	world.type_strike_delay.append(building.strike_delay if building != null else pad)
	world.type_strike_ticks.append(building.strike_ticks if building != null else pad)
	var weapon: int = World.TYPE_PAD_NONE
	if building != null:
		weapon = _weapon_for(world, building.strike_weapon)
	world.type_strike_weapon.append(weapon)


## The faction index for `faction`, -1 for none (an empty id: any faction). A faction is known by
## its id: the first type that names it adds it to `faction_ids`, so the order is first appearance.
static func _faction_for(world: World, faction: StringName) -> int:
	if faction.is_empty():
		return World.TYPE_PAD_NONE
	var found: int = world.faction_ids.find(faction)
	if found >= 0:
		return found
	world.faction_ids.append(faction)
	return world.faction_ids.size() - 1


## The weapon index for `weapon`, -1 for none. A weapon is known by its id like a type by its
## type_id: the first definition of an id is copied in and wins. A definition has four percents
## (a data test pins it for the shipped ones), so each weapon takes four table entries.
static func _weapon_for(world: World, weapon: WeaponDef) -> int:
	if weapon == null:
		return -1
	var found: int = world.weapon_ids.find(weapon.id)
	if found >= 0:
		return found
	world.weapon_ids.append(weapon.id)
	world.weapon_range.append(weapon.range)
	world.weapon_min_range.append(weapon.min_range)
	world.weapon_damage.append(weapon.damage)
	world.weapon_cooldown.append(weapon.cooldown_ticks)
	world.weapon_projectile_speed.append(weapon.projectile_speed)
	for armour: int in World.Armour.size():
		world.weapon_vs_armour.append(weapon.vs_armour[armour])
	world.weapon_targets.append(weapon.targets)
	world.weapon_blast_milli.append(weapon.blast_milli)
	return world.weapon_ids.size() - 1


## The start point of a unit whose grid point is (x, y) and whose spawn has a `jitter` above 0: the
## point moved by -jitter..jitter on each axis (always two draws, x then y), clamped into the map,
## and kept only when its tile is passable for `move_class`. Otherwise the unit starts on the grid
## point. Data keeps every grid point inside the map and passable (test_defs_data), so the unit is
## never more than `jitter` away on an axis; a grid point that is not, is not repaired here.
static func _jittered(world: World, x: int, y: int, jitter: int, move_class: int) -> Vector2i:
	var moved_x: int = x + world.rng.range_int(-jitter, jitter)
	var moved_y: int = y + world.rng.range_int(-jitter, jitter)
	if world.map_cols > 0:
		moved_x = clampi(moved_x, 0, world.map_w - 1)
		moved_y = clampi(moved_y, 0, world.map_h - 1)
		if not world.is_passable(world.cell_of(moved_x, moved_y), move_class):
			return Vector2i(x, y)
	return Vector2i(moved_x, moved_y)


## Copies the rule ints from `rules` under the same names.
static func copy_rules(world: World, rules: RulesDef) -> void:
	world.retarget_period_ticks = rules.retarget_period_ticks
	world.fog_period_ticks = rules.fog_period_ticks
	world.line_check_period_ticks = rules.line_check_period_ticks
	world.flow_cells_per_tick = rules.flow_cells_per_tick
	world.flow_cache_size = rules.flow_cache_size
	world.separation_neighbours = rules.separation_neighbours
	world.separation_scan = rules.separation_scan
	world.separation_idle_share = rules.separation_idle_share
	world.separation_push_max = rules.separation_push_max
	world.separation_coincident_divisor = rules.separation_coincident_divisor
	world.stall_ticks = rules.stall_ticks
	world.stall_range_spacings = rules.stall_range_spacings
	world.attack_rekey_milli = rules.attack_rekey_milli
	world.max_projectiles = rules.max_projectiles
	world.max_rows = rules.max_rows
	world.start_credits = rules.start_credits
	world.ore_start = rules.ore_start
	world.ore_cell_max = rules.ore_cell_max
	world.ore_regrow_ticks = rules.ore_regrow_ticks
	world.credits_per_ore = rules.credits_per_ore
	world.harvest_ticks_per_ore = rules.harvest_ticks_per_ore
	world.unload_ticks_per_ore = rules.unload_ticks_per_ore
	world.harvest_reach_milli = rules.harvest_reach_milli
	world.dock_reach_milli = rules.dock_reach_milli
	world.harvest_retry_ticks = rules.harvest_retry_ticks
	world.harvest_resume_ticks = rules.harvest_resume_ticks
	world.harvest_pick_milli = rules.harvest_pick_milli
	world.low_power_percent = rules.low_power_percent
	world.queue_slots = rules.queue_slots
	world.build_reach_tiles = rules.build_reach_tiles
	world.unit_cap = rules.unit_cap
	world.building_cap = rules.building_cap
	world.ghost_cap = rules.ghost_cap
	world.construct_start_hp_percent = rules.construct_start_hp_percent
	world.construct_refund_percent = rules.construct_refund_percent
	world.construction_sites_max = rules.construction_sites_max
	world.sell_refund_percent = rules.sell_refund_percent
	world.mend_hp = rules.mend_hp
	world.mend_period_ticks = rules.mend_period_ticks
	world.mend_cost_percent = rules.mend_cost_percent
	world.passenger_cap = rules.passenger_cap
	world.load_reach_milli = rules.load_reach_milli
	world.unload_reach_tiles = rules.unload_reach_tiles
	world.mine_cap = rules.mine_cap
	world.mine_lay_ticks = rules.mine_lay_ticks
	world.mine_arm_ticks = rules.mine_arm_ticks
	world.sweep_ticks = rules.sweep_ticks
	world.mine_known_cap = rules.mine_known_cap


## Sets `World.income_percent` of `player`, the percent of `credits_per_ore` that player's unloads
## pay (a level's `income_percent`, set at load before the first step); `percent` is clamped to 0
## or more. Player 0 is the neutral player and is refused, and so is a player above player_count on
## a prepared world (its array is fitted already: it would grow and move defs_hash). Before
## prepare() the array grows to `player`, and prepare() keeps what is set (size_match_state fits it
## to player_count + 1, dropping an entry above that). Entries before `player` are PERCENT.
static func set_income(world: World, player: int, percent: int) -> void:
	if player < 1 or (world.prepared and player > world.player_count):
		return
	size_income(world, maxi(player + 1, world.income_percent.size()))
	world.income_percent[player] = maxi(percent, 0)


## Fits `income_percent` to `players` entries: the values set stay, a new entry is PERCENT.
static func size_income(world: World, players: int) -> void:
	var had: int = world.income_percent.size()
	world.income_percent.resize(players)
	for player: int in range(had, players):
		world.income_percent[player] = PERCENT


## Gives every type table one entry per type_ids entry, with the TYPE_PAD_* values (a name is the
## capitalised type id), because Phase 1 code appends only the four Phase 1 tables. It also sizes
## the scratch arrays to max_rows, stats to the Stat count and the projectile slots to
## max_projectiles, sizes the player, ore, ghost and passenger state at its start values
## (size_match_state), and derives open grass from map_w and map_h when no map is loaded. Last it
## configures the helpers, once, because configure() re-creates their arrays, stamps the fog of the
## rows that exist (stamp_fog) and caches the map digest of the hash. Idempotent through
## `prepared`; World.prepare() is the wrapper and Sim.step calls it every tick. Types, players and
## sizes are fixed before it.
static func prepare_world(world: World) -> void:
	if world.prepared:
		return
	var types: int = world.type_ids.size()
	pad_types(world, types)
	var ids: Array[StringName] = world.type_ids
	var names: PackedStringArray = world.type_names
	for i: int in range(names.size(), types):
		names.append(String(ids[i]).capitalize())
	# The fixed-capacity arrays. Resizing keeps the contents, so a second call is a no-op.
	world.intent_x.resize(world.max_rows)
	world.intent_y.resize(world.max_rows)
	world.push_x.resize(world.max_rows)
	world.push_y.resize(world.max_rows)
	world.stats.resize(World.Stat.size())
	if world.proj_id.size() != world.max_projectiles:
		reset_projectile_slots(world)
	if world.map_cols == 0:
		derive_open_grass(world)
	size_match_state(world)
	world.fog.configure(world.map_cols, world.map_rows, world.player_count)
	stamp_fog(world)
	world.flow.configure(
		world.map_cols, world.map_rows, World.MoveClass.size(), world.flow_cache_size
	)
	world.sep_grid.configure(world.map_w, world.map_h, World.SEP_CELL_MILLI, world.max_rows)
	world.target_grid.configure(world.map_w, world.map_h, World.TARGET_CELL_MILLI, world.max_rows)
	world._map_digest_version = -1  # The grid may be new without a map_version bump.
	WorldHash.map_digest(world)
	Upgrades.rebuild(world)
	world.prepared = true


## Sizes the player, ore, ghost and passenger state at its start values (ADR 0017 section 3), from
## the player count and the rule ints, so that no later row moves the hash through a start value:
## credits at start_credits for players 1..player_count, rally points and queue slots at -1 (none),
## every ore cell at ore_start, the rest 0 (the pending strikes, none; the passenger table free).
## Entry 0 of a per-player array is the neutral player.
static func size_match_state(world: World) -> void:
	var players: int = world.player_count + 1
	var queues: int = players * World.TABS
	var ghosts: int = players * world.ghost_cap
	size_income(world, players)
	world.credits.resize(players)
	for player: int in range(1, players):
		world.credits[player] = world.start_credits
	world.defeated_tick.resize(players)
	world.had_producer.resize(players)
	world.stat_built.resize(players)
	world.stat_lost_units.resize(players)
	world.stat_lost_buildings.resize(players)
	world.stat_harvested.resize(players)
	world.queue_count.resize(queues)
	world.queue_progress.resize(queues)
	world.rally_x.resize(queues)
	world.rally_x.fill(-1)
	world.rally_y.resize(queues)
	world.rally_y.fill(-1)
	world.queue_type.resize(queues * world.queue_slots)
	world.queue_type.fill(-1)
	world.strike_x.resize(players)
	world.strike_y.resize(players)
	world.strike_tick.resize(players)
	world.reveal_site.resize(players)
	world.reveal.resize(players)
	world.upgrades.resize(players)
	for column_name: StringName in World.PASSENGER_ARRAYS:  # The passenger table: all slots free.
		var column: PackedInt32Array = world.get(column_name)
		column.resize(world.passenger_cap)
	var mine_slots: int = world.mine_cap * world.player_count  # The mine table and the records.
	for column_name: StringName in World.MINE_ARRAYS:
		var mine_column: PackedInt32Array = world.get(column_name)
		mine_column.resize(mine_slots)
	var known: int = players * world.mine_known_cap
	for column_name: StringName in World.MINE_SEEN_ARRAYS:
		var seen_column: PackedInt32Array = world.get(column_name)
		seen_column.resize(players if column_name == &"mine_seen_count" else known)
	world.mine_at.resize(world.map_cols * world.map_rows)  # Grows with zeros, sparse after that.
	world.ore_amount.resize(world.ore_cell.size())
	world.ore_amount.fill(world.ore_start)
	world.ghost_id.resize(ghosts)
	world.ghost_type.resize(ghosts)
	world.ghost_owner.resize(ghosts)
	world.ghost_cell.resize(ghosts)
	world.ghost_count.resize(players)
	world.power_made.resize(players)
	world.power_used.resize(players)


## Gives every type table one entry per type, with the World.TYPE_PAD_* values, because Phase 1 code
## appends only the four Phase 1 tables (World.prepare calls it). The tables of the air and repair
## columns pad with 0 (the repair period with 1, UnitDef's default), the layer bit with GROUND and
## `type_upgrade` and `type_mine_weapon` with -1; `type_pad_first` (0) names no pad, because
## `type_pads` is 0. Of the weapon tables only `weapon_targets` (to the weapon count, with GROUND,
## the WeaponDef default) and `weapon_blast_milli` (with 0) are padded: a weapon of a scenario
## exists only through `_weapon_for`, which appends all of them, and a test that builds one by hand
## names no mask.
static func pad_types(world: World, types: int) -> void:
	for table: PackedInt32Array in [
		world.type_speed,
		world.type_radius,
		world.type_selection_radius,
		world.type_spacing,
		world.type_foot_w,
		world.type_foot_h,
		world.type_cost,
		world.type_build_ticks,
		world.type_power,
		world.type_harvest,
		world.type_dock_x,
		world.type_dock_y,
		world.type_exit_x,
		world.type_exit_y,
		world.type_strike_kind,
		world.type_charge_ticks,
		world.type_strike_radius,
		world.type_strike_delay,
		world.type_strike_ticks,
		world.type_ammo,
		world.type_rearm_ticks,
		world.type_pads,
		world.type_pad_first,
		world.type_repair_classes,
		world.type_repair_hp,
		world.type_repair_cost_percent,
		world.type_repair_reach,
		world.type_repair_slots,
		world.type_repair_seek,
		world.type_carry_slots,
		world.type_carry_classes,
		world.type_carry_eject_percent,
		world.type_mine_cost,
		world.type_mine_aware,
		world.type_detect_milli,
	]:
		_pad(table, types, World.TYPE_PAD_V0)
	_pad(world.type_max_hp, types, World.TYPE_PAD_MAX_HP)
	_pad(world.type_armour, types, World.TYPE_PAD_ARMOUR)
	_pad(world.type_move_class, types, World.TYPE_PAD_MOVE_CLASS)
	_pad(world.type_sight, types, World.TYPE_PAD_SIGHT)
	_pad(world.type_acquire, types, World.TYPE_PAD_ACQUIRE)
	_pad(world.type_weapon, types, World.TYPE_PAD_WEAPON)
	_pad(world.type_layer_bit, types, World.TYPE_PAD_LAYER)
	_pad(world.type_repair_period, types, World.TYPE_PAD_REPAIR_PERIOD)
	_pad(world.weapon_targets, world.weapon_range.size(), World.WEAPON_PAD_TARGETS)
	_pad(world.weapon_blast_milli, world.weapon_range.size(), World.TYPE_PAD_V0)
	for table: PackedInt32Array in [
		world.type_tab,
		world.type_requires,
		world.type_produces,
		world.type_free_unit,
		world.type_faction,
		world.type_strike_weapon,
		world.type_upgrade,
		world.type_mine_weapon,
	]:
		_pad(table, types, World.TYPE_PAD_NONE)


## Appends `value` to `table` until it has `size` entries.
static func _pad(table: PackedInt32Array, size: int, value: int) -> void:
	for _i: int in range(table.size(), size):
		table.append(value)


## One sight mask per type, in type order, so a mask id is the type index (two types of equal sight
## repeat their mask), and the pad mask of TYPE_PAD_SIGHT after them, id `type_sight.size()`, for a
## row whose type has no entry (the fog code takes the smaller of the type index and that id, so a
## mask added later changes nothing). Then the disc of every row of a player (1..player_count) at
## its cell, so the first frame of a match shows each player's own vision and the tick-0 hash
## includes it (ADR 0010 section 1), then the sweep of each player whose `reveal` is 1 (P233). No
## map, no cells: nothing is stamped. It counts nothing in `stats`. World.prepare calls it. It
## expects a freshly configured fog and clears each player's `revealed` flag anyway, so a call on a
## reused fog stays correct.
static func stamp_fog(world: World) -> void:
	var fog: FogGrid = world.fog
	for sight: int in world.type_sight:
		fog.add_mask(sight)
	fog.add_mask(World.TYPE_PAD_SIGHT)
	if fog.cells == 0:
		return
	var pad: int = world.type_sight.size()
	var owners: PackedInt32Array = world.owner
	var types: PackedInt32Array = world.type_index
	var stamped: PackedInt32Array = world.fog_cell
	for row: int in owners.size():
		var player: int = owners[row]
		if player >= 1 and player <= world.player_count:
			var cell: int = world.cell_of(world.pos_x[row], world.pos_y[row])
			fog.stamp(player, cell, mini(types[row], pad), 1)
			stamped[row] = cell
	# A sweep that stands (ADR 0036 section 11): its +1 and its flag come from the hashed `reveal`
	# alone, for every player, so a rebuild never depends on derived state.
	var sweeps: PackedInt32Array = world.reveal
	for player: int in range(1, mini(sweeps.size(), fog.player_count + 1)):
		fog.revealed[player - 1] = 0
		if sweeps[player] == Reveal.State.ON:
			fog.reveal(player, 1)


## Sizes every projectile slot array to max_projectiles, all slots free. Only the first prepare()
## calls it (the sizes match afterwards). Changing max_projectiles after prepare() is not supported.
static func reset_projectile_slots(world: World) -> void:
	var slots: int = world.max_projectiles
	for column_name: StringName in World.PROJECTILE_ARRAYS:
		var column: PackedInt32Array = world.get(column_name)
		column.clear()
		column.resize(slots)
	var stack: PackedInt32Array = world.proj_free
	for i: int in slots:
		stack[i] = slots - 1 - i
	world.proj_free_top = slots


## Makes `cell` the terrain `terrain_index` (an index into terrain_ids) with that terrain's cost for
## each ground class (the AIR plane stays open), and bumps map_version, also when the terrain is the
## same. A cell outside the map, an index above TERRAIN_INDEX_MAX (a byte, P48) or an unknown
## terrain index (one whose `terrain_cost` row is missing) changes nothing. It leaves `ore_cell` as
## the load made it. Any other writer of `terrain`, `move_cost`, `terrain_cost`, `terrain_buildable`
## or `ore_cell` must bump map_version itself, because the map digest of the hash follows
## map_version alone (WorldHash.map_digest).
static func set_terrain(world: World, cell: int, terrain_index: int) -> void:
	var classes: int = World.GROUND_CLASSES
	var cells: int = world.map_cols * world.map_rows
	if cell < 0 or cell >= cells or terrain_index < 0 or terrain_index > World.TERRAIN_INDEX_MAX:
		return
	if (terrain_index + 1) * classes > world.terrain_cost.size():
		return
	world.terrain[cell] = terrain_index
	for move_class: int in classes:
		world.move_cost[move_class * cells + cell] = world.terrain_cost[
			terrain_index * classes + move_class
		]
	world.map_version += 1
	world.flow.invalidate(world.map_version)  # Before any acquire() under the new version.
