extends "res://game/ui/menu/menu_flow_service.gd"
## A MenuFlow for the result screen's tests (P532). Not a suite. It owns the runner it is given,
## hands out the award it is given and counts `restart` and `leave_match`, each of which waits for
## `release` so a test can tap a second time while the first still runs.

signal release

var runner: MatchRunner
var award: XpAward
var restarts: int = 0
var setup: MatchSetup
var last_screen: StringName = &"unset"
var leaves: int = 0
## Not OK: `restart` returns it at once and `leave_match` returns at once (a refused, busy call).
var refuse: Error = OK


func current_runner() -> MatchRunner:
	return runner


func current_setup() -> MatchSetup:
	return setup


func last_award() -> XpAward:
	return award


func restart() -> Error:
	restarts += 1
	if refuse != OK:
		return refuse
	await release
	return OK


func leave_match(screen: StringName = &"") -> void:
	leaves += 1
	last_screen = screen
	if refuse != OK:
		return
	await release
