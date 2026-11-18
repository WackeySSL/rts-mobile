class_name FullscreenRuns
extends RefCounted
## The bookkeeping of AdService's full-screen runs (ADR 0039 section 2): the run being awaited and
## the late runs, which timed out (or were withdrawn) but whose ad AdMob cannot recall, so it may
## still open. A late run stays listening until its close, so the game never goes on under an ad
## and the opened/closed pair is never lost, whichever kind comes next. The policy (when to
## withdraw, what the caps say) stays in AdService; this class relays the pair as `opened` and
## `closed` and answers whether a run is busy.

signal opened(placement: StringName)
signal closed(placement: StringName)

## Test hook: the last started run, weakly, so a test can see that it was freed.
var last_run: WeakRef = null
var _active: FullscreenRun = null
var _lates: Array[FullscreenRun] = []


## Awaitable. Runs `run` to its end and returns its result. A run of the kind of an unopened late
## run takes over that run's listening when it connects (see FullscreenRun.replaces).
func start(run: FullscreenRun) -> bool:
	for late: FullscreenRun in _lates:
		if late.ad_kind() == run.ad_kind() and not late.is_opened():
			run.replaces = late
	run.opened.connect(_on_opened)
	run.closed.connect(_on_closed)
	run.took_over.connect(_forget)
	run.gave_up.connect(_forget)
	last_run = weakref(run)
	_active = run
	var result: bool = await run.execute()
	_active = null
	if run.is_late_pending():
		_lates.append(run)
	return result


## Withdraws every show that has not opened yet, of `kind` or of any kind for an empty one.
func cancel_unopened(kind: StringName = &"") -> void:
	var runs: Array[FullscreenRun] = _lates.duplicate()
	if _active != null:
		runs.append(_active)
	for run: FullscreenRun in runs:
		if kind.is_empty() or run.ad_kind() == kind:
			run.cancel()


## True while a run is awaited or a late ad is open.
func is_busy() -> bool:
	return _active != null or _lates.any(func(run: FullscreenRun) -> bool: return run.is_opened())


## Late runs still listening.
func late_count() -> int:
	return _lates.size()


## True while a late run of `kind` has not settled: its show may still open, or it is open and not
## yet closed. A run whose show failed, or that closed, is forgotten and no longer counts.
func has_late(kind: StringName) -> bool:
	return _lates.any(func(run: FullscreenRun) -> bool: return run.ad_kind() == kind)


func _on_opened(placement: StringName, _run: FullscreenRun) -> void:
	opened.emit(placement)


func _on_closed(placement: StringName, run: FullscreenRun) -> void:
	_forget(run)
	closed.emit(placement)


func _forget(run: FullscreenRun) -> void:
	_lates.erase(run)
