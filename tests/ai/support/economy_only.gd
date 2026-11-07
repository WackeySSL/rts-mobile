extends OpponentAi
## An `OpponentAi` whose ECONOMY slot runs the economy alone (no production) and whose other two
## slots do nothing, so the economy suite's long matches test the economy's caps and tankers
## without the army's units and fights changing them (plan row P178). Not a test suite. Made from
## a real controller by `copy_from`, since `OpponentAi.create` is static.


func copy_from(other: OpponentAi) -> void:
	player_id = other.player_id
	think_period = other.think_period
	think_offset = other.think_offset
	rng = other.rng
	memory = other.memory
	tier = other.tier
	commands_per_think_max = other.commands_per_think_max
	economy = other.economy


func _run_economy_slot(view: PlayerView, out: Array[Command]) -> void:
	economy.run(view, memory, rng, out)
	work += economy.passes


func _run_army_slot(_view: PlayerView, _out: Array[Command]) -> void:
	pass


func _run_intel_slot(_view: PlayerView, _out: Array[Command]) -> void:
	pass
