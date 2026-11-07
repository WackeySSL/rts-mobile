extends GdUnitTestSuite
## The base of the `AiIntel` suites (plan row P177): a hand-built World of `faction_rig.gd` (the
## frozen defs, a real fog) read through `PlayerView`, the manager, its memory and the helpers.
## Player 1's Headquarters has its centre on tile (7, 7) of the 40 x 40 map, so its point mirror is
## tile (32, 32); player 2's base is 28 tiles away and hidden. Not a test suite.

const Rig: GDScript = preload("res://tests/ai/support/opponent_rig.gd")
const AiRig: GDScript = preload("res://tests/ai/support/ai_rig.gd")
const FactionRig: GDScript = preload("res://tests/ai/support/faction_rig.gd")

const MIRROR: Vector2i = Vector2i(32, 32)

var _world: World = null
var _loop: MatchLoop = null
var _intel: AiIntel = null
var _memory: AiMemory = null
var _rng: DetRandom = null
var _out: Array[Command] = []


func before_test() -> void:
	_world = FactionRig.start("fossil", "fossil")
	_loop = AiRig.loop_of(_world)
	_make("normal")


## A manager and a memory of the fossil def at `level`, with the scout's first tick changed when
## `first_tick` is not -1.
func _make(level: String, first_tick: int = -1, seed: int = 1) -> void:
	var def: OpponentDef = Rig.def_of("fossil")
	var chosen: AiDifficultyDef = Rig.level_of(level).duplicate() as AiDifficultyDef
	if first_tick >= 0:
		chosen.scout_first_tick = first_tick
	_intel = AiIntel.create(def, chosen, 1)
	_memory = AiMemory.create(def)
	_rng = DetRandom.create(seed, DetRandom.STREAM_AI_BASE + 1)
	_out = []


func _view() -> PlayerView:
	return PlayerView.of(_world, 1)


## The INTEL slot at `tick` with a fresh budget.
func _run(tick: int, budget: int = 8) -> void:
	_world.tick = tick
	_memory.commands_left = budget
	_out = []
	_intel.run(_view(), _memory, _rng, _out)


## An own scout (the fossil light tank) at tile (`col`, `line`); returns its id.
func _scout(col: int, line: int) -> int:
	return AiRig.add_unit_of(_world, 1, "light_tank", col * 1000 + 500, line * 1000 + 500)


func _type(id: String) -> int:
	return AiRig.type_of(_world, id)


func _row(id: int) -> int:
	return _view().row_of(id)


func _settle() -> void:
	AiRig.settle(_world, _loop)


func _triple(type: int) -> Array[int]:
	return [_memory.seen_count[type], _memory.seen_first_tick[type], _memory.seen_last_tick[type]]


func _row_in_world(id: int) -> int:
	for row: int in _world.unit_count():
		if _world.unit_id[row] == id:
			return row
	return -1


## Writes a record of an enemy barracks at tile (`col`, `line`) into player 1's block, as the sim's
## memory phase would, for a building that no row of the view shows.
func _remember_barracks(col: int, line: int) -> void:
	var id: int = AiRig.give(_world, 2, "barracks", col, line)
	var row: int = _row_in_world(id)
	var cell: int = _world.pos_y[row] / 1000 * _world.map_cols + _world.pos_x[row] / 1000
	_write_ghost(id, "barracks", cell)


## Writes a record of the enemy building `id` of the type `type_id` with its footprint's top-left
## tile at (`col`, `line`), for an id that no row has (a building that is gone).
func _ghost(id: int, type_id: String, col: int, line: int) -> void:
	_write_ghost(id, type_id, (line + 1) * _world.map_cols + col + 1)


func _write_ghost(id: int, type_id: String, cell: int) -> void:
	var cap: int = _world.ghost_cap
	_world.ghost_id[cap] = id
	_world.ghost_type[cap] = _type(type_id)
	_world.ghost_owner[cap] = 2
	_world.ghost_cell[cap] = cell
	_world.ghost_count[1] = 1


## Starts a trip by hand: scout `id` out at waypoint 1 with its trip begun at tick 1800.
func _start_trip(id: int) -> void:
	_memory.scout_id = id
	_memory.scout_waypoint = 1
	_memory.scout_trip_tick = 1800
	_memory.scout_hp = _view().row_hp(_row(id))
	_world.tick = 1800
	_intel.refresh(_view(), _memory)


## Replaces the World and its loop with a fresh start.
func _before_trip_world() -> void:
	_world = FactionRig.start("fossil", "fossil")
	_loop = AiRig.loop_of(_world)


## The tile of the own row `id`.
func _tile_of(id: int) -> Vector2i:
	var pos: Vector2i = _view().row_pos(_row(id))
	return Vector2i(pos.x / 1000, pos.y / 1000)


## The number of scout MOVE Commands in `sent`.
func _moves_in(sent: Array[Command]) -> int:
	var moves: int = 0
	for command: Command in sent:
		if _scout_move(command):
			moves += 1
	return moves


## Whether `command` is a MOVE of a unit of the scout type: through the controller the army also
## sends MOVEs (the return to the staging point), of its own units only.
func _scout_move(command: Command) -> bool:
	if command.type != Command.Type.MOVE:
		return false
	var view: PlayerView = _view()
	return view.row_type(view.row_of(command.unit_ids[0])) == _type("light_tank")


## The scout `id` stands on tile (`col`, `line`) and the sector's centre cell is explored.
func _arrive(id: int, col: int, line: int) -> void:
	var row: int = _row_in_world(id)
	_world.pos_x[row] = col * 1000 + 500
	_world.pos_y[row] = line * 1000 + 500
	_world.fog.explored[line * 40 + col] = 1
