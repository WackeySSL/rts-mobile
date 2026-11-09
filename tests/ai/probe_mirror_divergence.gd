extends SceneTree
## Mirror-divergence probe (P195d, not a CI suite: no GdUnitTestSuite base on purpose). Plays the
## fossil-mirror scenario with two Normal AIs that share ONE DetRandom stream seed, and after every
## tick compares player 1's state with the half turn of player 2's: unit rows (type, position, hp,
## order, goal, build_left, cargo), credits, harvested, fog explored and visible cells, and the
## Commands each AI issued that tick. It prints the first tick that differs and what.
##
## Run: godot --headless --path . -s res://tests/ai/probe_mirror_divergence.gd -- [seed=N] [ticks=N]
##      [think=1] [fog=1]     think=1 gives both AIs player 1's think offset, fog=1 makes the fog
##      turn every tick for both players (fog_period_ticks 1), the two deliberate index asymmetries.

const Smoke: GDScript = preload("res://tests/smoke/smoke_run.gd")


func _initialize() -> void:
	var seed_value: int = 1
	var ticks: int = 900
	var align_think: bool = false
	var align_fog: bool = false
	var all_flow: bool = false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("seed="):
			seed_value = int(arg.substr(5))
		elif arg.begins_with("ticks="):
			ticks = int(arg.substr(6))
		elif arg == "think=1":
			align_think = true
		elif arg == "fog=1":
			align_fog = true
		elif arg == "flow=1":
			all_flow = true
	quit(_run(seed_value, ticks, align_think, align_fog, all_flow))


func _run(seed_value: int, ticks: int, align_think: bool, align_fog: bool, all_flow: bool) -> int:
	var world: World = Smoke.world_of(seed_value, Smoke.FOSSIL_MIRROR)
	Smoke.attach_impl(world)
	var loop: MatchLoop = Smoke.loop_of(world, seed_value, Smoke.FOSSIL_MIRROR)
	var levels: Array[String] = ["normal", "normal"]
	var controllers: Array[AiController] = Smoke.controllers_of(
		seed_value, Smoke.FOSSIL_MIRROR, levels
	)
	# Same stream for both players: a fresh DetRandom of the same seed and stream id.
	for index: int in controllers.size():
		controllers[index].rng = DetRandom.create(seed_value, DetRandom.STREAM_AI_BASE + 1)
	if align_think:
		controllers[1].think_offset = controllers[0].think_offset
	if align_fog:
		world.fog_period_ticks = 1
	if all_flow:
		world.flow_cells_per_tick = 100000000
	print(
		(
			"probe: seed %d, think aligned %s, fog every tick %s, impl %s"
			% [seed_value, align_think, align_fog, Smoke.impl_name()]
		)
	)
	var commands: Array[Command] = []
	var width: int = world.map_w
	var height: int = world.map_h
	while world.tick < ticks and world.match_end_tick == 0:
		AiDriver.think_all(world, controllers, commands)
		var issued: Array[PackedStringArray] = [PackedStringArray(), PackedStringArray()]
		for command: Command in commands:
			if command.player_id < 1 or command.player_id > 2:
				continue
			var turned: bool = (
				command.player_id == 2 and (command.target_x != 0 or command.target_y != 0)
			)
			var is_place: bool = command.type == Command.Type.PLACE
			var x: int = width - command.target_x if turned else command.target_x
			var y: int = height - command.target_y if turned else command.target_y
			if is_place:
				x = 0  # an origin tile: the footprint decides its half turn, the states compare it
				y = 0
			issued[command.player_id - 1].append(
				(
					"type %d at (%d,%d) units %d payload %s"
					% [command.type, x, y, command.unit_ids.size(), str(command.payload)]
				)
			)
		var tick: int = world.tick
		loop.step(world, commands)
		commands.clear()
		var found: Array[String] = _compare(world, width, height, issued)
		if not found.is_empty():
			print(
				(
					"FIRST DIVERGENCE after the step of tick %d (world.tick now %d):"
					% [tick, world.tick]
				)
			)
			for line: String in found:
				print("  " + line)
			for ctl: AiController in controllers:
				var ai: OpponentAi = ctl as OpponentAi
				var m: AiMemory = ai.memory
				print(
					(
						"  memory P%d: home (%d,%d) base (%d,%d) staging (%d,%d) scout %d wp %d"
						% [
							ai.player_id,
							m.home_x,
							m.home_y,
							m.base_x,
							m.base_y,
							m.staging_x,
							m.staging_y,
							m.scout_id,
							m.scout_waypoint
						]
					)
				)
			return 0
	print("no divergence in %d ticks (match end tick %d)" % [world.tick, world.match_end_tick])
	return 0


func _compare(
	world: World, width: int, height: int, issued: Array[PackedStringArray]
) -> Array[String]:
	var out: Array[String] = []
	var first: PackedStringArray = _units(world, 1, width, height)
	var second: PackedStringArray = _units(world, 2, width, height)
	if first != second:
		out.append(
			(
				"units/buildings differ: P1 has %d rows, turned P2 has %d"
				% [first.size(), second.size()]
			)
		)
		var only_first: Array[String] = _minus(first, second)
		var only_second: Array[String] = _minus(second, first)
		for row: String in only_first.slice(0, 8):
			out.append("  only P1: " + row)
		for row: String in only_second.slice(0, 8):
			out.append("  only turned P2: " + row)
	if world.credits[1] != world.credits[2]:
		out.append("credits P1 %d, P2 %d" % [world.credits[1], world.credits[2]])
	if world.stat_harvested[1] != world.stat_harvested[2]:
		out.append("harvested P1 %d, P2 %d" % [world.stat_harvested[1], world.stat_harvested[2]])
	var cells: int = world.fog.cells
	var explored_bad: int = 0
	var visible_bad: int = 0
	var examples: Array[String] = []
	for cell: int in cells:
		var turned: int = cells - 1 - cell
		if (world.fog.explored[cell] != 0) != (world.fog.explored[cells + turned] != 0):
			explored_bad += 1
			if examples.size() < 4:
				examples.append(
					(
						"cell %d (col %d line %d)"
						% [cell, cell % world.fog.cols, cell / world.fog.cols]
					)
				)
		if (world.fog.visible[cell] > 0) != (world.fog.visible[cells + turned] > 0):
			visible_bad += 1
	if explored_bad > 0 or visible_bad > 0:
		out.append(
			(
				"fog: %d explored and %d visible cells differ %s"
				% [explored_bad, visible_bad, str(examples)]
			)
		)
	if explored_bad > 0 or visible_bad > 0:
		for row: int in world.owner.size():
			var side: int = world.owner[row]
			if side < 1 or side > 2:
				continue
			var turned_x: int = world.pos_x[row] if side == 1 else width - world.pos_x[row]
			var turned_y: int = world.pos_y[row] if side == 1 else height - world.pos_y[row]
			if turned_x < 14000 and turned_y < 14000:
				out.append(
					(
						"  near the corner: P%d type %d at (%d,%d) turned, sight %d"
						% [
							side,
							world.type_index[row],
							turned_x,
							turned_y,
							world.type_sight[world.type_index[row]]
						]
					)
				)
	if not out.is_empty():
		for row: int in world.owner.size():
			var side: int = world.owner[row]
			if side < 1 or side > 2:
				continue
			var tx: int = world.pos_x[row] if side == 1 else width - world.pos_x[row]
			var ty: int = world.pos_y[row] if side == 1 else height - world.pos_y[row]
			if absi(tx - 10064) < 3500 and absi(ty - 13230) < 3500:
				(
					out
					. append(
						(
							"  nearby P%d id %d type %d turned (%d,%d) order %d intent %d,%d nav %d next %d"
							% [
								side,
								world.unit_id[row],
								world.type_index[row],
								tx,
								ty,
								world.order[row],
								world.intent_x[row],
								world.intent_y[row],
								world.nav_mode[row],
								(
									world.nav_next[row]
									if side == 1
									else world.map_cols * world.map_rows - 1 - world.nav_next[row]
								)
							]
						)
					)
				)
	if not out.is_empty():
		for row: int in world.owner.size():
			var side: int = world.owner[row]
			if (side == 1 or side == 2) and world.harvest_mode[row] != 0:
				var slot: int = world.harvest_slot[row]
				var cell: int = world.ore_cell[slot] if slot >= 0 else -1
				var cell_x: int = cell % world.map_cols if cell >= 0 else -1
				var cell_y: int = cell / world.map_cols if cell >= 0 else -1
				if side == 2 and cell >= 0:
					cell_x = world.map_cols - 1 - cell_x
					cell_y = world.map_rows - 1 - cell_y
				(
					out
					. append(
						(
							"  harvester P%d id %d mode %d slot cell (%d,%d) turned, amount %d, cargo %d"
							% [
								side,
								world.unit_id[row],
								world.harvest_mode[row],
								cell_x,
								cell_y,
								world.ore_amount[slot] if slot >= 0 else -1,
								world.cargo[row]
							]
						)
					)
				)
	if issued[0] != issued[1]:
		out.append("commands differ: P1 %s" % str(issued[0]))
		out.append("                  turned P2 %s" % str(issued[1]))
	return out


## Sorted description of the rows of `player`, positions turned for player 2.
func _units(world: World, player: int, width: int, height: int) -> PackedStringArray:
	var rows: PackedStringArray = PackedStringArray()
	for row: int in world.owner.size():
		if world.owner[row] != player:
			continue
		var x: int = world.pos_x[row]
		var y: int = world.pos_y[row]
		var goal_x: int = world.goal_x[row]
		var goal_y: int = world.goal_y[row]
		if player == 2:
			x = width - x
			y = height - y
			goal_x = width - goal_x
			goal_y = height - goal_y
		rows.append(
			(
				"t%d (%d,%d) hp %d order %d goal (%d,%d) left %d cargo %d mode %d"
				% [
					world.type_index[row],
					x,
					y,
					world.hp[row],
					world.order[row],
					goal_x,
					goal_y,
					world.build_left[row],
					world.cargo[row],
					world.harvest_mode[row]
				]
			)
		)
	rows.sort()
	return rows


func _minus(a: PackedStringArray, b: PackedStringArray) -> Array[String]:
	var left: Dictionary = {}
	for row: String in b:
		left[row] = int(left.get(row, 0)) + 1
	var out: Array[String] = []
	for row: String in a:
		if int(left.get(row, 0)) > 0:
			left[row] = int(left[row]) - 1
		else:
			out.append(row)
	return out
