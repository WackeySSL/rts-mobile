extends "res://tests/ai/support/intel_suite.gd"
## The base of the `AiArmy` suites (plan row P179): the intel suite's World (player 1's Headquarters
## centred on tile (7, 7) of the 40 x 40 map, two rifle squads beside it, the enemy base 28 tiles
## away) with the army manager made beside the intel manager. Not a test suite.

## The staging point of player 1 while no enemy producer is known: 6 tiles from the Headquarters
## toward the point mirror (32, 32), (4, 4) along each axis after the integer division.
const STAGING: Vector2i = Vector2i(11, 11)

var _army: AiArmy = null


func before_test() -> void:
	super()
	_arm("normal")


## The managers of the fossil def at `level` (a fresh memory), and `_army` beside them.
func _arm(level: String) -> void:
	_make(level)
	_army = AiArmy.create(Rig.def_of("fossil"), Rig.level_of(level), 1)


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


## The tile of the centre of the point in milli-tiles.
static func _centre(tile: Vector2i) -> Vector2i:
	return tile * 1000 + Vector2i(500, 500)
