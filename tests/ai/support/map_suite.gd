extends GdUnitTestSuite
## The base of the map suites (plan row P555): the opponent AI on Heron Fords and Curlew Crags. A
## World is the real scenario of a map; a wall is a row of the enemy's power plants laid in two
## staggered layers across a crossing, so no tile of it stays open; the army is a few heavy tanks
## of the player's faction beside its base and the player's computer opponent is armed with a first
## wave of a few hundred ticks. Outcomes are read from the World (what stands, who is where), never
## from a timing. Not a test suite of its own.

const Rig: GDScript = preload("res://tests/ai/support/ai_rig.gd")
const Opp: GDScript = preload("res://tests/ai/support/opponent_rig.gd")
const Kestrel: GDScript = preload("res://tests/sim/support/kestrel_rig.gd")

const SEED: int = 5
const HQ: Dictionary[StringName, StringName] = {&"fossil": &"headquarters", &"renew": &"renew_hq"}
const TANKS: int = 6
## The tick the first wave launches at, and the strength it needs (the tanks cost more).
const WAVE_TICK: int = 100
const WAVE_STRENGTH: int = 1500
## Ticks the armies get to get through; far more than a crossing needs, so no run is a timing check.
const CAP: int = 6000
## A tank this close (tiles) to the enemy Headquarters has reached its base.
const NEAR: int = 12

var _world: World
var _loop: MatchLoop
var _ai: OpponentAi
var _faction: String = ""
var _enemy_faction: String = ""
var _tanks: PackedInt32Array = PackedInt32Array()
var _walls: PackedInt32Array = PackedInt32Array()
## What a map's suite sets: the crossings of its band (first column, width, first row of each) and
## the first and last row of the band.
var _crossings: Array[Vector3i] = []
var _band: Vector2i = Vector2i.ZERO
## The index of the crossing the first tank to enter the band took, -1 until one did.
var _used: int = -1
## The target of the first ATTACK the AI sent (0 until one) and the distance (milli-tiles) of that
## wall and of the nearest wall alive at the time from the army's tanks.
var _first_attack: int = 0
var _attack_gap: int = -1
var _nearest_gap: int = -1


## The World of the scenario at `path`, player 1's computer opponent on `level` and `TANKS` tanks
## of player 1 at (`army_x`, `army_y`) tiles. Every tile is explored unless `explored` is false (the
## scenarios start dark; most suites judge routes, not scouting). `stall_window` and `scout_units`,
## 0 or more, set the def's stall window (0 turns the answer off) and scouts; -1 keeps the file's.
func _start(
	path: String,
	army_x: int,
	army_y: int,
	level: String = "normal",
	explored: bool = true,
	stall_window: int = -1,
	scout_units: int = -1
) -> void:
	var scenario: ScenarioDef = load(path) as ScenarioDef
	_faction = String(scenario.factions[1].id)
	_enemy_faction = String(scenario.factions[2].id)
	_world = World.from_scenario(scenario, DetRandom.create(SEED, DetRandom.STREAM_SIM))
	_loop = Rig.loop_of(_world, SEED)
	var own: AiDifficultyDef = Opp.level_of(level).duplicate() as AiDifficultyDef
	own.wave_first_tick = WAVE_TICK
	own.wave_first_strength = WAVE_STRENGTH
	own.scout_first_tick = CAP * 10
	own.spend_margin_credits = 0  # The stall answer's numbers were made without the margin (P250e).
	var def: OpponentDef = Opp.def_of(_faction)
	if stall_window >= 0 or scout_units >= 0:
		def = def.duplicate() as OpponentDef
		def.stall_window_ticks = stall_window if stall_window >= 0 else def.stall_window_ticks
		def.stall_scout_units = scout_units if scout_units >= 0 else def.stall_scout_units
	_ai = OpponentAi.create(def, own, 1, DetRandom.create(SEED, DetRandom.STREAM_AI_BASE + 1))
	_tanks.clear()
	_walls.clear()
	_used = -1
	_first_attack = 0
	_attack_gap = -1
	_nearest_gap = -1
	for at: int in TANKS:
		var id: int = Rig.add_unit_of(
			_world,
			1,
			Kestrel.TANK[StringName(_faction)],
			(army_x + at) * 1000 + 500,
			army_y * 1000 + 500
		)
		_tanks.append(id)
	if explored:
		Rig.explore_all(_world)


## Seals the crossing `width` tiles wide that starts at column `first` on row `top`, `top + 1`, ...
## `top + 3` with the enemy's power plants: two layers of 2x2 buildings, the second shifted by one
## column when the width is odd, so no tile of the crossing stays free.
func _seal(first: int, width: int, top: int) -> void:
	var plant: String = String(Kestrel.POWER[StringName(_enemy_faction)])
	for layer: int in 2:
		var shift: int = 1 if width % 2 == 1 and layer == 1 else 0
		for column: int in range(first + shift, first + width - 1, 2):
			_walls.append(Rig.give(_world, 2, plant, column, top + layer * 2))


func _walls_alive() -> int:
	var alive: int = 0
	for id: int in _walls:
		if _world.index_of(id) >= 0:
			alive += 1
	return alive


## Seals crossing `index` of `_crossings`.
func _seal_crossing(index: int) -> void:
	_seal(_crossings[index].x, _crossings[index].y, _crossings[index].z)


## Runs the tick loop until `done` answers true (a Callable of no arguments) or `CAP` ticks passed,
## and notes the crossing the first tank in the band takes. The base is not reached at the start.
func _run_until(done: Callable) -> void:
	assert_bool(_reached_base()).is_false()
	for _step: int in CAP:
		var before: Vector2i = _wall_gaps(0)
		for command: Command in Rig.tick(_world, _loop, [_ai]):
			if command.type == Command.Type.ATTACK and _first_attack == 0:
				_attack_gap = _wall_gaps(command.target_id).x
				_nearest_gap = before.y
				_first_attack = command.target_id
		_note_crossing()
		if done.call():
			return


## `x`: the distance (milli-tiles) of wall `id` from the centre of the tanks alive, -1 for none;
## `y`: that of the nearest wall alive. Only the walls of `_walls` count.
func _wall_gaps(id: int) -> Vector2i:
	var sum: Vector2i = Vector2i.ZERO
	var count: int = 0
	for tank: int in _tanks:
		var row: int = _world.index_of(tank)
		if row >= 0:
			sum += Vector2i(_world.pos_x[row], _world.pos_y[row])
			count += 1
	if count == 0 or _walls.is_empty() or _first_attack != 0:
		return Vector2i(-1, -1)
	var centre: Vector2i = sum / count
	var chosen: int = -1
	var nearest: int = -1
	for wall: int in _walls:
		var row: int = _world.index_of(wall)
		if row < 0:
			continue
		var gap: Vector2i = Vector2i(_world.pos_x[row], _world.pos_y[row]) - centre
		var far: int = FixedMath.isqrt(gap.x * gap.x + gap.y * gap.y)
		if wall == id:
			chosen = far
		if nearest < 0 or far < nearest:
			nearest = far
	return Vector2i(chosen, nearest)


## Sets `_used` to the crossing whose columns hold the first tank found in the band's rows.
@warning_ignore("integer_division")
func _note_crossing() -> void:
	if _used >= 0:
		return
	for id: int in _tanks:
		var row: int = _world.index_of(id)
		if row < 0:
			continue
		var line: int = _world.pos_y[row] / World.MILLI_PER_TILE
		var column: int = _world.pos_x[row] / World.MILLI_PER_TILE
		if line < _band.x or line > _band.y:
			continue
		for index: int in _crossings.size():
			var crossing: Vector3i = _crossings[index]
			if column >= crossing.x and column < crossing.x + crossing.y:
				_used = index
				return


## Whether a tracked unit cannot get from the row below the band to the row above it through
## crossing `index`, the rest of the band being rock: the flow field of the World as it stands
## (walls and all) says so, not the AI.
@warning_ignore("integer_division")
func _blocked(index: int) -> bool:
	var crossing: Vector3i = _crossings[index]
	var cols: int = _world.map_cols
	var cells: int = cols * _world.map_rows
	var costs: PackedByteArray = _world.move_cost.duplicate()
	var plane: int = World.MoveClass.TRACKED * cells
	for line: int in range(_band.x, _band.y + 1):
		for column: int in cols:
			if column < crossing.x or column >= crossing.x + crossing.y:
				costs[plane + line * cols + column] = 0
	var middle: int = crossing.x + crossing.y / 2
	var south: Vector2i = Vector2i(middle, _band.y + 1)
	var flow: FlowField = Kestrel.field(_world, south, World.MoveClass.TRACKED, costs)
	return not Kestrel.reaches(flow, cols, Vector2i(middle, _band.x - 1))


## The crossing an open run of `path` with the army at (`army_x`, `army_y`) takes. A control: with
## nothing walled `_blocked` is false for it.
func _open_run(path: String, army_x: int, army_y: int) -> int:
	_start(path, army_x, army_y)
	for index: int in _crossings.size():
		assert_bool(_blocked(index)).override_failure_message(path).is_false()
	_run_until(_reached_base)
	assert_bool(_reached_base()).override_failure_message(path).is_true()
	assert_int(_used).override_failure_message(path).is_greater_equal(0)
	return _used


## The enemy Headquarters' tile, or (-1, -1) once it is gone.
func _enemy_hq() -> Vector2i:
	var row: int = Rig.row_of(_world, 2, String(HQ[StringName(_enemy_faction)]))
	if row < 0:
		return Vector2i(-1, -1)
	return _world.footprint_origin(row)


## Whether the enemy Headquarters is gone or one of the player's tanks stands within `NEAR` tiles
## of it.
@warning_ignore("integer_division")
func _reached_base() -> bool:
	var hq: Vector2i = _enemy_hq()
	if hq.x < 0:
		return true
	for id: int in _tanks:
		var row: int = _world.index_of(id)
		if row < 0:
			continue
		var dx: int = _world.pos_x[row] / World.MILLI_PER_TILE - hq.x
		var dy: int = _world.pos_y[row] / World.MILLI_PER_TILE - hq.y
		if dx * dx + dy * dy <= NEAR * NEAR:
			return true
	return false
