extends RefCounted
## The orders of the TARGETING lockstep runs (plan P41n2): the seed-42 perf arena's rush and seeded
## waves, and seeded random waves of every command that moves or fights (MOVE, ATTACK_MOVE, STOP and
## ATTACK). Every function is static and makes new Command objects on each call, because the loop
## stamps the ones it is given; the rig calls the Callable once per World. A side may have no unit
## left (units die since P42a) or none to attack: the function then sends nothing (null or an empty
## array), never an index past the ids. Not a test suite.

const LockstepRig: GDScript = preload("res://tests/sim/support/lockstep_rig.gd")
const MatchScript: GDScript = preload("res://tests/sim/support/match_script.gd")
## The arena's waves start at this tick, every WAVE_EVERY ticks, at tick % WAVE_EVERY == WAVE_AT.
const WAVE_FIRST: int = 160
const WAVE_EVERY: int = 25
const WAVE_AT: int = 7


## The commands of `tick` for one World of the perf arena (the seed-42 run of the INTEGRATE and
## SEPARATION lockstep): at tick 0 the P27c rush (each side attack-moves to the other side's spawn
## centre; the shipped scenario holds firing lines since P48, so these two orders are the rig's
## own), MatchScript's eight commands, and from WAVE_FIRST a seeded wave every WAVE_EVERY ticks.
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


## One seeded order of a side: 6 to 20 consecutive ids of its units, sent (MOVE or ATTACK_MOVE) to
## a point anywhere on the map, rock and wall included, or (ATTACK) at one unit of the other side.
## Null when the side has no unit, or the other none to attack. A side with fewer units than the
## group sends all it has.
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


## The commands of `tick` of a run of long attacks: every `every` ticks, a group of 10 to 24 of each
## side is sent at one unit of the other (ATTACK), wherever on the map it stands. On a big map the
## attackers walk with a clear line to a target far away, and re-test that line on their turns.
static func far_attacks(world: World, tick: int, every: int = 40) -> Array[Command]:
	var out: Array[Command] = []
	if tick % every != 0:
		return out
	var rng: DetRandom = DetRandom.create(9, 900 + tick)
	for player: int in [1, 2]:
		var mine: PackedInt32Array = LockstepRig.ids_of(world, player)
		var theirs: PackedInt32Array = LockstepRig.ids_of(world, 3 - player)
		if mine.is_empty() or theirs.is_empty():
			continue
		var count: int = mini(10 + rng.next_int(15), mine.size())
		var first: int = rng.next_int(mine.size() - count + 1)
		var group: PackedInt32Array = mine.slice(first, first + count)
		out.append(Command.attack(player, group, theirs[rng.next_int(theirs.size())]))
	return out
