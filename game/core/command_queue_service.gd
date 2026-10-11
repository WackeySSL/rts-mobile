# CommandQueue autoload (ADR 0002 section 1). Node-side inbox where input and AI controllers
# submit Commands; the match runner drains it into the sim's ordered per-tick command list.
# API v0 is defined in ADR 0003 section 7. Phase 2 may extend it.
extends Node

var _commands: Array[Command] = []


## Queues `command` behind the earlier ones. A null command is ignored.
func submit(command: Command) -> void:
	if command == null:
		return
	_commands.append(command)


## Appends the queued commands to `out` in submission order, empties the queue and returns how
## many were appended.
func drain_into(out: Array[Command]) -> int:
	var count: int = _commands.size()
	out.append_array(_commands)
	_commands.clear()
	return count


func clear() -> void:
	_commands.clear()


func pending() -> int:
	return _commands.size()
