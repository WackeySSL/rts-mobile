extends AiController
## A controller for the AI thread suite (plan row P303): every think sleeps WAIT_MSEC, longer than
## the few ms the job needs for the rest of its tick, so the next job must wait for the batch (ADR
## 0038 section 3), and sends one STOP of its player. `thinks` counts the thinks and `threads`
## collects the caller ids they ran on. Not a test suite. It has its own file because an inner class
## may not extend a script, and it never names itself
## (tests/project/test_inner_classes_extend_engine_classes.gd).

const WAIT_MSEC: int = 40

var thinks: int = 0
var threads: Dictionary[int, bool] = {}


func think(_view: PlayerView, out: Array[Command]) -> void:
	thinks += 1
	threads[OS.get_thread_caller_id()] = true
	OS.delay_msec(WAIT_MSEC)
	out.append(Command.stop(player_id, PackedInt32Array()))
