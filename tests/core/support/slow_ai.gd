extends AiController
## A controller whose think returns after the clock has moved by at least THINK_USEC microseconds,
## so a tick job that times the thinks must read a time of at least THINK_USEC. Not a test suite;
## test_tick_job.gd preloads it. It has its own file because an inner class may not extend a
## script, and it never names itself (tests/project/test_inner_classes_extend_engine_classes.gd).

const THINK_USEC: int = 100


func think(_view: PlayerView, _out: Array[Command]) -> void:
	var start: int = Time.get_ticks_usec()
	while Time.get_ticks_usec() < start + THINK_USEC:
		pass
