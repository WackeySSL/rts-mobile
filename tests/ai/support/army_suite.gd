extends "res://tests/ai/support/intel_suite.gd"
## The base of the `AiArmy` suites (plan row P179): the intel suite's World (player 1's Headquarters
## centred on tile (7, 7) of the 40 x 40 map, two rifle squads beside it, the enemy base 28 tiles
## away) with the army manager made beside the intel manager. Not a test suite.

## The staging point of player 1 while no enemy producer is known: 6 tiles from the Headquarters
## toward the point mirror (32, 32), (4, 4) along each axis after the integer division.
const STAGING: Vector2i = Vector2i(11, 11)
## The numbers the suites own (the def is copied and set to them, so a tuning row of the shipped
## `data/ai/` cannot move them): the staging offset and the defence radius, in tiles, and the
## goal-key cap.
const OFFSET: int = 6
const RADIUS: int = 12
const KEYS: int = 4

var _army: AiArmy = null


func before_test() -> void:
	super()
	_arm("normal")


## The managers of the fossil def at `level` (a fresh memory), and `_army` beside them. `def` is
## the fossil def with its offset and radius set to the suite's; a case may pass its own.
func _arm(level: String, def: OpponentDef = null) -> void:
	var own: OpponentDef = def if def != null else _def()
	_make(level)
	_memory = AiMemory.create(own)
	_army = AiArmy.create(own, _plain(level), 1)


## A copy of the shipped level `level` with Hard's unit control off (P180b owns its suite), so the
## suites of the group orders read the same plain defence and waves at every level.
func _plain(level: String) -> AiDifficultyDef:
	var plain: AiDifficultyDef = Rig.level_of(level).duplicate() as AiDifficultyDef
	plain.unit_retreat_hp_percent = 0
	plain.focus_fire = 0
	# P197 owns the siege and the press (tests/ai/test_ai_army_siege.gd).
	plain.press_percent = 0
	plain.siege_focus = 0
	plain.gather_tiles = 0
	plain.reinforce_percent = 0
	return plain


## A copy of the fossil def with the suite's staging offset, defence radius and key cap.
func _def() -> OpponentDef:
	var def: OpponentDef = Rig.def_of("fossil").duplicate() as OpponentDef
	def.staging_offset_tiles = OFFSET
	def.defend_radius_tiles = RADIUS
	def.goal_keys_max = KEYS
	return def


## An ARMY slot at `tick` with a budget of `budget` Commands: the intel refresh, then the army.
func _think(tick: int, budget: int = 8) -> void:
	_world.tick = tick
	_memory.commands_left = budget
	_out = []
	var view: PlayerView = _view()
	_intel.refresh(view, _memory)
	_army.run(view, _memory, _rng, _out)


## Every tile seen by player 1 (the fog is not stepped by these suites), so a crafted enemy row is
## seen wherever it stands.
func _see_all() -> void:
	_world.fog.visible.fill(1)


## An enemy unit of `type_id` at (`x`, `y`) milli-tiles; returns its id.
func _enemy(type_id: String, x: int, y: int) -> int:
	return AiRig.add_unit_of(_world, 2, type_id, x, y)


## Moves the unit `id` (any owner) to (`x`, `y`) milli-tiles.
func _put(id: int, x: int, y: int) -> void:
	var row: int = _row_in_world(id)
	_world.pos_x[row] = x
	_world.pos_y[row] = y


## The Commands of `_out` of one type.
func _of(type: int) -> Array[Command]:
	var found: Array[Command] = []
	for command: Command in _out:
		if command.type == type:
			found.append(command)
	return found


## The ids of player 1's two starting rifle squads, ascending.
func _squads() -> PackedInt32Array:
	return AiRig.ids_of(_world, 1, "rifle_squad")


## The centre of `tile` in milli-tiles.
static func _centre(tile: Vector2i) -> Vector2i:
	return tile * 1000 + Vector2i(500, 500)
