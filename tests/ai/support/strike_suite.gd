extends "res://tests/ai/support/intel_suite.gd"
## The base of the `AiStrikes` suites (plan row P181): the intel suite's World (player 1's fossil
## Headquarters on tile (7, 7), the enemy base 28 tiles away) with a charged Deep Bore of player 1
## at tile (12, 2) and the strike manager made on a copy of the fossil def and of Normal's level
## that hold the suite's own numbers, so a tuning row of `data/ai/` cannot move them. Not a suite.

## The suite's numbers: the least value a shot must hit, the age a sighting needs (ticks), the
## tests per run, and the first tick the Deep Bore is charged for (`ready_tick`).
const MIN: int = 2000
const REACTION: int = 30
const TESTS: int = 512
const READY: int = 1000
## The first tick every thing a case shows is old enough, and the Deep Bore's radius (the frozen
## def's, pinned by a case) in milli-tiles.
const KNOWN: int = READY + REACTION
const RADIUS: int = 3000

var _striker: AiStrikes = null
var _scratch: Array[Command] = []
var _strike: int = 0


func before_test() -> void:
	_world = FactionRig.start(_side(), "fossil")
	_loop = AiRig.loop_of(_world)
	_arm_strikes("normal", 1, _side())
	_strike = _give_strike(_side() + "_strike", 12, 2)


## The faction of player 1 (player 2 is always the Derrick League): a suite overrides it.
func _side() -> String:
	return "fossil"


## The strike manager of a copy of the def of `faction` (`least` as `strike_min_value`, `tests` as
## `target_tests_max`) at a copy of Normal's level (`uses_strike` as given, the suite's reaction),
## and a fresh memory.
func _arm_strikes(
	level: String = "normal",
	uses: int = 1,
	faction: String = "fossil",
	least: int = MIN,
	tests: int = TESTS
) -> void:
	var def: OpponentDef = Rig.def_of(faction).duplicate() as OpponentDef
	def.strike_min_value = least
	def.target_tests_max = tests
	var chosen: AiDifficultyDef = Rig.level_of(level).duplicate() as AiDifficultyDef
	chosen.uses_strike = uses
	chosen.reaction_ticks = REACTION
	_intel = AiIntel.create(def, chosen, 1)
	_memory = AiMemory.create(def)
	_striker = AiStrikes.create(def, chosen, 1)
	_rng = DetRandom.create(1, DetRandom.STREAM_AI_BASE + 1)
	_out = []


## Player 1's strike building `id` with its top-left tile at (`col`, `line`), charged from `READY`.
func _give_strike(id: String, col: int, line: int) -> int:
	var building: int = AiRig.give(_world, 1, id, col, line)
	_world.ready_tick[_row_in_world(building)] = READY
	return building


## An INTEL slot at `tick` with a budget of `budget`: the intel refresh (unless `refresh` is false:
## the ARMY slot's lists then stay as they were) and run (the sightings), then the strike manager;
## `_out` holds what the strike manager sent.
func _fire(tick: int, budget: int = 8, refresh: bool = true) -> void:
	_world.tick = tick
	var view: PlayerView = _view()
	_memory.commands_left = budget
	_scratch = []
	if refresh:
		_intel.refresh(view, _memory)
	_intel.run(view, _memory, _rng, _scratch)
	_memory.commands_left = budget
	_out = []
	_striker.run(view, _memory, _rng, _out)


## Every tile seen by player 1 (the fog is not stepped by these suites).
func _see_all() -> void:
	_world.fog.visible.fill(1)


## An enemy building of `id` with its top-left tile at (`col`, `line`); returns its id.
func _enemy_building(id: String, col: int, line: int) -> int:
	return AiRig.give(_world, 2, id, col, line)


## The SUPERWEAPON Commands of `_out`.
func _shots() -> Array[Command]:
	var found: Array[Command] = []
	for command: Command in _out:
		if command.type == Command.Type.SUPERWEAPON:
			found.append(command)
	return found


## One enemy cluster: a vehicle factory (1,800, centre (31500, 31500)) and a barracks (400, centre
## (30000, 34000), 2,915 milli-tiles from it): a radius of 3,000 holds both, 2,200 in all.
func _cluster() -> void:
	_enemy_building("vehicle_factory", 30, 30)
	_enemy_building("barracks", 29, 33)
	_see_all()


## The point of the one SUPERWEAPON of `_out`, as [x, y].
func _target() -> Array[int]:
	var shots: Array[Command] = _shots()
	assert_int(shots.size()).is_equal(1)
	return [shots[0].target_x, shots[0].target_y]
