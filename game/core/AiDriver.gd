class_name AiDriver
extends RefCounted
## The hook between a match and its computer players (ADR 0020 sections 2 and 3, plan row P82).
## think_all() is the only code that hands a World to the AI side: each controller whose turn it is
## gets a fresh PlayerView of its player and appends its Commands to the tick's list. Every driver
## calls it right before MatchLoop.step with that list: TickJob.run() on the thread that runs the
## job (the worker in WORKER, the main thread in SYNC), after the human's drained commands, and
## every headless loop. So the loop stamps and records the AI's Commands like a player's, the
## phone and CI cannot drift, and Replay.play needs no AI. Pure: no Node, no clock, no state, and
## no allocation of its own: a tick makes only the PlayerViews of the controllers that think.


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
	# A selection without scratch storage: each pass picks the due controller with the smallest
	# (player, list index) after the one that thought last. O(n^2), with n at most 3 opponents.
	var last: int = -1
	var last_player: int = 0
	while true:
		var next: int = -1
		for index: int in controllers.size():
			var controller: AiController = controllers[index]
			if controller == null:
				continue
			if (tick + controller.think_offset) % maxi(controller.think_period, 1) != 0:
				continue
			var player: int = controller.player_id
			if last >= 0 and (player < last_player or (player == last_player and index <= last)):
				continue
			if next < 0 or player < controllers[next].player_id:
				next = index
		if next < 0:
			return
		var chosen: AiController = controllers[next]
		last = next
		last_player = chosen.player_id
		chosen.think(PlayerView.of(world, last_player), out)
