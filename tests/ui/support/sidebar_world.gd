extends RefCounted
## The World behind the build sidebar's item suites (plan P85b): the shipped units and buildings
## (the twelve of Phase 2 and the first Phase 3 plan), a 24 x 16 open map and two players. A suite
## gives player 1 buildings, credits and queued items, captures the snapshot the sidebar reads and
## gets the real tables (costs, tabs, requirements, producers, build ticks) rather than copies of
## them, with one exception: the Derrick League's radar (plan P107, ADR 0023 section 7), which
## gates artillery and which the loader pulls in after it, is taken off the tabs and artillery's
## requirement is dropped, so that these suites keep pinning the sidebar's own rules on the same
## twelve tiles. Not a suite.

const Worlds: GDScript = preload("res://tests/sim/support/building_worlds.gd")
const IDS: Array[String] = [
	"rifle_squad",
	"rocket_squad",
	"light_tank",
	"heavy_tank",
	"harvester",
	"headquarters",
	"power_plant",
	"barracks",
	"refinery",
	"vehicle_factory",
	"defence_turret",
	"artillery",
]
const COLS: int = 24
const ROWS: int = 16
const BLOCK: int = 4  ## Tiles between the origins of two buildings: room for a 3x3.
const PER_LINE: int = 5


static func world() -> World:
	var made: World = Worlds.open(COLS, ROWS, IDS)
	made.type_tab[type_of(made, "fossil_radar")] = -1
	made.type_requires[type_of(made, "artillery")] = World.TYPE_PAD_NONE
	return made


## The type index of `id`.
static func type_of(made: World, id: String) -> int:
	return Worlds.type_of(made, id)


## Gives `player` one building of each of `ids` (plain Arrays: a call through the preloaded script
## carries an untyped literal), in rows of the map that clear each other.
static func own(made: World, ids: Array, player: int = 1) -> PackedInt32Array:
	var found: PackedInt32Array = PackedInt32Array()
	for at: int in ids.size():
		var col: int = 1 + at % PER_LINE * BLOCK
		var row: int = 1 + at / PER_LINE * BLOCK + (player - 1) * 2 * BLOCK
		found.append(made.add_building(player, type_of(made, ids[at]), col, row))
	return found


## Player 1's queue of `tab` holds `items` (type ids, head first), the head `progress` hundredths of
## a tick along.
static func enqueue(made: World, tab: int, items: Array, progress: int = 0) -> void:
	var queue: int = World.TABS + tab
	for slot: int in items.size():
		made.queue_type[queue * made.queue_slots + slot] = type_of(made, items[slot])
	made.queue_count[queue] = items.size()
	made.queue_progress[queue] = progress


## The snapshot of the world as it stands, a new match when `serial` is another number.
static func snapshot(made: World, serial: int = 0) -> MatchSnapshot:
	var snap: MatchSnapshot = MatchSnapshot.new()
	snap.match_serial = serial
	snap.capture(made, null)
	return snap
