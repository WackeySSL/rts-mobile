class_name SpawnDef
extends Resource
## One block of units of a scenario. Unit k (0-based) starts at
## origin_tile * 1000 + 500 + (k % columns, k / columns) * spacing, in milli-tiles, so a block
## fills rows of `columns` units from the centre of its origin tile. A `columns` below 1 is
## read as 1.

@export var owner: int = 0
@export var unit: UnitDef
@export var count: int = 0
@export var origin_tile: Vector2i = Vector2i.ZERO
@export var columns: int = 1
## Milli-tiles between neighbouring units of the block.
@export var spacing: int = 1000
