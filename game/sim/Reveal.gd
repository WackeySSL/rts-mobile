class_name Reveal
extends RefCounted
## The map reveal of the space centre's sweep (ADR 0036 section 11, plan row P233): the REMOVE-phase
## step that keeps `reveal` and the stamp in `fog.visible` in line with the building that fired it.
##
## `Strike.apply_superweapon` fires the sweep (kind REVEAL): `reveal_site[p]` is the building's id
## and `reveal[p]` is 1. `run` sits in `Sim.step` right after `World.remove_dead` and before
## `FogUpdate.run`, so after `FogUpdate.begin` (the flips it lists are not cleared on the player's
## fog turn). For each player whose `reveal_site` is not 0, with no pass over the rows:
## - the site is `World.index_of(reveal_site[p])`; gone (-1: destroyed or sold) it clears
##   `reveal_site` and `reveal` to 0, and the sweep is over;
## - else `reveal` is 2 (paused) while the row is offline (`offline_until` above the stamp
##   `world.tick + 1`, as `Strike` reads it) or the player is on low power (`Power.is_low` on the
##   totals ECONOMY left, the ones `Combat.fire` read in this step), and 1 (on) otherwise;
## - `reveal_stamped[p]` follows `reveal[p] == 1`: a difference calls `FogGrid.reveal(p, +1 or -1)`.
## So at every step end `reveal_stamped[p] == (reveal[p] == 1)` and `fog.visible` holds the sweep's
## +1 on every cell exactly while it is on. A pause lets `visible` fall back to the player's own
## discs; `explored` and the last-seen ghosts keep what the sweep showed.
##
## Why no kernel knows about it: the FOG phase only adds and removes discs to the counts (it never
## rebuilds `visible`), and TARGETING reads `visible` as it stands, so the whole-map +1 survives
## every stamp, unstamp and kernel call, and the kernel needs no row in `world_access.h`.
##
## Cost: one binary search per player per step while a sweep stands, the loop over the players
## otherwise, no allocation. Integers only. A rule here is GDScript only.


static func run(world: World) -> void:
	var sites: PackedInt32Array = world.reveal_site
	var states: PackedInt32Array = world.reveal
	var stamped: PackedInt32Array = world.reveal_stamped
	var offline: PackedInt32Array = world.offline_until
	var stamp: int = world.tick + 1
	for player: int in range(1, sites.size()):
		if sites[player] == 0:
			continue
		var row: int = world.index_of(sites[player])
		var state: int = 0
		if row < 0:
			sites[player] = 0
		elif offline[row] > stamp or Power.is_low(world, player):
			state = 2
		else:
			state = 1
		states[player] = state
		var want: int = 1 if state == 1 else 0
		if want != stamped[player]:
			world.fog.reveal(player, want - stamped[player])
			stamped[player] = want
