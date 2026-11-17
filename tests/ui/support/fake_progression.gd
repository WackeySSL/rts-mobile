extends "res://game/meta/progression_service.gd"
## A Progression for the result screen's tests (P532): the XP total and the rank titles are the
## test's. Not a suite.

var total: int = 0


func xp() -> int:
	return total


func title(rank_number: int) -> String:
	return "Rank%d" % rank_number
