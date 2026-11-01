extends GdUnitTestSuite
## The main scene on the worker thread, headless (ADR 0012 sections 1 to 3, ADR 0013 section 3,
## plan P50w). P50b is the first PR that runs a scene on the worker, so this suite runs
## `scenes/main.tscn` twice first, in one process: the reference with `tick_mode` SYNC and the
## candidate with WORKER, each set on the runner before the scene's _ready, which starts the match.
## The suite drives each instance with direct `_process` calls of exactly one tick period (the
## runner first, then every other node that has a `_process`, in tree order) and no engine frame
## between two calls, because no case awaits and every node's own processing is off. After each
## call of the candidate it waits through wait_idle(), so the clock rule alone decides which ticks
## publish, not the machine's speed, and the reference catches up to the candidate's published tick.
## The layers run while the job is in flight, so a layer that reads `runner.world`, `loop`,
## `replay` or `probe` there meets the runner's guard (an ERROR), and a write to an in-tree Node
## from the worker is refused by the debug build with an ERROR too; both are caught by the log scan
## that every case ends with, as is any other error or script error the engine logs.
## One order script plays in both: all 30 blue tanks attack-move toward the red group at tile
## (34, 10) while four of its tanks come out to meet them, five blue tanks stop, half of them move
## on, so that the rigs turn and move, the fog opens, shots fly and tanks die. The orders go
## through the real CommandQueue, each one just before the frame that drains it, so the two
## runners never share a queue entry. A command is stamped with the number of frames the instance
## made before it (the refill frame counts: it posts the job of tick 1), which is the same stamp
## in both modes.
## Per published tick the cases compare the rig count and names, every rig's position, visibility
## and Hull, Team and Turret turns, the fog image and the checkpoints; `ticked` must come from the
## main thread. The WORKER candidate also runs with sim_impl NATIVE against the GDScript reference
## (ADR 0013 section 3: the checkpoints and every view equal), a held tick and a start() during a
## job. The suite waits only through wait_idle() and the gated probe's capped wait_blocked(), and
## every loop that plays frames has a frame budget, so a runner that stops publishing fails the
## case by name where an unbounded loop would hang the job (gdUnit4's case timeout is a scene-tree
## timer and cannot fire inside a synchronous loop).
## The perf arena (plan P52) plays the same way with the card's slow seams replaced (ArenaRig) and
## no order script, for the gate's 900 ticks: the native worker arena against the GDScript sync
## arena at every published tick, and both on the golden checkpoints of data/dev/perf_gate.tres.

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const GatedProbe: GDScript = preload("res://tests/core/gated_probe.gd")
const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const ArenaRig: GDScript = preload("res://tests/ui/support/arena_rig.gd")
const MAIN_SCENE: String = "res://scenes/main.tscn"
const GATE_PATH: String = "res://data/dev/perf_gate.tres"
## The delta of a frame that moves the runner's clock by exactly one tick (the runner rounds it to
## 1_000_000 micro ticks).
const PERIOD: float = 1.0 / Sim.TICK_RATE
const SYNC: int = MatchRunner.TickMode.SYNC
const WORKER: int = MatchRunner.TickMode.WORKER
const GDSCRIPT: int = MatchRunner.SimImpl.GDSCRIPT
const NATIVE: int = MatchRunner.SimImpl.NATIVE
## The published ticks the equality cases play (plan P50w).
const TICKS: int = 300
@warning_ignore("integer_division") const CHECKPOINTS: int = TICKS / Replay.CHECKPOINT_PERIOD
## The scenario's rigs: 30 blue tanks (ids 1 to 30) and 10 red.
const UNITS: int = 40
const BLUE_UNITS: int = 30
## The orders of the run, by stamp: where blue goes, which tanks stop and which move on.
const ATTACK_AT: int = 3
const STOP_AT: int = 60
const MOVE_AT: int = 150
const STOPPED_UNITS: int = 5
const MOVED_UNITS: int = 15
const GOAL: Vector2i = Vector2i(34000, 10000)
const DETOUR: Vector2i = Vector2i(26000, 14000)
## Red's group at tile (34, 10) (ids 31 to 34) goes out to meet blue at the same stamp, so the
## armies close from both sides and the first shots come early in the run.
const RED_FIRST: int = 31
const RED_UNITS: int = 4
const MEETING: Vector2i = Vector2i(24000, 14000)
## The held case holds the job of this tick, keeps the candidate in the hold for HOLD_FRAMES
## frames (the first one reaches the boundary) and plays AFTER_RESUME frames once it is released.
## A held frame posts nothing, so the candidate's frame count runs ahead of its stamps after a
## hold: the orders lie outside that case's frames (HELD_TICK - 2 to HELD_TICK + 11).
const HELD_TICK: int = 30
const HOLD_FRAMES: int = 3
const AFTER_RESUME: int = 8
## The restart case plays RESTART_AT ticks, starts a job that takes JOB_MSEC, restarts the match
## during it and plays the new match to the checkpoint at tick 15.
const RESTART_AT: int = 40
const JOB_MSEC: int = 30
const CHECKPOINT_TICK: int = Replay.CHECKPOINT_PERIOD
## Frames a play may take beyond one per tick: the refill frame of a WORKER start, which publishes
## nothing, and one more.
const SLACK_FRAMES: int = 2

var _scenes: Array[MainScene] = []
var _probes: Array[SimProbe] = []
var _scan: LogScan
var _workers_before: int = 0
var _max_fps_before: int = 0


## The errors the engine logs while a case plays, from any thread: the lines scripts/verify.sh scans
## for (SCRIPT ERROR, ERROR:, Parse Error). Warnings are not in that scan.
class LogScan:
	extends Logger

	var _mutex: Mutex = Mutex.new()
	var _hits: PackedStringArray = PackedStringArray()

	func hits() -> PackedStringArray:
		_mutex.lock()
		var copy: PackedStringArray = _hits.duplicate()
		_mutex.unlock()
		return copy

	func _log_error(
		_function: String,
		file: String,
		line: int,
		code: String,
		rationale: String,
		_editor_notify: bool,
		error_type: int,
		_script_backtraces: Array[ScriptBacktrace]
	) -> void:
		if error_type != Logger.ERROR_TYPE_WARNING:
			_mutex.lock()
			_hits.append("%s:%d %s %s" % [file, line, code, rationale])
			_mutex.unlock()


## One instance of the main scene, played frame by frame. `published` lists the ticks of its
## runner's `ticked` since the last restart, `off_main` the ones that did not come from the main
## thread.
class MainScene:
	extends RefCounted

	var main: Node2D
	var runner: MatchRunner
	var units: UnitLayer
	var fog: FogLayer
	var published: Array[int] = []
	var off_main: int = 0
	var frames: int = 0
	## Whether the order script plays (the main scene); the arena's orders are its scenario's.
	var scripted: bool = true
	## The rigs the scene starts with.
	var rigs_at_start: int = 0
	## Frames in which a job was in flight when the layers ran (every WORKER frame, no SYNC one).
	var in_flight_frames: int = 0
	var _nodes: Array[Node] = []

	## Puts the scene under `parent` with `mode` and `impl` set on its runner before _ready, which
	## starts the match, and turns the processing of every node off: only frame() runs them. The
	## scene is main.tscn, or `root` (an instance not yet in the tree) when one is given.
	func open(parent: Node, mode: int, impl: int, root: Node2D = null) -> void:
		main = root if root != null else (load(MAIN_SCENE) as PackedScene).instantiate() as Node2D
		runner = main.get_node("MatchRunner") as MatchRunner
		runner.tick_mode = mode
		runner.sim_impl = impl
		runner.ticked.connect(_on_ticked)
		parent.add_child(main)
		units = main.get_node("UnitLayer") as UnitLayer
		fog = main.get_node("FogLayer") as FogLayer
		runner.set_process(false)
		for node: Node in main.find_children("*", "", true, false):
			if node.is_processing():
				_nodes.append(node)
				node.set_process(false)
		if main.is_processing():  # The arena's root follows the runner, before the layers.
			_nodes.push_front(main)
			main.set_process(false)
		rigs_at_start = units.rig_count()

	## One frame of exactly a tick period: the orders stamped with the frame number, the runner,
	## then the other nodes. A WORKER runner has a job in flight when the layers run.
	func frame() -> void:
		if scripted:
			for command: Command in orders(frames):
				CommandQueue.submit(command)
		frames += 1
		runner._process(PERIOD)
		if runner.job_in_flight():
			in_flight_frames += 1
		for node: Node in _nodes:
			node.call(&"_process", PERIOD)

	## One frame of every node but the runner at the delta 0, as the engine's first frame draws the
	## snapshot of tick 0: the runner does not tick.
	func draw_first_frame() -> void:
		for node: Node in _nodes:
			node.call(&"_process", 0.0)

	## frame(), then wait_idle(): false when the wait reached its cap.
	func step() -> bool:
		frame()
		return runner.wait_idle()

	## Starts a new match in place (the "Run again" path); the frame count starts again too.
	func restart() -> void:
		runner.start()
		frames = 0
		in_flight_frames = 0
		published.clear()
		off_main = 0

	func tick() -> int:
		return runner.snapshot.tick

	func close() -> void:
		if is_instance_valid(main):
			main.free()

	## The instance ids of the rig nodes, in row order.
	func rig_ids() -> Array[int]:
		var ids: Array[int] = []
		for rig: Node in units.world_sort.get_children():
			ids.append(rig.get_instance_id())
		return ids

	func positions() -> PackedVector2Array:
		var found: PackedVector2Array = PackedVector2Array()
		for rig: Node2D in units.world_sort.get_children():
			found.append(rig.position)
		return found

	## The checkpoints (tick, hash) up to the published tick, from the replay. Only when no job runs.
	func checkpoints() -> Array[int]:
		var found: Array[int] = []
		var replay: Replay = runner.replay
		for at: int in replay.checkpoint_ticks.size():
			if replay.checkpoint_ticks[at] <= tick():
				found.append(replay.checkpoint_ticks[at])
				found.append(replay.checkpoint_hashes[at])
		return found

	## The first way `other` shows something else than this scene at the same published tick, or "".
	func diff(other: MainScene) -> String:
		var where: String = "tick %d: " % tick()
		var found: String = _header_diff(other)
		if found.is_empty() and units.rig_count() != other.units.rig_count():
			found = "rig count %d against %d" % [units.rig_count(), other.units.rig_count()]
		var rows: int = units.rig_count() if found.is_empty() else 0
		for row: int in rows:
			found = _rig_diff(row, other)
			if not found.is_empty():
				break
		if found.is_empty() and fog.image().get_data() != other.fog.image().get_data():
			found = "fog image"
		return "" if found.is_empty() else where + found

	## The tick, the last hash and, when no job runs in either, the checkpoints.
	func _header_diff(other: MainScene) -> String:
		if tick() != other.tick():
			return "published tick %d against %d" % [tick(), other.tick()]
		if runner.snapshot.last_hash != other.runner.snapshot.last_hash:
			return "last_hash"
		var idle: bool = not runner.job_in_flight() and not other.runner.job_in_flight()
		if idle and checkpoints() != other.checkpoints():
			return "checkpoints"
		return ""

	func _rig_diff(row: int, other: MainScene) -> String:
		var rig: Node2D = units.rig(row)
		var twin: Node2D = other.units.rig(row)
		if rig.name != twin.name:
			return "rig %s against %s" % [rig.name, twin.name]
		if rig.position != twin.position or rig.visible != twin.visible:
			return "rig %s position or visibility" % rig.name
		if turns(row) != other.turns(row):
			return "rig %s hull or turret turn" % rig.name
		if shown_frames(rig) != other.shown_frames(twin):
			return "rig %s frames" % rig.name
		return ""

	## The angles the hull and the turret of row `row` show (0 for a type without a turret).
	func turns(row: int) -> Vector2:
		var has_turret: bool = units.rig(row).has_node("Turret")
		return Vector2(units.heading(row), units.turret_angle(row) if has_turret else 0.0)

	## The region of each sprite of a rig, in child order: the frames it shows.
	func shown_frames(rig: Node2D) -> Array[Rect2]:
		var found: Array[Rect2] = []
		for sprite: Sprite2D in rig.find_children("*", "Sprite2D", false, false):
			found.append(sprite.region_rect)
		return found

	## The orders stamped `stamp`: blue attack-moves at ATTACK_AT, five tanks stop at STOP_AT and
	## fifteen move on to a point on the way at MOVE_AT.
	static func orders(stamp: int) -> Array[Command]:
		var found: Array[Command] = []
		if stamp == ATTACK_AT:
			found.append(Command.attack_move(1, _ids(BLUE_UNITS), GOAL.x, GOAL.y))
			var red: PackedInt32Array = PackedInt32Array(range(RED_FIRST, RED_FIRST + RED_UNITS))
			found.append(Command.attack_move(2, red, MEETING.x, MEETING.y))
		elif stamp == STOP_AT:
			found.append(Command.stop(1, _ids(STOPPED_UNITS)))
		elif stamp == MOVE_AT:
			found.append(Command.move(1, _ids(MOVED_UNITS), DETOUR.x, DETOUR.y))
		return found

	static func _ids(count: int) -> PackedInt32Array:
		return PackedInt32Array(range(1, count + 1))

	func _on_ticked(tick_number: int) -> void:
		published.append(tick_number)
		if OS.get_thread_caller_id() != OS.get_main_thread_id():
			off_main += 1


func before_test() -> void:
	MenuRig.begin()
	CommandQueue.clear()
	_workers_before = MatchRunner.live_workers()
	_max_fps_before = Engine.max_fps
	_scan = LogScan.new()
	OS.add_logger(_scan)


## Releases every gated probe, waits for every runner so no worker is left holding a job, frees
## the scenes (which joins their workers), and asserts that nothing matches the error scan, that
## no job began before the one before it ended, that no hold reached its cap, that every worker
## is joined and that the frame cap is as it was (an arena sets it while it is in the tree). The
## scenes go in the reverse order of their opening, so each arena puts back the cap that it found.
## The logger and the queue are global and must not outlive the case.
func after_test() -> void:
	MenuRig.end()
	for probe: SimProbe in _probes:
		probe.release()
	for scene: MainScene in _scenes:
		if is_instance_valid(scene.main):
			assert_bool(scene.runner.wait_idle()).is_true()
	for at: int in range(_scenes.size() - 1, -1, -1):
		_scenes[at].close()
	for probe: SimProbe in _probes:
		assert_array([probe.overlapped, probe.gave_up]).is_equal([false, false])
	assert_int(MatchRunner.live_workers()).is_equal(_workers_before)
	assert_int(Engine.max_fps).is_equal(_max_fps_before)
	assert_array(_scan.hits()).is_empty()
	OS.remove_logger(_scan)
	_probes.clear()
	_scenes.clear()
	CommandQueue.clear()


## The worker scene and the sync scene show the same at every published tick up to 300: the rigs,
## the fog image, the last hash and the checkpoints. `ticked` came from the main thread, once per
## tick, and the WORKER clock never held a tick or rebuilt the fog for a gap (P47's rule).
func test_a_worker_scene_shows_what_a_sync_scene_shows_at_every_published_tick() -> void:
	var reference: MainScene = _open(SYNC, GDSCRIPT)
	var worker: MainScene = _open(WORKER, GDSCRIPT)
	assert_str(_play(worker, reference, TICKS)).is_empty()
	_assert_alike_runs(worker, reference)
	assert_bool(worker.runner.worker_active()).is_true()
	assert_bool(reference.runner.worker_active()).is_false()
	assert_int(worker.runner.last_hash).is_not_equal(0)


## The same run with the candidate on the C++ kernels (ADR 0013 section 3): the checkpoints, the
## last hash and every view equal the GDScript reference's at every published tick. The library is
## required, not skipped (verify.sh builds it).
func test_a_native_worker_scene_shows_what_a_gdscript_sync_scene_shows() -> void:
	var reference: MainScene = _open(SYNC, GDSCRIPT)
	var native: MainScene = _open(WORKER, NATIVE)
	assert_str(_play(native, reference, TICKS)).is_empty()
	_assert_alike_runs(native, reference)
	var world: World = native.runner.world
	(
		assert_object(world.kernels)
		. override_failure_message("SimKernels is not loaded: run bash scripts/build-native.sh")
		. is_not_null()
	)
	assert_int(world.native_phases).is_equal(SimImpls.expected_mask())
	assert_object(reference.runner.world.kernels).is_null()
	assert_array(native.checkpoints()).is_equal(reference.checkpoints())
	assert_int(native.checkpoints().size()).is_equal(2 * CHECKPOINTS)


## A job held past its boundary leaves the rigs where they were: the published tick, the rig
## nodes and their positions stay as the first held frame left them (the newest state, alpha() 1),
## and held_ticks counts it once. Released after HOLD_FRAMES calls, the next frame publishes the
## held tick and clears the clock, and each frame after it publishes exactly one tick (no burst);
## from there on the views equal the reference's again.
func test_a_held_tick_leaves_the_rigs_in_place_and_resumes_without_a_burst() -> void:
	var gated: SimProbe = _gated_probe()
	gated.hold(HELD_TICK)
	var reference: MainScene = _open(SYNC, GDSCRIPT)
	var worker: MainScene = _open(WORKER, GDSCRIPT)
	worker.runner.set_probe(gated)
	assert_str(_play(worker, reference, HELD_TICK - 2)).is_empty()
	worker.frame()  # Publishes the tick before the held one and posts the held job.
	assert_bool(gated.wait_blocked()).is_true()
	assert_bool(_catch_up(reference, worker)).is_true()
	assert_str(worker.diff(reference)).is_empty()
	var tick: int = worker.tick()
	var snap: MatchSnapshot = worker.runner.snapshot
	worker.frame()  # The clock reaches the boundary while the job runs: held.
	var rigs: Array[int] = worker.rig_ids()
	var held_at: PackedVector2Array = worker.positions()
	assert_array([worker.runner.held_ticks, worker.runner.alpha()]).is_equal([1, 1.0])
	for row: int in rigs.size():
		var shown: Vector2 = IsoProjection.ground_to_px(snap.pos_x[row], snap.pos_y[row])
		assert_vector(held_at[row]).is_equal_approx(shown, Vector2(0.01, 0.01))
	for _frame: int in HOLD_FRAMES - 1:
		worker.frame()
		assert_array(worker.rig_ids()).is_equal(rigs)
		assert_bool(worker.positions() == held_at).is_true()
		assert_array([worker.tick(), worker.runner.held_ticks]).is_equal([tick, 1])
		assert_bool(is_same(worker.runner.snapshot, snap)).is_true()
	gated.release()
	assert_bool(worker.runner.wait_idle()).is_true()
	worker.frame()  # Publishes the held job and restarts the clock.
	assert_array([worker.tick(), worker.runner.alpha()]).is_equal([tick + 1, 0.0])
	assert_bool(worker.runner.wait_idle()).is_true()
	for after: int in AFTER_RESUME:
		assert_bool(_catch_up(reference, worker)).is_true()
		assert_str(worker.diff(reference)).is_empty()
		assert_bool(worker.step()).is_true()
		assert_int(worker.tick()).is_equal(tick + 2 + after)
	assert_array(worker.published).is_equal(range(1, worker.tick() + 1))
	assert_array([worker.runner.held_ticks, worker.off_main]).is_equal([1, 0])
	assert_int(worker.fog.rebuild_count()).is_equal(1)


## start() while a job runs (the "Run again" path) waits for the job and drops it, and the scene
## rebuilds every rig for the new match_serial and the fog image for the new match. The new match
## equals a fresh instance's at every tick up to the checkpoint at tick 15, whose hash is the
## fresh run's.
func test_start_during_a_job_rebuilds_every_rig_and_matches_a_fresh_run() -> void:
	var gated: SimProbe = _gated_probe()
	var reference: MainScene = _open(SYNC, GDSCRIPT)
	var worker: MainScene = _open(WORKER, GDSCRIPT)
	worker.runner.set_probe(gated)
	assert_str(_play(worker, reference, RESTART_AT)).is_empty()
	var old_rigs: Array[int] = worker.rig_ids()
	var old_positions: PackedVector2Array = worker.positions()
	var serial: int = worker.runner.match_serial
	var rebuilds: int = worker.fog.rebuild_count()
	gated.delay(JOB_MSEC)
	worker.frame()  # Posts a job that takes JOB_MSEC in its probe.
	assert_bool(worker.runner.job_in_flight()).is_true()
	worker.restart()
	gated.delay(0)
	assert_array([worker.runner.job_in_flight(), worker.tick()]).is_equal([false, 0])
	assert_int(worker.runner.match_serial).is_equal(serial + 1)
	var fresh: MainScene = _open(SYNC, GDSCRIPT)
	assert_str(_play(worker, fresh, CHECKPOINT_TICK)).is_empty()
	var new_rigs: Array[int] = worker.rig_ids()
	assert_int(new_rigs.size()).is_equal(UNITS)
	for id: int in new_rigs:
		# The rigs of the match that ended wait in the layer's pool and the new match's rows take
		# them (P114b): every rig is rebuilt for its new unit, and none is made for want of one.
		assert_array(old_rigs).contains([id])
	assert_bool(worker.positions() != old_positions).is_true()
	assert_int(worker.fog.rebuild_count()).is_equal(rebuilds + 1)
	assert_int(worker.runner.last_hash).is_not_equal(0)
	assert_int(worker.runner.last_hash).is_equal(fresh.runner.last_hash)
	assert_array(worker.checkpoints()).has_size(2)
	assert_array(worker.published).is_equal(range(1, CHECKPOINT_TICK + 1))
	assert_int(worker.off_main).is_equal(0)


## The perf arena of the gate, 150 units for the gate's 900 ticks, on the C++ kernels on the worker
## against the GDScript twins in sync: the same rigs, fog image, last hash and checkpoints at every
## published tick, and both runs end on the golden checkpoints of perf_gate.tres (the hashes that
## the APK and the web build must match). Nothing can enter the arena, so no order plays; the
## units meet and fight as their scenario orders. The card's run is longer than the case, so it
## does not finish inside it.
func test_the_native_worker_arena_shows_what_the_sync_arena_shows_and_holds_the_golden_hashes(
) -> void:
	var gate: PerfGateDef = load(GATE_PATH) as PerfGateDef
	var ticks: int = gate.golden_ticks[gate.golden_ticks.size() - 1]
	var reference: MainScene = _open_arena(SYNC, GDSCRIPT, ticks)
	var native: MainScene = _open_arena(WORKER, NATIVE, ticks)
	assert_int(native.rigs_at_start).is_equal(reference.rigs_at_start)
	assert_str(_play(native, reference, ticks)).is_empty()
	_assert_alike_runs(native, reference, ticks)
	assert_bool(native.runner.worker_active()).is_true()
	assert_object(native.runner.world.kernels).is_not_null()
	assert_int(native.runner.world.native_phases).is_equal(SimImpls.expected_mask())
	assert_object(reference.runner.world.kernels).is_null()
	for scene: MainScene in [native, reference]:
		assert_array(_golden_diff(scene, gate)).is_empty()


## The error scan sees an error from any thread and leaves a warning alone.
func test_the_error_scan_flags_an_error_and_not_a_warning() -> void:
	var scan: LogScan = LogScan.new()
	scan._log_error("f", "a.gd", 3, "code", "why", false, Logger.ERROR_TYPE_ERROR, [])
	scan._log_error("f", "b.gd", 4, "code", "why", false, Logger.ERROR_TYPE_WARNING, [])
	scan._log_error("f", "c.gd", 5, "code", "why", false, Logger.ERROR_TYPE_SCRIPT, [])
	assert_array(scan.hits()).is_equal(["a.gd:3 code why", "c.gd:5 code why"])


## An instance of the main scene.
func _open(mode: int, impl: int) -> MainScene:
	var scene: MainScene = MainScene.new()
	scene.open(self, mode, impl)
	_scenes.append(scene)
	return scene


## An instance of the perf arena for a run of `ticks` ticks. Its card's seams are replaced, so the
## 60-tick self-check and the 0.4 s burst do not run in its `_ready`, and its run is longer than
## the case. The arena starts its match in its own `_ready`, after its layers' (the main scene's
## runner comes first), so the fog layer builds its image on its first frame: both instances draw
## that frame before they are compared at tick 0.
func _open_arena(mode: int, impl: int, ticks: int) -> MainScene:
	var scene: MainScene = MainScene.new()
	scene.scripted = false
	var calls: Array[String] = []
	scene.open(self, mode, impl, ArenaRig.make(calls, 2 * ticks))
	scene.draw_first_frame()
	_scenes.append(scene)
	return scene


## The golden checkpoints of `gate` that `scene`'s replay does not hold, as "tick: hash, golden
## hash" lines; empty when each one is there and equal (World.hash_hex() text).
func _golden_diff(scene: MainScene, gate: PerfGateDef) -> Array[String]:
	var found: Array[String] = []
	var replay: Replay = scene.runner.replay
	for at: int in gate.golden_ticks.size():
		var tick: int = gate.golden_ticks[at]
		var index: int = replay.checkpoint_ticks.find(tick)
		var hex: String = "none" if index < 0 else World.hash_hex(replay.checkpoint_hashes[index])
		if hex != gate.golden_hex[at]:
			found.append("tick %d: %s, golden %s" % [tick, hex, gate.golden_hex[at]])
	return found


func _gated_probe() -> SimProbe:
	var probe: SimProbe = GatedProbe.new()
	_probes.append(probe)
	return probe


## Steps `reference` until it has published the tick `worker` has, one frame per tick. False when a
## wait hits the cap or a frame publishes nothing (the loop would not end).
func _catch_up(reference: MainScene, worker: MainScene) -> bool:
	while reference.tick() < worker.tick():
		var before: int = reference.tick()
		if not reference.step() or reference.tick() == before:
			return false
	return true


## Plays `worker` from its refill frame until it has published `ticks`, waiting after each frame,
## catches `reference` up to it and compares the two after every frame. The first difference, or "".
## A frame of one tick period publishes one tick, so SLACK_FRAMES beyond the ticks and the refill
## is the budget: a clock that stops publishing fails here and does not loop.
func _play(worker: MainScene, reference: MainScene, ticks: int) -> String:
	var budget: int = ticks - worker.tick() + SLACK_FRAMES
	while worker.tick() < ticks:
		if budget == 0:
			return "tick %d was not published within the frame budget" % (worker.tick() + 1)
		budget -= 1
		if not worker.step() or not _catch_up(reference, worker):
			return "a wait reached its cap or a frame published nothing at tick %d" % worker.tick()
		var found: String = worker.diff(reference)
		if not found.is_empty():
			return found
	return ""


## What a whole run has in common: `ticked` once per tick in order and always on the main thread,
## no held tick, a job in flight whenever the candidate's layers ran, the same commands in the
## replay, the fog rebuilt once (the match start) and patched the same number of times, and a run
## that was not idle: rigs died and the fog opened. `ticks` is the length of the run.
func _assert_alike_runs(worker: MainScene, reference: MainScene, ticks: int = TICKS) -> void:
	for scene: MainScene in [worker, reference]:
		assert_array(scene.published).is_equal(range(1, ticks + 1))
		assert_int(scene.off_main).is_equal(0)
		assert_int(scene.fog.rebuild_count()).is_equal(1)
	assert_int(worker.runner.held_ticks).is_equal(0)
	assert_array([worker.in_flight_frames, worker.frames]).is_equal([ticks + 1, ticks + 1])
	assert_int(reference.in_flight_frames).is_equal(0)
	assert_int(worker.fog.upload_count()).is_equal(reference.fog.upload_count())
	assert_array(worker.runner.replay.commands).is_equal(reference.runner.replay.commands)
	if worker.scripted:
		assert_int(worker.runner.replay.commands.size()).is_greater(0)
	assert_int(reference.fog.upload_count()).is_greater(10)
	var quiet: String = "no rig died in %d ticks: re-check the orders and the ticks" % ticks
	var rigs: int = reference.units.rig_count()
	assert_int(rigs).override_failure_message(quiet).is_less(reference.rigs_at_start)
