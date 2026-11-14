extends MatchRunner
## A runner for the AI thread suite (plan row P303) that records, at every _join_ai_thread(),
## whether the sim worker was joined already (ADR 0038 section 2: the AI thread is joined after it).

var sim_joined_first: Array[bool] = []


func _join_ai_thread() -> void:
	sim_joined_first.append(_thread == null)
	super()
