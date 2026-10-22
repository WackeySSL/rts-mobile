class_name Production
extends RefCounted
## The PRODUCTION phase and its Commands (ADR 0017 section 5, ADR 0018 section 5): the queues
## advance, finished units spawn at their exit and leave for the rally point, finished structures
## turn ready. A skeleton until plan rows P73 (QUEUE, CANCEL, the queues and the unit spawns) and
## P73b (PLACE, the ready structures): `run` does nothing and every `apply_*` refuses, so the
## Command is dropped and counted.


static func run(_world: World) -> void:
	pass


## QUEUE `[type_index]`: true when the item joined the player's queue.
static func apply_queue(_world: World, _command: Command) -> bool:
	return false


## CANCEL `[tab, slot]`: true when the item left the queue and its cost came back.
static func apply_cancel(_world: World, _command: Command) -> bool:
	return false


## PLACE: true when the ready head of the STRUCTURES queue stands on the ground of the point.
static func apply_place(_world: World, _command: Command) -> bool:
	return false
