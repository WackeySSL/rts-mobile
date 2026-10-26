class_name Outcome
extends RefCounted
## Rally points, surrender and the end of a match (ADR 0017 sections 4 and 5, ADR 0018 sections 6
## and 7). `run` is the defeat and victory check, the last step of PRODUCTION; RALLY and SURRENDER
## are Commands that `Sim._apply` hands here after its `_playing` gate (the rule "a defeated player
## sends none" is the gate's, so the two `apply_*` functions do not ask for it).
##
## Defeat. A player is defeated when `defeated_tick` is set, to the tick the defeating step
## produces, `world.tick + 1` (0 keeps meaning "playing", so a defeat on the first step reads 1).
## SURRENDER sets it in COMMANDS. `run` sets it for a player still playing whose `had_producer` is 1
## and who owns no building that produces a tab; a ready structure in a queue does not save the
## player, and a side that never owned a producer (the perf arena, the controls scenario, a
## hand-built World with units only) is never defeated by this rule.
##
## The end. Once somebody has been defeated and at most one player is still playing, the match ends:
## `match_end_tick` is `world.tick + 1` and `winner` is the player left, or 0 when the last players
## fell on the same tick (a draw). Nobody having been defeated, a World with one player is no match
## that has ended, so a lone side keeps playing. After the end `run` changes nothing, so the values
## the runner published stay as they were; `Sim._apply` drops every Command from then on.
##
## What a defeat does not do (plan row P76's decisions): the rows of a defeated player stay on the
## map, only its queues stop (`Production.run` skips them). `stat_lost_units` and
## `stat_lost_buildings` are not counted yet: ADR 0018 section 7 counts the owner of every dying
## row in `World.remove_dead`, which writes the perf arena's `players` section from its first
## death on and moves its golden hashes (tick 150 already), so the count waits for a decision.


## The defeat and victory check, after the queues. No end yet, one pass over the players ascending
## (the players past the arrays of a hand-built World are not playing, as in `Sim._playing`). The
## cost on a tick where nobody is a candidate (every player defeated or without a producer) is the
## loop over the players, nothing else.
static func run(world: World) -> void:
	if world.match_end_tick > 0:
		return
	var defeated: PackedInt32Array = world.defeated_tick
	var had: PackedInt32Array = world.had_producer
	var stamp: int = world.tick + 1
	var playing: int = 0
	var left: int = 0
	var fallen: bool = false
	for player: int in range(1, mini(defeated.size(), had.size())):
		if defeated[player] == 0 and had[player] == 1 and not _owns_producer(world, player):
			defeated[player] = stamp
		if defeated[player] == 0:
			playing += 1
			left = player
		else:
			fallen = true
	if fallen and playing <= 1:
		world.match_end_tick = stamp
		world.winner = left if playing == 1 else 0


## RALLY: true when the point became the rally point of the tab that the building produces. The
## command names (`target_id`) a building of the player's own whose type produces INFANTRY or
## VEHICLES (ADR 0018 section 6; the Headquarters produces STRUCTURES, whose items are placed and
## never leave for a point, so it is refused), and carries no payload. The point is clamped to the
## map, 0 up to the last milli-tile of each axis, because a stored value below 0 means "no rally
## point" to ProductionSpawn. Anything else is dropped and counted by the caller.
static func apply_rally(world: World, command: Command) -> bool:
	if not command.payload.is_empty():
		return false
	var row: int = world.index_of(command.target_id)
	if row < 0 or world.owner[row] != command.player_id:
		return false
	var type: int = world.type_index[row]
	var produces: PackedInt32Array = world.type_produces
	if type >= produces.size():
		return false
	var tab: int = produces[type]
	var queue: int = command.player_id * World.TABS + tab
	if tab < World.Tab.INFANTRY or tab >= World.TABS or queue >= world.rally_x.size():
		return false
	world.rally_x[queue] = clampi(command.target_x, 0, maxi(world.map_w - 1, 0))
	world.rally_y[queue] = clampi(command.target_y, 0, maxi(world.map_h - 1, 0))
	return true


## SURRENDER: true when the player was defeated at once, which is `world.tick + 1`, the stamp `run`
## gives a defeat of the same step. The match ends in the same step's `run` when no other player
## is left but one. The payload is empty.
static func apply_surrender(world: World, command: Command) -> bool:
	var player: int = command.player_id
	if not command.payload.is_empty() or player < 1 or player >= world.defeated_tick.size():
		return false
	world.defeated_tick[player] = world.tick + 1
	return true


## Whether `player` owns a building whose type produces a tab (a Headquarters, a barracks or a
## vehicle factory). The first one found ends the scan; the derived building list is brought up to
## date first (a no-op when `rows_version` has not moved since ECONOMY rebuilt it).
static func _owns_producer(world: World, player: int) -> bool:
	Buildings.rebuild_lists(world)
	var owners: PackedInt32Array = world.owner
	var types: PackedInt32Array = world.type_index
	var produces: PackedInt32Array = world.type_produces
	for row: int in world.building_rows:
		if owners[row] == player and produces[types[row]] >= 0:
			return true
	return false
