extends "res://game/meta/progression_service.gd"
## A Progression for the map select's tests (P525): the rank is the test's; the unlock table is the
## real one (`data/meta/progression.tres`). Not a suite and never added to the tree (no save is
## read).

var rank_now: int = 1


func _init() -> void:
	bind(null, null)  # The real tuning; the save is never read (`rank` and `xp` are overridden).


func rank() -> int:
	return rank_now
