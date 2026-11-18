extends "res://game/ui/menu/menu_flow_service.gd"
## A MenuFlow for the map select's tests (P525). Not a suite. `start_match` records the setup it
## is given and waits for `release`; with `refuse` not OK it returns that error at once.

signal release

var started: Array[MatchSetup] = []
var refuse: Error = OK


func start_match(setup: MatchSetup) -> Error:
	started.append(setup)
	if refuse != OK:
		return refuse
	await release
	return OK
