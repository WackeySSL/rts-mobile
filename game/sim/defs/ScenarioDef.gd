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
## The factions of the match by player: entry `p` is player p's faction, entry 0 is unused (null).
## World.from_scenario registers every listed faction's roster after `roster` (ADR 0023 section 6).
## Empty = no faction listed, as in every scenario before Phase 3's revision 5.
@export var factions: Array[FactionDef] = []
## The team colour per player, for the view alone: entry `p` is the index into `WorldSort.TRIADS` of
## the triad player p wears (entry 0 unused). Empty, or past the end: triad p - 1. The Skirmish
## scenarios name the side's colour: Nordvaern orange (0), Facet blue (3, Kobolt, the nearest
## triad to its #40A3FF), the other player the other one. Since 2026-11-25 (P632) this is interim:
## the default marker colours of ADR 0050 section 3 (own Sne, the computer's Karmin) switch in with
## the last model batch, P647, when the models carry fixed faction panels and a small marker.
@export var team_triads: PackedInt32Array = PackedInt32Array()
