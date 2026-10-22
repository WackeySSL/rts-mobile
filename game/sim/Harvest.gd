class_name Harvest
extends RefCounted
## The harvest loop and the ore (ADR 0017 section 5, ADR 0018 sections 2 and 3): ore regrowth, and
## the harvesters' SEEK, MINE, RETURN and UNLOAD. A skeleton until plan rows P75 (the loop) and
## P75b (HARVEST and the player orders): `run` and `release` do nothing and `apply_harvest`
## refuses, so a HARVEST is dropped and counted.


static func run(_world: World) -> void:
	pass


## HARVEST: true when a harvester among the command's units took an ore cell near the point.
static func apply_harvest(_world: World, _command: Command) -> bool:
	return false


## A unit-group order (MOVE, ATTACK_MOVE, STOP) on `rows` hands those harvesters back to the player
## (harvest mode IDLE, the cargo kept). Sim calls it with the rows it accepted.
static func release(_world: World, _rows: PackedInt32Array) -> void:
	pass
