class_name ScenarioDef
extends Resource
## A match setup: map size, the local player, where the camera starts and the unit blocks.
## World.from_scenario() reads it once at match start (ADR 0003 section 6, ADRs 0007 and 0008).

@export var map_size_tiles: Vector2i = Vector2i(32, 32)
@export var local_player: int = 1
@export var camera_start_tile: Vector2i = Vector2i.ZERO
@export var spawns: Array[SpawnDef] = []
## Null = open grass of map_size_tiles.
@export var map: MapDef
## Null = the RulesDef script defaults. Every shipped scenario sets data/rules.tres.
@export var rules: RulesDef
## Orders given by the scenario itself, as if a player had issued them.
@export var orders: Array[OrderDef] = []
## Players are 1..player_count. 0 = the highest spawn owner.
@export var player_count: int = 0
## Unit types registered at setup even if no spawn uses them.
@export var roster: Array[UnitDef] = []
