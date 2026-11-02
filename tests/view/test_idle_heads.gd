extends GdUnitTestSuite
## The idle sweep of a defence's Head (plan P140, ADR 0027 sections 1, 3, 6 and 8): a shown head
## whose building has no target, is complete and is not in a blackout walks 0, 1, 2, 1, 0, -1, -2,
## -1 frames off its last aim, holding each frame `sweep_ms`, by its region only. A target puts it
## back on its aim and it turns as before, a site, a blackout, a hidden enemy and `reduced` stop the
## sweep, and nothing but the head's region ever changes: the building's node, its Body, its shadow
## and the head's position stay. The function is in test_idle_life.gd; this is the layer's use of
## it. Fixtures: recoil_rig.gd. The Redoubt (id 4, Derrick League) changes frame at 245, 945, 1645,
## 2345, 3045, 3745, 4445 and 5145 ms of each 5600 ms cycle (the Python restatement of the
## function), to 0, 1, 2, 1, 0, -1, -2 and -1 frames off its aim; it shows -1 from the start.

const Rig: GDScript = preload("res://tests/view/support/recoil_rig.gd")
const Buildings: GDScript = preload("res://tests/view/support/building_rig.gd")
const AIM: int = 6  ## `d06`, east on the grid: where a head stands until it has a target.
## The Redoubt's offset in the middle of each of its holds, from the one that starts at 245 ms.
const REDOUBT_WALK: Array[int] = [0, 1, 2, 1, 0, -1, -2, -1]
const FIRST_MID_MS: float = 595.0  ## 245 ms plus half a hold.
const HOLD_MS: float = 700.0

var _runner: MatchRunner
var _layer: BuildingLayer
var _life: LifeSettings


func before_test() -> void:
	_runner = auto_free(Rig.runner())
	_start(LifeSettings.new())


func after_test() -> void:
	CommandQueue.clear()


func test_a_head_with_no_target_sweeps_within_reach_of_its_last_aim_as_pinned() -> void:
	assert_int(Buildings.head_frame(_layer, Rig.REDOUBT)).is_equal(AIM - 1)  # From the start.
	var frames: Array[int] = []
	for step: int in 16:  # Two cycles, a sample in the middle of each hold.
		_at_ms(FIRST_MID_MS + HOLD_MS * step)
		frames.append(Buildings.head_frame(_layer, Rig.REDOUBT) - AIM)
	for step: int in 16:
		assert_int(frames[step]).override_failure_message("step %d" % step).is_equal(
			REDOUBT_WALK[step % 8]
		)


func test_it_holds_each_frame_sweep_ms_and_writes_only_when_the_frame_changes() -> void:
	# A frame every 10 ms for 5.6 s (one cycle): 8 changes, every hold 700 ms (the first is cut by
	# the start), and one life write for each change and one for the first frame off the aim.
	var last: int = -99
	var held: int = 0
	var changes: int = 0
	var bad: int = 0
	for ms: int in range(0, 5600, 10):
		_at_ms(float(ms) + 0.5)
		var frame: int = Buildings.head_frame(_layer, Rig.REDOUBT) - AIM
		if frame != last:
			if last != -99:
				changes += 1
				if changes > 1 and held != 70:
					bad += 1
			last = frame
			held = 0
		held += 1
	assert_int(bad).is_equal(0)
	assert_int(changes).is_equal(8)
	assert_int(_layer.life_writes()).is_equal(9)


func test_the_sweep_moves_the_region_only_never_the_head_the_body_the_shadow_or_the_node() -> void:
	var node: Node2D = _layer.building(Rig.REDOUBT)
	var head: Sprite2D = Buildings.head(_layer, Rig.REDOUBT)
	var body: Sprite2D = node.get_node("Body")
	var shadow: Vector2 = Buildings.shadow(_layer, Rig.REDOUBT).position
	var at: Vector2 = node.position
	var mount: Vector2 = head.position
	var row: int = _runner.snapshot.index_of(Rig.REDOUBT)
	var box: Rect2 = _layer.frame_box(row)
	for ms: int in range(0, 6000, 50):
		_at_ms(float(ms))
		assert_vector(head.position).is_equal(mount)
		assert_vector(body.position).is_equal(Vector2.ZERO)
		assert_vector(node.position).is_equal(at)
	assert_int(_layer.life_writes()).is_greater(0)
	assert_vector(Buildings.shadow(_layer, Rig.REDOUBT).position).is_equal(shadow)
	assert_that(_layer.frame_box(row)).is_equal(box)


func test_a_target_puts_the_head_back_on_its_aim_and_it_turns_as_before() -> void:
	var snap: MatchSnapshot = _runner.snapshot
	var row: int = snap.index_of(Rig.REDOUBT)
	_at_ms(1000.0)  # In the hold from 945 ms: one frame off the aim.
	assert_int(Buildings.head_frame(_layer, Rig.REDOUBT)).is_equal(AIM + 1)
	var written: int = _layer.life_writes()
	snap.target_row[row] = snap.index_of(Rig.ENEMY_TANK)  # Far to the south east.
	Buildings.see(snap, 1, [Rig.FAR_TILE])
	_layer._process(1.0)  # A long frame: the head turns all the way, to the bearing itself.
	var aim: int = Buildings.head_frame(_layer, Rig.REDOUBT)
	assert_int(aim).is_not_equal(AIM)
	assert_int(_layer.life_writes()).is_equal(written)  # The turn wrote it; the sweep wrote nothing.
	for ms: int in range(1100, 4000, 100):  # And holds the bearing, no sweep, while it has one.
		_at_ms(float(ms))
		assert_int(Buildings.head_frame(_layer, Rig.REDOUBT)).is_equal(aim)
	assert_int(_layer.life_writes()).is_equal(written)
	snap.target_row[row] = -1  # The target is gone: it sweeps around the aim it has now.
	var seen: Dictionary[int, bool] = {}
	for ms: int in range(4000, 10000, 100):
		_at_ms(float(ms))
		seen[posmod(Buildings.head_frame(_layer, Rig.REDOUBT) - aim + 8, 16) - 8] = true
	assert_array(seen.keys()).contains_exactly_in_any_order([-2, -1, 0, 1, 2])


func test_a_site_and_a_blackout_hold_the_head_on_its_aim() -> void:
	var snap: MatchSnapshot = _runner.snapshot
	var row: int = snap.index_of(Rig.REDOUBT)
	_at_ms(1000.0)
	assert_int(Buildings.head_frame(_layer, Rig.REDOUBT)).is_not_equal(AIM)
	snap.build_left[row] = 100  # A site again: no sweep.
	_at_ms(1100.0)
	assert_int(Buildings.head_frame(_layer, Rig.REDOUBT)).is_equal(AIM)
	for ms: int in range(1200, 5000, 100):
		_at_ms(float(ms))
		assert_int(Buildings.head_frame(_layer, Rig.REDOUBT)).is_equal(AIM)
	snap.build_left[row] = 0  # Complete.
	var swept: bool = false
	for ms: int in range(5000, 7000, 100):
		_at_ms(float(ms))
		swept = swept or Buildings.head_frame(_layer, Rig.REDOUBT) != AIM
	assert_bool(swept).is_true()
	snap.offline_until[row] = snap.tick + 50  # A blackout for the next 50 ticks (3.3 s).
	_layer._process(0.0)
	assert_int(Buildings.head_frame(_layer, Rig.REDOUBT)).is_equal(AIM)
	var stayed: bool = true
	for ms: int in range(7000, 9000, 100):
		_at_ms(float(ms))
		stayed = stayed and Buildings.head_frame(_layer, Rig.REDOUBT) == AIM
	assert_bool(stayed).is_true()
	snap.offline_until[row] = 0  # Back online.
	var again: bool = false
	for ms: int in range(9600, 12000, 100):
		_at_ms(float(ms))
		again = again or Buildings.head_frame(_layer, Rig.REDOUBT) != AIM
	assert_bool(again).is_true()


func test_a_hidden_enemy_defence_does_not_sweep_and_a_seen_one_does() -> void:
	var head: int = Rig.ENEMY_DEFENCE
	var row: int = _runner.snapshot.index_of(head)
	assert_bool(_layer.is_shown(row)).is_false()
	for ms: int in range(0, 6000, 100):
		_at_ms(float(ms))
		assert_int(Buildings.head_frame(_layer, head)).is_equal(AIM)
	Buildings.see(_runner.snapshot, 1, [Rig.DEFENCE_TILE])
	assert_bool(_layer.is_shown(row)).is_true()
	var frames: Dictionary[int, bool] = {}
	for ms: int in range(6000, 12000, 100):
		_at_ms(float(ms))
		frames[Buildings.head_frame(_layer, head)] = true
	assert_int(frames.size()).is_equal(5)  # It sweeps through its five frames.


func test_reduced_drops_the_sweep_and_switching_to_it_puts_the_head_on_its_aim() -> void:
	var life: LifeSettings = LifeSettings.new()
	life.reduced = true
	_start(life)
	for ms: int in range(0, 6000, 100):
		_at_ms(float(ms))
		assert_int(Buildings.head_frame(_layer, Rig.REDOUBT)).is_equal(AIM)
	assert_int(_layer.life_writes()).is_equal(0)
	life.reduced = false
	var ms: int = 6000
	while Buildings.head_frame(_layer, Rig.REDOUBT) == AIM and ms < 12000:
		ms += 100
		_at_ms(float(ms))
	assert_int(Buildings.head_frame(_layer, Rig.REDOUBT)).is_not_equal(AIM)
	var written: int = _layer.life_writes()
	life.reduced = true  # Mid-sweep: one write to the aim, then none.
	_layer._process(0.0)
	assert_int(Buildings.head_frame(_layer, Rig.REDOUBT)).is_equal(AIM)
	assert_int(_layer.life_writes()).is_equal(written + 1)
	for later: int in range(ms, ms + 3000, 100):
		_at_ms(float(later))
	assert_int(_layer.life_writes()).is_equal(written + 1)


func test_the_settings_decide_how_far_it_sweeps() -> void:
	var off: LifeSettings = LifeSettings.new()
	off.sweep_frames = 0
	_start(off)
	for ms: int in range(0, 6000, 100):
		_at_ms(float(ms))
		assert_int(Buildings.head_frame(_layer, Rig.REDOUBT)).is_equal(AIM)
	assert_int(_layer.life_writes()).is_equal(0)
	var narrow: LifeSettings = LifeSettings.new()
	narrow.sweep_frames = 1
	_start(narrow)
	var seen: Dictionary[int, bool] = {}
	for ms: int in range(0, 6000, 100):
		_at_ms(float(ms))
		seen[Buildings.head_frame(_layer, Rig.REDOUBT) - AIM] = true
	assert_array(seen.keys()).contains_exactly_in_any_order([-1, 0, 1])


func test_a_pause_freezes_the_sweep_with_the_match() -> void:
	_at_ms(1000.0)
	var shown: int = Buildings.head_frame(_layer, Rig.REDOUBT)
	var writes: int = _layer.life_writes()
	_runner.paused = true
	for _frame_index: int in 200:
		_runner._process(0.5)
		_layer._process(0.05)
	assert_int(Buildings.head_frame(_layer, Rig.REDOUBT)).is_equal(shown)
	assert_int(_layer.life_writes()).is_equal(writes)


func test_the_kick_and_the_sweep_are_independent() -> void:
	# A shot of the Redoubt at tick 30 kicks the head back 2.5 px; the region goes on sweeping and the
	# position is the mount plus the kick, whatever frame the head shows.
	var head: Sprite2D = Buildings.head(_layer, Rig.REDOUBT)
	var mount: Vector2 = head.position
	var from: Vector2i = Rig.position_of(_runner, Rig.REDOUBT)
	Rig.deliver(
		_runner,
		Rig.shot(_runner, Rig.REDOUBT, from, Rig.EAST_ON_SCREEN, &"redoubt_gun"),
		Rig.SHOT_TICK
	)
	Rig.at(_runner, Rig.SHOT_TICK, 0.75)  # 50 ms into the kick, 2050 ms: the peak.
	_layer._process(0.0)
	assert_vector(head.position - mount).is_equal_approx(Vector2(-2.5, 0.0), Vector2(0.001, 0.001))
	assert_int(Buildings.head_frame(_layer, Rig.REDOUBT)).is_equal(AIM + 2)  # The hold from 1645.


## A layer on the fixture runner with the settings `life`.
func _start(life: LifeSettings) -> void:
	if is_instance_valid(_layer):
		_layer.free()
	_life = life
	_layer = auto_free(BuildingLayer.new())
	_layer.runner = _runner
	_layer.life = _life
	add_child(_layer)
	_layer.set_process(false)
	_layer._process(0.0)


## One frame at match time `ms`.
func _at_ms(ms: float) -> void:
	var ticks: float = ms * float(Sim.TICK_RATE) / 1000.0
	var tick: int = floori(ticks)
	Rig.at(_runner, tick, ticks - float(tick))
	_layer._process(0.0)
