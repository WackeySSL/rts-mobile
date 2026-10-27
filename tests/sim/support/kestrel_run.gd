extends RefCounted
## The scripted Kestrel Flats match of the determinism cases (plan row P79): both rifle squads
## attack-move at tick 0 to the middle of the map and meet there, and each side queues its
## faction's power plant, places it, queues its refinery and places that, so that the run reaches
## fighting, the production queues, the placement of two buildings, a free tanker and its harvest
## loop. One run is one World under one implementation, stepped by one MatchLoop. Not a test suite.

const Rig: GDScript = preload("res://tests/sim/support/kestrel_rig.gd")
const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const TICKS: int = 1200
## The attack-move target of both sides in milli-tiles: open grass north-west of the rock outcrop in
## the middle.
const MIDDLE: Vector2i = Vector2i(31500, 28500)
## The ticks of the script: the power plant queued, placed (150 build ticks later), the refinery
## queued (375 build ticks) and placed.
const QUEUE_POWER: int = 10
const PLACE_POWER: int = 165
const QUEUE_REFINERY: int = 170
const PLACE_REFINERY: int = 560
## Each side's footprints, as the origin tile of its power plant (2 x 2) and refinery (3 x 3):
## player 1 east and north-east of its Headquarters, player 2 the half turn of that.
const POWER_TILES: Array[Vector2i] = [Vector2i(11, 7), Vector2i(51, 55)]
const REFINERY_TILES: Array[Vector2i] = [Vector2i(10, 3), Vector2i(51, 58)]

## What SimImpls.use and the phase checks found wrong; a test asserts it is empty.
var problems: Array[String] = []
var world: World
var loop: MatchLoop
var _faction: Array[StringName] = [&"", &"", &""]


## Builds the World of the scenario at `path` under `impl`, then steps `ticks` ticks of the script.
## Returns self.
func play(path: String, impl: int, ticks: int = TICKS) -> RefCounted:
	var scenario: ScenarioDef = load(path) as ScenarioDef
	world = Rig.world(path)
	problems.append_array(SimImpls.use(world, impl))
	for phase: int in SimImpls.EXPECTED_PHASES:
		if SimImpls.is_native(world, phase) != (impl == SimImpls.Impl.NATIVE):
			problems.append("phase %d does not run in implementation %d" % [phase, impl])
	for player: int in [1, 2]:
		_faction[player] = scenario.factions[player].id
	loop = MatchLoop.create(scenario, path, Rig.SEED, world)
	for _tick: int in ticks:
		loop.step(world, _commands_at(world.tick))
	return self


## The commands of `tick`: none on most ticks. Types come by name from the faction table, so the
## same script serves both scenarios; ids are read from the World at tick 0, before anything moves.
func _commands_at(tick: int) -> Array[Command]:
	var out: Array[Command] = []
	for player: int in [1, 2]:
		var side: int = player - 1
		var own: StringName = _faction[player]
		if tick == 0:
			out.append(
				Command.attack_move(player, Rig.mobile_ids(world, player), MIDDLE.x, MIDDLE.y)
			)
		elif tick == QUEUE_POWER:
			out.append(Command.queue(player, world.type_ids.find(Rig.POWER[own])))
		elif tick == PLACE_POWER:
			out.append(_place(player, POWER_TILES[side]))
		elif tick == QUEUE_REFINERY:
			out.append(Command.queue(player, world.type_ids.find(Rig.REFINERY[own])))
		elif tick == PLACE_REFINERY:
			out.append(_place(player, REFINERY_TILES[side]))
	return out


## A PLACE at the centre of `tile`, so that the footprint's origin is that tile.
func _place(player: int, tile: Vector2i) -> Command:
	return Command.place(
		player,
		tile.x * World.MILLI_PER_TILE + World.TILE_CENTRE,
		tile.y * World.MILLI_PER_TILE + World.TILE_CENTRE
	)
