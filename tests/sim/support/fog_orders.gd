extends RefCounted
## The orders of the FOG lockstep runs (plan P46n2): the seed-42 perf arena's rush and seeded waves,
## seeded random waves of every command that moves or fights, and two ways to drive a hand-built
## World without Movement: `walkers`, a seeded random walk of its rows (steps, jumps anywhere, jumps
## to the edges and corners and off the map, deaths and births), and `scripted`, the rows moved,
## killed and added at the ticks a case lists. A rig calls the Callable once per World, so every
## function makes new Command objects on each call (the loop stamps the ones it is given), and the
## ones that change the World change it the same way each time: they read the World and the seeded
## stream of (salt, tick) only. A side may have no unit left (units die): a wave then sends nothing
## (null or an empty array), never an index past the ids. Not a test suite.

const LockstepRig: GDScript = preload("res://tests/sim/support/lockstep_rig.gd")
const MatchScript: GDScript = preload("res://tests/sim/support/match_script.gd")
## The arena's waves start at this tick, every WAVE_EVERY ticks, at tick % WAVE_EVERY == WAVE_AT.
const WAVE_FIRST: int = 160
const WAVE_EVERY: int = 25
const WAVE_AT: int = 7
## The kinds of a scripted entry: [id, x, y] moves a unit, [id] kills it (hit points 0), and
## [owner, type, x, y] adds a unit (see move(), kill() and add()).
const MOVE: int = 3
const KILL: int = 1
const ADD: int = 4


## The commands of `tick` for one World of the perf arena: at tick 0 the P27c rush (each side
## attack-moves to the other side's spawn centre), MatchScript's eight commands and, from
## WAVE_FIRST, a seeded wave every WAVE_EVERY ticks.
static func arena(world: World, tick: int) -> Array[Command]:
	var out: Array[Command] = []
	if tick == 0:
		out.append(Command.attack_move(1, LockstepRig.ids_of(world, 1), 39500, 32500))
		out.append(Command.attack_move(2, LockstepRig.ids_of(world, 2), 24500, 32500))
	out.append_array(MatchScript.commands_at(tick))
	if tick >= WAVE_FIRST and tick % WAVE_EVERY == WAVE_AT:
		var command: Command = wave(world, tick)
		if command != null:
			out.append(command)
	return out


## One seeded order of a side: 6 to 20 consecutive ids of its units, sent (MOVE or ATTACK_MOVE) to a
## point anywhere on the map, or (ATTACK) at one unit of the other side. Null when the side has no
## unit, or the other none to attack.
static func wave(world: World, tick: int) -> Command:
	var rng: DetRandom = DetRandom.create(42, 500 + tick)
	var player: int = 1 + rng.next_int(2)
	var mine: PackedInt32Array = LockstepRig.ids_of(world, player)
	var theirs: PackedInt32Array = LockstepRig.ids_of(world, 3 - player)
	if mine.is_empty():
		return null
	var count: int = mini(6 + rng.next_int(15), mine.size())
	var first: int = rng.next_int(mine.size() - count + 1)
	var group: PackedInt32Array = mine.slice(first, first + count)
	var x: int = rng.next_int(world.map_w)
	var y: int = rng.next_int(world.map_h)
	match rng.next_int(3):
		0:
			return Command.move(player, group, x, y)
		1:
			return Command.attack_move(player, group, x, y)
	if theirs.is_empty():
		return null
	return Command.attack(player, group, theirs[rng.next_int(theirs.size())])


## The commands of `tick` of a run of random waves: every `every` ticks from tick 1, one wave of a
## seeded side (see random_wave()); `salt` tells two runs apart.
static func random_waves(world: World, tick: int, salt: int, every: int = 6) -> Array[Command]:
	var out: Array[Command] = []
	if tick >= 1 and tick % every == 1 % every:
		var command: Command = random_wave(world, tick, salt)
		if command != null:
			out.append(command)
	return out


## One random command of a seeded side to 1 to 24 consecutive ids of its units: MOVE (3 in 10),
## ATTACK_MOVE (4), STOP (1) or ATTACK (2) at an enemy; one ATTACK in ten names a unit of its own
## side instead (Sim.step drops it). The point is anywhere on the map, off the map included now and
## then. Null when the side has no unit, or (for an ATTACK) the other side none.
static func random_wave(world: World, tick: int, salt: int) -> Command:
	var rng: DetRandom = DetRandom.create(salt, 700 + tick)
	var player: int = 1 + rng.next_int(2)
	var mine: PackedInt32Array = LockstepRig.ids_of(world, player)
	var theirs: PackedInt32Array = LockstepRig.ids_of(world, 3 - player)
	if mine.is_empty():
		return null
	var count: int = mini(1 + rng.next_int(24), mine.size())
	var first: int = rng.next_int(mine.size() - count + 1)
	var group: PackedInt32Array = mine.slice(first, first + count)
	var x: int = rng.next_int(world.map_w + 4000) - 2000
	var y: int = rng.next_int(world.map_h + 4000) - 2000
	var kind: int = rng.next_int(10)
	if kind < 3:
		return Command.move(player, group, x, y)
	if kind < 7:
		return Command.attack_move(player, group, x, y)
	if kind == 7:
		return Command.stop(player, group)
	if theirs.is_empty():
		return null
	var target: int = theirs[rng.next_int(theirs.size())]
	if rng.next_int(10) == 0:
		target = mine[rng.next_int(mine.size())]
	return Command.attack(player, group, target)


## A seeded random walk of the rows of a hand-driven World, applied before the tick (it sends no
## command): of every 100 rows-ticks, 45 stay where they are, 30 step up to a tile either way on
## each axis, 8 jump to a point of the map, 8 jump to the edge or the corner of the map (the
## positions 0, 1 milli in, the last milli, and one past it, on each axis), 4 jump off the map by up
## to 3 tiles, and 5 move onto the tile of the row before them (stacking units); `deaths` rows in
## 1000 die (hit points 0, taken out by the removal of that tick) and `births` in 1000 are followed
## by a new unit of a random player (refused past player_count or max_rows, which both Worlds
## count alike) and type at a random point of the map. A row is stamped only at its player's turn,
## so most steps wait for it. Returns no command.
static func walkers(
	world: World, tick: int, salt: int, deaths: int = 12, births: int = 6
) -> Array[Command]:
	var rng: DetRandom = DetRandom.create(salt, 900 + tick)
	var width: int = world.map_w
	var height: int = world.map_h
	var count: int = world.unit_count()
	for row: int in count:
		var kind: int = rng.next_int(100)
		var step_x: int = rng.next_int(2001) - 1000
		var step_y: int = rng.next_int(2001) - 1000
		var jump_x: int = rng.next_int(width)
		var jump_y: int = rng.next_int(height)
		var edge_x: int = _edge(rng.next_int(8), width)
		var edge_y: int = _edge(rng.next_int(8), height)
		var out_x: int = rng.next_int(width + 6000) - 3000
		var out_y: int = rng.next_int(height + 6000) - 3000
		var doom: int = rng.next_int(1000)
		if kind >= 45 and kind < 75:
			world.pos_x[row] = clampi(world.pos_x[row] + step_x, -3000, width + 3000)
			world.pos_y[row] = clampi(world.pos_y[row] + step_y, -3000, height + 3000)
		elif kind >= 75 and kind < 83:
			world.pos_x[row] = jump_x
			world.pos_y[row] = jump_y
		elif kind >= 83 and kind < 91:
			world.pos_x[row] = edge_x
			world.pos_y[row] = edge_y
		elif kind >= 91 and kind < 95:
			world.pos_x[row] = out_x
			world.pos_y[row] = out_y
		elif kind >= 95 and row > 0:
			world.pos_x[row] = world.pos_x[row - 1]
			world.pos_y[row] = world.pos_y[row - 1]
		if doom < deaths:
			world.hp[row] = 0
		elif doom >= 1000 - births:
			var owner: int = 1 + rng.next_int(maxi(world.player_count, 1))
			var type: int = rng.next_int(maxi(world.type_ids.size(), 1))
			world.add_unit(owner, type, jump_x, jump_y)
	var none: Array[Command] = []
	return none


## The Callable's entry for a script: the entries listed under `tick`, applied in order (a unit is
## named by its id, so a row index never moves under a script when an earlier unit dies). An entry
## for a unit that is gone does nothing. Returns no command.
static func scripted(world: World, tick: int, script: Dictionary) -> Array[Command]:
	for entry: Array in script.get(tick, []):
		if entry.size() == ADD:
			world.add_unit(entry[0], entry[1], entry[2], entry[3])
			continue
		var row: int = world.index_of(entry[0])
		if row < 0:
			continue
		if entry.size() == MOVE:
			world.pos_x[row] = entry[1]
			world.pos_y[row] = entry[2]
		elif entry.size() == KILL:
			world.hp[row] = 0
	var none: Array[Command] = []
	return none


## A scripted entry that moves unit `id` to (x, y) milli.
static func move(id: int, x: int, y: int) -> Array:
	return [id, x, y]


## A scripted entry that kills unit `id`.
static func kill(id: int) -> Array:
	return [id]


## A scripted entry that adds a unit of `owner` and `type` at (x, y) milli.
static func add(owner: int, type: int, x: int, y: int) -> Array:
	return [owner, type, x, y]


## One of the eight positions of an axis of `size` milli that the edges ask for: the origin, one
## milli in, the last milli but one, the last milli, one past it, 999 and 1000 (the first tile's
## border), and one before the origin.
static func _edge(which: int, size: int) -> int:
	var table: Array[int] = [0, 1, size - 2, size - 1, size, 999, 1000, -1]
	return table[which]
