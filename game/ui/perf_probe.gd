extends Node2D
## Phone perf probe (plan P26s, ADR 0011 section 5), a throwaway dev scene. At camera zoom 0.75
## with every unit on screen it draws what the Phase 2 view contracts promise, at absolute z:
## 75 rings (1; sprites, or the Phase 1 code-drawn rings), 150 tank rigs (2-4, the real SVGs),
## 150 health bars (5, rects), 60 projectiles (6) and 128 effects (7) as quads of one placeholder
## atlas, a 64x64 fog texture (8) patched at 5 Hz, and the mock tick at 15 Hz in the frame. A run
## of `run_seconds` records the frame; the card is the clipboard report. `Engine.max_fps` is 60
## while the scene is open, so a 90 or 120 Hz panel is judged at 60 fps.
## The fourth mode (ADR 0012 section 1) is mode 1 with each mock tick, and the flow slice, run on
## one dedicated Thread: a tick ahead, handed over by two Semaphores, never blocking the frame.
## The view draws from its own copies, taken at publish, while the worker owns `sim`.

@warning_ignore_start("integer_division")

enum Mode { SPRITE_RINGS, CODE_RINGS, ALTERNATING_TINTS, WORKER_TICK }
enum Series { INTERVAL, PROCESS, RENDER, CALLS, WORK_TICK, WORK_OTHER, TICK, SLICE, FOG, LATENCY }
## The worker job, as ADR 0012 section 1: nothing posted, posted and not taken, taken and not
## published.
enum Job { IDLE, RUNNING, FINISHED }

const ART: String = "res://assets/art/svg/units/light_tank_%s.svg"
const UNITS: int = PerfProbeTick.UNITS
const COLS: int = PerfProbeTick.COLS
const SIDE: int = PerfProbeTick.SIDE
const TICK_USEC: int = 66667  ## 15 Hz.
const FLOW_CELLS: int = 512
const ON_TIME_MS: float = 17.5
const MODES: Array[String] = [
	"sprite rings",
	"code rings",
	"sprite rings, tints alternate",
	"sprite rings, worker tick",
]

var run_seconds: int = 60
var mode: int = Mode.SPRITE_RINGS  ## Code rings are the Phase 1 ones; the tint order is by team.
var clipboard_sink: Callable = DisplayServer.clipboard_set
## The worker mode hands it to the worker. Swap it before the node enters the tree, not after.
var sim: PerfProbeTick = PerfProbeTick.new()

var _rigs: Array[Node2D] = []
var _rings: Array[Node2D] = []  ## Per selected unit: a sprite ring, then a code ring.
var _layers: Array[Painted] = []
var _series: Array[PackedFloat64Array] = []
## What the frame reads: `sim`, or `_shown` in the worker mode. Bound by `_follow_sim()` in
## `_ready`, after any swap of `sim`, so it is never a stale object.
var _view: PerfProbeTick = null
var _shown: PerfProbeTick = PerfProbeTick.new()  ## The worker mode's copies, taken at publish.
var _prev_x: PackedInt32Array = PackedInt32Array()
var _prev_y: PackedInt32Array = PackedInt32Array()
var _atlas: ImageTexture = null
var _fog_image: Image = Image.create_empty(COLS, COLS, false, Image.FORMAT_RGBA8)
var _fog_texture: ImageTexture = null
var _viewport: RID = RID()
var _fog_bytes: PackedByteArray = PackedByteArray()  ## RGBA8 of the fog image, patched in place.
var _max_fps: int = 0
var _kept_on: bool = false
var _last_us: int = 0
var _start_us: int = 0
var _end_us: int = 0  ## 0 while the run goes on.
var _clock_us: int = 0
var _process_start_us: int = 0  ## Top of this frame's `_process`, the first one in the tree.
var _pre_draw_us: int = 0
var _ticked: bool = false  ## This frame ran at least one mock tick (worker: published one).
var _thread: Thread = null
var _work: Semaphore = Semaphore.new()  ## The main thread posts a job; the worker waits.
var _done: Semaphore = Semaphore.new()  ## The worker posts when the job is finished.
var _quit: bool = false  ## Set before the last `_work.post()`; the worker then returns.
var _job: int = Job.IDLE
var _held: bool = false  ## A held tick is waiting for its job to finish.
var _held_ticks: int = 0  ## Boundaries reached with the job running, once per held job.
var _late_ticks: int = 0  ## Jobs whose post to done exceeded `TICK_USEC`, counted at publish.
var _post_us: int = 0  ## Main thread, at the post; read at publish.
var _job_tick_usec: int = 0  ## Worker, from `sim.step()`; read at publish, after `_done`.
var _job_slice_usec: int = -1  ## Worker; -1 when the job ran no whole 512-cell slice.
var _job_end_us: int = 0  ## Worker, before `_done.post()`.

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
	_kept_on = DisplayServer.screen_is_kept_on()
	DisplayServer.screen_set_keep_on(true)  # A 60 s run outlasts the usual screen timeout.
	# Performance.TIME_PROCESS is the slowest frame of the past second, so each frame is timed here:
	# this node processes first, and the frame's process time ends when the server starts to draw.
	process_priority = -1000
	RenderingServer.frame_pre_draw.connect(_on_pre_draw)
	RenderingServer.frame_post_draw.connect(_on_post_draw)


func _exit_tree() -> void:
	_stop_worker()  # Joined before anything else goes away; a running job finishes first.
	Engine.max_fps = _max_fps
	DisplayServer.screen_set_keep_on(_kept_on)
	RenderingServer.frame_pre_draw.disconnect(_on_pre_draw)
	RenderingServer.frame_post_draw.disconnect(_on_post_draw)
	RenderingServer.viewport_set_measure_render_time(_viewport, false)


func _ready() -> void:
	_follow_sim()  # After any swap of `sim`, before the mode decides who reads what.
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
	_fog_bytes = _fog_image.get_data()
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
	_process_start_us = _last_us
	_start_run()


func _draw() -> void:
	var side: float = float(ViewScale.PX_PER_TILE * COLS)
	draw_rect(Rect2(0.0, 0.0, side, side), Color("6F8F57"))


func _process(_delta: float) -> void:
	var now: int = Time.get_ticks_usec()
	_process_start_us = now
	var interval: int = now - _last_us
	_last_us = now
	_record(Series.INTERVAL, interval / 1000.0)
	_clock_us += interval
	_ticked = false
	if mode == Mode.WORKER_TICK:
		_tick_worker()
	else:
		_tick_in_frame()
	for i: int in UNITS:
		var from: Vector2 = ViewScale.milli_to_px_vec(_prev_x[i], _prev_y[i])
		var to: Vector2 = ViewScale.milli_to_px_vec(_view.x[i], _view.y[i])
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


## Modes 0-2: the mock tick, the flow slice and the fog patch run inside the frame.
func _tick_in_frame() -> void:
	for _step: int in 4:  # At most four ticks a frame; time beyond that is dropped.
		if _clock_us < TICK_USEC:
			break
		_clock_us -= TICK_USEC
		_prev_x = sim.x.duplicate()
		_prev_y = sim.y.duplicate()
		_record(Series.TICK, sim.step() / 1000.0)
		if sim.tick % 15 == 0:
			var elapsed: int = sim.flow_slice(FLOW_CELLS)
			# A field's last slice is short; it would pull the mean down.
			_record(Series.SLICE, elapsed / 1000.0 if sim.slice_cells == FLOW_CELLS else -1.0)
		_record(Series.FOG, _patch_fog() if sim.tick % 3 == 0 else -1.0)  # 5 Hz.
		_ticked = true
	_clock_us = _clock_us if _clock_us < TICK_USEC else 0


## The worker mode, one tick ahead (ADR 0012 section 1). At a boundary the main thread publishes
## the finished job, then posts the next one. A boundary reached while the job still runs is a held
## tick: nothing is published or posted, the view keeps the newest state, and the frame goes on. A
## hold is not a late tick: a main-thread hitch holds a quick job too. `_publish` counts late ticks.
func _tick_worker() -> void:
	if _job == Job.RUNNING and _done.try_wait():
		_job = Job.FINISHED
	if _job == Job.IDLE:  # First frame of a run: start the first job, show the current state.
		_clock_us = 0
		_post_job()
		return
	if _clock_us < TICK_USEC:
		return
	if _job == Job.RUNNING:
		if not _held and _end_us == 0:
			_held_ticks += 1
		_held = true
		_clock_us = TICK_USEC  # The newest state stays on screen; the waiting is not caught up.
		return
	_publish()
	# Whole ticks still owed are dropped, only the part of a tick is kept; after a hold, none.
	_clock_us = 0 if _held else _clock_us % TICK_USEC
	_held = false
	_post_job()
	_ticked = true


## Main thread, job finished: the worker is asleep, so `sim` is readable. Takes the view's copies
## (packed arrays copy on write, so the worker's next writes leave these alone) and the timings.
## A late tick (ADR 0012 section 1) is a job whose post to done exceeds the period: the worker
## itself was slow, whatever the main thread was doing.
func _publish() -> void:
	_prev_x = _view.x
	_prev_y = _view.y
	_view.x = sim.x.duplicate()
	_view.y = sim.y.duplicate()
	_view.target = sim.target.duplicate()
	var fog_tick: bool = sim.tick % 3 == 0  # 5 Hz, as in the in-frame modes.
	if fog_tick:
		_view.seen = sim.seen.duplicate()
		_view.dirty = sim.dirty.duplicate()
		_view.dirty_count = sim.dirty_count
		sim.dirty_count = 0
	_record(Series.TICK, _job_tick_usec / 1000.0)
	_record(Series.SLICE, _job_slice_usec / 1000.0 if _job_slice_usec >= 0 else -1.0)
	_record(Series.LATENCY, (_job_end_us - _post_us) / 1000.0)
	if _end_us == 0 and _job_end_us - _post_us > TICK_USEC:
		_late_ticks += 1
	_record(Series.FOG, _patch_fog() if fog_tick else -1.0)
	_job = Job.IDLE


func _post_job() -> void:
	_post_us = Time.get_ticks_usec()
	_job = Job.RUNNING
	_work.post()


## The worker thread: sleeps on `_work`, runs one mock tick (and, every 15th, one flow slice),
## stamps the end time and posts `_done`. It touches `sim` and the `_job_*` fields only; the two
## semaphores order every hand-over between the threads.
func _serve() -> void:
	while true:
		_work.wait()
		if _quit:
			return
		_job_tick_usec = sim.step()  # The usec timer inside the tick body.
		_job_slice_usec = -1
		if sim.tick % 15 == 0:
			var elapsed: int = sim.flow_slice(FLOW_CELLS)
			_job_slice_usec = elapsed if sim.slice_cells == FLOW_CELLS else -1
		_job_end_us = Time.get_ticks_usec()
		_done.post()


## Starts or stops the worker to match `mode`. The view reads `_shown` while the worker runs and
## goes back to `sim` when it is joined.
func _sync_worker() -> void:
	if mode == Mode.WORKER_TICK:
		_start_worker()
	elif _thread != null:
		_stop_worker()
		_follow_sim()


## The frame reads `sim` again, and interpolates from where `sim` stands. Only with no worker.
func _follow_sim() -> void:
	_view = sim
	_prev_x = sim.x.duplicate()
	_prev_y = sim.y.duplicate()


func _start_worker() -> void:
	_work = Semaphore.new()  # Fresh tokens: a joined worker may have left one behind.
	_done = Semaphore.new()
	_quit = false
	_job = Job.IDLE
	_held = false
	_thread = Thread.new()
	if _thread.start(_serve) != OK:
		push_warning("perf probe: the worker thread did not start; staying in the frame")
		_thread = null
		mode = Mode.SPRITE_RINGS  # Same picture as the worker mode, the tick back in the frame.
		return
	_shown.x = sim.x.duplicate()  # The worker is asleep until the first post: `sim` is ours.
	_shown.y = sim.y.duplicate()
	_shown.target = sim.target.duplicate()
	_shown.seen = sim.seen.duplicate()
	_shown.dirty = sim.dirty.duplicate()
	_shown.dirty_count = 0
	_view = _shown
	_prev_x = _shown.x
	_prev_y = _shown.y


## Joins the worker: any job in flight finishes first. Safe to call twice or with no worker.
func _stop_worker() -> void:
	if _thread != null and _thread.is_started():
		_quit = true
		_work.post()
		_thread.wait_to_finish()
	_thread = null
	_job = Job.IDLE
	_held = false


## True while a started worker thread has not been joined.
func worker_active() -> bool:
	return _thread != null and _thread.is_started()


func _on_pre_draw() -> void:
	_pre_draw_us = Time.get_ticks_usec()


## Files this frame's process and render CPU time under this frame's tick flag.
func _on_post_draw() -> void:
	var process_ms: float = (_pre_draw_us - _process_start_us) / 1000.0
	var render_ms: float = RenderingServer.viewport_get_measured_render_time_cpu(_viewport)
	_record(Series.PROCESS, process_ms)
	_record(Series.RENDER, render_ms)
	_record(Series.CALLS, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	_record(Series.WORK_TICK if _ticked else Series.WORK_OTHER, process_ms + render_ms)


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
		_row("process (_process start to draw)", Series.PROCESS, "ms"),
		_row("render CPU (viewport time)", Series.RENDER, "ms"),
		_row("draw calls (monitor, HUD in)", Series.CALLS, "calls"),
		_row("work, tick frames (process + render)", Series.WORK_TICK, "ms"),
		_row("work, other frames (process + render)", Series.WORK_OTHER, "ms"),
		_row("mock tick (15 Hz, usec timer)", Series.TICK, "ms"),
		_row("flow slice %d cells (usec timer)" % FLOW_CELLS, Series.SLICE, "ms"),
		_row("fog patch (bytes + set_data + update, 5 Hz)", Series.FOG, "ms"),
	]
	if mode == Mode.WORKER_TICK:  # Rows only this mode has; the rows above keep their format.
		var ticks: int = _series[Series.TICK].size()
		lines.append(
			(
				"late ticks (job post to done above %.1f ms): %d of %d ticks"
				% [TICK_USEC / 1000.0, _late_ticks, ticks]
			)
		)
		lines.append(
			(
				"held ticks (boundary reached with the job running): %d of %d ticks"
				% [_held_ticks, ticks]
			)
		)
		lines.append(_row("job post to done (worker wake-up + tick + slice)", Series.LATENCY, "ms"))
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
	_held_ticks = 0
	_late_ticks = 0
	_rings_button.visible = false
	_copy_button.visible = false


func _next_mode() -> void:
	mode = (mode + 1) % MODES.size()
	if mode == Mode.WORKER_TICK and not OS.has_feature("threads"):
		mode = Mode.SPRITE_RINGS  # The web preview has no threads: the cycle skips the worker mode.
	_apply_mode()
	_start_run()


## Shows one kind of ring and tints the Team layers by team, grouped or alternating.
func _apply_mode() -> void:
	for ring: Node2D in _rings:
		ring.visible = (ring is Sprite2D) != (mode == Mode.CODE_RINGS)
	for i: int in UNITS:
		var team: int = i % 2 if mode == Mode.ALTERNATING_TINTS else i / SIDE
		_rigs[i].get_child(1).modulate = Color("2F80ED") if team == 0 else Color("E5484D")
	_sync_worker()


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


## Patches the alpha byte of the cells whose sight flipped, uploads the image and returns ms.
func _patch_fog() -> float:
	var started: int = Time.get_ticks_usec()
	for k: int in _view.dirty_count:  # ADR 0010 section 2: patch the alpha bytes, then upload.
		var cell: int = _view.dirty[k]
		_fog_bytes[cell * 4 + 3] = 0 if _view.seen[cell] > 0 else 140
	_view.dirty_count = 0
	_fog_image.set_data(COLS, COLS, false, Image.FORMAT_RGBA8, _fog_bytes)
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
		var to: int = _view.target[k] if _view.target[k] >= 0 else k
		var at: Vector2 = _rigs[k].position.lerp(
			_rigs[to].position, fposmod(flight + k * 0.07, 1.0)
		)
		_quad(canvas, at, 12.0, 0, 1.0)


func _paint_effects(canvas: CanvasItem) -> void:
	var age: float = (Time.get_ticks_msec() % 1000) / 1000.0
	for e: int in 128:
		var life: float = fposmod(age + e * 0.013, 1.0)
		_quad(canvas, _rigs[e].position, 8.0 + 14.0 * life, 1 + e % 3, 1.0 - life)
