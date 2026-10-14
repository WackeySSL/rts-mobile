extends SimProbe
## A SimProbe that takes 2 ms in begin() and in mark() and stamps the clock where begin() returns
## and where mark() starts, so a probe that passes its calls on can be checked to read the clock
## between them. Not a test suite; test_match_runner.gd preloads it. It has its own file because an
## inner class may not extend a script, and it never names itself
## (tests/project/test_inner_classes_extend_engine_classes.gd).

const WAIT_USEC: int = 2000

var begin_exit_usec: int = 0
var mark_entry_usec: int = 0


func begin() -> void:
	_wait()
	begin_exit_usec = Time.get_ticks_usec()


func mark(_phase: int) -> void:
	mark_entry_usec = Time.get_ticks_usec()
	_wait()


func _wait() -> void:
	var until: int = Time.get_ticks_usec() + WAIT_USEC
	while Time.get_ticks_usec() < until:
		pass
