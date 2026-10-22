extends Node2D
## The perf arena (plan P50b, ADR 0011 section 5, ADR 0012 sections 1 and 4, ADR 0013 section 3):
## the seed-42 arena of 150 units through the real view (map, units, health bars, projectiles,
## effects, player 1's fog, every enemy revealed) with the perf card over it. It is a developer
## scene: Dev menu, Perf arena. Its runner is AUTO in tick mode and in implementation, so the APK
## runs the sim on the worker with the C++ kernels while the web preview and every headless test
## run SYNC. `TouchInput` has no controller, so a finger pans and zooms and no Command can enter.
##
## On entry: `Engine.max_fps` 60 (a 90 or 120 Hz panel is judged at 60 fps) and the screen kept on
## through `keep_on_sink`; leaving puts both back as they were (the engine keeps the screen on by
## default, so leaving does not switch it off). `_ready` runs the card's preflight first (the
## self-check and the burst, with no World and no job, so its long frame lies in no timed window),
## then sets the scenario and starts the runner, then starts the card's first run. Every player-1
## unit is selected for the view (rings are part of what is measured), again after each new match.
## Every run starts at the scenario's framing (P50c): the first, and each one "Run again" or a
## layer-mode step starts, because the heavy window counts the rigs inside the camera. A finger
## still pans and zooms (to inspect on the preview), but a move while a run records makes it
## INVALID (`PerfHud.REASON_CAMERA_MOVED`): keep the phone on the table.
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

@export var scenario: ScenarioDef
## The frame cap of the arena (ADR 0011 section 5).
@export var max_fps: int = 60
## The camera zoom at the start (the lowest level of data/input_settings.tres).
@export var start_zoom: float = 0.75
@export var runner: MatchRunner
@export var map_view: MapView
@export var unit_layer: UnitLayer
@export var bar_layer: HealthBarLayer
@export var projectile_layer: ProjectileLayer
@export var effects_layer: EffectsLayer
@export var fog_layer: FogLayer
@export var camera: RtsCamera
@export var hud: PerfHud
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
var layer_mode: String = MODE_ALL

var _max_fps_before: int = 0
var _keep_on_before: bool = false
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


func _exit_tree() -> void:
	Engine.max_fps = _max_fps_before
	keep_on_sink.call(_keep_on_before)


func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	layers_button.pressed.connect(_on_layers_pressed)
	get_viewport().size_changed.connect(_apply_dp)
	_apply_dp()
	hud.rigs_source = drawn_rigs
	hud.fog_source = fog_update_usec
	hud.camera_source = camera.visible_world_rect
	hud.before_restart = frame_camera
	set_layer_mode(MODE_ALL)
	# The runner has no scenario in the scene, so its own _ready started nothing: the preflight
	# sees no World and no job.
	hud.preflight(runner)
	runner.scenario = scenario
	runner.start()
	frame_camera()
	_select_own_units()
	hud.restart()


func _process(_delta: float) -> void:
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
	camera.set_map_rect(Rect2(map_view.map_rect_px()))
	camera.zoom = Vector2.ONE * start_zoom
	camera.centre_on(
		(Vector2(scenario.camera_start_tile) + Vector2(0.5, 0.5)) * ViewScale.PX_PER_TILE
	)


## The rows shown and inside the camera's visible world rect now (`PerfHud.rigs_source`).
func drawn_rigs() -> int:
	var view: Rect2 = camera.visible_world_rect()
	var count: int = 0
	for index: int in unit_layer.get_child_count():
		var rig: Node2D = unit_layer.get_child(index)
		if rig.visible and view.has_point(rig.position):
			count += 1
	return count


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
