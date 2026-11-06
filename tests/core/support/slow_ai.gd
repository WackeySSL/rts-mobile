extends AiController
## A controller whose think returns after the clock has moved by at least one microsecond, so a
## tick job that times the thinks reads a time above 0. Not a test suite; test_tick_job.gd preloads
## it. It has its own file because an inner class may not extend a script, and it never names
## itself (tests/project/test_inner_classes_extend_engine_classes.gd).


func think(_view: PlayerView, _out: Array[Command]) -> void:
	var start: int = Time.get_ticks_usec()
	while Time.get_ticks_usec() == start:
		pass
