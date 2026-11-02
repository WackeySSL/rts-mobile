extends RefCounted
## Fixtures of the recoil suites (plan P136, ADR 0027). Not a test suite. A match on the building
## suites' 32 x 32 map with the local player 1: player 1 has a light tank, a heavy tank, a rifle
## squad and a Redoubt, player 2 a heavy tank and a Lumen Accord defence in the far corner, out of
## sight. The runner is paused and not in the tree: a test sets the published snapshot's tick and
## the runner's alpha itself (`at`), delivers a tick's events (`deliver`) the way the runner does,
## and calls the layer's `_process` once for a frame. Match time is then
## `(tick + alpha) x 1000 / 15` ms.

const Buildings: GDScript = preload("res://tests/view/support/building_rig.gd")
const Effects: GDScript = preload("res://tests/view/support/effects_rig.gd")

## Unit ids, in spawn order.
const LIGHT: int = 1  ## Derrick League light tank, `tank_cannon`, no rock.
const HEAVY: int = 2  ## Derrick League heavy tank, `heavy_cannon`, rocks.
const SQUAD: int = 3  ## Rifle squad: no turret.
const REDOUBT: int = 4  ## Derrick League defence, `redoubt_gun`.
const ENEMY_TANK: int = 5  ## Lumen Accord heavy tank at tile (28, 28), out of sight.
const ENEMY_DEFENCE: int = 6  ## Lumen Accord defence at tile (28, 4), out of sight.
const FAR_TILE: Vector2i = Vector2i(28, 28)
const DEFENCE_TILE: Vector2i = Vector2i(28, 4)
## A SHOT's aim, as a ground vector in milli-tiles: this one is straight east on the screen
## ((dx - dy) x 32 = 256 px, (dx + dy) x 16 = 0), so the kick goes straight west.
const EAST_ON_SCREEN: Vector2i = Vector2i(4000, -4000)
## Straight south on the screen: the kick goes straight up.
const SOUTH_ON_SCREEN: Vector2i = Vector2i(4000, 4000)
## Match times in ms after tick 30 to (tick, alpha), exact in a double: 25 ms is 30 + 0.375 ticks.
const SHOT_TICK: int = 30
const SAMPLES: Array[Vector2] = [
	Vector2(30, 0.375),  # 25 ms
	Vector2(30, 0.75),  # 50
	Vector2(31, 0.125),  # 75
	Vector2(31, 0.5),  # 100
	Vector2(31, 0.875),  # 125
	Vector2(32, 0.25),  # 150
	Vector2(32, 0.625),  # 175
	Vector2(33, 0.0),  # 200
	Vector2(33, 0.375),  # 225
]
## The turret's distance back from its mount at SAMPLES with `tank_cannon` (3 px) in the default
## settings (out 50 ms, back 200 ms, 0.5 px steps) and, after the last sample, 0.
const TANK_CANNON_BACK: Array[float] = [1.5, 3.0, 2.0, 1.5, 1.0, 0.5, 0.0, 0.0, 0.0]


## `life` (the data file's numbers when null) with the idle life off: the recoil suites read exact
## offsets and write counts, which a shaking tank, a tank looking aside or a sweeping head would
## change. The idle life has suites of its own.
static func calmed(life: LifeSettings) -> LifeSettings:
	var out: LifeSettings = life
	if out == null:
		out = (load("res://data/life_settings.tres") as LifeSettings).duplicate() as LifeSettings
	out.shake_px = 0.0
	out.look_ms = 0
	out.sweep_frames = 0
	return out


## A paused, started runner on the fixture match.
static func runner() -> MatchRunner:
	var spawns: Array[SpawnDef] = [
		Buildings.spawn(1, "light_tank", 10, 10),
		Buildings.spawn(1, "heavy_tank", 14, 10),
		Buildings.spawn(1, "rifle_squad", 10, 14),
		Buildings.spawn(1, "defence_turret", 18, 10),
		Buildings.spawn(2, "renew_tank", FAR_TILE.x, FAR_TILE.y),
		Buildings.spawn(2, "renew_defence", DEFENCE_TILE.x, DEFENCE_TILE.y),
	]
	return Buildings.runner(Buildings.scenario(spawns))


## Sets the published snapshot's tick and the runner's alpha: the match time of the next frame.
static func at(match_runner: MatchRunner, tick: int, alpha: float) -> void:
	match_runner.snapshot.tick = tick
	match_runner._micro_ticks = roundi(alpha * float(MatchRunner.MICRO_TICKS_PER_TICK))


## Delivers `events` as the events of tick `tick`, the way the runner emits them.
static func deliver(match_runner: MatchRunner, events: PackedInt32Array, tick: int) -> void:
	match_runner.snapshot.tick = tick
	match_runner.snapshot.events = events
	match_runner.ticked.emit(tick)


## A SHOT of the unit `shooter_id` standing at `from` (milli-tiles) towards `from + aim`, with the
## weapon named `weapon_id` of the match's weapon table.
static func shot(
	match_runner: MatchRunner, shooter_id: int, from: Vector2i, aim: Vector2i, weapon_id: StringName
) -> PackedInt32Array:
	var weapon: int = match_runner.snapshot.weapon_ids.find(weapon_id)
	return Effects.shot(from, from + aim, weapon, shooter_id, 99)


## The milli-tile centre of tile (x, y).
static func centre(tile: Vector2i) -> Vector2i:
	return Vector2i(tile.x * 1000 + 500, tile.y * 1000 + 500)


## Where unit `id` of the published snapshot stands, milli-tiles.
static func position_of(match_runner: MatchRunner, id: int) -> Vector2i:
	var snap: MatchSnapshot = match_runner.snapshot
	var row: int = snap.index_of(id)
	return Vector2i(snap.pos_x[row], snap.pos_y[row])
