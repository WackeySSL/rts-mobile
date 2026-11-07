extends OpponentAi
## An `OpponentAi` without the army: its ARMY slot makes only the intel refresh, so the production
## suite's scout tick (a pin on the economy, production and intel) does not move when the army
## changes (plan row P178). Not a test suite. Made from a real controller by `copy_from`, since
## `OpponentAi.create` is static.


func copy_from(other: OpponentAi) -> void:
	player_id = other.player_id
	think_period = other.think_period
	think_offset = other.think_offset
	rng = other.rng
	memory = other.memory
	tier = other.tier
	commands_per_think_max = other.commands_per_think_max
	intel = other.intel
	economy = other.economy
	production = other.production
	striker = other.striker


func _run_army_slot(view: PlayerView, _out: Array[Command]) -> void:
	intel.refresh(view, memory)
	work += intel.passes
