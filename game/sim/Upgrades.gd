class_name Upgrades
extends RefCounted
## Research and the modifier tables (ADR 0036 section 10, plan row P246). A research item is a
## queue-only type that WorldLoad makes from an `UpgradeDef`; when it completes in PRODUCTION,
## `finish` sets the upgrade's bit in `world.upgrades[player]` and rebuilds the tables below. The
## tables are derived (never hashed): `rebuild` makes them from `upgrades` and the upgrade lists,
## so `prepare()` sizes and fills them. No World is restored from a snapshot today; a loader that
## ever does must write `upgrades` before `prepare()` or call `rebuild` (`prepare_world` runs once).
##
## - `mod_dealt`: per player and weapon (`player * weapon count + weapon`), a percent, 100 = none.
##   Keyed on the weapon because a shell stores only its owner and weapon (`proj_owner`,
##   `proj_weapon`); two types that share one weapon share its upgrade.
## - `mod_taken`: per player and type (`player * type count + type`), a percent, 100 = none.
## - `mod_ammo`: per player and type, the extra shots on top of `type_ammo` (0 = none).
##
## Several upgrades of one stat on one type multiply (percents) or add (ammo); the data rule keeps
## a stat to one upgrade per type (damage dealt: per weapon), each at most 400 %. An upgrade counts
## once per weapon, however many of its types share it. Integers only; `rebuild` allocates nothing
## once the tables are sized at `prepare()`; events only.

## A damage modifier of 100 percent changes nothing.
const BASE_PERCENT: int = 100

## Sizes the tables to the players, weapons and types and fills them from the researched bits.
## Players ascending, upgrades in `upgrade_ids` order, so the result depends on the state alone.
@warning_ignore("integer_division")
static func rebuild(world: World) -> void:
	var players: int = world.upgrades.size()
	var weapons: int = world.weapon_damage.size()
	var types: int = world.type_ids.size()
	world.mod_dealt.resize(players * weapons)
	world.mod_dealt.fill(BASE_PERCENT)
	world.mod_taken.resize(players * types)
	world.mod_taken.fill(BASE_PERCENT)
	world.mod_ammo.resize(players * types)
	world.mod_ammo.fill(0)
	for player: int in range(1, players):
		var owned: int = world.upgrades[player]
		for up: int in world.upgrade_ids.size():
			if (owned >> up) & 1 == 0:
				continue
			var stat: int = world.upgrade_stat[up]
			var value: int = world.upgrade_value[up]
			var first: int = world.upgrade_type_first[up]
			for at: int in range(first, first + world.upgrade_type_count[up]):
				var type: int = world.upgrade_types[at]
				if stat == UpgradeDef.Stat.DAMAGE_DEALT:
					var weapon: int = world.type_weapon[type]
					# Once per weapon and upgrade: an earlier type of this upgrade on it counts.
					if weapon >= 0 and weapon < weapons and not _seen(world, first, at, weapon):
						var slot: int = player * weapons + weapon
						world.mod_dealt[slot] = world.mod_dealt[slot] * value / BASE_PERCENT
				elif stat == UpgradeDef.Stat.DAMAGE_TAKEN:
					var slot: int = player * types + type
					world.mod_taken[slot] = world.mod_taken[slot] * value / BASE_PERCENT
				elif stat == UpgradeDef.Stat.AMMO:
					world.mod_ammo[player * types + type] += value


## Whether an entry of `upgrade_types` from `first` up to (not including) `at` has weapon `weapon`.
static func _seen(world: World, first: int, at: int, weapon: int) -> bool:
	for before: int in range(first, at):
		if world.type_weapon[world.upgrade_types[before]] == weapon:
			return true
	return false


## The upgrade a type gives (-1: not a research item).
static func of_type(world: World, type: int) -> int:
	return world.type_upgrade[type] if type >= 0 and type < world.type_upgrade.size() else -1


## Whether `player` has researched the upgrade the research item `type` gives.
static func has(world: World, player: int, type: int) -> bool:
	var up: int = of_type(world, type)
	return up >= 0 and (world.upgrades[player] >> up) & 1 == 1


## Whether a QUEUE of research item `type` is dropped: its bit is set, or the item is queued.
static func queue_refused(world: World, player: int, type: int) -> bool:
	if of_type(world, type) < 0:
		return false
	if has(world, player, type):
		return true
	var queue: int = player * World.TABS + World.Tab.RESEARCH
	var base: int = queue * world.queue_slots
	for slot: int in world.queue_count[queue]:
		if world.queue_type[base + slot] == type:
			return true
	return false


## A research item of `player` completed: sets the bit and rebuilds the tables. Spawns nothing.
static func finish(world: World, player: int, type: int) -> void:
	var up: int = of_type(world, type)
	if up >= 0:
		world.upgrades[player] |= 1 << up
		rebuild(world)


## The entry `index` of a per-player table of `stride` entries per player, or `none` when the
## player or the index is outside it. The loops of FIRE and PROJECTILES pass aliased arrays.
static func pick(table: PackedInt32Array, stride: int, player: int, index: int, none: int) -> int:
	if player < 0 or index < 0 or index >= stride or (player + 1) * stride > table.size():
		return none
	return table[player * stride + index]


## The damage percent for shots of `weapon` fired by `player` (100 when no table covers it).
static func dealt(world: World, player: int, weapon: int) -> int:
	return pick(world.mod_dealt, world.weapon_damage.size(), player, weapon, BASE_PERCENT)


## The damage percent a row of `type` owned by `player` takes (100 when no table covers it).
static func taken(world: World, player: int, type: int) -> int:
	return pick(world.mod_taken, world.type_ids.size(), player, type, BASE_PERCENT)


## The extra ammo cap of `type` for `player` (0 when no table covers it).
static func extra_ammo(world: World, player: int, type: int) -> int:
	return pick(world.mod_ammo, world.type_ids.size(), player, type, 0)
