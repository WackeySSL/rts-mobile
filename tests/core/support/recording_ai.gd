extends AiController
## A controller for the tests/core suites (plan row P82): each think appends one record to
## `journal`, a list that the controllers of a case share, and sends one STOP of its player for no
## unit, so a case sees who thought, in which order, on which view and thread, and where the
## Commands went. Not a test suite.

## [label, view.player, view.tick, the view, out.size() before the think, the thread's caller id]
## per think.
var journal: Array = []
var label: String = ""


func think(view: PlayerView, out: Array[Command]) -> void:
	var thread: int = OS.get_thread_caller_id()
	journal.append([label, view.player, view.tick, view, out.size(), thread])
	out.append(Command.stop(player_id, PackedInt32Array()))
