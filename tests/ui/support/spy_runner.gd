extends MatchRunner
## A MatchRunner that logs the two calls "Run again" makes on it, wait_idle() and start(), into
## `calls` (a log a test shares with its seams), and that reports a job in flight until wait_idle()
## takes it when `busy` is set: a preflight that comes first is then refused. Not a suite. It has
## its own file because an inner class may not extend a script, and it never names itself
## (tests/project/test_inner_classes_extend_engine_classes.gd).

## One entry per call, in order. A test assigns the array its seams log into.
var calls: Array[String] = []
## A job "in flight" for job_in_flight() until wait_idle() runs.
var busy: bool = false


func wait_idle(timeout_msec: int = WAIT_CAP_MSEC) -> bool:
	calls.append("wait_idle")
	busy = false
	return super(timeout_msec)


func start() -> void:
	calls.append("start")
	super()


func job_in_flight() -> bool:
	return busy or super()
