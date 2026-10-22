class_name Outcome
extends RefCounted
## Rally points, surrender and the end of a match (ADR 0017 section 5, ADR 0018 sections 6 and 7):
## `run` is the defeat and victory check after the queues. A skeleton until plan row P76: `run` does
## nothing and every `apply_*` refuses, so a RALLY or SURRENDER is dropped and counted.


static func run(_world: World) -> void:
	pass


## RALLY: true when the point became the rally point of the tab that the building produces.
static func apply_rally(_world: World, _command: Command) -> bool:
	return false


## SURRENDER: true when the player was defeated at once.
static func apply_surrender(_world: World, _command: Command) -> bool:
	return false
