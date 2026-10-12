class_name TerrainSetDef
extends Resource
## The kinds of ground a map may use (ADR 0008 section 1). The index in this list is the terrain
## index that World stores per tile.

@export var terrains: Array[TerrainDef] = []
