class_name Radar
extends RefCounted
## The radar scope's dark rule (ADR 0047 section 3), derived from the rows and never stored or
## hashed. Player p's radar is dark at a stamp when p owns a complete radar building (`type_radar`,
## `build_left` 0) with `offline_until` above the stamp and no complete radar building with
## `offline_until` at or below it. No radar building means never dark (the minimap needs none), low
## power and a site change nothing, and a radar that is sold or lost leaves the rule. Each static
## is one pass over `building_rows` and allocates nothing. The stamp is the snapshot's tick, which
## is the one `BuildingLayer`'s offline glyph uses.


## True when `player`'s radar scope is dark at `stamp`.
static func dark(world: World, player: int, stamp: int) -> bool:
	return dark_until(world, player, stamp) > stamp


## The lowest `offline_until` among the player's complete radar buildings, or 0 when the scope is
## not dark at `stamp` (no complete radar, one of them online, or none offline).
static func dark_until(world: World, player: int, stamp: int) -> int:
	Buildings.rebuild_lists(world)
	var lowest: int = 0
	var types: PackedInt32Array = world.type_index
	var flags: PackedInt32Array = world.type_radar
	for row: int in world.building_rows:
		if world.owner[row] != player or world.build_left[row] != 0:
			continue
		var type: int = types[row]
		if type >= flags.size() or flags[type] != 1:
			continue
		var until: int = world.offline_until[row]
		if until <= stamp:
			return 0
		if lowest == 0 or until < lowest:
			lowest = until
	return lowest
