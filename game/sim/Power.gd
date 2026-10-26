class_name Power
extends RefCounted
## The power totals (ADR 0017 section 5, ADR 0018 section 4): when `rows_version` has moved, ECONOMY
## rebuilds the derived lists and the power made and used per player. Since plan row P71 `run`
## rebuilds the lists (Buildings.rebuild_lists); the power totals follow with plan row P74.


static func run(world: World) -> void:
	Buildings.rebuild_lists(world)
