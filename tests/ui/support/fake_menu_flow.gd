extends "res://game/ui/menu/menu_flow_service.gd"
## A MenuFlow for the result screen's tests (P532). Not a suite. It owns the runner it is given,
## hands out the award it is given and counts `restart` and `leave_match`, each of which waits for
## `release` so a test can tap a second time while the first still runs.

signal release

var runner: MatchRunner
var award: XpAward
var restarts: int = 0
var leaves: int = 0


func current_runner() -> MatchRunner:
	return runner


func last_award() -> XpAward:
	return award


func restart() -> Error:
	restarts += 1
	await release
	return OK


func leave_match(_screen: StringName = &"") -> void:
	leaves += 1
	await release
