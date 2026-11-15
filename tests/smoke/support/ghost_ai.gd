extends AiController
## A controller for tests/smoke/test_smoke_expired.gd: every think sends a MOVE for a unit id that
## does not exist, so the Command is already invalid at its view tick. `sent` counts them. Not a
## test suite.

const GHOST_ID: int = 999999
var sent: int = 0


func think(_view: PlayerView, out: Array[Command]) -> void:
	out.append(Command.move(player_id, PackedInt32Array([GHOST_ID]), 10500, 4500))
	sent += 1
