class_name AiDriver
extends RefCounted
## The hook between a match and its computer players (ADR 0020 sections 2 and 3, plan row P82).
## think_all() is the only code that hands a World to the AI side: each controller whose turn it is
## gets a fresh PlayerView of its player and appends its Commands to the tick's list. Every driver
## calls it right before MatchLoop.step with that list: TickJob.run() on the thread that runs the
## job (the worker in WORKER, the main thread in SYNC), after the human's drained commands, and
## every headless loop. So the loop stamps and records the AI's Commands like a player's, the
## phone and CI cannot drift, and Replay.play needs no AI. Pure: no Node, no clock, no state.


## Lets every controller of `controllers` whose turn it is think, in ascending player order (two of
## one player in list order), each on a fresh PlayerView of its player at `world.tick`, appending
## to `out` after what it holds. A controller's turn is a tick with `(tick + think_offset) %
## think_period == 0`, a period below 1 counting as 1. A null entry is skipped. Nothing thinks once
## the match has ended (`match_end_tick` above 0): the sim drops every Command after the end, and a
## controller cannot see the end through its view.
static func think_all(world: World, controllers: Array[AiController], out: Array[Command]) -> void:
	if world.match_end_tick > 0 or controllers.is_empty():
		return
	var tick: int = world.tick
	var due: Array[AiController] = []
	for controller: AiController in controllers:
		if controller == null:
			continue
		if (tick + controller.think_offset) % maxi(controller.think_period, 1) != 0:
			continue
		# An insertion that keeps the list stable: after every controller of a lower or equal player.
		var at: int = due.size()
		while at > 0 and due[at - 1].player_id > controller.player_id:
			at -= 1
		due.insert(at, controller)
	for controller: AiController in due:
		controller.think(PlayerView.of(world, controller.player_id), out)
