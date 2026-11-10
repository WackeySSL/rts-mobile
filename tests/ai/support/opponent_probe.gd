extends OpponentAi
## An `OpponentAi` whose five slot hooks record which one ran and whose ECONOMY hook appends
## Commands, for the skeleton's suite (plan row P175). Not a test suite. Made from a real controller
## by `copy_from`, since `OpponentAi.create` is static.

## The slots whose hook ran, in order.
var ran: Array[int] = []
## Commands the ECONOMY hook appends, with the distinct unit ids 1, 2, 3 ... each. With `polite` it
## asks `memory.can_send` first, as a manager must; else it appends them all.
var extra: int = 0
var polite: bool = false


func copy_from(other: OpponentAi) -> void:
	player_id = other.player_id
	think_period = other.think_period
	think_offset = other.think_offset
	slot_shift = other.slot_shift
	memory = other.memory
	tier = other.tier
	commands_per_think_max = other.commands_per_think_max


func _run_economy_slot(_view: PlayerView, out: Array[Command]) -> void:
	ran.append(Slot.ECONOMY)
	for id: int in range(1, extra + 1):
		if polite:
			if not memory.can_send():
				return
			memory.spent()
		out.append(Command.stop(player_id, PackedInt32Array([id])))


func _run_production_slot(_view: PlayerView, _out: Array[Command]) -> void:
	ran.append(Slot.PRODUCTION)


func _run_refresh_slot(_view: PlayerView) -> void:
	ran.append(Slot.REFRESH)


func _run_army_slot(_view: PlayerView, _out: Array[Command]) -> void:
	ran.append(Slot.ARMY)


func _run_intel_slot(_view: PlayerView, _out: Array[Command]) -> void:
	ran.append(Slot.INTEL)
