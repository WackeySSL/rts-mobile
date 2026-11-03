extends GdUnitTestSuite
## The functions behind the squads' poses (plan P142, ADR 0027 section 5), without a layer:
## `RigLife.travel_step` and `walk_frame` (the walk frame of the ground a squad covered),
## `pose_idle` and `pose_step` (the idle windows) and `Pose.dress` (what a sheet says). The layer's
## use of them is in test_squad_poses.gd. The idle windows are pinned by a Python restatement of
## `LifeClock.mix` and the cycle rule: for ids 1 to 8, standing from 0 ms with the default settings,
## the first three windows [from, to) in ms and the frame each shows, the length of the id's cycle
## and the windows that begin inside 60 s.

const STRIDE: int = 352
const QUARTER: int = 88
const WINDOWS: Dictionary[int, Array] = {
	1: [2874, 3474, 0, 9362, 9962, 1, 15427, 16027, 1],
	2: [3990, 4590, 0, 8997, 9597, 0, 15847, 16447, 1],
	3: [2262, 2862, 1, 7935, 8535, 1, 16486, 17086, 1],
	4: [4530, 5130, 1, 9496, 10096, 0, 18138, 18738, 0],
	5: [4512, 5112, 0, 8368, 8968, 0, 15650, 16250, 0],
	6: [3673, 4273, 0, 10598, 11198, 1, 15933, 16533, 0],
	7: [1593, 2193, 1, 7521, 8121, 0, 11162, 11762, 0],
	8: [2618, 3218, 0, 7615, 8215, 0, 13678, 14278, 0],
}
const PERIODS: Dictionary[int, int] = {
	1: 6075, 2: 6315, 3: 6343, 4: 6788, 5: 6801, 6: 6814, 7: 4500, 8: 5277
}
const COUNTS: Dictionary[int, int] = {1: 10, 2: 9, 3: 10, 4: 9, 5: 9, 6: 9, 7: 13, 8: 11}
const SQUAD_SHEETS: Array[String] = [
	"res://assets/art/iso/fossil/inf/rifle_squad_sheet.tres",
	"res://assets/art/iso/fossil/inf/rocket_squad_sheet.tres",
	"res://assets/art/iso/renew/inf/renew_rifle_sheet.tres",
	"res://assets/art/iso/renew/inf/renew_rocket_sheet.tres",
]

var _life: RigLife


func before_test() -> void:
	_life = RigLife.new()
	_life.setup(LifeSettings.new())


func test_the_walk_frame_is_floor_of_travel_plus_phase_over_the_quarter_mod_the_frames() -> void:
	var walk: PackedInt32Array = PackedInt32Array([0, 0, -1, 100])
	RigLife.travel_step(walk, 0, 7, 67 * 67, true, STRIDE)
	assert_int(walk[RigLife.W_STEP]).is_equal(67)
	assert_int(walk[RigLife.W_TICK]).is_equal(7)
	assert_int(RigLife.walk_frame(walk, 0, 0.0, QUARTER, 4)).is_equal(1)  # 100 / 88
	assert_int(RigLife.walk_frame(walk, 0, 0.5, QUARTER, 4)).is_equal(1)  # 133 / 88
	walk[RigLife.W_PHASE] = 120
	assert_int(RigLife.walk_frame(walk, 0, 0.5, QUARTER, 4)).is_equal(1)  # 153 / 88
	assert_int(RigLife.walk_frame(walk, 0, 1.0, QUARTER, 4)).is_equal(2)  # 187 / 88
	# Past four quarters the frame wraps: 300 and a phase of 100 are 400 / 88 = 4, which is 0.
	walk[RigLife.W_SUM] = 300
	walk[RigLife.W_PHASE] = 100
	walk[RigLife.W_STEP] = 0
	assert_int(RigLife.walk_frame(walk, 0, 0.0, QUARTER, 4)).is_equal(0)


func test_a_tick_joins_the_sum_once_and_a_new_tick_adds_the_step_of_the_last_one() -> void:
	var walk: PackedInt32Array = PackedInt32Array([0, 0, -1, 0])
	RigLife.travel_step(walk, 0, 5, 67 * 67, true, STRIDE)
	RigLife.travel_step(walk, 0, 5, 99 * 99, true, STRIDE)  # The same tick again: nothing.
	assert_array(walk).is_equal([0, 67, 5, 0])
	RigLife.travel_step(walk, 0, 6, 67 * 67, true, STRIDE)
	assert_array(walk).is_equal([67, 67, 6, 0])
	RigLife.travel_step(walk, 0, 7, 0, false, STRIDE)  # It stops: the last step joins, then none.
	assert_array(walk).is_equal([134, 0, 7, 0])
	RigLife.travel_step(walk, 0, 8, 0, false, STRIDE)
	assert_array(walk).is_equal([134, 0, 8, 0])


func test_the_sum_stays_below_the_stride_and_the_frame_does_not_notice() -> void:
	var wrapped: PackedInt32Array = PackedInt32Array([0, 0, -1, 40])
	var plain: int = 0  # The same ground summed without the wrap.
	for tick: int in 200:
		RigLife.travel_step(wrapped, 0, tick, 67 * 67, true, STRIDE)
		for part: int in 4:
			var alpha: float = float(part) / 4.0
			var want: int = (plain + int(alpha * 67.0) + 40) / QUARTER % 4
			assert_int(RigLife.walk_frame(wrapped, 0, alpha, QUARTER, 4)).is_equal(want)
		assert_int(wrapped[RigLife.W_SUM]).is_less(STRIDE)
		plain += 67


func test_the_step_is_the_straight_line_length_not_the_sum_of_the_axes() -> void:
	var walk: PackedInt32Array = PackedInt32Array([0, 0, -1, 0])
	RigLife.travel_step(walk, 0, 1, 47 * 47 + 47 * 47, true, STRIDE)
	assert_int(walk[RigLife.W_STEP]).is_equal(66)  # |dx| + |dy| would say 94.
	RigLife.travel_step(walk, 0, 2, 60 * 60 + 80 * 80, true, STRIDE)
	assert_int(walk[RigLife.W_STEP]).is_equal(100)  # A 3-4-5 move.


func test_the_idle_windows_of_ids_one_to_eight_are_the_pinned_ones() -> void:
	for id: int in WINDOWS:
		var pinned: Array = WINDOWS[id]
		for window: int in 3:
			var from: float = float(pinned[3 * window])
			var to: float = float(pinned[3 * window + 1])
			var frame: int = pinned[3 * window + 2]
			var note: String = "id %d window %d" % [id, window]
			var before: int = _life.pose_idle(id, 0.0, from - 0.5, 2)
			var inside: int = _life.pose_idle(id, 0.0, from + 0.5, 2)
			var last: int = _life.pose_idle(id, 0.0, to - 0.5, 2)
			var after: int = _life.pose_idle(id, 0.0, to + 0.5, 2)
			assert_array([before, inside, last, after]).override_failure_message(note).is_equal(
				[-1, frame, frame, -1]
			)


func test_each_id_has_one_window_in_each_of_its_cycles_which_last_four_to_seven_seconds() -> void:
	for id: int in WINDOWS:
		var starts: Array[float] = []
		var shown: bool = false
		var now: float = 0.5
		while now < 60000.0:
			var frame: int = _life.pose_idle(id, 0.0, now, 2)
			if frame >= 0 and not shown:
				starts.append(now)
			shown = frame >= 0
			now += 5.0
		assert_int(starts.size()).override_failure_message("id %d" % id).is_equal(COUNTS[id])
		var period: int = PERIODS[id]
		assert_int(period).is_between(4000, 7000)
		# One window begins in each cycle, in the first half of its spare time.
		for at: int in starts.size():
			var cycle: int = floori((starts[at] - 1500.0) / float(period))
			assert_int(cycle).is_equal(at)
			var into: float = starts[at] - 1500.0 - float(cycle * period)
			assert_float(into).is_between(0.0, float((period - 600) / 2 + 5))


func test_nothing_shows_before_idle_after_and_the_hull_shows_with_no_window() -> void:
	for id: int in 40:
		assert_int(_life.pose_idle(id, 1000.0, 1000.0, 2)).is_equal(-1)
		assert_int(_life.pose_idle(id, 1000.0, 2499.0, 2)).is_equal(-1)
	var off: LifeSettings = LifeSettings.new()
	off.idle_ms = 0
	var quiet: RigLife = RigLife.new()
	quiet.setup(off)
	for now: float in [3000.5, 9000.5, 30000.5]:
		assert_int(quiet.pose_idle(3, 0.0, now, 2)).is_equal(-1)
	assert_int(_life.pose_idle(3, 0.0, 2500.5, 0)).is_equal(-1)  # No idle frames: none.


func test_the_ids_use_both_idle_frames_and_their_windows_are_not_in_step() -> void:
	var frames: Dictionary[int, bool] = {}
	var firsts: Dictionary[int, bool] = {}
	for id: int in 60:
		var now: float = 0.5
		var found: bool = false
		while now < 12000.0:
			var frame: int = _life.pose_idle(id, 0.0, now, 2)
			if frame >= 0:
				frames[frame] = true
				if not found:
					firsts[int(now / 500.0)] = true
					found = true
				now += 600.0
			else:
				now += 25.0
	assert_array(frames.keys()).contains_exactly_in_any_order([0, 1])
	assert_int(firsts.size()).is_greater(5)  # The first windows of 60 ids start all over.


func test_pose_step_asks_again_only_outside_the_stretch_and_a_walk_forgets_the_stand() -> void:
	var state: RigLife.Idle = RigLife.Idle.new()
	assert_int(_life.pose_step(state, 3, 5000.0, true, 2)).is_equal(-1)  # It begins to stand.
	assert_float(state.still_ms).is_equal(5000.0)
	# Its windows are those of the id from 5000: id 3 shows frame 1 from 5000 + 2262.
	assert_int(_life.pose_step(state, 3, 7261.5, true, 2)).is_equal(-1)
	assert_int(_life.pose_step(state, 3, 7262.5, true, 2)).is_equal(1)
	assert_int(_life.pose_step(state, 3, 7861.5, true, 2)).is_equal(1)
	assert_int(_life.pose_step(state, 3, 7862.5, true, 2)).is_equal(-1)
	assert_int(_life.pose_step(state, 3, 7500.0, false, 2)).is_equal(-1)  # It walks off.
	assert_float(state.still_ms).is_equal(-1.0)
	assert_int(_life.pose_step(state, 3, 7600.0, true, 2)).is_equal(-1)  # It stands from here.
	assert_float(state.still_ms).is_equal(7600.0)
	assert_int(_life.pose_step(state, 3, 7600.0 + 2262.5, true, 2)).is_equal(1)
	state.reset()
	assert_float(state.still_ms).is_equal(-1.0)
	assert_int(state.pose).is_equal(-1)


func test_a_sheet_is_read_into_the_pose_with_its_offsets_frames_and_quarter_stride() -> void:
	var sheet: IsoSheetDef = load(SQUAD_SHEETS[0])
	var pose: RigLife.Pose = RigLife.Pose.new()
	assert_bool(pose.dress(sheet, 0.5)).is_true()
	assert_int(pose.quarter).is_equal(QUARTER)
	assert_array(pose.frames).is_equal([1, 4, 2])
	# The idle pose is anchored one px lower than the hull: its offset says so.
	assert_vector(pose.offsets[RigLife.POSE_HULL]).is_equal(Vector2(-43.0, -49.0) * 0.5)
	assert_vector(pose.offsets[RigLife.POSE_WALK]).is_equal(Vector2(-43.0, -49.0) * 0.5)
	assert_vector(pose.offsets[RigLife.POSE_IDLE]).is_equal(Vector2(-43.0, -50.0) * 0.5)


func test_a_stride_that_the_walk_frames_do_not_divide_gives_no_poses() -> void:
	var sheet: IsoSheetDef = (load(SQUAD_SHEETS[0]) as IsoSheetDef).duplicate() as IsoSheetDef
	var pose: RigLife.Pose = RigLife.Pose.new()
	sheet.stride_milli = 350  # 350 / 4 would floor to 87 and walk the cadence 1 % fast.
	assert_bool(pose.dress(sheet, 1.0)).is_false()
	assert_int(pose.quarter).is_equal(0)
	sheet.stride_milli = 0
	assert_bool(pose.dress(sheet, 1.0)).is_false()
	var plain: IsoSheetDef = load("res://assets/art/iso/fossil/veh/light_tank_sheet.tres")
	assert_bool(pose.dress(plain, 1.0)).is_false()  # A vehicle has no poses.


func test_every_squad_of_both_rosters_divides_its_stride_by_its_frames() -> void:
	for path: String in SQUAD_SHEETS:
		var sheet: IsoSheetDef = load(path)
		var pose: RigLife.Pose = RigLife.Pose.new()
		(
			assert_int(sheet.stride_milli % sheet.frame_count(&"walk"))
			. override_failure_message(path)
			. is_equal(0)
		)
		assert_bool(pose.dress(sheet, 1.0)).override_failure_message(path).is_true()
