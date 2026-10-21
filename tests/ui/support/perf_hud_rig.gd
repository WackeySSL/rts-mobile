extends RefCounted
## Fixtures of the PerfHud suites (plan P50a and P50a2). Not a test suite. A HUD made here sits
## outside the tree on a 60 Hz panel with no frame cap, a release build and a worker run on Linux,
## after a burst whose peak is 25 us, so a default PerfGateDef judges it. Its gate holds the golden
## values of the snapshots made here. `run()` feeds it a run that passes every verdict, and a test
## changes one thing: a gate field, a flag or a frame. Frames are specs merged over FRAME, in
## microseconds.

const ARENA: String = "res://data/scenarios/perf_arena.tres"
const FRAME: Dictionary = {
	"interval": 16667,
	"process": 3000,
	"render": 1000,
	"calls": 40,
	"rigs": 140,
	"published": false,
	"ref": 25,
	"fog": -1,
}
## The kept samples of a burst whose p25 and p95 are 25 us: the frames' own reference samples.
const BURST: PackedFloat64Array = [25.0, 25.0, 25.0, 25.0]


## A HUD on `gate` (the script defaults without one), restarted and preflighted on the kept samples
## of `burst`. A gate without golden values gets those of `snapshot()`.
static func hud(gate: PerfGateDef = null, burst: PackedFloat64Array = BURST) -> PerfHud:
	var out: PerfHud = PerfHud.new()
	if gate != null:
		out.gate = gate
	if out.gate.golden_ticks.is_empty():
		pin_golden(out.gate)
	out.refresh_source = func() -> float: return 60.0
	out.max_fps_source = func() -> int: return 0
	out.burst_step = func() -> PackedFloat64Array: return burst
	out.kernels_source = func() -> Object: return null  # No library: the twins run.
	out.debug_build = false
	out.restart()
	out.run_preflight(false, true)
	out.worker_mode = true  # restart() clears it, as it clears every count.
	return out


## The checkpoint hash `snapshot()` gives published tick `tick`.
static func last_hash(tick: int) -> int:
	return tick * 1000 + 7


## The golden values of `snapshot()`: ticks 150 to 900, every 150th.
static func pin_golden(gate: PerfGateDef) -> void:
	for tick: int in range(150, 901, 150):
		gate.golden_ticks.append(tick)
		gate.golden_hex.append(World.hash_hex(last_hash(tick)))


## One frame: FRAME with the entries of `spec` over it.
static func frame(hud: PerfHud, spec: Dictionary = {}) -> void:
	var f: Dictionary = FRAME.merged(spec, true)
	hud.record_frame(
		f["interval"],
		f["process"],
		f["render"],
		f["calls"],
		f["rigs"],
		f["published"],
		f["ref"],
		f["fog"]
	)


static func frames(hud: PerfHud, count: int, spec: Dictionary = {}) -> void:
	for _i: int in count:
		frame(hud, spec)


## 1000 heavy frames that pass every verdict: every 4th publishes and every 12th carries a fog
## update of 0.2 ms. `spec` is merged into each, and `at` maps a frame number to a spec merged into
## that frame alone.
static func pass_frames(hud: PerfHud, spec: Dictionary = {}, at: Dictionary = {}) -> void:
	for i: int in 1000:
		var one: Dictionary = {"published": i % 4 == 0, "fog": 200 if i % 12 == 0 else -1}
		frame(hud, one.merged(spec, true).merged(at.get(i, {}), true))


## A snapshot of published tick `tick` with the timings a job leaves in it.
static func snapshot(tick: int, job_usec: int = 10_000, step_usec: int = 8_000) -> MatchSnapshot:
	var snap: MatchSnapshot = MatchSnapshot.new()
	snap.tick = tick
	snap.job_usec = job_usec
	snap.step_usec = step_usec
	snap.last_hash = last_hash(tick)
	return snap


## Ticks 1 to `count` of ordinary jobs; `slow` ticks (from the first) take `slow_usec`.
static func ticks(hud: PerfHud, count: int, slow: int = 0, slow_usec: int = 10_000) -> void:
	for tick: int in range(1, count + 1):
		hud.record_snapshot(snapshot(tick, slow_usec if tick <= slow else 10_000))


## A whole run that passes every verdict of a default gate: the frames, then 900 ordinary jobs,
## which end the run.
static func run(hud: PerfHud) -> void:
	pass_frames(hud)
	ticks(hud, hud.run_ticks)


## The names of the verdict lines of `summary` that failed, in order.
static func failed(summary: Dictionary) -> Array[String]:
	var names: Array[String] = []
	for line: String in summary["verdicts"]:
		if line.contains(": FAIL ("):
			names.append(line.get_slice(":", 0))
	return names
