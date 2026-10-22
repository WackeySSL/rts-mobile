class_name WorldLoad
extends RefCounted
## The scenario loader of a World, split out of World.gd (P70c) so that file stays under gdlint's
## 1,000 lines. Pure static helpers: they read the scenario, the map and the definitions passed in
## and write the World passed in, and they keep nothing. World.from_scenario() is a thin wrapper
## over from_scenario() here, and World.prepare() calls derive_open_grass(), so no caller names
## this class. No rule lives here: the code is World.gd's own, moved (ADR 0007 section 2, ADR 0017
## section 3 keep every column, list and rule int in World itself).


## Reads the scenario and its definitions once and returns a prepared world; a null scenario gives
## an empty one. The rules come from `scenario.rules`, else they stay the RulesDef defaults. A null
## `rng` keeps the default stream. The map grid comes from `scenario.map`, which also sets the map
## size; without a map, or with one that fails validate(), the world is open grass of
## `map_size_tiles`. Types come from the spawns (one without a unit is skipped), then the roster.
## `player_count` is the scenario's value, raised to the highest spawn owner. A spawn with a jitter
## draws two values per unit (see _jittered). The SPAWNED events of the setup are dropped. Spawns
## run before prepare(), so no row is refused here: data keeps their total within `max_rows`.
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
		_load_map(world, map)
	else:
		world.map_w = scenario.map_size_tiles.x * World.MILLI_PER_TILE
		world.map_h = scenario.map_size_tiles.y * World.MILLI_PER_TILE
		derive_open_grass(world)
	for spawn: SpawnDef in scenario.spawns:
		if spawn == null or spawn.unit == null:
			continue
		var type: int = _type_for(world, spawn.unit)
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
			column += 1
			if column == columns:
				column = 0
				row += 1
	for unit: UnitDef in scenario.roster:
		if unit != null:
			_type_for(world, unit)
	world.prepare()
	world.events.clear()
	return world


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
	var classes: int = World.MoveClass.size()
	world.terrain.resize(cells)
	world.move_cost.resize(classes * cells)
	world.move_cost.fill(World.GRASS_COST)
	world.terrain_cost.resize(classes)
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
	var classes: int = World.MoveClass.size()
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
	world.move_cost.resize(classes * cells)
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
## definition is read once however many spawns use it. A BuildingDef also fills the footprint,
## power, produced tab, free unit, dock and exit tables (a UnitDef pads them); the type it
## `requires` and the `free_unit` of a building are copied in too, after it, when no earlier type
## was theirs.
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
	# The other types last, so that this type is complete before they are read.
	var index: int = world.type_ids.size() - 1
	if unit.requires != null:
		world.type_requires[index] = _type_for(world, unit.requires)
	if building != null and building.free_unit != null:
		world.type_free_unit[index] = _type_for(world, building.free_unit)
	return index


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
