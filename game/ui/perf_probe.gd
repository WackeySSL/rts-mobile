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
## The fifth mode (spike P26n, never merged) is the fourth with the worker running the C++ port of
## the tick (the GDExtension class ProbeTickNative, native/probe_tick) instead of PerfProbeTick. It
## first plays 60 ticks of both in lockstep and reports whether they matched, then brings the C++
## tick to the tick `sim` stands at, so that it times the same stretch of the deterministic tick
## sequence as the other modes. Every mode prints the tick it started at.
## Without the library (no build, or the web preview) the mode says so and measures nothing.
## Spike P26n2 (ADR 0014 section 5, never merged) adds the calibration rows: every mode starts from
## a fresh tick at `START_TICK` (mode 5's C++ tick too), so all modes time ticks 3-903 in 60 s;
## before every run a 400 ms burst of the reference loop gives `ref_peak`; every timed frame starts
## with a discarded warm-up run and its ref sample, both outside the frame's work; the card prints
## the pacing rows (PerfProbeCalib) and the raw, class-method and per-frame normalised main-thread
## times, and the report ends with a CALIBRATION block of the values checks C1-C5 need.

@warning_ignore_start("integer_division")

enum Mode { SPRITE_RINGS, CODE_RINGS, ALTERNATING_TINTS, WORKER_TICK, NATIVE_TICK }
enum Series {
	INTERVAL,
	PROCESS,
	RENDER,
	CALLS,
	WORK_TICK,
	WORK_OTHER,
	TICK,
	SLICE,
	FOG,
	LATENCY,
	WARMUP,  ## P26n2: the discarded warm-up run of every timed frame, usec.
	WORK_TICK_REF,  ## The frame's ref sample (usec) of every WORK_TICK value, and so on.
	WORK_OTHER_REF,
	TICK_REF,
	FOG_REF,
}
## The worker job, as ADR 0012 section 1: nothing posted, posted and not taken, taken and not
## published.
enum Job { IDLE, RUNNING, FINISHED }

const ART: String = "res://assets/art/svg/units/light_tank_%s.svg"
const UNITS: int = PerfProbeTick.UNITS
const COLS: int = PerfProbeTick.COLS
const SIDE: int = PerfProbeTick.SIDE
const TICK_USEC: int = 66667  ## 15 Hz.
const FLOW_CELLS: int = 512
const CHECK_TICKS: int = 60  ## Mode 5's lockstep self-check, not timed.
const START_TICK: int = 3  ## P26n2: every mode starts from a fresh tick here (its warm-up ticks).
const NATIVE_MISSING: String = "C++ tick not available on this build"
const MODES: Array[String] = [
	"sprite rings",
	"code rings",
	"sprite rings, tints alternate",
	"sprite rings, worker tick",
	"sprite rings, C++ worker tick",
]

var run_seconds: int = 60
var mode: int = Mode.SPRITE_RINGS  ## Code rings are the Phase 1 ones; the tint order is by team.
var clipboard_sink: Callable = DisplayServer.clipboard_set
## The worker mode hands it to the worker. Swap it before the node enters the tree, not after.
var sim: PerfProbeTick = PerfProbeTick.new()
## The GDExtension class mode 5 runs; a test swaps it for a name that is not registered.
var native_class: String = PerfProbeLockstep.NATIVE_CLASS
## P26n2: makes the fresh tick every later mode starts from (the first mode runs `sim` as set); a
## test that swaps `sim` swaps this too.
var new_sim: Callable = func() -> PerfProbeTick: return PerfProbeTick.new()
## One reference run in usec (ADR 0014 section 3), for the burst and the per-frame samples.
var ref_sampler: Callable = PerfProbeCalib.ref_usec
var burst_usec: int = PerfProbeCalib.BURST_USEC  ## Tests shorten it; the phone run never does.
## Mode 5's C++ tick, owned by the worker while it runs. A RefCounted, never a ProbeTickNative:
## that class does not exist (and a typed variable would not parse) without the library.
var native: RefCounted = null

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
var _runner: RefCounted = null  ## Who the worker ticks: `sim`, or `native`; set before it starts.
var _start_tick: int = 0  ## The tick the worker's runner stood at when the worker started.
var _check: String = ""  ## Mode 5's self-check result line.
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
var _ref_peak: PackedFloat64Array = PackedFloat64Array()  ## The burst's kept second half, usec.
var _frame_ref_us: float = 0.0  ## This frame's ref sample, taken after the warm-up run.
var _sampled: bool = false  ## This frame's `_process` ran in the run and took the ref runs.
var _refresh_start: float = 0.0  ## `screen_get_refresh_rate()` at run start and at run end.
var _refresh_end: float = 0.0

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
	_fog_texture = ImageTexture.create_from_image(_fog_image)
	var fog: Sprite2D = _sprite(_fog_texture, 8)
	fog.centered = false
	fog.scale = Vector2.ONE * ViewScale.PX_PER_TILE
	fog.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(fog)
	_apply_mode()  # Resets the fog image to `sim`'s.
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
	var interval: int = now - _last_us
	_last_us = now
	_sampled = _end_us == 0
	if _sampled:  # ADR 0014 section 3: a discarded warm-up run, then the frame's ref sample.
		_record(Series.WARMUP, float(ref_sampler.call()))
		_frame_ref_us = float(ref_sampler.call())
	_process_start_us = Time.get_ticks_usec()  # The frame's work starts after both ref runs.
	_record(Series.INTERVAL, interval / 1000.0)
	_clock_us += interval
	_ticked = false
	if _thread != null:
		_tick_worker()
	elif mode == Mode.NATIVE_TICK:  # Mode 5 without the library: nothing ticks.
		_clock_us = 0
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
		_card.text = (
			"PERF PROBE: running, %d s left.\nLeave the phone alone.\n%s" % [left, _impl_text()]
		)
		if left <= 0:
			_end_us = now
			_refresh_end = DisplayServer.screen_get_refresh_rate()
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
		_record_ref(Series.TICK, sim.step() / 1000.0, Series.TICK_REF)
		if sim.tick % 15 == 0:
			var elapsed: int = sim.flow_slice(FLOW_CELLS)
			# A field's last slice is short; it would pull the mean down.
			_record(Series.SLICE, elapsed / 1000.0 if sim.slice_cells == FLOW_CELLS else -1.0)
		_record_ref(Series.FOG, _patch_fog() if sim.tick % 3 == 0 else -1.0, Series.FOG_REF)
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
	var source: RefCounted = _runner  # `sim`, or `native` (its getters return copies).
	_prev_x = _view.x
	_prev_y = _view.y
	_view.x = source.x.duplicate()
	_view.y = source.y.duplicate()
	_view.target = source.target.duplicate()
	var fog_tick: bool = source.tick % 3 == 0  # 5 Hz, as in the in-frame modes.
	if fog_tick:
		_view.seen = source.seen.duplicate()
		_view.dirty = source.dirty.duplicate()
		_view.dirty_count = source.dirty_count
		source.dirty_count = 0
	_record_ref(Series.TICK, _job_tick_usec / 1000.0, Series.TICK_REF)
	_record(Series.SLICE, _job_slice_usec / 1000.0 if _job_slice_usec >= 0 else -1.0)
	_record(Series.LATENCY, (_job_end_us - _post_us) / 1000.0)
	if _end_us == 0 and _job_end_us - _post_us > TICK_USEC:
		_late_ticks += 1
	_record_ref(Series.FOG, _patch_fog() if fog_tick else -1.0, Series.FOG_REF)
	_job = Job.IDLE


func _post_job() -> void:
	_post_us = Time.get_ticks_usec()
	_job = Job.RUNNING
	_work.post()


## The worker thread: sleeps on `_work`, runs one mock tick (and, every 15th, one flow slice),
## stamps the end time and posts `_done`. It touches its runner (`sim` or `native`) and the `_job_*`
## fields only; the two semaphores order every hand-over between the threads.
func _serve() -> void:
	var job: RefCounted = _runner  # Set before the thread started, never changed while it runs.
	while true:
		_work.wait()
		if _quit:
			return
		_job_tick_usec = job.step()  # The usec timer inside the tick body.
		_job_slice_usec = -1
		if job.tick % 15 == 0:
			var elapsed: int = job.flow_slice(FLOW_CELLS)
			_job_slice_usec = elapsed if job.slice_cells == FLOW_CELLS else -1
		_job_end_us = Time.get_ticks_usec()
		_done.post()


## Starts or stops the worker to match `mode`, from `sim` at `START_TICK` (P26n2: `_next_mode` has
## made it fresh; the first mode's is fresh by construction). The view reads `_shown` while the
## worker runs, else `sim`. Mode 5 first plays its self-check and makes a fresh C++ tick; without
## the library it starts nothing and the view stays on `sim`.
func _sync_worker() -> void:
	_stop_worker()  # Safe with no worker; the old runner is ours again.
	native = null
	_check = ""
	PerfProbeLockstep.advance(sim, START_TICK, FLOW_CELLS)  # A fresh tick stands there already.
	_follow_sim()
	_reset_fog()
	_start_tick = sim.tick
	if mode == Mode.NATIVE_TICK:
		if native_available():
			_check = _self_check()
			native = ClassDB.instantiate(native_class)
			_catch_up(native)
			_start_worker(native)
	elif mode == Mode.WORKER_TICK:
		_start_worker(sim)
	_restart_frame_clock()


## True when the C++ tick's class is registered: the library is built and loaded on this platform.
func native_available() -> bool:
	return ClassDB.class_exists(native_class)


## Mode 5, before the measurement and not timed: a fresh GDScript tick and a fresh C++ tick play
## `CHECK_TICKS` ticks in lockstep (the flow slice on every 15th, as in the run) and every state
## array is compared after each call. Returns the report line.
func _self_check() -> String:
	var found: String = PerfProbeLockstep.play(
		PerfProbeTick.new(), ClassDB.instantiate(native_class), CHECK_TICKS, FLOW_CELLS
	)
	_restart_frame_clock()
	if found == "":
		return "C++ matches GDScript: yes (%d ticks)" % CHECK_TICKS
	print("perf probe: C++ differs from GDScript: ", found)
	var at: String = found.get_slice(" ", 1)
	var field: String = PerfProbeLockstep.field_of(found.get_slice(": ", 1))
	return "C++ matches GDScript: NO at tick %s (%s)" % [at, field]


## Mode 5, not timed: plays the fresh C++ tick forward to the tick `sim` stands at, with the cadence
## of every probe mode (a flow slice on every 15th tick, the dirty drain on every 3rd). The tick is
## deterministic, so it then holds the state `sim` holds. Since P26n2 `sim` is fresh at
## `START_TICK`, where a fresh C++ tick stands too, so every mode times ticks 3-903. The dirty list
## is copied from `sim`: the mode's fog reset drained it once, outside any tick, which a replay
## cannot know, and nothing else depends on it.
func _catch_up(cpp: RefCounted) -> void:
	PerfProbeLockstep.advance(cpp, sim.tick, FLOW_CELLS)
	cpp.dirty = sim.dirty.duplicate()
	cpp.dirty_count = sim.dirty_count
	_restart_frame_clock()


## A long call on the main thread (the self-check, the catch-up) must not count as a long frame.
func _restart_frame_clock() -> void:
	_last_us = Time.get_ticks_usec()
	_process_start_us = _last_us


## The implementation lines of the card: who ticks, from which tick, and mode 5's self-check or its
## absence.
func _impl_text() -> String:
	var start: String = "\nstart tick %d (a fresh tick in every mode)" % _start_tick
	if mode != Mode.NATIVE_TICK:
		return "tick impl: GDScript%s%s" % [_from_text(), start]
	if native == null:
		return "tick impl: C++\n%s" % NATIVE_MISSING
	return "tick impl: C++ (%s)%s%s\n%s" % [native.get_build_info(), _from_text(), start, _check]


## ", worker from tick N" in the worker modes, else "". The two worker modes play the same
## deterministic ticks, so the tick a run starts at says which stretch of them it timed.
func _from_text() -> String:
	return ", worker from tick %d" % _start_tick if _worker_mode() else ""


## The frame reads `sim` again, and interpolates from where `sim` stands. Only with no worker.
func _follow_sim() -> void:
	_view = sim
	_prev_x = sim.x.duplicate()
	_prev_y = sim.y.duplicate()


func _start_worker(runner: RefCounted) -> void:
	_runner = runner
	_start_tick = runner.tick
	_work = Semaphore.new()  # Fresh tokens: a joined worker may have left one behind.
	_done = Semaphore.new()
	_quit = false
	_job = Job.IDLE
	_held = false
	_thread = Thread.new()
	if _thread.start(_serve) != OK:
		push_warning("perf probe: the worker thread did not start; staying in the frame")
		_thread = null
		native = null
		mode = Mode.SPRITE_RINGS  # Same picture as the worker mode, the tick back in the frame.
		return
	_shown.x = runner.x.duplicate()  # The worker is asleep until the first post: the runner is ours.
	_shown.y = runner.y.duplicate()
	_shown.target = runner.target.duplicate()
	_shown.seen = runner.seen.duplicate()
	_shown.dirty = runner.dirty.duplicate()
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


## True in the two worker modes, when their worker was started (mode 5 needs the library).
func _worker_mode() -> bool:
	return mode == Mode.WORKER_TICK or (mode == Mode.NATIVE_TICK and native != null)


## True while a started worker thread has not been joined.
func worker_active() -> bool:
	return _thread != null and _thread.is_started()


func _on_pre_draw() -> void:
	_pre_draw_us = Time.get_ticks_usec()


## Files this frame's process and render CPU time under this frame's tick flag, with its ref sample.
## Only a timed frame: one whose `_process` ran in the run.
func _on_post_draw() -> void:
	if not _sampled:
		return
	_sampled = false
	var process_ms: float = (_pre_draw_us - _process_start_us) / 1000.0
	var render_ms: float = RenderingServer.viewport_get_measured_render_time_cpu(_viewport)
	_record(Series.PROCESS, process_ms)
	_record(Series.RENDER, render_ms)
	_record(Series.CALLS, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	if _ticked:
		_record_ref(Series.WORK_TICK, process_ms + render_ms, Series.WORK_TICK_REF)
	else:
		_record_ref(Series.WORK_OTHER, process_ms + render_ms, Series.WORK_OTHER_REF)


## The plain-text report: the card shows it and "Copy report" puts it on the clipboard.
func report() -> String:
	if mode == Mode.NATIVE_TICK and native == null:  # Nothing was measured.
		return "PERF PROBE P26s | %s | not available\n%s" % [MODES[mode], _impl_text()]
	var pace: PerfProbeCalib.Pacing = _pacing()
	var seconds: float = ((_end_us if _end_us > 0 else _last_us) - _start_us) / 1e6
	var build: String = "debug" if OS.is_debug_build() else "release"
	var engine: String = "%s %s" % [Engine.get_version_info()["string"], build]
	var screen: Vector2i = DisplayServer.screen_get_size()
	var lines: PackedStringArray = [
		"PERF PROBE P26s | %s | %s" % [MODES[mode], "done" if _end_us > 0 else "running"],
		_impl_text(),
		"device %s | %s | Godot %s" % [OS.get_model_name(), OS.get_name(), engine],
		(
			"screen %s px | refresh_hz start %.2f, end %.2f | max_fps %d"
			% [screen, _refresh_start, _refresh_end_now(), Engine.max_fps]
		),
		(
			"frames %d in %.1f s | jitter (<= 17.5 ms, diagnostic, was on time) %.1f %%"
			% [pace.frames, seconds, pace.jitter_pct]
		),
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
	if _worker_mode():  # Rows only the worker modes have; the rows above keep their format.
		var ticks: int = _series[Series.TICK].size()
		lines.append(_usec_row())
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
	lines.append_array(_pacing_lines(pace))
	lines.append_array(_cpu_lines())
	lines.append_array(_calibration(pace))
	return "\n".join(lines)


## The refresh rate P and V are computed from: the run start's, or `max_fps` when the platform does
## not report one (headless, -1).
func _pacing_hz() -> float:
	return _refresh_start if _refresh_start > 0.0 else float(maxi(Engine.max_fps, 1))


func _refresh_end_now() -> float:
	return _refresh_end if _end_us > 0 else DisplayServer.screen_get_refresh_rate()


func _pacing() -> PerfProbeCalib.Pacing:
	return PerfProbeCalib.pacing(_series[Series.INTERVAL], _pacing_hz(), Engine.max_fps)


## ADR 0014 sections 1 and 4. The window is the whole timed run: the probe is heavy throughout.
func _pacing_lines(pace: PerfProbeCalib.Pacing) -> PackedStringArray:
	var assumed: String = "" if _refresh_start > 0.0 else " (refresh unknown: max_fps assumed)"
	var slots: PackedInt32Array = pace.slots
	return [
		(
			"pacing, window = the whole timed run (heavy throughout): P %.2f ms, V %.2f ms, drop_ms %.2f%s"
			% [pace.period_ms, pace.slot_ms, pace.drop_ms, assumed]
		),
		(
			"dropped (interval > drop_ms) %d of %d (%.2f %%) | cadence %.2f %% | hitches (>= 66.7 ms) %d"
			% [pace.dropped, pace.frames, pace.dropped_pct, pace.cadence_pct, pace.hitches]
		),
		(
			"interval median %.2f, p99 %.2f, max %.2f ms | extra slots 0/1/2/>=3: %d/%d/%d/%d"
			% [pace.median_ms, pace.p99_ms, pace.max_ms, slots[0], slots[1], slots[2], slots[3]]
		),
		"(extra slots: 0 up to drop_ms, else ceil((interval - drop_ms) / V); P + k V gives k)",
	]


## ADR 0014 sections 3 and 4: `ref_peak`, the warm-up runs, and per main-thread class the raw p95
## next to the class-method and the per-frame normalised p95. The worker's rows above stay raw.
func _cpu_lines() -> PackedStringArray:
	var peak: PackedFloat64Array = _ref_peak
	var warm: PackedFloat64Array = _series[Series.WARMUP]
	var ref: String = (
		"ref loop (%d iterations): ref_peak p25 %.1f, p95 %.1f us"
		% [
			PerfProbeCalib.REF_ITERATIONS,
			PerfProbeTick.percentile(peak, 25),
			PerfProbeTick.percentile(peak, 95),
		]
	)
	var lines: PackedStringArray = [
		(
			ref
			+ (
				" (%d ms burst, second half, n %d) | warm-up p25 %.1f us (n %d, discarded)"
				% [burst_usec / 1000, peak.size(), PerfProbeTick.percentile(warm, 25), warm.size()]
			)
		),
	]
	for row: Array in [
		["all frames, work", _stats_all()],
		["tick frames, work", _stats(Series.WORK_TICK, Series.WORK_TICK_REF)],
		["other frames, work", _stats(Series.WORK_OTHER, Series.WORK_OTHER_REF)],
		["fog patches", _stats(Series.FOG, Series.FOG_REF)],
	]:
		var c: PerfProbeCalib.Stats = row[1]
		var head: String = (
			"cpu %s: n %d, ref_span p25 %.1f us, speed_main %.1f %%"
			% [row[0], c.frames, c.ref_span_us, c.speed_pct]
		)
		var tail: String = (
			" | p95 raw %.3f, norm class %.3f, norm frame %.3f ms"
			% [c.p95_raw, c.p95_class, c.p95_frame]
		)
		lines.append(head + tail)
	if not _worker_mode():
		var t: PerfProbeCalib.Stats = _stats(Series.TICK, Series.TICK_REF)
		lines.append(
			(
				"in-frame tick mean: raw %.3f, norm class %.3f, norm frame %.3f ms"
				% [t.mean_raw, t.mean_class, t.mean_frame]
			)
		)
	return lines


## The values checks C1-C5 of ADR 0014 section 5 need from this mode, one per line, so the lead
## computes them from the four pasted reports. Modes are numbered 1-5 as on the plan.
func _calibration(pace: PerfProbeCalib.Pacing) -> PackedStringArray:
	var peak: PackedFloat64Array = _ref_peak
	var lines: PackedStringArray = [
		"CALIBRATION P26n2 | mode %d (%s) | start_tick %d" % [mode + 1, MODES[mode], _start_tick],
		"C1 refresh_hz_start=%.2f" % _refresh_start,
		"C1 refresh_hz_end=%.2f" % _refresh_end_now(),
		"C1 max_fps=%d" % Engine.max_fps,
		"C1 period_ms=%.3f" % pace.period_ms,
		"C1 median_ms=%.3f" % pace.median_ms,
		"C1 median_floor_ms=%.3f" % (pace.period_ms * PerfProbeCalib.MEDIAN_FLOOR),
		"C2 ref_peak_p25_us=%.1f" % PerfProbeTick.percentile(peak, 25),
		"C2 ref_peak_p95_us=%.1f" % PerfProbeTick.percentile(peak, 95),
		"C2 warmup_p25_us=%.1f" % PerfProbeTick.percentile(_series[Series.WARMUP], 25),
	]
	if mode in [Mode.SPRITE_RINGS, Mode.WORKER_TICK, Mode.NATIVE_TICK]:
		var other: PerfProbeCalib.Stats = _stats(Series.WORK_OTHER, Series.WORK_OTHER_REF)
		lines.append("C3 other_ref_span_us=%.1f" % other.ref_span_us)
		lines.append("C3 other_work_p95_raw_ms=%.3f" % other.p95_raw)
		lines.append("C3 other_work_p95_norm_class_ms=%.3f" % other.p95_class)
		lines.append("C3 other_work_p95_norm_frame_ms=%.3f" % other.p95_frame)
	if mode in [Mode.SPRITE_RINGS, Mode.CODE_RINGS]:
		var tick: PerfProbeCalib.Stats = _stats(Series.TICK, Series.TICK_REF)
		lines.append("C4 tick_ref_span_us=%.1f" % tick.ref_span_us)
		lines.append("C4 tick_mean_raw_ms=%.3f" % tick.mean_raw)
		lines.append("C4 tick_mean_norm_class_ms=%.3f" % tick.mean_class)
		lines.append("C4 tick_mean_norm_frame_ms=%.3f" % tick.mean_frame)
	lines.append("C5 frames=%d" % pace.frames)
	lines.append("C5 dropped=%d" % pace.dropped)
	lines.append("C5 dropped_pct=%.2f" % pace.dropped_pct)
	lines.append("C5 cadence_pct=%.2f" % pace.cadence_pct)
	lines.append("C5 hitches=%d" % pace.hitches)
	if _worker_mode():  # Raw: the worker is never normalised (ADR 0014 section 3).
		var job: PackedFloat64Array = _series[Series.TICK]
		var done: PackedFloat64Array = _series[Series.LATENCY]
		lines.append("C5 job_tick_mean_ms=%.3f" % PerfProbeTick.mean(job))
		lines.append("C5 job_tick_p95_ms=%.3f" % PerfProbeTick.percentile(job, 95))
		lines.append("C5 job_done_mean_ms=%.3f" % PerfProbeTick.mean(done))
		lines.append("C5 job_done_p95_ms=%.3f" % PerfProbeTick.percentile(done, 95))
	return lines


func _stats(work: int, refs: int) -> PerfProbeCalib.Stats:
	return PerfProbeCalib.stats(
		_series[work], _series[refs], PerfProbeTick.percentile(_ref_peak, 25)
	)


## Tick and other frames together.
func _stats_all() -> PerfProbeCalib.Stats:
	var work: PackedFloat64Array = _series[Series.WORK_TICK] + _series[Series.WORK_OTHER]
	var refs: PackedFloat64Array = _series[Series.WORK_TICK_REF] + _series[Series.WORK_OTHER_REF]
	return PerfProbeCalib.stats(work, refs, PerfProbeTick.percentile(_ref_peak, 25))


## The worker's tick and flow slice in microseconds, as the usec timer measured them: the rows in
## ms print two decimals, which is one or two significant digits for a C++ tick.
func _usec_row() -> String:
	var tick: PackedFloat64Array = _series[Series.TICK]
	var slice: PackedFloat64Array = _series[Series.SLICE]
	return (
		"worker tick usec: mean %.1f, p95 %.1f, max %.1f | flow slice usec: mean %.1f, p95 %.1f, max %.1f"
		% [
			PerfProbeTick.mean(tick) * 1000.0,
			PerfProbeTick.percentile(tick, 95) * 1000.0,
			PerfProbeTick.percentile(tick, 100) * 1000.0,
			PerfProbeTick.mean(slice) * 1000.0,
			PerfProbeTick.percentile(slice, 95) * 1000.0,
			PerfProbeTick.percentile(slice, 100) * 1000.0,
		]
	)


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


## `_record`, and this frame's ref sample to `paired` with it, so the two stay parallel.
func _record_ref(series: int, value: float, paired: int) -> void:
	if _end_us == 0 and value >= 0.0:
		_series[series].append(value)
		_series[paired].append(_frame_ref_us)


func _start_run() -> void:
	for values: PackedFloat64Array in _series:
		values.clear()
	_held_ticks = 0
	_late_ticks = 0
	_clock_us = 0
	_rings_button.visible = false
	_copy_button.visible = false
	_refresh_start = DisplayServer.screen_get_refresh_rate()
	_refresh_end = _refresh_start
	_ref_peak = PackedFloat64Array()
	if mode == Mode.NATIVE_TICK and native == null:  # No library: the card says so and stops.
		_start_us = Time.get_ticks_usec()
		_end_us = _start_us + 1
		_card.text = report()
		_rings_button.visible = true
		_copy_button.visible = true
		_copy_button.text = "Copy report"
		return
	# ADR 0014 section 3: the burst, after the mode's reset and before the timed window.
	_ref_peak = PerfProbeCalib.burst(burst_usec, ref_sampler)
	_restart_frame_clock()
	_start_us = _last_us
	_end_us = 0


func _next_mode() -> void:
	mode = (mode + 1) % MODES.size()
	if mode >= Mode.WORKER_TICK and not OS.has_feature("threads"):
		mode = Mode.SPRITE_RINGS  # The web preview has no threads: the cycle skips the worker modes.
	_stop_worker()  # The old runner is ours again; then a fresh tick replaces it (P26n2).
	sim = new_sim.call()
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


## P26n2: the fog image of the mode's fresh tick, all black, then the cells its warm-up ticks
## revealed. This drains the dirty list once, outside any tick and timed window, in every mode.
func _reset_fog() -> void:
	_fog_image.fill(Color.BLACK)
	_fog_bytes = _fog_image.get_data()
	_patch_fog()


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
