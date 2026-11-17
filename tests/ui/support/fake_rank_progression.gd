extends "res://game/meta/progression_service.gd"
## A Progression for the map select's tests (P525): the rank and the unlock table are the test's.
## Not a suite and never added to the tree (no save is read).

var rank_now: int = 1
## "kind/id" -> the rank that opens it; anything else is open from the start.
var table: Dictionary[String, int] = {"map/map_2": 2, "level/hard": 3}


func rank() -> int:
	return rank_now


func unlock_rank(kind: StringName, id: StringName) -> int:
	return table.get("%s/%s" % [kind, id], 1)
