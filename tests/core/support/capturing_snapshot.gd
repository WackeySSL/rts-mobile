extends MatchSnapshot
## A MatchSnapshot whose capture() takes 2 ms more and stamps the clock: `captured_usec` where it
## returns, `capture_usec` its whole length. A test checks with it that a TickJob reads its end
## after the capture and counts the capture in job_usec. Not a test suite; test_tick_job.gd
## preloads it. It has its own file because an inner class may not extend a script, and it never
## names itself (tests/project/test_inner_classes_extend_engine_classes.gd).

const WAIT_USEC: int = 2000

var captured_usec: int = 0
var capture_usec: int = 0


func capture(world: World, previous: MatchSnapshot) -> void:
	var entry: int = Time.get_ticks_usec()
	super(world, previous)
	var until: int = Time.get_ticks_usec() + WAIT_USEC
	while Time.get_ticks_usec() < until:
		pass
	captured_usec = Time.get_ticks_usec()
	capture_usec = captured_usec - entry
