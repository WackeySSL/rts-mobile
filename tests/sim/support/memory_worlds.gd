extends RefCounted
## Worlds and helpers for the last-seen suites (plan row P77, ADR 0017 section 3). Not a test suite.
##
## `world()` is 24 x 12 tiles of grass with two players, the shipped roster below, the shipped
## rules except the fog period (the suites own it: `FOG_PERIOD`, as the fog suites own theirs, so
## retuning `data/rules.tres` moves none of the turn tables here) and the fog real: nothing is
## stamped, so nobody sees anything until a test says so. A rule
## case does not move units to light a cell: `show` and `hide` write the player's `visible` count of
## a cell (derived state that `LastSeen` reads and no hashed state depends on), and `turn` runs the
## MEMORY phase at a tick that is the player's fog turn, so each case names exactly what the player
## sees on exactly which turn. The cases that follow the real pipeline step the World and stamp the
## fog of their own rows (`TargetingWorlds.stamp_fog`).

const Worlds: GDScript = preload("res://tests/sim/support/building_worlds.gd")
const GridWorld: GDScript = preload("res://tests/sim/support/grid_world.gd")
const IDS: Array[String] = ["rifle_squad", "headquarters", "power_plant", "barracks"]
const COLS: int = 24
const ROWS: int = 12
## The fog period of every World `world()` makes, in ticks: the suites' own value, above the player
## count of 2 so that some ticks are nobody's turn (`idle_tick`). With it player 1 turns on ticks
## 0, 3, 6 and player 2 on 1, 4, 7.
const FOG_PERIOD: int = 3


## The map described above, prepared. `ghost_cap` below 0 keeps the rule's value; another one
## resizes the four record arrays (the World sized them at the rule's value), so that a case can
## fill a block with a few buildings or give a player no room at all.
static func world(ghost_cap: int = -1) -> World:
	var made: World = Worlds.world(GridWorld.grass(COLS, ROWS), IDS, false)
	made.prepare()
	made.fog_period_ticks = FOG_PERIOD
	if ghost_cap >= 0:
		made.ghost_cap = ghost_cap
		var entries: int = (made.player_count + 1) * ghost_cap
		made.ghost_id.resize(entries)
		made.ghost_type.resize(entries)
		made.ghost_owner.resize(entries)
		made.ghost_cell.resize(entries)
	return made


## A building of `id` for `owner` with its top-left tile at (`col`, `line`); returns its id.
static func build(made: World, owner: int, id: String, col: int, line: int) -> int:
	return made.add_building(owner, Worlds.type_of(made, id), col, line)


## The cell that holds the building of `width` x `height` tiles with its top-left tile at (`col`,
## `line`): the tile of its footprint centre.
@warning_ignore("integer_division")
static func cell_of(col: int, line: int, width: int, height: int) -> int:
	return (line + height / 2) * COLS + col + width / 2


## The cell of the building `id`, as the World gives it for its position.
static func cell_at(made: World, id: int) -> int:
	var row: int = made.index_of(id)
	return made.cell_of(made.pos_x[row], made.pos_y[row])


## Makes `cell` visible (`seen`) or dark to `player` by writing its visible count.
static func show(made: World, player: int, cell: int, seen: bool = true) -> void:
	made.fog.visible[(player - 1) * made.fog.cells + cell] = 1 if seen else 0


## Runs the MEMORY phase at the first tick from `from_tick` on that is `player`'s fog turn, and
## leaves the World's tick there. Every other player's turn at that tick runs too, as in the sim.
static func turn(made: World, player: int, from_tick: int = 0) -> void:
	var period: int = maxi(made.fog_period_ticks, 1)
	var tick: int = from_tick
	while (tick - player + 1) % period != 0:
		tick += 1
	made.tick = tick
	LastSeen.run(made)


## The first tick that is no player's fog turn in `made`: the fog rule's own test, over every
## player, so that the answer follows the World's period and not a number written in a case.
static func idle_tick(made: World) -> int:
	var period: int = maxi(made.fog_period_ticks, 1)
	for tick: int in period:
		var turns: bool = false
		for player: int in range(1, made.player_count + 1):
			turns = turns or (tick - player + 1) % period == 0
		if not turns:
			return tick
	return -1  # A period that gives every tick to some player: no case here asks for one.


## Kills the building `id` and removes it, as the REMOVE phase does.
static func destroy(made: World, id: int) -> void:
	made.hp[made.index_of(id)] = 0
	made.remove_dead()


## The player's records as [id, type, owner, cell] lists, in record order.
static func records(made: World, player: int) -> Array[Array]:
	var found: Array[Array] = []
	var first: int = player * made.ghost_cap
	for record: int in made.ghost_count[player]:
		var entry: int = first + record
		found.append(
			[
				made.ghost_id[entry],
				made.ghost_type[entry],
				made.ghost_owner[entry],
				made.ghost_cell[entry]
			]
		)
	return found


## The ids of the player's records, in record order.
static func ids(made: World, player: int) -> Array[int]:
	var found: Array[int] = []
	for record: Array in records(made, player):
		found.append(record[0])
	return found
