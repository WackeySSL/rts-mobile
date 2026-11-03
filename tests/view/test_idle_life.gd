extends GdUnitTestSuite
## The idle life's three functions (plan P140, ADR 0027 sections 2 and 3): `RigLife.shake_offset`,
## `look_side` and `sweep_offset` are functions of a unit id and the match time alone, drawn with
## `LifeClock.mix`. Golden values and exact counts for a fixed set of 20 ids (ids 1 to 20), restated
## in Python from the same mix (a second implementation, not a copy of the GDScript), so a change
## of a salt, a range or a rule shows up here. The layers' use of them is in test_idle_units.gd and
## test_idle_heads.gd.

const IDS: int = 20
const LOOK_SCAN_MS: int = 60000
const LOOK_STEP_MS: int = 10
const BUCKET_MS: int = 5000
const BUCKETS: int = 12
## The ids that look at some instant of each 5 s bucket of the first minute, and the windows they
## open in all (every id's 6 to 10 s cycle holds one).
const LOOKING_PER_BUCKET: Array[int] = [13, 16, 14, 18, 14, 12, 12, 15, 14, 16, 14, 13]
const LOOK_WINDOWS: Array[int] = [10, 8, 8, 6, 8, 8, 7, 9, 6, 9, 7, 6, 7, 6, 7, 7, 7, 9, 8, 6]
## Each id's cycle: look_every_ms 6000 plus mix(id, SALT_LOOK) of 0 to 4000.
const PERIODS: Array[int] = [
	6153,
	8259,
	7531,
	9636,
	7279,
	6855,
	9803,
	6796,
	8755,
	7044,
	9594,
	9934,
	8990,
	9986,
	9357,
	8148,
	8509,
	7325,
	7204,
	9853
]

## Each id's shake phase, mix(id, SALT_SHAKE) of 80: its 80 ms steps end at the ms with
## (ms + phase) % 80 == 0.
const SHAKE_PHASES: Array[int] = [
	7, 57, 0, 65, 41, 35, 41, 20, 6, 33, 25, 61, 39, 54, 7, 65, 21, 55, 33, 47
]
## The windows that ids 1, 4, 7 and 14 open in 120 s (a window cut off at the start counts too).
const WINDOWS_120S: Dictionary[int, int] = {1: 19, 4: 12, 7: 13, 14: 12}
## The windows each of the 20 ids opens in 24 s when every cycle is 6 s (look_every_spread_ms 0).
const WINDOWS_24S_SIX_SECOND_CYCLES: Array[int] = [
	5, 4, 4, 4, 4, 4, 5, 4, 4, 4, 4, 4, 4, 4, 4, 5, 4, 4, 4, 4
]

var _life: LifeSettings
var _rig: RigLife


func before_test() -> void:
	_life = LifeSettings.new()
	_rig = RigLife.new()
	_rig.setup(_life)


func test_the_shake_matches_its_golden_values() -> void:
	assert_vector(_rig.shake_offset(1, 0.0)).is_equal(Vector2(-0.5, 0.5))
	assert_vector(_rig.shake_offset(1, 40.0)).is_equal(Vector2(-0.5, 0.5))  # The same step.
	assert_vector(_rig.shake_offset(1, 80.0)).is_equal(Vector2(0.5, 0.5))
	assert_vector(_rig.shake_offset(2, 0.0)).is_equal(Vector2(-0.5, 0.0))
	assert_vector(_rig.shake_offset(7, 1234.0)).is_equal(Vector2(0.5, 0.0))
	assert_vector(_rig.shake_offset(20, 99999.0)).is_equal(Vector2(0.5, -0.5))


func test_the_shake_of_20_ids_at_one_instant_is_spread_over_the_nine_offsets_as_pinned() -> void:
	var counts: Dictionary[Vector2, int] = {}
	for id: int in range(1, IDS + 1):
		var offset: Vector2 = _rig.shake_offset(id, 0.0)
		counts[offset] = counts.get(offset, 0) + 1
	assert_int(counts.size()).is_equal(8)  # All but (0, -0.5) turn up in this set.
	assert_int(counts[Vector2(-0.5, -0.5)]).is_equal(3)
	assert_int(counts[Vector2(-0.5, 0.0)]).is_equal(1)
	assert_int(counts[Vector2(-0.5, 0.5)]).is_equal(6)
	assert_int(counts[Vector2(0.0, 0.0)]).is_equal(2)
	assert_int(counts[Vector2(0.0, 0.5)]).is_equal(1)
	assert_int(counts[Vector2(0.5, -0.5)]).is_equal(2)
	assert_int(counts[Vector2(0.5, 0.0)]).is_equal(1)
	assert_int(counts[Vector2(0.5, 0.5)]).is_equal(4)


func test_the_shake_is_in_whole_half_pixels_within_shake_px_and_changes_once_per_shake_ms() -> void:
	# For every id, over 2 s in 1 ms steps: each axis is a multiple of 0.5 and at most shake_px, the
	# offset changes only on a step boundary of the id, (ms + phase) % 80 == 0 (25 of them in 2 s, an
	# eighth of which repeat the offset), so never twice inside one, 441 times in all for the 20
	# ids and 25 at the most for one.
	var off_grid: int = 0
	var too_far: int = 0
	var off_boundary: int = 0
	var total: int = 0
	var most_changes: int = 0
	for id: int in range(1, IDS + 1):
		var changes: int = 0
		var last: Vector2 = _rig.shake_offset(id, 0.0)
		for ms: int in range(1, 2000):
			var offset: Vector2 = _rig.shake_offset(id, float(ms))
			if absf(offset.x) > _life.shake_px or absf(offset.y) > _life.shake_px:
				too_far += 1
			if fposmod(offset.x, 0.5) != 0.0 or fposmod(offset.y, 0.5) != 0.0:
				off_grid += 1
			if offset != last:
				changes += 1
				last = offset
				if (ms + SHAKE_PHASES[id - 1]) % 80 != 0:
					off_boundary += 1
		total += changes
		most_changes = maxi(most_changes, changes)
	assert_int(too_far).is_equal(0)
	assert_int(off_grid).is_equal(0)
	assert_int(off_boundary).is_equal(0)
	assert_int(total).is_equal(441)
	assert_int(most_changes).is_equal(25)


func test_the_shake_follows_the_numbers_of_the_settings() -> void:
	_life.shake_px = 0.4  # Under one step: nothing shakes.
	assert_vector(_rig.shake_offset(1, 0.0)).is_equal(Vector2.ZERO)
	_life.shake_px = 0.0
	assert_vector(_rig.shake_offset(1, 0.0)).is_equal(Vector2.ZERO)
	_life.shake_px = 1.0  # Two steps either way, at most 1 px.
	var widest: float = 0.0
	for id: int in range(1, IDS + 1):
		for step: int in 50:
			var offset: Vector2 = _rig.shake_offset(id, float(step * 80))
			widest = maxf(widest, maxf(absf(offset.x), absf(offset.y)))
	assert_float(widest).is_equal(1.0)
	_life.shake_px = 0.9  # Whole steps below it: 0.5.
	for id: int in range(1, IDS + 1):
		assert_float(absf(_rig.shake_offset(id, 123.0).x)).is_less_equal(0.5)
	_life.shake_px = 0.5
	_life.shake_ms = 0
	assert_vector(_rig.shake_offset(1, 0.0)).is_equal(Vector2.ZERO)
	_life.shake_ms = 160  # Half as often: 12.5 boundaries in 2 s, 220 changes in all, 13 at the most.
	var most: int = 0
	var total: int = 0
	var off_boundary: int = 0
	for id: int in range(1, IDS + 1):
		var changes: int = 0
		var phase: int = LifeClock.pick(id, RigLife.SALT_SHAKE, 160)
		var last: Vector2 = _rig.shake_offset(id, 0.0)
		for ms: int in range(1, 2000):
			var offset: Vector2 = _rig.shake_offset(id, float(ms))
			if offset != last:
				changes += 1
				last = offset
				if (ms + phase) % 160 != 0:
					off_boundary += 1
		total += changes
		most = maxi(most, changes)
	assert_int(off_boundary).is_equal(0)
	assert_int(total).is_equal(220)
	assert_int(most).is_equal(13)


func test_the_shake_is_the_same_on_two_runs() -> void:
	var other: RigLife = RigLife.new()
	other.setup(LifeSettings.new())
	for id: int in range(1, IDS + 1):
		for ms: int in range(0, 3000, 37):
			assert_vector(_rig.shake_offset(id, float(ms))).is_equal(
				other.shake_offset(id, float(ms))
			)


func test_each_id_has_its_own_cycle_of_6_to_10_s_as_pinned() -> void:
	for id: int in range(1, IDS + 1):
		var period: int = _life.look_every_ms + LifeClock.pick(id, RigLife.SALT_LOOK, 4001)
		assert_int(period).is_between(6000, 10000)
		assert_int(period).override_failure_message("id %d" % id).is_equal(PERIODS[id - 1])


@warning_ignore("integer_division")
func test_the_looking_ids_of_each_5_s_bucket_and_the_windows_are_as_pinned() -> void:
	var looking: Array[int] = []
	looking.resize(BUCKETS)
	looking.fill(0)
	var windows: Array[int] = []
	for id: int in range(1, IDS + 1):
		var seen: Dictionary[int, bool] = {}
		var count: int = 0
		var before: int = 0
		for ms: int in range(0, LOOK_SCAN_MS, LOOK_STEP_MS):
			var side: int = _rig.look_side(id, float(ms))
			if side != 0:
				seen[ms / BUCKET_MS] = true
				if before == 0:
					count += 1
			before = side
		for bucket: int in seen:
			looking[bucket] += 1
		windows.append(count)
	assert_array(looking).is_equal(LOOKING_PER_BUCKET)
	assert_array(windows).is_equal(LOOK_WINDOWS)


@warning_ignore("integer_division")
func test_a_look_is_one_frame_aside_for_look_ms_once_per_cycle_and_never_back_to_back() -> void:
	# Four ids over two minutes in 1 ms steps: every window that is not cut off by the start lasts
	# exactly 900 ms on one side, there is one in each of the id's cycles, two windows are at least
	# (cycle - 900) / 2 apart (a window starts in the first half of the spare time), and both sides
	# turn up.
	var sides: Dictionary[int, int] = {}
	for id: int in [1, 4, 7, 14]:
		var period: int = PERIODS[id - 1]
		var starts: Array[int] = []
		var bad_length: int = 0
		var mixed_sides: int = 0
		var too_close: int = 0
		var run: int = 0
		var run_side: int = 0
		var last_end: int = -1
		for ms: int in range(0, 120000):
			var side: int = _rig.look_side(id, float(ms))
			if side != 0:
				if run == 0:
					starts.append(ms)
					run_side = side
					if last_end >= 0 and ms - last_end < (period - 900) / 2:
						too_close += 1
				if side != run_side:
					mixed_sides += 1
				run += 1
			elif run > 0:
				if run != 900 and starts[-1] != 0:
					bad_length += 1
				sides[run_side] = sides.get(run_side, 0) + 1
				run = 0
				last_end = ms
		var note: String = "id %d" % id
		assert_int(bad_length).override_failure_message(note).is_equal(0)
		assert_int(mixed_sides).override_failure_message(note).is_equal(0)
		assert_int(too_close).override_failure_message(note).is_equal(0)
		# 120 s hold 120000 / period cycles, plus or minus the one the scan cuts at an end: pinned.
		assert_int(starts.size()).override_failure_message(note).is_equal(WINDOWS_120S[id])
	assert_bool(sides.has(-1) and sides.has(1)).is_true()


func test_a_look_is_off_for_a_zero_window_and_for_one_as_long_as_the_cycle() -> void:
	_life.look_ms = 0
	assert_int(_rig.look_side(1, 3000.0)).is_equal(0)
	_life.look_ms = 6000  # Not below look_every_ms: no gap left to look in.
	assert_int(_rig.look_side(1, 3000.0)).is_equal(0)
	_life.look_ms = 900
	assert_int(_rig.look_side(1, 3000.0)).is_equal(-1)  # The golden value again.
	assert_int(_rig.look_side(1, 0.0)).is_equal(0)
	assert_int(_rig.look_side(3, 1000.0)).is_equal(0)
	_life.look_every_spread_ms = 0  # Every cycle 6 s.
	var counts: Array[int] = []
	for id: int in range(1, IDS + 1):
		var windows: int = 0
		var before: int = 0
		for ms: int in range(0, 24000, 10):
			var side: int = _rig.look_side(id, float(ms))
			if side != 0 and before == 0:
				windows += 1
			before = side
		counts.append(windows)  # 24 s of 6 s cycles: four, and a fifth where the phase cuts one.
	assert_array(counts).is_equal(WINDOWS_24S_SIX_SECOND_CYCLES)


func test_the_sweep_matches_its_golden_values() -> void:
	assert_int(_rig.sweep_offset(1, 0.0)).is_equal(1)
	assert_int(_rig.sweep_offset(1, 700.0)).is_equal(0)
	assert_int(_rig.sweep_offset(1, 1400.0)).is_equal(-1)
	assert_int(_rig.sweep_offset(4, 0.0)).is_equal(-1)
	assert_int(_rig.sweep_offset(4, 5600.0)).is_equal(-1)  # A whole cycle of 8 x 700 ms later.
	assert_int(_rig.sweep_offset(9, 12345.0)).is_equal(-1)


func test_the_sweep_of_20_ids_at_one_instant_is_spread_as_pinned() -> void:
	var counts: Dictionary[int, int] = {}
	for id: int in range(1, IDS + 1):
		var frames: int = _rig.sweep_offset(id, 0.0)
		counts[frames] = counts.get(frames, 0) + 1
	assert_int(counts[-2] if counts.has(-2) else 0).is_equal(0)
	assert_int(counts[-1]).is_equal(6)
	assert_int(counts[0]).is_equal(3)
	assert_int(counts[1]).is_equal(5)
	assert_int(counts[2]).is_equal(6)


func test_the_sweep_walks_one_frame_at_a_time_within_reach_and_holds_each_frame_sweep_ms() -> void:
	# One id over three cycles in 1 ms steps: a frame holds exactly 700 ms (bar the first, which the
	# scan may cut), the steps are one frame, the walk is 0, 1, 2, 1, 0, -1, -2, -1 and round again,
	# and it reaches both ends.
	var walk: Array[int] = []
	var last: int = _rig.sweep_offset(4, 0.0)
	walk.append(last)
	var held: int = 1
	var bad_hold: int = 0
	var bad_step: int = 0
	var out_of_reach: int = 0
	for ms: int in range(1, 3 * 5600):
		var frames: int = _rig.sweep_offset(4, float(ms))
		if absi(frames) > 2:
			out_of_reach += 1
		if frames != last:
			if absi(frames - last) != 1:
				bad_step += 1
			if walk.size() > 1 and held != 700:
				bad_hold += 1
			walk.append(frames)
			last = frames
			held = 0
		held += 1
	assert_int(out_of_reach).is_equal(0)
	assert_int(bad_step).is_equal(0)
	assert_int(bad_hold).is_equal(0)
	var cycle: Array[int] = [0, 1, 2, 1, 0, -1, -2, -1]
	var at: int = -1  # The frame alone does not say which way the walk goes: the next one does.
	for index: int in cycle.size():
		if cycle[index] == walk[0] and cycle[(index + 1) % 8] == walk[1]:
			at = index
	assert_int(at).is_greater_equal(0)
	for index: int in walk.size():
		assert_int(walk[index]).is_equal(cycle[(at + index) % 8])
	assert_int(walk.size()).is_equal(25)  # The frame at 0 and 24 changes (245 + 700 k, k < 24).


func test_the_sweep_follows_the_numbers_of_the_settings() -> void:
	_life.sweep_frames = 3  # A longer walk: 12 steps, 0 to 3 and -3.
	var seen: Dictionary[int, bool] = {}
	for ms: int in range(0, 12 * 700, 100):
		seen[_rig.sweep_offset(5, float(ms))] = true
	assert_array(seen.keys()).contains_exactly_in_any_order([-3, -2, -1, 0, 1, 2, 3])
	_life.sweep_frames = 0
	assert_int(_rig.sweep_offset(5, 1000.0)).is_equal(0)
	_life.sweep_frames = 2
	_life.sweep_ms = 0
	assert_int(_rig.sweep_offset(5, 1000.0)).is_equal(0)
	_life.sweep_ms = 350  # Twice as fast: the same walk in half the time.
	var steps: int = 0
	var last: int = _rig.sweep_offset(5, 0.0)
	for ms: int in range(1, 2800):
		var frames: int = _rig.sweep_offset(5, float(ms))
		if frames != last:
			steps += 1
			last = frames
	assert_int(steps).is_equal(8)  # 2800 ms / 350 ms = 8 holds.


func test_an_answer_holds_for_the_span_the_function_reports() -> void:
	# A layer asks again only outside [span_from, span_to): inside it, at its first ms, half way and
	# at its last whole ms, every function must answer as it did, for every id and many instants.
	var wrong: int = 0
	var outside: int = 0
	for kind: int in 3:
		for id: int in range(1, IDS + 1):
			for ms: int in range(0, 60000, 457):
				var at: float = float(ms) + 0.25
				var answer: Variant = _answer(kind, id, at)
				var from: float = _rig.span_from
				var to: float = _rig.span_to
				if at < from or at >= to:
					outside += 1
				for probe: float in [maxf(from, 0.0), (maxf(from, 0.0) + to) * 0.5, to - 1.0]:
					if probe >= from and probe < to and _answer(kind, id, probe) != answer:
						wrong += 1
	assert_int(outside).is_equal(0)
	assert_int(wrong).is_equal(0)


func test_a_function_that_is_off_holds_for_ever() -> void:
	_life.shake_px = 0.0
	_life.look_ms = 0
	_life.sweep_frames = 0
	for call: Callable in [
		func() -> void: _rig.shake_offset(3, 1234.0),
		func() -> void: _rig.look_side(3, 1234.0),
		func() -> void: _rig.sweep_offset(3, 1234.0)
	]:
		call.call()
		assert_float(_rig.span_from).is_equal(0.0)
		assert_bool(is_inf(_rig.span_to)).is_true()


## What the idle function `kind` (0 shake, 1 look, 2 sweep) answers for `id` at `at` ms.
func _answer(kind: int, id: int, at: float) -> Variant:
	match kind:
		0:
			return _rig.shake_offset(id, at)
		1:
			return _rig.look_side(id, at)
	return _rig.sweep_offset(id, at)
