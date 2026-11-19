extends "res://tests/ai/support/wave_suite.gd"
## The stall answer's gates (plan row P555b, `AiStall`): a wave idle for a whole window and no
## closer to its target is sent at the nearest seen building (the enemy Headquarters is seen in
## these Worlds); but not while a seen enemy stands near it or a focus target is set (a fight in
## progress, Hard's focus fire), not when the idle share broke inside the window, and never with
## the window 0.

const WINDOW: int = 60
## Where the wave stands after the launch: 12 tiles or more from the enemy squads and from every
## own building, so nothing seen is near it unless the case puts it there.
const FAR: Vector2i = Vector2i(14500, 18500)
## The first think after the launch and the last one the cases run to.
const FIRST: int = 125
const LAST: int = 400


## The fossil def of the suite with the stall answer on (a window of `WINDOW`).
func _stall_def(window: int = WINDOW) -> OpponentDef:
	var def: OpponentDef = _def()
	def.stall_window_ticks = window
	def.stall_progress_tiles = 2
	def.stall_arrive_tiles = 10
	def.stall_idle_percent = 50
	return def


## Arms the wave managers on `def` (Hard's focus on when `focus`), launches the first wave, and
## puts its units far out at `FAR`, idle (the suites do not step the sim, so no order is applied).
func _stalled(def: OpponentDef, focus: bool = false) -> PackedInt32Array:
	var level: AiDifficultyDef = _level()
	level.focus_fire = 1 if focus else 0
	_arm_waves(level, def)
	var ids: PackedInt32Array = _all_ids(_launched())
	for id: int in ids:
		_put(id, FAR.x, FAR.y)
	_see_all()
	return ids


## Thinks from `FIRST` to `LAST` every 15 ticks.
func _watch() -> void:
	for tick: int in range(FIRST, LAST, 15):
		_think(tick)


func test_a_wave_idle_for_the_window_is_sent_at_the_nearest_seen_building() -> void:
	_stalled(_stall_def())
	_watch()
	assert_int(_army.stall_attacks()).is_greater(0)


func test_a_seen_enemy_near_the_wave_keeps_the_answer_off() -> void:
	_stalled(_stall_def())
	_enemy("rifle_squad", FAR.x + 2000, FAR.y)
	_watch()
	assert_int(_army.stall_retries()).is_equal(0)
	assert_int(_army.stall_attacks()).is_equal(0)


func test_a_seen_enemy_near_the_wave_keeps_the_answer_off_on_hard() -> void:
	_stalled(_stall_def(), true)
	_enemy("rifle_squad", FAR.x + 2000, FAR.y)
	_watch()
	assert_int(_army.stall_retries()).is_equal(0)
	assert_int(_army.stall_attacks()).is_equal(0)


func test_a_focus_target_keeps_the_answer_off() -> void:
	_stalled(_stall_def())
	_memory.squad_focus[AiArmy.WAVE] = 99
	_watch()
	assert_int(_army.stall_retries()).is_equal(0)
	assert_int(_army.stall_attacks()).is_equal(0)


func test_an_enemy_that_leaves_the_wave_lets_the_answer_come() -> void:
	_stalled(_stall_def())
	var enemy: int = _enemy("rifle_squad", FAR.x + 2000, FAR.y)
	_watch()
	assert_int(_army.stall_attacks()).is_equal(0)
	_put(enemy, 1000, 38000)
	for tick: int in range(LAST, LAST + 300, 15):
		_think(tick)
	assert_int(_army.stall_attacks()).is_greater(0)


func test_a_wave_that_moves_inside_the_window_is_not_stalled() -> void:
	var ids: PackedInt32Array = _stalled(_stall_def())
	# Every think the wave is a few tiles closer to the target, so the window never runs out.
	var step: int = 0
	for tick: int in range(FIRST, LAST, 15):
		step += 1000
		for id: int in ids:
			_put(id, FAR.x + step, FAR.y + step)
		_think(tick)
	assert_int(_army.stall_retries() + _army.stall_attacks()).is_equal(0)


func test_a_window_of_zero_sends_nothing_and_touches_no_state() -> void:
	var ids: PackedInt32Array = _stalled(_stall_def(0))
	var stall: AiStall = AiStall.create(_stall_def(0))
	_target_at()
	var view: PlayerView = _view()
	var saved: Array = _freeze()
	var out: Array[Command] = []
	for tick: int in range(FIRST, LAST, 15):
		_world.tick = tick
		assert_bool(stall.run(_army, _view(), _memory, out, ids, FAR, ids.size())).is_false()
	assert_array(out).is_empty()
	assert_int(stall.attacks + stall.retries).is_equal(0)
	assert_array(_freeze()).is_equal(saved)
	assert_int(view.tick).is_greater_equal(0)
	_watch()
	assert_int(_army.stall_retries() + _army.stall_attacks()).is_equal(0)


func test_a_pause_inside_the_window_starts_the_window_again() -> void:
	var ids: PackedInt32Array = _stalled(_stall_def())
	# The units hold an order for one think at tick 170 (a fight, a re-order): idle from 185 on.
	for tick: int in range(FIRST, 230, 15):
		var busy: bool = tick == 170
		for id: int in ids:
			_world.order[_row_in_world(id)] = World.Order.ATTACK_MOVE if busy else World.Order.IDLE
		_think(tick)
	assert_int(_army.stall_attacks()).is_equal(0)
	for tick: int in range(230, LAST, 15):
		_think(tick)
	assert_int(_army.stall_attacks()).is_greater(0)


func test_the_attack_books_the_army_key_at_the_waves_goal_not_at_the_building() -> void:
	_stalled(_stall_def())
	_watch()
	assert_int(_army.stall_attacks()).is_greater(0)
	var goal: Vector2i = Vector2i(
		_memory.squad_goal_x[AiArmy.WAVE], _memory.squad_goal_y[AiArmy.WAVE]
	)
	var held: bool = false
	for at: int in _memory.goal_keys():
		var army_key: bool = _memory.goal_owner[at] & (1 << AiMemory.Owner.ARMY) != 0
		held = held or (army_key and Vector2i(_memory.goal_x[at], _memory.goal_y[at]) == goal)
	assert_bool(held).is_true()


func test_the_building_stays_in_view_and_the_next_answer_is_the_retry_not_a_second_attack() -> void:
	_stalled(_stall_def())
	var tick: int = FIRST
	while _army.stall_retries() == 0 and tick < LAST + 600:
		_think(tick)
		tick += 15
	assert_int(_army.stall_retries()).is_equal(1)
	assert_int(_army.stall_attacks()).is_equal(1)


func test_the_attack_goes_to_the_nearer_of_two_buildings_in_view() -> void:
	_stalled(_stall_def())
	# The farther building has the lower id, so neither "farthest" nor "lowest id" passes.
	var far: int = AiRig.give(_world, 2, "power_plant", 22, 24)
	var near: int = AiRig.give(_world, 2, "power_plant", 16, 19)
	_see_all()
	var targets: Array[int] = []
	for tick: int in range(FIRST, LAST, 15):
		_think(tick)
		for command: Command in _of(Command.Type.ATTACK):
			targets.append(command.target_id)
	assert_array(targets).is_not_empty()
	assert_int(targets[0]).is_equal(near)
	assert_bool(near != far).is_true()
