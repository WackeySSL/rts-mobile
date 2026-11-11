extends Node2D
## The perf arena (plan P50b, ADR 0011 section 5, ADR 0012 sections 1 and 4, ADR 0013 section 3):
## the seed-42 arena of 150 units through the real view (map, units, health bars, projectiles,
## effects, player 1's fog, every enemy revealed) with the perf card over it. It is a developer
## scene: Dev menu, Perf arena. Its runner is AUTO in tick mode and in implementation, so the APK
## runs the sim on the worker with the C++ kernels while the web preview and every headless test
## run SYNC. `TouchInput` has no controller, so a finger pans and zooms and no Command can enter.
##
## On entry: `Engine.max_fps` 60 (a 90 or 120 Hz panel is judged at 60 fps), the screen kept on
## through `keep_on_sink` and, where the display server has `FEATURE_ORIENTATION` (the APK), the
## screen held in sensor landscape (plan P63b, ADR 0015: the gate is a landscape measurement, and a
## phone held upright shows fewer than `heavy_rigs` rigs). Leaving puts all three back as found
## (the engine keeps the screen on by default, so leaving does not switch it off, and the
## orientation put back is the one found, so the game follows the phone again). The web preview and
## headless have no such feature: neither orientation seam is called there, and since the preview
## cannot lock the screen, a run that sees a portrait view is INVALID (`PerfHud.REASON_PORTRAIT`).
## `_ready` runs the card's preflight first (the self-check and the burst, with no World and no job,
## so its long frame lies in no timed window), then sets the scenario and starts the runner, then
## starts the card's first run. When entry asked for the landscape lock and the view is still
## portrait (a phone held upright: Android turns the window a few frames after the request, and a
## run that began before it would be INVALID for the moved camera and the portrait view), the
## runner's start, the framing and the card's first run wait for the viewport's `size_changed` that
## makes it landscape, at most `LANDSCAPE_WAIT_FRAMES` frames (plan P63c): then the run starts
## anyway and `PerfHud.REASON_PORTRAIT` marks it. Without the lock (the web preview, headless) or
## in a landscape view the first run starts at once. Every player-1 unit is selected for the view
## (rings are part of what is measured), again after each new match.
## Every run starts at the scenario's framing (P50c): the first, and each one "Run again" or a
## layer-mode step starts, because the heavy window counts the rigs inside the camera. A finger
## still pans and zooms (to inspect on the preview), but a move while a run records makes it
## INVALID (`PerfHud.REASON_CAMERA_MOVED`): keep the phone on the table.
## Two atlases are baked once in `_ready`, before the card's preflight and so outside every timed
## window (plans P113 and P114). The sorted world draws from the first: the art of the scenario's
## three types for each of its two players, scale 1; the match start finds it there and keeps it.
## The card and one console line (`atlas_bake_ms`, `atlas_page`, `atlas_page2`) describe the second, P113's
## report-only bake: every sheet of both factions, each player in its faction's key triad, which is
## what a real two-faction match start bakes (ADR 0023 section 2), whatever this scenario spawns.
## Two scenarios (plan P93c): the seed-42 arena above, and the base arena (`arena_kind` bases, set
## by the dev menu's "Perf bases" through `DevRoutes.open_perf_bases` before the scene enters the
## tree), P80's `perf_bases.tres` on the same card machinery; the card then checks the run against
## `bases_golden_ticks` and `bases_golden_hex` and names them in a mismatch. Its framing is not the
## scenario's tile and zoom but every sprite inside the map's diamond, overhangs included (the P50c
## rule as revision 5 states it): the camera centres on the union of their boxes and zooms out,
## below the start zoom when they need it, until they fit the view.
## A third scenario (plan P185, `arena_kind` ai, `DevRoutes.open_perf_ai`): `perf_ai.tres`, two
## mirror bases with a Normal computer player on each; the card adds the AI's think time (no
## verdict) and has no golden comparison. Framed as the scenario says, like the seed-42 arena.
## The look is the theme's (`game/ui/theme.tres`): the scene sets it on the margin the controls sit
## in, and this script sets no colour, font or style.

const MODE_ALL: String = "all"
const MODE_NO_FOG: String = "no fog"
const MODE_NO_BARS: String = "no bars"
## Hides the projectile layer and the effects layer.
const MODE_NO_EFFECTS: String = "no effects"
const MODE_RIGS_ONLY: String = "rigs only"
const MODES: PackedStringArray = [
	MODE_ALL, MODE_NO_FOG, MODE_NO_BARS, MODE_NO_EFFECTS, MODE_RIGS_ONLY
]
const LAYERS_TEXT: String = "Layers: %s"
const GAP_DP: float = 8.0
## How long the first run waits for the window to turn to landscape: 120 frames, 2 s at the arena's
## 60 fps cap. Android turns the window a few frames after `screen_set_orientation` (P63b's review
## saw `_ready` finish first), so 2 s is many times that and covers a slow turn, yet stays short
## for a window that never turns (split screen, a system that refuses the request): its run then
## starts anyway and `portrait` marks it, as on the web preview.
const LANDSCAPE_WAIT_FRAMES: int = 120
const ATLAS_SCALE: float = 1.0  ## The scale the arena asks the atlas for.
## The box of a unit's rig, world px, around its feet: a tile's width and a tile and a half up
## (the sprite of a tank or a squad with its bar's room), a view size and not a rule value.
const RIG_BOX_PX: Vector2 = Vector2(64.0, 48.0)
## Room grown round the union of the boxes, world px.
const FRAME_MARGIN_PX: float = 32.0

@export var scenario: ScenarioDef
## The frame cap of the arena (ADR 0011 section 5).
@export var max_fps: int = 60
## The camera zoom at the start (the lowest level of data/input_settings.tres).
@export var start_zoom: float = 0.75
@export var runner: MatchRunner
@export var map_view: MapView
@export var world_sort: WorldSort  ## Draws the rigs and holds the atlas.
@export var unit_layer: UnitLayer
@export var bar_layer: HealthBarLayer
@export var projectile_layer: ProjectileLayer
@export var effects_layer: EffectsLayer
@export var fog_layer: FogLayer
@export var building_layer: BuildingLayer
@export var camera: RtsCamera
@export var hud: PerfHud
## `PerfHud.ARENA_UNITS` (the scene's scenario), `PerfHud.ARENA_BASES` (P80's) or
## `PerfHud.ARENA_AI` (P174's, with its computers); both loaded in `_ready`.
@export var arena_kind: String = PerfHud.ARENA_UNITS
@export var back_button: Button
@export var layers_button: Button
## The boxes whose gap is GAP_DP: the column of bar and card, and the bar of the two buttons.
@export var layout: BoxContainer
@export var bar: BoxContainer

## Keeps the screen on while the arena is up, and the state it found on entry that leaving puts
## back. Tests replace both: headless `screen_is_kept_on()` stays false, so they inject the state
## and assert on the sink.
var keep_on_sink: Callable = DisplayServer.screen_set_keep_on
var keep_on_source: Callable = DisplayServer.screen_is_kept_on
## Holds the screen in landscape while the arena is up (plan P63b): the feature check, the source
## of the orientation found on entry and the sink that sets it and puts it back. Tests replace all
## three with spies; the default feature check is false headless and on the web, so neither of the
## other two is called there (the engine would print a warning).
var orientation_feature: Callable = DisplayServer.has_feature.bind(
	DisplayServer.FEATURE_ORIENTATION
)
var orientation_source: Callable = DisplayServer.screen_get_orientation
var orientation_sink: Callable = DisplayServer.screen_set_orientation
## Bakes the atlases and returns the card's (a test replaces it with a stub: the real bake
## rasterises every frame).
var atlas_source: Callable = _bake_atlas
var layer_mode: String = MODE_ALL

var _wait_left: int = 0  ## Frames the first run may still wait for landscape; 0: not waiting.
var _max_fps_before: int = 0
var _keep_on_before: bool = false
var _orientation_locked: bool = false  ## The sink was called on entry, so leaving calls it too.
var _orientation_before: int = DisplayServer.SCREEN_LANDSCAPE
var _serial: int = -1  ## match_serial the selection was made for.
var _fog_uploads: int = 0  ## upload_count() at the last fog_update_usec().


## The mode after `mode` in the selector's order, wrapping.
static func next_mode(mode: String) -> String:
	return MODES[(MODES.find(mode) + 1) % MODES.size()]


func _enter_tree() -> void:
	_max_fps_before = Engine.max_fps
	Engine.max_fps = max_fps
	_keep_on_before = keep_on_source.call()
	keep_on_sink.call(true)
	_orientation_locked = bool(orientation_feature.call())
	if _orientation_locked:
		_orientation_before = int(orientation_source.call())
		orientation_sink.call(DisplayServer.SCREEN_SENSOR_LANDSCAPE)


func _exit_tree() -> void:
	Engine.max_fps = _max_fps_before
	keep_on_sink.call(_keep_on_before)
	if _orientation_locked:
		orientation_sink.call(_orientation_before)
		_orientation_locked = false
	_wait_left = 0  # An arena that left the tree starts no run.


func _ready() -> void:
	if arena_kind == PerfHud.ARENA_BASES:
		scenario = load(DevRoutes.PERF_BASES_SCENARIO) as ScenarioDef
	elif arena_kind == PerfHud.ARENA_AI:
		scenario = load(DevRoutes.PERF_AI_SCENARIO) as ScenarioDef
		_seat_computers()
	hud.arena_kind = arena_kind
	back_button.pressed.connect(_on_back_pressed)
	layers_button.pressed.connect(_on_layers_pressed)
	get_viewport().size_changed.connect(_apply_dp)
	get_viewport().size_changed.connect(_on_view_resized)
	_apply_dp()
	_report_atlas()
	hud.rigs_source = drawn_rigs
	hud.fog_source = fog_update_usec
	hud.camera_source = camera.visible_world_rect
	hud.before_restart = frame_camera
	set_layer_mode(MODE_ALL)
	# The runner has no scenario in the scene, so its own _ready started nothing: the preflight
	# sees no World and no job.
	hud.preflight(runner)
	runner.scenario = scenario
	if _orientation_locked and _view_is_portrait():
		_wait_left = LANDSCAPE_WAIT_FRAMES
	else:
		_start_first_run()


## The AI arena's computers (plan P185, P189b): a Normal `OpponentAi` on the frozen defs with early
## contact on each player, the Derrick League's on player 1 (`first_opponent` 1, the view stays
## player 1's) and the Lumen Accord's on player 2.
func _seat_computers() -> void:
	var opponents: Array[AiDef] = [
		load(DevRoutes.PERF_AI_FOSSIL) as AiDef, load(DevRoutes.PERF_AI_RENEW) as AiDef
	]
	var normal: AiDifficultyDef = load(DevRoutes.PERF_AI_LEVEL) as AiDifficultyDef
	var levels: Array[AiDifficultyDef] = [normal, normal]
	runner.opponents = opponents
	runner.opponent_levels = levels
	runner.first_opponent = 1


func _process(_delta: float) -> void:
	if _wait_left > 0:
		_wait_left -= 1
		if _wait_left == 0:
			_start_first_run()
	hud.zoom = camera.zoom.x
	_select_own_units()


## Shows the layers of `mode` and prints it on the card. The sim is not touched: a gate run is
## "all", and the other modes narrow a render miss in one more run. An unknown mode is ignored.
func set_layer_mode(mode: String) -> void:
	if not MODES.has(mode):
		return
	layer_mode = mode
	hud.layer_mode = mode
	var rigs_only: bool = mode == MODE_RIGS_ONLY
	fog_layer.visible = mode != MODE_NO_FOG and not rigs_only
	bar_layer.visible = mode != MODE_NO_BARS and not rigs_only
	var shots: bool = mode != MODE_NO_EFFECTS and not rigs_only
	projectile_layer.visible = shots
	effects_layer.visible = shots
	layers_button.text = LAYERS_TEXT % mode


## The scenario's framing: the start zoom, centred on its camera tile, inside the map. A run begins
## here (`_ready` and `PerfHud.before_restart`), wherever a finger left the camera.
func frame_camera() -> void:
	camera.set_map_rect(map_view.map_diamond_px())
	if arena_kind == PerfHud.ARENA_BASES:
		_frame_sprites()
		return
	camera.zoom = Vector2.ONE * start_zoom
	camera.centre_on(
		IsoProjection.cell_centre_px(scenario.camera_start_tile.x, scenario.camera_start_tile.y)
	)


## The base arena's framing: the camera centred on the union of every sprite box inside the diamond
## and zoomed to hold it, at most the start zoom. A match with no sprite falls back to the
## scenario's tile and the start zoom.
func _frame_sprites() -> void:
	var box: Rect2 = union_of(sprite_boxes())
	if box.size == Vector2.ZERO:
		camera.zoom = Vector2.ONE * start_zoom
		camera.centre_on(
			IsoProjection.cell_centre_px(scenario.camera_start_tile.x, scenario.camera_start_tile.y)
		)
		return
	box = box.grow(FRAME_MARGIN_PX)
	var view: Vector2 = get_viewport_rect().size
	camera.zoom = Vector2.ONE * minf(start_zoom, minf(view.x / box.size.x, view.y / box.size.y))
	camera.centre_on(box.get_center())


## The box of every sprite of the match whose feet stand inside the map's diamond, world px: a
## building's `frame_box` (footprint width, from the top of the picture to the diamond's bottom
## corner) and a rig's `RIG_BOX_PX` round its position. Both layers are synced first, so a frame
## right after the match start sees the rows.
func sprite_boxes() -> Array[Rect2]:
	var boxes: Array[Rect2] = []
	var snap: MatchSnapshot = runner.snapshot
	if snap == null:
		return boxes
	unit_layer.sync_rows()
	building_layer.sync_rows()
	for row: int in snap.unit_id.size():
		var box: Rect2 = building_layer.frame_box(row)
		var feet: Vector2 = Vector2(box.get_center().x, box.end.y - IsoProjection.HALF_H)
		var rig: Node2D = unit_layer.rig(row)
		if rig != null:
			box = Rect2(rig.position - Vector2(RIG_BOX_PX.x * 0.5, RIG_BOX_PX.y), RIG_BOX_PX)
			feet = rig.position
		if box.size != Vector2.ZERO and in_diamond(feet, snap.map_cols, snap.map_rows):
			boxes.append(box)
	return boxes


## Whether the world px `feet` lie on a map of `cols` by `rows` tiles.
static func in_diamond(feet: Vector2, cols: int, rows: int) -> bool:
	var ground: Vector2i = IsoProjection.px_to_ground(feet)
	var milli: int = ViewScale.MILLI_PER_TILE
	return ground.x >= 0 and ground.y >= 0 and ground.x < cols * milli and ground.y < rows * milli


## The smallest rect that holds all of `boxes`, empty for none.
static func union_of(boxes: Array[Rect2]) -> Rect2:
	if boxes.is_empty():
		return Rect2()
	var out: Rect2 = boxes[0]
	for box: Rect2 in boxes:
		out = out.merge(box)
	return out


## The first run (plan P63c), in the order "Run again" keeps: the match starts, the view is framed
## (it needs the match's map), then the card's run begins and reads the view it is judged against.
func _start_first_run() -> void:
	_wait_left = 0
	runner.start()
	frame_camera()
	_select_own_units()
	hud.restart()


## Whether the card would judge the view portrait now: its own seam and rule, so the arena waits
## for exactly what would mark the run.
func _view_is_portrait() -> bool:
	return (
		hud.view_size_source.is_valid()
		and UiScale.is_portrait_size(Vector2i(hud.view_size_source.call()))
	)


## The turn the first run waits for. A flip emits twice; the second finds the run started.
func _on_view_resized() -> void:
	if _wait_left > 0 and not _view_is_portrait():
		_start_first_run()


## The rows shown and inside the camera's visible world rect now (`PerfHud.rigs_source`).
func drawn_rigs() -> int:
	return unit_layer.count_in(camera.visible_world_rect())


## The fog layer's update time in us when it uploaded since the last call, else -1
## (`PerfHud.fog_source`): the layer keeps its last value between updates, so a frame without an
## upload must not count it again.
func fog_update_usec() -> int:
	var uploads: int = fog_layer.upload_count()
	if uploads == _fog_uploads:
		return -1
	_fog_uploads = uploads
	return fog_layer.last_update_usec()


## A new match (the first, or "Run again") has no rings: select every unit of the local player,
## for the view only.
func _select_own_units() -> void:
	var snap: MatchSnapshot = runner.snapshot
	if snap == null or snap.match_serial == _serial:
		return
	_serial = snap.match_serial
	var player: int = FogLayer.local_player_of(runner)
	var ids: PackedInt32Array = PackedInt32Array()
	for row: int in snap.owner.size():
		if snap.owner[row] == player:
			ids.append(snap.unit_id[row])
	unit_layer.set_selected(ids)


## Another layer mode is a new run, so a run never mixes two modes.
func _on_layers_pressed() -> void:
	set_layer_mode(next_mode(layer_mode))
	hud.run_again()


func _on_back_pressed() -> void:
	DevRoutes.open(get_tree(), DevRoutes.DEV_MENU_SCENE)


## Sizes are dp, so they follow a resize.
func _apply_dp() -> void:
	var gap: int = roundi(UiScale.dp(GAP_DP))
	layout.add_theme_constant_override("separation", gap)
	bar.add_theme_constant_override("separation", gap)


## Bakes the atlas the sorted world draws from (the scenario's match, so the match start finds it
## and bakes nothing in a timed window) and returns the card's: all sheets of both factions, each of
## two players in its faction's key triad (`FactionDef.key_triad`), the worst case of a match start
## however few types the scenario spawns. The card's atlas is never drawn from.
func _bake_atlas() -> IsoAtlas:
	world_sort.bake_scale = ATLAS_SCALE
	world_sort.bake(scenario)
	var sheets: Array[IsoSheetDef] = IsoAtlas.load_sheets()
	var players: Array[IsoPlayerArt] = _report_players(sheets)
	var neutral: IsoSheetDef = world_sort.neutral_sheet()  # After the players: no faction file.
	if neutral != null:
		sheets.append(neutral)
	return IsoAtlas.build(sheets, players, ATLAS_SCALE)


## One player per faction that has a sheet, in the order of the faction ids, each wearing its
## faction's key triad.
static func _report_players(sheets: Array[IsoSheetDef]) -> Array[IsoPlayerArt]:
	var ids: Array[String] = []
	for sheet: IsoSheetDef in sheets:
		if not ids.has(String(sheet.faction)):
			ids.append(String(sheet.faction))
	ids.sort()
	var players: Array[IsoPlayerArt] = []
	for id: String in ids:
		var faction: FactionDef = load(WorldSort.FACTION_FILE % id) as FactionDef
		players.append(IsoPlayerArt.make(faction.id, faction.key_triad, faction.key_triad))
	return players


## Bakes the atlas and gives the card its numbers (and the console its one line). The card's atlas
## is report-only and is not kept: its pages are uploaded textures that nothing draws from.
func _report_atlas() -> void:
	var baked: IsoAtlas = atlas_source.call()
	var page: Vector2i = baked.page_px()
	var second: Vector2i = baked.page_px(IsoAtlas.PAGE_UNSORTED)
	hud.atlas_bake_ms = baked.bake_ms()
	hud.atlas_page = "none"
	hud.atlas_page2 = "none"
	if not baked.is_empty():
		hud.atlas_page = "%dx%d at %.3f" % [page.x, page.y, baked.bake_scale()]
		if second != Vector2i.ZERO:
			hud.atlas_page2 = "%dx%d" % [second.x, second.y]
		print(baked.report())
