extends "res://tests/ai/support/control_suite.gd"
## The army reads lists that the REFRESH slot wrote one think (3 ticks) before (plan row P198b): a
## unit that died since is left out of an order (and counted in `stale_ids`), an order for none or
## on a dead target is not sent and costs nothing, and Hard's focus centre is the one of the living
## members.


## A refresh at `tick`, then `dead` units die, then the army runs on a fresh view: what one REFRESH
## and one ARMY think with a death between them see.
func _refresh_kill_run(tick: int, dead: PackedInt32Array) -> void:
	_world.tick = tick
	_memory.commands_left = 8
	_out = []
	_intel.refresh(_view(), _memory)
	for id: int in dead:
		_kill(id)
	_world.tick = tick
	_army.run(_view(), _memory, _rng, _out)


func test_an_order_leaves_out_a_dead_id_and_counts_it() -> void:
	var ids: PackedInt32Array = _squads()
	_kill(ids[1])
	_see_all()
	_memory.commands_left = 3
	var sent: bool = _army._order(
		_view(), _memory, _out, ids, STAGING, AiMemory.Owner.STAGING, _centre(STAGING)
	)
	assert_bool(sent).is_true()
	assert_int(_out.size()).is_equal(1)
	assert_array(_out[0].unit_ids).is_equal(PackedInt32Array([ids[0]]))
	assert_array([_army.stale_ids, _memory.commands_left]).is_equal([1, 2])


func test_an_order_for_no_living_id_sends_nothing_and_costs_nothing() -> void:
	var ids: PackedInt32Array = _squads()
	for id: int in ids:
		_kill(id)
	_memory.commands_left = 3
	var sent: bool = _army._order(
		_view(), _memory, _out, ids, STAGING, AiMemory.Owner.STAGING, _centre(STAGING)
	)
	assert_bool(sent).is_false()
	assert_array(_out).is_empty()
	assert_array([_army.stale_ids, _memory.commands_left, _memory.goal_keys()]).is_equal([2, 3, 0])


func test_an_order_on_a_dead_target_sends_nothing_and_costs_nothing() -> void:
	var ids: PackedInt32Array = _squads()
	var foe: int = _enemy("heavy_tank", 25500, 25500)
	_kill(foe)
	_memory.commands_left = 3
	var sent: bool = _army._order(
		_view(), _memory, _out, ids, STAGING, AiMemory.Owner.ARMY, _centre(STAGING), foe
	)
	assert_bool(sent).is_false()
	assert_array(_out).is_empty()
	assert_array([_memory.commands_left, _memory.goal_keys()]).is_equal([3, 0])


func test_the_home_focus_centre_is_the_one_of_the_living_members() -> void:
	_control(0, 1)
	# Two rifle squads and a tank stand 11 tiles east of the Headquarters, a foe beside them. Two
	# of the three die between the refresh and the army: a centre that counted them as (-1, -1)
	# would be 12.7 tiles from the foe, past the radius of 12, and find no target.
	var tank: int = _tank(19000, 8000)
	var squads: PackedInt32Array = _squads()
	for id: int in squads:
		_put(id, 19000, 8000)
	var foe: int = _enemy("heavy_tank", 19000, 7500)
	_settle()
	_see_all()
	_think(5)
	_think(20)
	_refresh_kill_run(35, squads)
	var sent: Array[Command] = _of(Command.Type.ATTACK)
	assert_int(sent.size()).is_equal(1)
	assert_int(sent[0].target_id).is_equal(foe)
	assert_array(sent[0].unit_ids).is_equal(PackedInt32Array([tank]))
