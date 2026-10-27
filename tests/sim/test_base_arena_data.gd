extends GdUnitTestSuite
## The base arena as data (plan row P80, ADR 0021 section 2, ADR 0023 sections 6, 7 and 14): the
## map `data/maps/perf_bases.tres` and the scenario `data/scenarios/perf_bases.tres`. Two compact
## bases facing each other across a ridge with three gaps, the Derrick League (player 1) in the
## west and the Lumen Accord (player 2) in the east, every building type of both, four harvesters
## and two ore fields a side, an army a side at the unit cap and the scenario orders that start the
## economy, the queues and, once the charge has ended and inside the 900-tick run, a strike each.
## What these data do when played is test_base_arena_run's and test_base_arena_strikes'. The layout
## numbers are literals (the data are layout); every rule number is read from the data files and the
## World.

const BaseArena: GDScript = preload("res://tests/sim/support/base_arena.gd")
const MAP_PATH: String = "res://data/maps/perf_bases.tres"
const SCENARIO_PATH: String = "res://data/scenarios/perf_bases.tres"
const TERRAIN_PATH: String = "res://data/terrain/standard.tres"
const RULES_PATH: String = "res://data/rules.tres"
const SIZE: Vector2i = Vector2i(54, 24)
## The ridge is the rock of columns 26 and 27, the map's two middle columns, except on the gap rows.
const RIDGE: int = 26
const GAP_ROWS: Array[int] = [6, 7, 11, 12, 13, 17, 18]
## The buildings of a side by role, in the order a faction's roster lists them (ADR 0023 section 7):
## Headquarters, power, refinery, barracks, factory, radar, defence, strike.
const PER_ROLE: Array[int] = [1, 4, 1, 1, 1, 1, 4, 1]
const HARVESTERS: int = 4
## Tiles per ore field, and fields a side.
const ORE_FIELD: int = 9
const ORE_FIELDS: int = 2
## The ground of the opening view in the iso projection of ADR 0023 section 1 (a tile is 64 x 32
## px, `sx = (gx - gy) x 32`, `sy = (gx + gy) x 16`) fits the 1280 x 720 viewport at this zoom
## around the camera tile. The perf arena's start zoom is 0.75; two bases and two armies need less.
const FRAME_ZOOM: float = 0.55
const VIEWPORT: Vector2 = Vector2(1280.0, 720.0)

var _world: World
var _scenario: ScenarioDef


func before() -> void:
	_scenario = load(SCENARIO_PATH) as ScenarioDef
	_world = World.from_scenario(_scenario, DetRandom.create(42, DetRandom.STREAM_SIM))


func test_the_map_is_a_mirror_image_with_a_ridge_three_gaps_and_two_ore_fields_a_side() -> void:
	var map: MapDef = load(MAP_PATH) as MapDef
	assert_array(map.validate()).is_empty()
	assert_that(map.size_tiles()).is_equal(SIZE)
	assert_str(map.terrain.resource_path).is_equal(TERRAIN_PATH)
	var gap_rows: Array[int] = []
	for y: int in map.rows.size():
		var row: String = map.rows[y]
		var mirrored: String = row.reverse()
		assert_str(mirrored).override_failure_message("row %d" % y).is_equal(row)
		var ridge: String = row.substr(RIDGE, 2)
		if ridge == "..":
			gap_rows.append(y)
		else:
			assert_str(ridge).override_failure_message("row %d" % y).is_equal("##")
		assert_int(row.count("#")).override_failure_message("row %d" % y).is_equal(
			0 if ridge == ".." else 2
		)
	assert_array(gap_rows).is_equal(GAP_ROWS)
	# Two fields of nine ore tiles a side, as the World lists them (the cells of terrain `ore`).
	assert_int(_world.ore_cell.size()).is_equal(2 * ORE_FIELDS * ORE_FIELD)
	for side: int in [0, 1]:
		var cells: Array[int] = []
		for cell: int in _world.ore_cell:
			if (cell % SIZE.x >= RIDGE + 2) == (side == 1):
				cells.append(cell)
		assert_array(_field_sizes(cells)).is_equal([ORE_FIELD, ORE_FIELD])


func test_the_scenario_is_two_players_with_both_factions_and_the_shared_rules() -> void:
	assert_int(_scenario.player_count).is_equal(2)
	assert_int(_scenario.local_player).is_equal(1)
	assert_that(_scenario.map_size_tiles).is_equal(SIZE)
	assert_str(_scenario.map.resource_path).is_equal(MAP_PATH)
	assert_str(_scenario.rules.resource_path).is_equal(RULES_PATH)
	# Entry 0 is unused; player 1 plays the Derrick League and player 2 the Lumen Accord.
	assert_int(_scenario.factions.size()).is_equal(3)
	assert_object(_scenario.factions[0]).is_null()
	assert_array([_scenario.factions[1].id, _scenario.factions[2].id]).is_equal(
		[&"fossil", &"renew"]
	)
	# The camera starts on the middle of the ridge, where the rows are framed from.
	assert_that(_scenario.camera_start_tile).is_equal(Vector2i(RIDGE + 1, SIZE.y / 2))


func test_each_side_places_every_building_type_of_its_faction_with_the_counts_of_the_table(
) -> void:
	var placed: Dictionary[StringName, int] = {}
	for spawn: SpawnDef in _scenario.spawns:
		if spawn.unit is BuildingDef:
			assert_int(spawn.owner).is_greater(0)
			var key: StringName = StringName("%d/%s" % [spawn.owner, spawn.unit.type_id])
			placed[key] = placed.get(key, 0) + spawn.count
	for player: int in [1, 2]:
		var roster: Array[UnitDef] = _scenario.factions[player].roster
		var total: int = 0
		for role: int in PER_ROLE.size():
			var def: UnitDef = roster[role]
			assert_bool(def is BuildingDef).override_failure_message(str(def.type_id)).is_true()
			var key: StringName = StringName("%d/%s" % [player, def.type_id])
			assert_int(placed.get(key, 0)).override_failure_message(str(key)).is_equal(
				PER_ROLE[role]
			)
			assert_str(String(def.faction)).is_equal(String(_scenario.factions[player].id))
			total += PER_ROLE[role]
		assert_int(total).is_equal(14)
	# 28 buildings in all ("about 30"), which are the rows with a footprint.
	var rows: int = 0
	for type: int in _world.type_ids.size():
		if _world.type_foot_w[type] > 0:
			rows += _world.type_index.count(type)
	assert_int(rows).is_equal(28)


## Every footprint is inside the map on buildable ground and clear of the others, and the tile of a
## dock or an exit is open: a unit leaves at the exit itself and a harvester docks at the dock
## itself, with no walk round the ring (ProductionSpawn.tile_from finds them at once).
func test_the_buildings_stand_on_buildable_ground_apart_with_open_docks_and_exits() -> void:
	assert_int(_world.spawn_refused).is_equal(0)
	var taken: Dictionary[int, int] = {}
	var problems: Array[String] = []
	var tracked: int = World.MoveClass.TRACKED
	for row: int in _world.unit_count():
		var type: int = _world.type_index[row]
		var width: int = _world.type_foot_w[type]
		if width <= 0:
			continue
		var origin: Vector2i = _world.footprint_origin(row)
		for dx: int in width:
			for dy: int in _world.type_foot_h[type]:
				var cell: int = (origin.y + dy) * _world.map_cols + origin.x + dx
				if taken.has(cell):
					problems.append("%s overlaps row %d" % [_world.type_names[type], taken[cell]])
				taken[cell] = row
				if _world.terrain_buildable[_world.terrain[cell]] != 1:
					problems.append("%s on ground that is not buildable" % _world.type_names[type])
		var exits: Array[Vector2i] = []
		if _world.type_produces[type] > 0:
			exits.append(Vector2i(_world.type_exit_x[type], _world.type_exit_y[type]))
		if _world.type_dock_x[type] != 0 or _world.type_dock_y[type] != 0:
			exits.append(Vector2i(_world.type_dock_x[type], _world.type_dock_y[type]))
		for offset: Vector2i in exits:
			for move_class: int in [World.MoveClass.FOOT, tracked]:
				var found: Vector2i = ProductionSpawn.tile_from(_world, row, move_class, offset)
				if found != origin + offset:
					problems.append("%s: tile %s is not open" % [_world.type_names[type], offset])
	assert_array(problems).is_empty()
	assert_int(taken.size()).is_greater(28)


## No side starts on low power (a player's output covers what its buildings use), so the queues run
## at the full rate until a blackout: the first thing a player would notice otherwise is the slow
## start of a run that is meant to be a fight.
func test_each_side_makes_the_power_its_buildings_use() -> void:
	for player: int in [1, 2]:
		var made: int = 0
		var used: int = 0
		for row: int in _world.unit_count():
			var power: int = _world.type_power[_world.type_index[row]]
			if _world.owner[row] == player:
				made += maxi(power, 0)
				used += maxi(-power, 0)
		assert_int(used).override_failure_message("player %d" % player).is_greater(0)
		assert_int(made).override_failure_message("player %d" % player).is_greater_equal(used)


## Each side's mobile rows are exactly the unit cap (75: 71 fighters and four harvesters), on open
## ground on its own side of the ridge, and each harvester starts in SEEK beside an ore field of its
## own side. The production queues therefore wait for the first death of their side.
func test_the_armies_start_at_the_unit_cap_on_open_ground_and_the_harvesters_beside_their_ore(
) -> void:
	var mobile: Array[int] = [0, 0, 0]
	var tankers: Array[int] = [0, 0, 0]
	var problems: Array[String] = []
	for row: int in _world.unit_count():
		var type: int = _world.type_index[row]
		if _world.type_speed[type] <= 0:
			continue
		var player: int = _world.owner[row]
		mobile[player] += 1
		var x: int = _world.pos_x[row]
		var own_side: bool = x < RIDGE * 1000 if player == 1 else x >= (RIDGE + 2) * 1000
		var cell: int = _world.cell_of(x, _world.pos_y[row])
		if not own_side or not _world.is_passable(cell, _world.type_move_class[type]):
			problems.append(
				(
					"%s of player %d at %d, %d"
					% [_world.type_names[type], player, x, _world.pos_y[row]]
				)
			)
		if _world.type_harvest[type] > 0:
			tankers[player] += 1
			assert_int(_world.harvest_mode[row]).is_equal(World.HarvestMode.SEEK)
			assert_int(_nearest_ore(row)).is_less_equal(_world.harvest_pick_milli)
			assert_bool((_ore_x(row) < RIDGE) == (player == 1)).is_true()
	assert_array(problems).is_empty()
	assert_array(mobile).is_equal([0, _world.unit_cap, _world.unit_cap])
	assert_array(tankers).is_equal([0, HARVESTERS, HARVESTERS])


## The orders at tick 0, side by side: the army to its firing line before the ridge (on its side,
## on open ground), the harvesters back to their ore (the group order pulls them out of work and
## Harvest.release makes them the player's), then the queue items of the faction, tab by tab, which
## fit the queue slots and the starting credits. Then the strikes, one each, from the strike
## building of the side's faction, at or after the end of its charge and aimed at the other base.
func test_the_orders_start_the_economy_the_queues_and_one_strike_a_side() -> void:
	var types: Array[int] = []
	for order: OrderDef in _scenario.orders:
		types.append(order.type)
	var side: Array[int] = [Command.Type.ATTACK_MOVE, Command.Type.HARVEST]
	for _item: int in 7:
		side.append(Command.Type.QUEUE)
	assert_array(types).is_equal(side + side + [Command.Type.SUPERWEAPON, Command.Type.SUPERWEAPON])
	for player: int in [1, 2]:
		var faction: FactionDef = _scenario.factions[player]
		var cost: int = 0
		var slots: Array[int] = [0, 0, 0]
		for order: OrderDef in _scenario.orders:
			if order.player != player:
				continue
			match order.type:
				Command.Type.ATTACK_MOVE:
					assert_int(order.tick).is_equal(0)
					var line: int = order.target_tile.x * 1000
					(
						assert_bool(
							line < RIDGE * 1000 if player == 1 else line > (RIDGE + 2) * 1000
						)
						. is_true()
					)
					(
						assert_bool(
							_world.is_passable(
								order.target_tile.y * SIZE.x + order.target_tile.x, 0
							)
						)
						. is_true()
					)
				Command.Type.HARVEST:
					var cell: int = order.target_tile.y * SIZE.x + order.target_tile.x
					assert_bool(_world.ore_cell.has(cell)).is_true()
					assert_bool((order.target_tile.x < RIDGE) == (player == 1)).is_true()
				Command.Type.QUEUE:
					assert_int(order.tick).is_equal(0)
					assert_bool(faction.roster.has(order.unit)).is_true()
					assert_str(String(order.unit.faction)).is_equal(String(faction.id))
					cost += order.unit.cost
					slots[order.unit.tab] += 1
				Command.Type.SUPERWEAPON:
					_check_strike(order, player)
		assert_int(cost).is_less_equal(_world.start_credits)
		assert_int(slots[World.Tab.STRUCTURES]).is_equal(0)
		assert_int(slots[World.Tab.INFANTRY]).is_between(1, _world.queue_slots)
		assert_int(slots[World.Tab.VEHICLES]).is_between(1, _world.queue_slots)


## Every row at the start, its footprint corners for a building and the tile for a unit, projected,
## stays inside the viewport at FRAME_ZOOM around the camera tile: the arena camera frames every row
## at the run start (the P50c rule; sprite overhang is the view's).
func test_the_start_formation_fits_the_arena_frame() -> void:
	var half: Vector2 = VIEWPORT / FRAME_ZOOM / 2.0
	var camera: Vector2 = _iso(Vector2(_scenario.camera_start_tile) + Vector2(0.5, 0.5))
	var worst: Vector2 = Vector2.ZERO
	for row: int in _world.unit_count():
		var type: int = _world.type_index[row]
		var centre: Vector2 = Vector2(_world.pos_x[row], _world.pos_y[row]) / 1000.0
		var reach: Vector2 = Vector2(0.5, 0.5)
		if _world.type_foot_w[type] > 0:
			reach = Vector2(_world.type_foot_w[type], _world.type_foot_h[type]) / 2.0
		for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
			var shown: Vector2 = _iso(centre + corner * reach) - camera
			worst = Vector2(maxf(worst.x, absf(shown.x)), maxf(worst.y, absf(shown.y)))
	assert_float(worst.x).is_less_equal(half.x)
	assert_float(worst.y).is_less_equal(half.y)
	# Not slack: the formation uses most of the width, so a wider layout is noticed.
	assert_float(worst.x).is_greater(half.x * 0.8)


## One SUPERWEAPON order of `player`: the strike building of its faction (a BuildingDef of its
## roster with a strike kind), a tick at or after the end of its charge and inside the arena's run,
## and a target tile in the other base, with an enemy building within the strike's radius and none
## of the firing player's own (a rupture takes own rows too). The building's spawn block starts
## `charge_elapsed_ticks` into the charge (a Deep Bore placed at tick 0 would need `charge_ticks`,
## longer than the run), so the first tick accepted is the difference, floored at 0 (ready_tick is
## the stamp of the placement plus the charge, less the ticks already behind it). The strike falls
## inside the run: a rupture lands `strike_delay` ticks after the order, a blackout works at once.
func _check_strike(order: OrderDef, player: int) -> void:
	var def: BuildingDef = order.unit as BuildingDef
	assert_object(def).is_not_null()
	assert_bool(_scenario.factions[player].roster.has(def)).is_true()
	assert_int(def.strike_kind).is_greater(0)
	var spawn: SpawnDef = null
	for candidate: SpawnDef in _scenario.spawns:
		if candidate.owner == player and candidate.unit == def:
			spawn = candidate
	assert_object(spawn).is_not_null()
	assert_int(spawn.count).is_equal(1)
	assert_int(spawn.charge_elapsed_ticks).is_greater(0)
	assert_int(order.tick).is_greater_equal(maxi(def.charge_ticks - spawn.charge_elapsed_ticks, 0))
	var delay: int = def.strike_delay if def.strike_kind == Strike.Kind.RUPTURE else 0
	assert_int(order.tick + 1 + delay).is_less_equal(BaseArena.RUN_TICKS)
	var point: Vector2i = order.target_tile * 1000 + Vector2i(500, 500)
	var reach: int = def.strike_radius
	var enemy: int = 0
	var own: int = 0
	for row: int in _world.unit_count():
		if _world.type_foot_w[_world.type_index[row]] <= 0:
			continue
		var dx: int = _world.pos_x[row] - point.x
		var dy: int = _world.pos_y[row] - point.y
		if dx * dx + dy * dy <= reach * reach:
			if _world.owner[row] == player:
				own += 1
			else:
				enemy += 1
	assert_int(enemy).override_failure_message("player %d" % player).is_greater_equal(1)
	assert_int(own).override_failure_message("player %d" % player).is_equal(0)


## The sizes of the 4-connected groups among `cells` (map cell indexes), sorted.
func _field_sizes(cells: Array[int]) -> Array[int]:
	var left: Dictionary[int, bool] = {}
	for cell: int in cells:
		left[cell] = true
	var sizes: Array[int] = []
	for first: int in cells:
		if not left.has(first):
			continue
		var open: Array[int] = [first]
		left.erase(first)
		var size: int = 0
		while not open.is_empty():
			var cell: int = open.pop_back()
			size += 1
			for step: int in [-1, 1, -SIZE.x, SIZE.x]:
				if (
					left.has(cell + step)
					and (absi(step) != 1 or (cell + step) / SIZE.x == cell / SIZE.x)
				):
					left.erase(cell + step)
					open.append(cell + step)
		sizes.append(size)
	sizes.sort()
	return sizes


## The squared-distance-nearest ore cell of row `row`, as its distance in milli-tiles.
func _nearest_ore(row: int) -> int:
	var best: int = -1
	for cell: int in _world.ore_cell:
		var centre: Vector2i = Vector2i(cell % SIZE.x * 1000 + 500, cell / SIZE.x * 1000 + 500)
		var dx: int = centre.x - _world.pos_x[row]
		var dy: int = centre.y - _world.pos_y[row]
		var d2: int = dx * dx + dy * dy
		best = d2 if best < 0 or d2 < best else best
	return int(sqrt(float(best)))


## The column of the ore cell that `_nearest_ore` finds for `row`.
func _ore_x(row: int) -> int:
	var best: int = -1
	var column: int = -1
	for cell: int in _world.ore_cell:
		var dx: int = cell % SIZE.x * 1000 + 500 - _world.pos_x[row]
		var dy: int = cell / SIZE.x * 1000 + 500 - _world.pos_y[row]
		if best < 0 or dx * dx + dy * dy < best:
			best = dx * dx + dy * dy
			column = cell % SIZE.x
	return column


func _iso(tile: Vector2) -> Vector2:
	return Vector2((tile.x - tile.y) * 32.0, (tile.x + tile.y) * 16.0)
