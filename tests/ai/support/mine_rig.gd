extends "res://tests/ai/support/support_suite.gd"
## The mine manager (plan row P295, ADR 0037 section 8): it lays on the own half of the route,
## sweeps a known mine before a wave, sends a scout layer ahead on Hard, builds its layer, and does
## nothing on Easy, on a def with no layer type or on the frozen copies. The rig's World is its own:
## a 40 x 24 map, the Headquarters of player 1 at (2, 2) and of player 2 at (36, 20) (the route is
## 34 tiles, so its own half ends 17 tiles out), a vehicle factory and a radar (the layer's
## requirement) of player 1 and one layer.

const Smoke: GDScript = preload("res://tests/smoke/smoke_run.gd")
const MATCH_TICKS: int = 6000
const COLS: int = 40
const LINES: int = 24
const HOME_TILE: Vector2i = Vector2i(3, 3)
const BASE_TILE: Vector2i = Vector2i(37, 21)


## An AI-vs-AI Normal match from one seed on the lagged pipeline (`AiDriver.lagged_tick`, the one
## the worker runs: the views are built before the step and the Commands land a tick later): the
## mines laid over the match and the state hash.
func _match(level: String) -> Dictionary:
	var levels: Array[String] = [level, level]
	var setup: Dictionary = Smoke.start(1, "cross", levels)
	var world: World = setup["world"]
	Smoke.run(world, setup["loop"], setup["controllers"], MATCH_TICKS)
	return {
		"laid": world.next_mine_id,
		"hash": WorldHash.state_hash(world),
		"dropped": world.dropped_commands
	}


func _fixture(radar: bool = true) -> Array:
	var world: World = _mine_world(radar)
	var memory: AiMemory = _memory()
	memory.home_x = HOME_TILE.x
	memory.home_y = HOME_TILE.y
	memory.base_x = BASE_TILE.x
	memory.base_y = BASE_TILE.y
	return [world, memory]


func _mine_world(radar: bool) -> World:
	var weapon: WeaponDef = WeaponDef.new()
	weapon.id = &"test_mine"
	weapon.damage = 60
	weapon.vs_armour = PackedInt32Array([100, 50, 25, 0])
	weapon.blast_milli = 1500
	var radar_def: BuildingDef = _building("radar", NONE, Vector2i(2, 2), 500)
	var layer: UnitDef = _unit("layer", World.Tab.VEHICLES, false, 200)
	layer.move_class = World.MoveClass.WHEELED
	layer.mine_weapon = weapon
	layer.mine_cost = 60
	layer.mine_aware = true
	layer.detect_milli = 3000
	layer.requires = radar_def
	var depot: BuildingDef = _building("depot", NONE, Vector2i(2, 2), 100)
	depot.mine_weapon = weapon
	depot.mine_cost = 60
	var units: Array[UnitDef] = [
		depot,
		_unit("hauler", World.Tab.VEHICLES, false, 100),
		_building("hq", World.Tab.STRUCTURES, Vector2i(3, 3), 0),
		_building("factory", World.Tab.VEHICLES, Vector2i(3, 3), 800),
		radar_def,
		layer,
	]
	var made: World = Rig.world_of(units, COLS, LINES, true, 2, "res://data/rules.tres")
	made.add_building(1, Worlds.type_of(made, "hq"), 2, 2)
	made.add_building(1, Worlds.type_of(made, "factory"), 8, 1)
	if radar:
		made.add_building(1, Worlds.type_of(made, "radar"), 12, 1)
	made.add_building(2, Worlds.type_of(made, "hq"), 36, 20)
	made.credits[1] = 100000
	return made


func _mine_def() -> OpponentDef:
	var def: OpponentDef = _def()
	def.mine_layer_type = &"layer"
	def.mine_scout_reach_percent = 75
	return def


func _mine_level(target: int, layers: int, scout: int) -> AiDifficultyDef:
	var level: AiDifficultyDef = AiDifficultyDef.new()
	level.mine_target = target
	level.mine_layers = layers
	level.mine_scout_ahead = scout
	return level


func _think(world: World, memory: AiMemory, miner: AiMines) -> Array[Command]:
	memory.commands_left = 99
	_fill(world, memory)
	var out: Array[Command] = []
	miner.run(PlayerView.of(world, 1), memory, out)
	return out


## `thinks` thinks one second apart, each followed by the fifteen ticks the sim runs; returns every
## Command sent.
func _play(
	world: World, loop: MatchLoop, memory: AiMemory, miner: AiMines, thinks: int
) -> Array[Command]:
	var all: Array[Command] = []
	for _think_at: int in thinks:
		var sent: Array[Command] = _think(world, memory, miner)
		all.append_array(sent)
		AiRig.step(world, loop, sent)
		for _tick: int in 14:
			AiRig.step(world, loop)
	assert_int(world.dropped_commands).is_equal(0)
	return all


## A mine of `owner` on `cell` in the table.
func _put(world: World, owner: int, cell: Vector2i) -> void:
	for column_name: StringName in World.MINE_ARRAYS:
		var column: PackedInt32Array = world.get(column_name)
		column.resize(maxi(column.size(), world.mine_count + 1))
	var at: int = world.mine_count
	world.mine_id[at] = world.next_mine_id
	world.mine_owner[at] = owner
	world.mine_cell[at] = cell.y * COLS + cell.x
	world.mine_weapon[at] = world.type_mine_weapon[Worlds.type_of(world, "layer")]
	world.mine_armed_tick[at] = 1
	world.mine_at[cell.y * COLS + cell.x] = at + 1
	world.next_mine_id += 1
	world.mine_count += 1


## A record of the mine of `owner` on `cell` in player `player`'s block, as `MineMemory` writes it.
func _record(world: World, player: int, owner: int, cell: Vector2i) -> void:
	var at: int = player * world.mine_known_cap + world.mine_seen_count[player]
	world.mine_seen_id[at] = world.mine_id[world.mine_at[cell.y * COLS + cell.x] - 1]
	world.mine_seen_owner[at] = owner
	world.mine_seen_cell[at] = cell.y * COLS + cell.x
	world.mine_seen_count[player] += 1


func _layer_production(def: OpponentDef, layers: int = 1) -> AiProduction:
	return AiProduction.create(def, _mine_level(2, layers, 0), 1)
