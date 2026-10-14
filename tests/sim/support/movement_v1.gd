extends RefCounted
## Phase 1's unit movement, frozen: `Sim._move_units` as it was before P37a2, kept verbatim as the
## oracle of "on an open map the positions equal Phase 1's, tick by tick" (the same role as
## formation_v1.gd for the slots). Do not modernise it. Not a test suite.

## Each unit with an order steps towards its goal, in ascending id order. Within one step it snaps
## to the goal and goes idle, except an ATTACK unit, which keeps its order and its target.
## Division truncates toward zero.
@warning_ignore("integer_division")
static func move_units(world: World) -> void:
	for row: int in world.unit_count():
		if world.order[row] == World.Order.IDLE:
			continue
		var speed: int = world.type_speed[world.type_index[row]]
		var dx: int = world.goal_x[row] - world.pos_x[row]
		var dy: int = world.goal_y[row] - world.pos_y[row]
		var d2: int = dx * dx + dy * dy
		if d2 <= speed * speed:
			world.pos_x[row] = world.goal_x[row]
			world.pos_y[row] = world.goal_y[row]
			if world.order[row] != World.Order.ATTACK:
				world.order[row] = World.Order.IDLE
		else:
			var distance: int = FixedMath.isqrt(d2)
			world.pos_x[row] += dx * speed / distance
			world.pos_y[row] += dy * speed / distance
