class_name Power
extends RefCounted
## The power totals (ADR 0017 section 5, ADR 0018 section 4): when `rows_version` has moved, ECONOMY
## rebuilds the derived lists and the power made and used per player. A skeleton until plan row
## P74 (P71 adds the derived row lists): `run` does nothing.


static func run(_world: World) -> void:
	pass
