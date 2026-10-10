class_name ScenarioDef
extends Resource
## A match setup: map size, the local player, where the camera starts and the unit blocks.
## World.from_scenario() reads it once at match start (ADR 0003 section 6).

@export var map_size_tiles: Vector2i = Vector2i(32, 32)
@export var local_player: int = 1
@export var camera_start_tile: Vector2i = Vector2i.ZERO
@export var spawns: Array[SpawnDef] = []
