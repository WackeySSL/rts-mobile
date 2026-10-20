extends RefCounted
## Fixtures of the EffectsLayer suites (plan P44b). Not a test suite. `battle()` is a small match
## of both sides' tanks and rifle squads that meet and fight, with all three shipped types and
## weapons registered, so its snapshot has the weapon and type tables the layer reads, whatever
## the shipped scenarios hold. The record builders write the events that the sim writes
## (game/sim/Combat.gd, game/sim/World.gd), so a case can set up exactly the tick it wants.

const RULES: String = "res://data/rules.tres"
const UNITS: Array[String] = [
	"res://data/units/light_tank.tres",
	"res://data/units/rifle_squad.tres",
	"res://data/units/rocket_squad.tres",
]
const TANK: String = "res://data/units/light_tank.tres"
const RIFLE_SQUAD: String = "res://data/units/rifle_squad.tres"


## Tanks and rifle squads on both sides, a few tiles apart and ordered to attack-move at each
## other, so shells fly, rifles fire and units die within a few hundred ticks. Player 1 is on the
## left. `jitter` makes the first shots fall on different ticks.
static func battle() -> ScenarioDef:
	var scenario: ScenarioDef = ScenarioDef.new()
	scenario.map_size_tiles = Vector2i(40, 24)
	scenario.rules = load(RULES)
	for path: String in UNITS:
		scenario.roster.append(load(path))
	for side: int in [1, 2]:
		var column: int = 8 if side == 1 else 26
		scenario.spawns.append(_spawn(side, TANK, 4, Vector2i(column, 6), 2))
		scenario.spawns.append(_spawn(side, RIFLE_SQUAD, 12, Vector2i(column + 3, 6), 3))
		var order: OrderDef = OrderDef.new()
		order.player = side
		order.target_tile = Vector2i(26 if side == 1 else 8, 8)
		scenario.orders.append(order)
	return scenario


## A duel of two rifle squads of the owners `owners` (a neutral one is owner 0), three tiles
## apart. A test sets their hp to 1, so the first shot kills its target in the tick it is fired.
static func duel(owners: Vector2i = Vector2i(1, 2)) -> ScenarioDef:
	var scenario: ScenarioDef = ScenarioDef.new()
	scenario.map_size_tiles = Vector2i(24, 24)
	scenario.rules = load(RULES)
	for path: String in UNITS:
		scenario.roster.append(load(path))
	scenario.spawns.append(_spawn(owners.x, RIFLE_SQUAD, 1, Vector2i(8, 8), 1))
	scenario.spawns.append(_spawn(owners.y, RIFLE_SQUAD, 1, Vector2i(11, 8), 1))
	return scenario


## [SHOT, shooter id, shooter x, shooter y, target id, weapon, target x, target y], in milli-tiles.
static func shot(
	shooter: Vector2i, target: Vector2i, weapon: int, shooter_id: int = 1, target_id: int = 2
) -> PackedInt32Array:
	return PackedInt32Array(
		[World.Event.SHOT, shooter_id, shooter.x, shooter.y, target_id, weapon, target.x, target.y]
	)


## [IMPACT, projectile id, x, y, target id or 0, weapon, 0, 0].
static func impact(
	at: Vector2i, weapon: int, projectile_id: int = 1, target_id: int = 0
) -> PackedInt32Array:
	return PackedInt32Array(
		[World.Event.IMPACT, projectile_id, at.x, at.y, target_id, weapon, 0, 0]
	)


## [DIED, unit id, x, y, type index, owner, 0, 0].
static func died(
	at: Vector2i, type_index: int, unit_id: int = 1, owner_id: int = 1
) -> PackedInt32Array:
	return PackedInt32Array([World.Event.DIED, unit_id, at.x, at.y, type_index, owner_id, 0, 0])


static func _spawn(
	owner_id: int, path: String, count: int, origin: Vector2i, columns: int
) -> SpawnDef:
	var spawn: SpawnDef = SpawnDef.new()
	spawn.owner = owner_id
	spawn.unit = load(path)
	spawn.count = count
	spawn.origin_tile = origin
	spawn.columns = columns
	spawn.spacing = 1300
	spawn.jitter = 300
	return spawn
