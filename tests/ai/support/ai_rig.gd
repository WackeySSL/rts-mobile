extends RefCounted
## Matches for the AI suites (plan row P83). Not a test suite.
##
## `start()` is a skirmish-like start on 40 x 40 tiles of the shipped terrain and rules with the
## fog real: each of two players has a Headquarters (3x3), two rifle squads beside it and 2,000
## credits (the rules' `start_credits`), and ore near its base. Player 1's Headquarters has its
## top-left tile at (6, 6), with ore at tiles 14-17 x 6-9 and 6-9 x 14-17; player 2's base is the
## same base moved 20 tiles east and 20 south (Headquarters at (26, 26), ore at 34-37 x 26-29 and
## 26-29 x 34-37), so two dummies on it run alike. The bases are 28 tiles apart, so no row sees or
## hits a row of the other base. The roster is the Headquarters, the five buildings of the dummy's
## build order, the turret, the harvester and the two units.
##
## `tick()` is the headless loop of ADR 0020 section 3 as the driver of plan row P82 will do it:
## each controller on its turn gets a fresh `PlayerView` and appends its Commands, `MatchLoop`
## stamps and records them and runs `Sim.step`.

const RULES_PATH: String = "res://data/rules.tres"
const TERRAIN_PATH: String = "res://data/terrain/standard.tres"
const UNIT_DIR: String = "res://data/units/"
const DUMMY_PATH: String = "res://data/ai/dummy.tres"
const SIZE: int = 40
const ROSTER: Array[String] = [
	"headquarters",
	"power_plant",
	"refinery",
	"barracks",
	"vehicle_factory",
	"defence_turret",
	"harvester",
	"rifle_squad",
	"light_tank",
]
const ORE: Array[Rect2i] = [
	Rect2i(14, 6, 4, 4),
	Rect2i(6, 14, 4, 4),
	Rect2i(34, 26, 4, 4),
	Rect2i(26, 34, 4, 4),
]
const HQ_1: Vector2i = Vector2i(6, 6)
const HQ_2: Vector2i = Vector2i(26, 26)


## The rows of the shipped start: grass with the ore patches, or, with `blocked`, rock everywhere
## but the tiles of the two Headquarters (a base nothing can be built beside).
static func rows(blocked: bool = false) -> Array[String]:
	var lines: Array[String] = []
	for line: int in SIZE:
		var text: String = ""
		for column: int in SIZE:
			text += "."
			if blocked and not _in_base(column, line):
				text = text.left(len(text) - 1) + "#"
		lines.append(text)
	for patch: Rect2i in ORE:
		for line: int in range(patch.position.y, patch.end.y):
			for column: int in range(patch.position.x, patch.end.x):
				lines[line] = lines[line].left(column) + "o" + lines[line].substr(column + 1)
	return lines


## A prepared World of the start: two players, the roster above and the map `map_rows` (the
## shipped one when empty), on the shipped rules or on `rules` when given.
static func start(map_rows: Array[String] = [], rules: RulesDef = null) -> World:
	var map: MapDef = MapDef.new()
	map.rows = PackedStringArray(map_rows if not map_rows.is_empty() else rows())
	map.terrain = load(TERRAIN_PATH) as TerrainSetDef
	var scenario: ScenarioDef = ScenarioDef.new()
	scenario.map = map
	scenario.player_count = 2
	scenario.rules = rules if rules != null else load(RULES_PATH) as RulesDef
	scenario.spawns.append(_spawn(1, "headquarters", HQ_1, 1))
	scenario.spawns.append(_spawn(1, "rifle_squad", Vector2i(4, 10), 2))
	scenario.spawns.append(_spawn(2, "headquarters", HQ_2, 1))
	scenario.spawns.append(_spawn(2, "rifle_squad", Vector2i(24, 30), 2))
	for id: String in ROSTER:
		scenario.roster.append(load(UNIT_DIR + id + ".tres") as UnitDef)
	return World.from_scenario(scenario)


## The shipped dummy def.
static func dummy_def() -> AiDef:
	return load(DUMMY_PATH) as AiDef


## A dummy of `player` on the shipped def, with its own stream of `seed`.
static func dummy(player: int, seed: int = 1) -> DummyAi:
	return ai_of(dummy_def(), player, seed)


## A dummy of `player` on `def`, with its own stream of `seed`.
static func ai_of(def: AiDef, player: int, seed: int = 1) -> DummyAi:
	return DummyAi.create(def, player, DetRandom.create(seed, DetRandom.STREAM_AI_BASE + player))


## A copy of the shipped def whose build order is the type ids `ids` (a plain Array of strings).
static func def_with(ids: Array) -> AiDef:
	var def: AiDef = dummy_def().duplicate() as AiDef
	var order: Array[StringName] = []
	for id: String in ids:
		order.append(StringName(id))
	def.build_order = order
	return def


## Gives `player` a building of the type `id` with its top-left tile at (`col`, `line`), as a
## scenario would (no placement rule is asked), and returns its id.
static func give(world: World, player: int, id: String, col: int, line: int) -> int:
	return world.add_building(player, type_of(world, id), col, line)


## A loop for `world` (no scenario orders, nothing recorded about a scenario).
static func loop_of(world: World, seed: int = 1) -> MatchLoop:
	return MatchLoop.create(null, "", seed, world)


## One tick of the headless loop: every controller of `controllers` (a plain Array: a caller reaches
## this through a preloaded script, so its literal is not typed) whose turn it is thinks on a fresh
## view, `loop` stamps and records what they sent and the sim steps. Returns the Commands sent.
static func tick(world: World, loop: MatchLoop, controllers: Array) -> Array[Command]:
	var sent: Array[Command] = []
	for controller: AiController in controllers:
		if (world.tick + controller.think_offset) % controller.think_period == 0:
			controller.think(PlayerView.of(world, controller.player_id), sent)
	loop.step(world, sent)
	return sent


## `ticks` ticks of `tick()`; returns every Command sent, stamped, in the order it was sent.
static func run(world: World, loop: MatchLoop, controllers: Array, ticks: int) -> Array[Command]:
	var all: Array[Command] = []
	for _step: int in ticks:
		all.append_array(tick(world, loop, controllers))
	return all


## `sent` without the ATTACK_MOVE orders of the dummy's defence (plan row P83b), for the suites that
## judge only its economy, the QUEUE and PLACE commands.
static func economy(sent: Array[Command]) -> Array[Command]:
	var kept: Array[Command] = []
	for command: Command in sent:
		if command.type != Command.Type.ATTACK_MOVE:
			kept.append(command)
	return kept


## Ticks with no controller until every player's fog has been stamped again: each player updates
## once in `fog_period_ticks` ticks, so a row or a building given since then is seen or seeing.
static func settle(world: World, loop: MatchLoop) -> void:
	run(world, loop, [], world.fog_period_ticks)


## The ids of the rows of `player` with the type `id`, ascending.
static func ids_of(world: World, player: int, id: String) -> PackedInt32Array:
	var type: int = type_of(world, id)
	var found: PackedInt32Array = PackedInt32Array()
	for row: int in world.unit_count():
		if world.owner[row] == player and world.type_index[row] == type:
			found.append(world.unit_id[row])
	return found


## One tick with `commands` (a plain Array) stamped and applied, and no controller thinking.
static func step(world: World, loop: MatchLoop, commands: Array = []) -> void:
	var sent: Array[Command] = []
	sent.assign(commands)
	loop.step(world, sent)


## Gives `player` a unit of the type `id` at (`x`, `y`) milli-tiles and returns its id.
static func add_unit_of(world: World, player: int, id: String, x: int, y: int) -> int:
	return world.add_unit(player, type_of(world, id), x, y)


## The type index of the type id `id`.
static func type_of(world: World, id: String) -> int:
	return world.type_ids.find(StringName(id))


## How many rows of `player` have the type `id`.
static func count_of(world: World, player: int, id: String) -> int:
	var type: int = type_of(world, id)
	var found: int = 0
	for row: int in world.unit_count():
		if world.owner[row] == player and world.type_index[row] == type:
			found += 1
	return found


## The row of the first building of `player` with the type `id`, -1 for none.
static func row_of(world: World, player: int, id: String) -> int:
	var type: int = type_of(world, id)
	for row: int in world.unit_count():
		if world.owner[row] == player and world.type_index[row] == type:
			return row
	return -1


## Kills the row `row` and runs the tick that removes it (the loop's own step, no controller).
static func kill(world: World, loop: MatchLoop, row: int) -> void:
	world.hp[row] = 0
	step(world, loop)


## Makes every tile explored for both players, so that no placement is refused as unexplored.
static func explore_all(world: World) -> void:
	world.fog.explored.fill(1)


static func _spawn(owner: int, id: String, tile: Vector2i, count: int) -> SpawnDef:
	var spawn: SpawnDef = SpawnDef.new()
	spawn.owner = owner
	spawn.unit = load(UNIT_DIR + id + ".tres") as UnitDef
	spawn.count = count
	spawn.origin_tile = tile
	spawn.columns = 2
	spawn.spacing = 1000
	return spawn


static func _in_base(column: int, line: int) -> bool:
	for origin: Vector2i in [HQ_1, HQ_2]:
		if (
			column >= origin.x
			and column < origin.x + 3
			and line >= origin.y
			and line < origin.y + 3
		):
			return true
	return false
