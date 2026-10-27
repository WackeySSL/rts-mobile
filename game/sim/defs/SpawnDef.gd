class_name SpawnDef
extends Resource
## One block of units of a scenario. Unit k (0-based) starts at
## origin_tile * 1000 + 500 + (k % columns, k / columns) * spacing, in milli-tiles, so a block
## fills rows of `columns` units from the centre of its origin tile. A `columns` below 1 is
## read as 1. When `unit` is a BuildingDef the block is `count` buildings (World.add_building):
## building k has its top-left tile at origin_tile + (k % columns * width, k / columns * height),
## so the footprints sit side by side; `spacing` and `jitter` do nothing for them.

@export var owner: int = 0
@export var unit: UnitDef
@export var count: int = 0
@export var origin_tile: Vector2i = Vector2i.ZERO
@export var columns: int = 1
## Milli-tiles between neighbouring units of the block.
@export var spacing: int = 1000
## Milli-tiles. Above 0, each unit starts up to this far from its grid point (two draws per unit,
## x then y, ADR 0007 section 2). 0 draws nothing. Data keeps it in 0..8000, as DetRandom.range_int
## draws nothing for a span above 2^31 (test_defs_data).
@export var jitter: int = 0
## Buildings only, and only a strike building (strike_kind above 0) feels it: the ticks of its
## charge that are already behind it when the match starts. `Strike.age_charge` takes them off the
## end of the charge, so the building is first ready `charge_ticks - charge_elapsed_ticks` ticks
## into the match (at once when this is `charge_ticks` or more). 0, the default, is the whole
## charge a PLACE gets. Data keeps it at 0 or more, and above 0 only on a strike building
## (test_defs_data).
@export var charge_elapsed_ticks: int = 0
