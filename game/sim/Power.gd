class_name Power
extends RefCounted
## Power (ADR 0017 section 5, ADR 0018 section 4). `run` is the first half of ECONOMY: it brings the
## derived row lists up to date (Buildings.rebuild_lists) and sums `type_power` over the building
## rows into `power_made` (the positive entries) and `power_used` (the negative ones, as positive
## numbers) per player, every ECONOMY: one pass over the building rows, so there is no stamp to
## keep (and no field in the World) and nothing that a rebuild of the lists by someone else, or a
## moved type table, can leave stale. Both are derived (ADR 0016): in no hash section, rebuilt from
## the rows, and compared with a scan at every checkpoint by `tests/sim/test_power.gd`. A building
## placed or lost in tick t counts in t's ECONOMY (the totals are built after REMOVE), so PRODUCTION
## of tick t and FIRE of tick t+1 see it.
##
## Low power is `power_used > power_made` (`is_low`; equal is not low). Its two effects are
## elsewhere: the queues of a low player advance at `low_power_percent` (`scaled`, called by
## `Production.run`), and the player's defences (building rows with a weapon) keep their targets but
## do not shoot (`Combat.fire`, GDScript only, with the rule inlined over aliased arrays).

## A percent divides by this: structure, not balance.
const PERCENT: int = 100


## ECONOMY, first half. The lists are rebuilt first (a no-op when `Production.producer_row` has
## already done it in COMMANDS or PRODUCTION since the rows last moved), and its answer is not
## asked: the totals are summed from the rows whatever it says.
static func run(world: World) -> void:
	Buildings.rebuild_lists(world)
	var made: PackedInt32Array = world.power_made
	var used: PackedInt32Array = world.power_used
	var players: int = mini(made.size(), used.size())
	# Not sized yet (prepare() has not run): nothing to write.
	if players == 0:
		return
	made.fill(0)
	used.fill(0)
	var owners: PackedInt32Array = world.owner
	var types: PackedInt32Array = world.type_index
	var table: PackedInt32Array = world.type_power
	var known: int = table.size()
	for row: int in world.building_rows:
		var player: int = owners[row]
		var type: int = types[row]
		# Entry 0 is the neutral player's and stays 0; a player past the arrays (a hand-built World
		# whose player_count was raised after prepare()) and a type past the table have no entry.
		if player < 1 or player >= players or type >= known:
			continue
		var power: int = table[type]
		if power > 0:
			made[player] += power
		else:
			used[player] -= power


## Whether `player` is on low power: the totals `run` built have it using more than it makes. False
## for the neutral player and for a player past the arrays. The totals are as ECONOMY left them, so
## a row added since then does not count yet.
static func is_low(world: World, player: int) -> bool:
	var made: PackedInt32Array = world.power_made
	var used: PackedInt32Array = world.power_used
	return player >= 1 and player < mini(made.size(), used.size()) and used[player] > made[player]


## `amount` as `player` earns it this tick: all of it, or `low_power_percent` of it on low power
## (integer division, toward zero). A queue's progress step goes through here.
@warning_ignore("integer_division")
static func scaled(world: World, player: int, amount: int) -> int:
	if is_low(world, player):
		return amount * world.low_power_percent / PERCENT
	return amount
