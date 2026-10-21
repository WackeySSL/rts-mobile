extends RefCounted
## Fixtures of the perf arena suites (plan P50b). Not a test suite. The arena is made outside the
## tree with the card's slow seams replaced (the 60-tick self-check and the 0.4 s burst would run
## in every `_ready` otherwise) by seams that log what the runner looks like when they run: that is
## how a test sees the order of the preflight, the runner's start and the card's restart.

const SCENE: String = "res://scenes/dev/perf_arena.tscn"
const MAIN_SCENE: String = "res://scenes/main.tscn"
const ArenaScript: GDScript = preload("res://game/ui/perf_arena.gd")
## The kept samples of a burst: a peak of 25 us.
const BURST: PackedFloat64Array = [25.0, 25.0, 25.0, 25.0]
## The log entry of a seam: the runner has no job and, before its start, no World and serial 0.
const STATE: String = "%s job=%s world=%s serial=%d"


## The arena instantiated, not yet in the tree, its seams logging into `calls`. `ticks` is the
## card's run length.
static func make(calls: Array[String], ticks: int = 900) -> Node2D:
	var arena: Node2D = (load(SCENE) as PackedScene).instantiate() as Node2D
	var runner: MatchRunner = arena.runner
	var hud: PerfHud = arena.hud
	hud.run_ticks = ticks
	hud.self_check_step = func() -> String:
		calls.append(state("self_check", runner))
		return PerfHud.SELF_CHECK_NOT_RUN
	hud.burst_step = func() -> PackedFloat64Array:
		calls.append(state("burst", runner))
		return BURST
	hud.refresh_source = func() -> float:
		calls.append("restart serial=%d" % runner.match_serial)
		return 60.0
	return arena


## `make()`, in the tree under `parent`: `_ready` has run.
static func open(parent: Node, calls: Array[String], ticks: int = 900) -> Node2D:
	var arena: Node2D = make(calls, ticks)
	parent.add_child(arena)
	return arena


## The log entry for seam `name`: whether a job is in flight, whether the runner holds a World, and
## its match serial.
static func state(name: String, runner: MatchRunner) -> String:
	return (
		STATE
		% [
			name,
			runner.job_in_flight(),
			"set" if runner.world != null else "null",
			runner.match_serial
		]
	)


## Takes `arena` out of the tree and frees it, as the dev menu's Back does.
static func close(parent: Node, arena: Node2D) -> void:
	if arena.get_parent() == parent:
		parent.remove_child(arena)
	arena.free()
