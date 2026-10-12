extends Node2D
## Phone perf probe (plan P26s, ADR 0011 section 5), a throwaway dev scene. At camera zoom 0.75
## with every unit on screen it draws what the Phase 2 view contracts promise, at absolute z:
## 75 rings (1; sprites, or the Phase 1 code-drawn rings), 150 tank rigs (2-4, the real SVGs),
## 150 health bars (5, rects), 60 projectiles (6) and 128 effects (7) as quads of one placeholder
## atlas, a 64x64 fog texture (8) patched at 5 Hz, and the mock tick at 15 Hz in the frame. A run
## of `run_seconds` records the frame; the card is the clipboard report. `Engine.max_fps` is 60
## while the scene is open, so a 90 or 120 Hz panel is judged at 60 fps.

@warning_ignore_start("integer_division")

enum Mode { SPRITE_RINGS, CODE_RINGS, ALTERNATING_TINTS }
enum Series { INTERVAL, PROCESS, RENDER, CALLS, WORK_TICK, WORK_OTHER, TICK, SLICE, FOG }

const ART: String = "res://assets/art/svg/units/light_tank_%s.svg"
const UNITS: int = PerfProbeTick.UNITS
const COLS: int = PerfProbeTick.COLS
const SIDE: int = PerfProbeTick.SIDE
const TICK_USEC: int = 66667  ## 15 Hz.
const FLOW_CELLS: int = 512
const ON_TIME_MS: float = 17.5
const MODES: Array[String] = ["sprite rings", "code rings", "sprite rings, tints alternate"]

var run_seconds: int = 60
var mode: int = Mode.SPRITE_RINGS  ## Code rings are the Phase 1 ones; the tint order is by team.
var clipboard_sink: Callable = DisplayServer.clipboard_set
var sim: PerfProbeTick = PerfProbeTick.new()

var _rigs: Array[Node2D] = []
var _rings: Array[Node2D] = []  ## Per selected unit: a sprite ring, then a code ring.
var _layers: Array[Painted] = []
var _series: Array[PackedFloat64Array] = []
var _prev_x: PackedInt32Array = sim.x.duplicate()
var _prev_y: PackedInt32Array = sim.y.duplicate()
var _atlas: ImageTexture = null
var _fog_image: Image = Image.create_empty(COLS, COLS, false, Image.FORMAT_RGBA8)
var _fog_texture: ImageTexture = null
var _viewport: RID = RID()
var _max_fps: int = 0
var _last_us: int = 0
var _start_us: int = 0
var _end_us: int = 0  ## 0 while the run goes on.
var _clock_us: int = 0
var _prev_ticked: bool = false

@onready var _card: Label = $Hud/Margin/Card
@onready var _back: Button = $Hud/Margin/Buttons/BackButton
@onready var _rings_button: Button = $Hud/Margin/Buttons/RingsButton
@onready var _copy_button: Button = $Hud/Margin/Buttons/CopyButton


## A Node2D that draws with `painter(self)` inside its own `_draw()`.
class Painted:
	extends Node2D

	var painter: Callable

	func _draw() -> void:
		painter.call(self)


func _enter_tree() -> void:
	_max_fps = Engine.max_fps
	Engine.max_fps = 60
	DisplayServer.screen_set_keep_on(true)  # A 60 s run outlasts the usual screen timeout.


func _exit_tree() -> void:
	Engine.max_fps = _max_fps
	DisplayServer.screen_set_keep_on(false)
	RenderingServer.viewport_set_measure_render_time(_viewport, false)


func _ready() -> void:
	_viewport = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_viewport, true)
	for _s: int in Series.size():
		_series.append(PackedFloat64Array())
	var unit: float = UiScale.base_px_per_dp() / $Camera.zoom.x
	var radius: float = maxf(35.2, 18.0 * unit)  # STYLE.md: the tank ring, 18 dp at least.
	var frame: Image = Image.create_empty(64, 64, false, Image.FORMAT_RGBA8)  # Ring: a square frame.
	frame.fill(Color.WHITE)
	frame.fill_rect(Rect2i(4, 4, 56, 56), Color(1.0, 1.0, 1.0, 0.0))
	var ring_texture: ImageTexture = ImageTexture.create_from_image(frame)
	var atlas: Image = Image.create_empty(64, 16, false, Image.FORMAT_RGBA8)  # Four 16 px cells.
	for cell: int in 4:
		atlas.fill_rect(Rect2i(cell * 16, 0, 16, 16), Color.from_hsv(0.15 * cell, 0.8, 1.0))
	_atlas = ImageTexture.create_from_image(atlas)
	for i: int in UNITS:
		var rig: Node2D = Node2D.new()
		for k: int in 3:  # Hull, team and turret.
			var art: String = ["hull", "team", "turret"][k]
			var sprite: Sprite2D = _sprite(load(ART % art), k + 2)
			rig.add_child(sprite)
		if i < SIDE:  # The 75 selected units are player 0's; both rings exist, one shows.
			var ring: Sprite2D = _sprite(ring_texture, 1)
			ring.scale = Vector2.ONE * radius / 28.0
			var code_ring: UnitLayer.Ring = UnitLayer.Ring.new()
			code_ring.radius = radius
			code_ring.unit = unit
			code_ring.z_index = 1
			code_ring.z_as_relative = false
			rig.add_child(ring)
			rig.add_child(code_ring)
			_rings.append_array([ring, code_ring])
		add_child(rig)
		_rigs.append(rig)
	for z: int in [5, 6, 7]:
		var layer: Painted = Painted.new()
		layer.painter = [_paint_bars, _paint_projectiles, _paint_effects][z - 5]
		layer.z_index = z
		layer.z_as_relative = false
		add_child(layer)
		_layers.append(layer)
	_apply_mode()
	_fog_image.fill(Color.BLACK)
	_fog_texture = ImageTexture.create_from_image(_fog_image)
	var fog: Sprite2D = _sprite(_fog_texture, 8)
	fog.centered = false
	fog.scale = Vector2.ONE * ViewScale.PX_PER_TILE
	fog.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(fog)
	_patch_fog()
	_back.pressed.connect(DevRoutes.open.bind(get_tree(), DevRoutes.DEV_MENU_SCENE))
	_rings_button.pressed.connect(_next_mode)
	_copy_button.pressed.connect(_copy_report)
	get_viewport().size_changed.connect(_apply_dp)
	_apply_dp()
	_last_us = Time.get_ticks_usec()
	_start_run()


func _draw() -> void:
	draw_rect(Rect2(0.0, 0.0, 64.0 * COLS, 64.0 * COLS), Color("6F8F57"))


func _process(_delta: float) -> void:
	var now: int = Time.get_ticks_usec()
	var interval: int = now - _last_us
	_last_us = now
	# The engine counters describe the frame before this one, so the tick flag does too.
	var process_ms: float = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var render_ms: float = RenderingServer.viewport_get_measured_render_time_cpu(_viewport)
	_record(Series.INTERVAL, interval / 1000.0)
	_record(Series.PROCESS, process_ms)
	_record(Series.RENDER, render_ms)
	_record(Series.CALLS, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	_record(Series.WORK_TICK if _prev_ticked else Series.WORK_OTHER, process_ms + render_ms)
	_clock_us += interval
	_prev_ticked = false
	for _step: int in 4:  # At most four ticks a frame; time beyond that is dropped.
		if _clock_us < TICK_USEC:
			break
		_clock_us -= TICK_USEC
		_prev_x = sim.x.duplicate()
		_prev_y = sim.y.duplicate()
		_record(Series.TICK, sim.step() / 1000.0)
		_record(Series.SLICE, sim.flow_slice(FLOW_CELLS) / 1000.0 if sim.tick % 15 == 0 else -1.0)
		_record(Series.FOG, _patch_fog() if sim.tick % 3 == 0 else -1.0)  # 5 Hz.
		_prev_ticked = true
	_clock_us = _clock_us if _clock_us < TICK_USEC else 0
	for i: int in UNITS:
		var from: Vector2 = ViewScale.milli_to_px_vec(_prev_x[i], _prev_y[i])
		var to: Vector2 = ViewScale.milli_to_px_vec(sim.x[i], sim.y[i])
		_rigs[i].position = from.lerp(to, float(_clock_us) / TICK_USEC)
	for layer: Painted in _layers:
		layer.queue_redraw()
	if _end_us == 0:
		var left: int = run_seconds - (now - _start_us) / 1000000
		_card.text = "PERF PROBE: running, %d s left.\nLeave the phone alone." % left
		if left <= 0:
			_end_us = now
			_card.text = report()
			_rings_button.visible = true
			_copy_button.visible = true
			_copy_button.text = "Copy report"


## The plain-text report: the card shows it and "Copy report" puts it on the clipboard.
func report() -> String:
	var frames: int = _series[Series.INTERVAL].size()
	var on_time: int = 0
	for ms: float in _series[Series.INTERVAL]:
		on_time += int(ms <= ON_TIME_MS)
	var seconds: float = ((_end_us if _end_us > 0 else _last_us) - _start_us) / 1e6
	var build: String = "debug" if OS.is_debug_build() else "release"
	var engine: String = "%s %s" % [Engine.get_version_info()["string"], build]
	var screen: Vector2i = DisplayServer.screen_get_size()
	var hz: float = DisplayServer.screen_get_refresh_rate()
	var refresh: String = "%.0f Hz" % hz if hz > 0.0 else "unknown"
	var share: float = 100.0 * on_time / maxi(frames, 1)
	var lines: PackedStringArray = [
		"PERF PROBE P26s | %s | %s" % [MODES[mode], "done" if _end_us > 0 else "running"],
		"device %s | %s | Godot %s" % [OS.get_model_name(), OS.get_name(), engine],
		"screen %s px | refresh %s | max_fps %d" % [screen, refresh, Engine.max_fps],
		"frames %d in %.1f s | on time (<= 17.5 ms) %.1f %%" % [frames, seconds, share],
		_row("frame interval (wall clock)", Series.INTERVAL, "ms"),
		_row("process (TIME_PROCESS)", Series.PROCESS, "ms"),
		_row("render CPU (viewport time)", Series.RENDER, "ms"),
		_row("draw calls (monitor, HUD in)", Series.CALLS, "calls"),
		_row("work, tick frames (process + render)", Series.WORK_TICK, "ms"),
		_row("work, other frames (process + render)", Series.WORK_OTHER, "ms"),
		_row("mock tick (15 Hz, usec timer)", Series.TICK, "ms"),
		_row("flow slice %d cells (usec timer)" % FLOW_CELLS, Series.SLICE, "ms"),
		_row("fog patch (set_pixel + update, 5 Hz)", Series.FOG, "ms"),
	]
	return "\n".join(lines)


func _row(label: String, series: int, unit: String) -> String:
	var v: PackedFloat64Array = _series[series]
	var p95: float = PerfProbeTick.percentile(v, 95)
	var peak: float = PerfProbeTick.percentile(v, 100)
	var mean: float = PerfProbeTick.mean(v)
	return "%s: p95 %.2f, mean %.2f, max %.2f %s" % [label, p95, mean, peak, unit]


## Appends to a series while the run goes on; a negative value means "no sample".
func _record(series: int, value: float) -> void:
	if _end_us == 0 and value >= 0.0:
		_series[series].append(value)


func _start_run() -> void:
	for values: PackedFloat64Array in _series:
		values.clear()
	_start_us = Time.get_ticks_usec()
	_end_us = 0
	_rings_button.visible = false
	_copy_button.visible = false


func _next_mode() -> void:
	mode = (mode + 1) % MODES.size()
	_apply_mode()
	_start_run()


## Shows one kind of ring and tints the Team layers by team, grouped or alternating.
func _apply_mode() -> void:
	for ring: Node2D in _rings:
		ring.visible = (ring is Sprite2D) != (mode == Mode.CODE_RINGS)
	for i: int in UNITS:
		var team: int = i % 2 if mode == Mode.ALTERNATING_TINTS else i / SIDE
		_rigs[i].get_child(1).modulate = Color("2F80ED") if team == 0 else Color("E5484D")


func _copy_report() -> void:
	var text: String = report()
	clipboard_sink.call(text)
	_copy_button.text = "Copied (%d chars)" % text.length()


func _apply_dp() -> void:
	var backdrop: StyleBoxFlat = StyleBoxFlat.new()
	backdrop.bg_color = Color(0.0, 0.0, 0.0, 0.55)
	_card.add_theme_stylebox_override("normal", backdrop)
	_card.add_theme_font_size_override("font_size", roundi(UiScale.dp(14.0)))
	for button: Button in [_back, _rings_button, _copy_button]:
		button.custom_minimum_size = UiScale.dp_vec(96.0, 56.0)
		button.add_theme_font_size_override("font_size", roundi(UiScale.dp(16.0)))


## Sets the pixels of the cells whose sight flipped, uploads the image and returns ms.
func _patch_fog() -> float:
	var started: int = Time.get_ticks_usec()
	for k: int in sim.dirty_count:
		var cell: int = sim.dirty[k]
		var alpha: float = 0.0 if sim.seen[cell] > 0 else 140.0 / 255.0
		_fog_image.set_pixel(cell % COLS, cell / COLS, Color(0.0, 0.0, 0.0, alpha))
	sim.dirty_count = 0
	_fog_texture.update(_fog_image)
	return (Time.get_ticks_usec() - started) / 1000.0


func _sprite(texture: Texture2D, z: int) -> Sprite2D:
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = texture
	sprite.z_index = z
	sprite.z_as_relative = false
	return sprite


func _quad(canvas: CanvasItem, at: Vector2, half: float, cell: int, alpha: float) -> void:
	var to: Rect2 = Rect2(at - Vector2(half, half), Vector2(half, half) * 2.0)
	canvas.draw_texture_rect_region(
		_atlas, to, Rect2(cell * 16.0, 0.0, 16.0, 16.0), Color(1, 1, 1, alpha)
	)


func _paint_bars(canvas: CanvasItem) -> void:
	for i: int in UNITS:
		var at: Vector2 = _rigs[i].position + Vector2(-20.0, -40.0)
		var full: float = 0.25 + 0.75 * ((i * 7) % 10) / 9.0
		canvas.draw_rect(Rect2(at, Vector2(40.0, 6.0)), Color(0.0, 0.0, 0.0, 0.6))
		var fill: Color = Color("3FB950") if i % 2 == 0 else Color("D29922")
		canvas.draw_rect(Rect2(at, Vector2(40.0 * full, 6.0)), fill)


func _paint_projectiles(canvas: CanvasItem) -> void:
	var flight: float = (Time.get_ticks_msec() % 1000) / 1000.0
	for k: int in 60:
		var to: int = sim.target[k] if sim.target[k] >= 0 else k
		var at: Vector2 = _rigs[k].position.lerp(
			_rigs[to].position, fposmod(flight + k * 0.07, 1.0)
		)
		_quad(canvas, at, 12.0, 0, 1.0)


func _paint_effects(canvas: CanvasItem) -> void:
	var age: float = (Time.get_ticks_msec() % 1000) / 1000.0
	for e: int in 128:
		var life: float = fposmod(age + e * 0.013, 1.0)
		_quad(canvas, _rigs[e].position, 8.0 + 14.0 * life, 1 + e % 3, 1.0 - life)
