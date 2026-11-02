extends RefCounted
## The world and the readers of the CANCEL_BUILD suites (plan row P128b, ADR 0026 section 6). Not a
## test suite. `site_rig.gd`'s world, then two sites a step old: player 1's Power Plant (id 6) at
## `SiteRig.SPOT` and player 2's Wind Park (id 7) at `SiteRig.SPOT_2`, and a rifle squad of player 1
## (id 8) for the cases that name a unit.

const SiteRig: GDScript = preload("res://tests/sim/support/site_rig.gd")
## The ids of the two sites: the five scenario buildings come first.
const OWN_SITE: int = 6
const ENEMY_SITE: int = 7
## The cost of a tile, for foot, wheels and tracks.
const OPEN: Array[int] = [10, 10, 10]
const BLOCKED: Array[int] = [0, 0, 0]
## The cell of the Power Plant site's first tile (SiteRig.SPOT is its origin).
const SPOT_CELL: int = 5 * SiteRig.COLS + 6


## The world described above.
static func world() -> World:
	var made: World = SiteRig.world()
	step(
		made,
		[
			SiteRig.place(made, "power_plant", SiteRig.SPOT),
			SiteRig.place(made, "renew_power", SiteRig.SPOT_2, 2),
		]
	)
	made.add_unit(1, SiteRig.type_of(made, "rifle_squad"), 3500, 11500)
	return made


## One tick with `commands` (a plain Array) stamped with the World's tick.
static func step(made: World, commands: Array) -> void:
	SiteRig.step(made, commands)


## The DIED records of the last tick, each as its eight ints.
static func died(made: World) -> Array[Array]:
	var found: Array[Array] = []
	var events: PackedInt32Array = made.events
	for at: int in range(0, events.size(), World.EVENT_STRIDE):
		if events[at] == World.Event.DIED:
			found.append(Array(events.slice(at, at + World.EVENT_STRIDE)))
	return found


## The names of the hash sections where `a` and `b` differ.
static func differing(a: World, b: World) -> Array[String]:
	var names: PackedStringArray = World.hash_section_names()
	var left: PackedInt64Array = a.hash_parts()
	var right: PackedInt64Array = b.hash_parts()
	var found: Array[String] = []
	for index: int in names.size():
		if left[index] != right[index]:
			found.append(names[index])
	return found


## What a scan of the rows gives for `player`: [made, used] over its complete buildings, from the
## type table alone.
static func scan(made: World, player: int) -> Array[int]:
	var found: Array[int] = [0, 0]
	for row: int in made.unit_count():
		var type: int = made.type_index[row]
		if made.owner[row] == player and made.type_foot_w[type] > 0 and made.build_left[row] == 0:
			found[0 if made.type_power[type] > 0 else 1] += absi(made.type_power[type])
	return found
