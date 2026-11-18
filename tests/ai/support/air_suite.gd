extends "res://tests/ai/support/production_suite.gd"
## The base of the air and tech suites (plan row P250): the shipped fossil roster Worlds (the
## frozen arena of the other AI suites has no airfield, aircraft, engineering centre or
## upgrades), bases with an airfield and an engineering centre, and the helpers. Not a test
## suite.

const FIELD_TILE: Vector2i = Vector2i(30, 12)
const WORKS_TILE: Vector2i = Vector2i(30, 20)
const BOMBER: String = "fossil_bomber"
const FIGHTER: String = "fossil_fighter"


## The shipped fossil start (the shipped rules and both players' shipped roster), the fog open.
func _shipped(credits: int) -> World:
	var built: ScenarioDef = FactionRig.scenario("fossil", "fossil")
	var listed: Array[FactionDef] = [null]
	for _at: int in 2:
		listed.append(load("res://data/factions/fossil.tres") as FactionDef)
	built.factions = listed
	built.rules = load("res://data/rules.tres") as RulesDef
	var world: World = World.from_scenario(built)
	AiRig.explore_all(world)
	world.credits[1] = credits
	return world


## A base with the plants, the refinery, the barracks, the factory and the radar.
func _base() -> World:
	var world: World = _shipped(RICH)
	for row: Array in [
		["power_plant", 10, 2],
		["power_plant", 13, 2],
		["power_plant", 16, 2],
		["refinery", 10, 10],
		["barracks", 2, 2],
		["vehicle_factory", 2, 12],
		["fossil_radar", 22, 2],
	]:
		AiRig.give(world, 1, row[0], row[1], row[2])
	Power.run(world)
	return world


## The base and a finished airfield (four pads).
func _air_base() -> World:
	var world: World = _base()
	AiRig.give(world, 1, "fossil_airfield", FIELD_TILE.x, FIELD_TILE.y)
	Power.run(world)
	return world


## The air base and an engineering centre.
func _research_base() -> World:
	var world: World = _air_base()
	AiRig.give(world, 1, "fossil_engineering", WORKS_TILE.x, WORKS_TILE.y)
	Power.run(world)
	return world


func _economy_run(economy: AiEconomy, memory: AiMemory, world: World, tries: int) -> Array[Command]:
	var all: Array[Command] = []
	var loop: MatchLoop = AiRig.loop_of(world)
	for _at: int in tries:
		memory.commands_left = 99
		var out: Array[Command] = []
		economy.run(PlayerView.of(world, 1), memory, _stream(), out)
		all.append_array(out)
		AiRig.step(world, loop, out)
	return all


func _ids(sent: Array[Command], world: World) -> Array[String]:
	var found: Array[String] = []
	for command: Command in sent:
		if command.type == Command.Type.QUEUE:
			found.append(String(world.type_ids[command.payload[0]]))
	return found


func _ids_in_tab(sent: Array[Command], world: World, tab: int) -> Array[String]:
	var found: Array[String] = []
	for command: Command in sent:
		if command.type == Command.Type.QUEUE and world.type_tab[command.payload[0]] == tab:
			found.append(String(world.type_ids[command.payload[0]]))
	return found


func _in_flight(sent: Array[Command], world: World) -> Array[String]:
	return _ids_in_tab(sent, world, World.Tab.FLIGHT)


## The aircraft of 200 first draws of one stream, with `seen` aircraft seen at once.
func _air_draws(seen: int, credits: int = RICH) -> Dictionary[String, int]:
	var counts: Dictionary[String, int] = {BOMBER: 0, FIGHTER: 0}
	var stream: DetRandom = _stream()
	var production: AiProduction = _production("fossil", "normal")
	var memory: AiMemory = _memory("fossil")
	memory.seen_air_peak = seen
	var world: World = _air_base()
	world.credits[1] = credits
	for _at: int in 200:
		world.queue_count.fill(0)
		world.credits[1] = credits
		memory.commands_left = 99
		var out: Array[Command] = []
		production.run(PlayerView.of(world, 1), memory, stream, out)
		for id: String in _in_flight(out, world):
			counts[id] += 1
	return counts
