extends RefCounted
## Fixtures of the P87 order suites (plan P87, ADR 0019 section 3). Not a test suite. The main
## scene on a 32 x 32 map of grass with one oil field, a 2 x 2 block of ore at tiles (16, 16) to
## (17, 17), and these rows, player 1 the local one, ids from 1 in this order: its Headquarters
## `HQ` (3x3 at tile (2, 2)), barracks `BARRACKS` (2x2 at (7, 2)), vehicle factory `FACTORY` (3x3
## at (11, 2)), refinery `REFINERY` (3x3 at (2, 7)), power plant `PLANT` (2x2 at (7, 7)), turret
## `TURRET` (at (11, 7)), two tankers `TANKER_A` and `TANKER_B` (at (6, 12) and (8, 12)), a light
## tank `TANK` (at (6, 15)) and a rifle squad `RIFLE` (at (8, 15)); player 2's Headquarters
## `ENEMY_HQ` (3x3 at (24, 24)) and a rifle squad `ENEMY_RIFLE` (at (20, 18)), which player 1 sees.
## `GROUND` is a tile no row stands within five tiles of and no field is near. An instance holds the
## scene, a fake clock, the Commands the controller sent and the haptics it asked for, and taps and
## boxes through the real TouchInput the way a finger does.

const BuildingRig: GDScript = preload("res://tests/view/support/building_rig.gd")
const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const TERRAIN: String = "res://data/terrain/standard.tres"
const HQ: int = 1
const BARRACKS: int = 2
const FACTORY: int = 3
const REFINERY: int = 4
const PLANT: int = 5
const TURRET: int = 6
const TANKER_A: int = 7
const TANKER_B: int = 8
const TANK: int = 9
const RIFLE: int = 10
const ENEMY_HQ: int = 11
const ENEMY_RIFLE: int = 12
const SPAWNS: Array[Array] = [
	[1, "headquarters", 2, 2],
	[1, "barracks", 7, 2],
	[1, "vehicle_factory", 11, 2],
	[1, "refinery", 2, 7],
	[1, "power_plant", 7, 7],
	[1, "defence_turret", 11, 7],
	[1, "harvester", 6, 12],
	[1, "harvester", 8, 12],
	[1, "light_tank", 6, 15],
	[1, "rifle_squad", 8, 15],
	[2, "renew_hq", 24, 24],
	[2, "renew_rifle", 20, 18],
]
const FIELD_TILES: Array[Vector2i] = [
	Vector2i(16, 16), Vector2i(17, 16), Vector2i(16, 17), Vector2i(17, 17)
]
const GROUND: Vector2i = Vector2i(22, 10)

var main: Node2D
var runner: MatchRunner
var camera: RtsCamera
var touch: TouchInput
var controller: PlayerController
var buildings: BuildingLayer
var units: UnitLayer
var now_ms: int = 0
var sent: Array[Command] = []
var buzzes: Array[int] = []  ## The ms of every haptic the controller asked for.


## The scenario of this rig: the spawns above on a map with the field. A suite sets it on the
## main scene's `MatchRunner` before the scene enters the tree.
static func scenario() -> ScenarioDef:
	var spawns: Array[SpawnDef] = []
	for entry: Array in SPAWNS:
		spawns.append(BuildingRig.spawn(entry[0], entry[1], entry[2], entry[3]))
	var made: ScenarioDef = BuildingRig.scenario(spawns)
	var map: MapDef = MapDef.new()
	map.terrain = load(TERRAIN)
	var rows: PackedStringArray = PackedStringArray()
	for row: int in BuildingRig.MAP.y:
		var line: String = ""
		for col: int in BuildingRig.MAP.x:
			line += "o" if FIELD_TILES.has(Vector2i(col, row)) else "."
		rows.append(line)
	map.rows = rows
	made.map = map
	return made


## Takes the nodes of `scene`, pauses the runner (only `run_ticks` moves time), lets the local
## player see the enemy Headquarters and puts a fake clock and a recording sink in place.
func bind(scene: Node2D) -> void:
	main = scene
	runner = main.get_node("MatchRunner")
	runner.paused = true
	camera = main.get_node("Camera")
	touch = main.get_node("TouchInput")
	controller = main.get_node("PlayerController")
	buildings = main.get_node("BuildingLayer")
	units = main.get_node("UnitLayer")
	# The cells under the enemy Headquarters' position and the enemy rifle squad's.
	BuildingRig.see(runner.snapshot, 1, [Vector2i(25, 25), Vector2i(20, 18)])
	now_ms = 0
	sent.clear()
	buzzes.clear()
	touch.clock = func() -> int: return now_ms
	controller.command_sink = func(command: Command) -> void: sent.append(command)
	controller.vibrate = func(ms: int) -> void: buzzes.append(ms)


## Passes the Commands on to the real queue as well as recording them, so a tick applies them.
func send_to_the_sim() -> void:
	controller.command_sink = func(command: Command) -> void:
		sent.append(command)
		CommandQueue.submit(command)


## Camera back at zoom 1, nothing selected, nothing recorded: what a case starts from.
func reset() -> void:
	camera.zoom = Vector2.ONE
	controller.selection.clear()
	sent.clear()
	buzzes.clear()


## The world px of the middle of tile (`col`, `row`).
static func tile_px(col: int, row: int) -> Vector2:
	return IsoProjection.cell_centre_px(col, row)


## Centres the camera on `world` and taps it.
func tap_world(world: Vector2) -> void:
	camera.centre_on(world)
	tap(camera.world_to_screen(world))


## Selects building `id` with a tap on the middle of its footprint.
func tap_building(id: int) -> void:
	var node: Node2D = buildings.building(id)
	camera.centre_on(node.position)
	tap(camera.world_to_screen(node.position))


## Selects unit `id` with a tap on its picture (the unit layer's row of the id).
func tap_unit(id: int, twice: bool = false) -> void:
	var row: int = runner.snapshot.index_of(id)
	camera.centre_on(
		IsoProjection.ground_to_px(runner.snapshot.pos_x[row], runner.snapshot.pos_y[row])
	)
	tap(units.unit_screen_position(row), twice)


## A finger down and up at `at` (base px), then a pause past the double-tap time; `twice` taps again
## inside the double-tap time first.
func tap(at: Vector2, twice: bool = false) -> void:
	var viewport: Viewport = main.get_viewport()
	for tap_count: int in 2 if twice else 1:
		TouchEvents.press(viewport, 0, at)
		now_ms += 50
		touch._process(0.0)
		TouchEvents.release(viewport, 0, at)
		now_ms += 100 if twice and tap_count == 0 else 1000


## Holds the long-press time at `from`, drags to `to` and lets go: a box.
func box(from: Vector2, to: Vector2) -> void:
	var viewport: Viewport = main.get_viewport()
	TouchEvents.press(viewport, 0, from)
	now_ms += touch.settings.long_press_ms
	touch._process(0.0)  # The frame that sees the hold.
	TouchEvents.drag(viewport, 0, to, to - from)
	TouchEvents.release(viewport, 0, to)
	now_ms += 1000


## Centres the camera on the middle of units `ids` and boxes them: a rectangle round their places
## on the screen, 14 px beyond them and 40 above (a unit is boxed by its centre, which stands higher
## than its place). Units further than that from every one of them are not in it.
func box_around(ids: Array[int]) -> void:
	var snap: MatchSnapshot = runner.snapshot
	var places: Array[Vector2] = []
	var middle: Vector2 = Vector2.ZERO
	for id: int in ids:
		var row: int = snap.index_of(id)
		places.append(IsoProjection.ground_to_px(snap.pos_x[row], snap.pos_y[row]))
		middle += places.back() / ids.size()
	camera.centre_on(middle)
	var rect: Rect2 = Rect2(camera.world_to_screen(places[0]), Vector2.ZERO)
	for place: Vector2 in places:
		rect = rect.expand(camera.world_to_screen(place))
	box(rect.position - Vector2(14.0, 40.0), rect.end + Vector2(14.0, 14.0))
