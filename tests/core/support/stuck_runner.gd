extends MatchRunner
## A runner that never goes idle (plan P516): `wait_idle` fails as it does when a job misses its
## cap, so the Restorer's end check meets a timeout. Set `stuck` after `start()`.

var stuck: bool = false


func wait_idle(timeout_msec: int = WAIT_CAP_MSEC) -> bool:
	return false if stuck else super(timeout_msec)
