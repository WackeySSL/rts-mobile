extends GdUnitTestSuite
## The clock and the variation of the unit life (plan P136, ADR 0027 section 2): match time is
## `(tick + alpha) x 1000 / 15` ms and does not move while the runner is paused; an age is the
## clock minus a birth, never below 0 (WORKER mode restarts alpha at 0 after a pause, which steps
## the clock back by up to a tick); `mix` is an integer hash of an id and a salt, pinned by golden
## values and by how it spreads a fixed set of 1000 ids. The golden values were computed with an
## independent implementation of the same mix (Python big integers, masked to 32 bits after every
## product), so the 64-bit wrap of GDScript's integers is not what the table rests on.

const Rig: GDScript = preload("res://tests/view/support/recoil_rig.gd")
## [id, salt, mix]: the mix of the constants in LifeClock.gd.
const GOLDEN: Array[Vector3i] = [
	Vector3i(0, 0, 1601874631),
	Vector3i(1, 0, 1801978118),
	Vector3i(1, 1, 209679636),
	Vector3i(2, 0, 134257143),
	Vector3i(7, 3, 1850719245),
	Vector3i(100, 5, 107494402),
	Vector3i(12345, 678, 1170323460),
	Vector3i(2147483647, 0, 1623258970),
	Vector3i(2147483647, 2147483647, 922299706),  # The largest pair: no product passes 2^63.
]
## Ids 1 to 1000 in each of four windows, for salts 0 and 1, and in each of ten for salt 0.
const FOUR_WINDOWS_SALT_0: Array[int] = [258, 232, 245, 265]
const FOUR_WINDOWS_SALT_1: Array[int] = [272, 246, 262, 220]
const TEN_WINDOWS_SALT_0: Array[int] = [95, 108, 103, 94, 89, 100, 111, 113, 105, 82]


func after_test() -> void:
	CommandQueue.clear()


func test_match_time_is_the_tick_plus_alpha_at_the_tick_rate_in_ms() -> void:
	var snap: MatchSnapshot = MatchSnapshot.new()
	snap.tick = 0
	assert_float(LifeClock.ms(snap, 0.0)).is_equal(0.0)
	snap.tick = 30
	assert_float(LifeClock.ms(snap, 0.0)).is_equal(2000.0)
	assert_float(LifeClock.ms(snap, 0.375)).is_equal(2025.0)
	snap.tick = 1
	assert_float(LifeClock.ms(snap, 0.0)).is_equal_approx(1000.0 / 15.0, 0.0001)
	assert_float(LifeClock.ms(snap, 1.0)).is_equal_approx(2000.0 / 15.0, 0.0001)
	assert_float(LifeClock.tick_ms(15)).is_equal(1000.0)
	assert_float(LifeClock.tick_ms(0)).is_equal(0.0)
	snap.tick = 54000  # An hour of match: the clock still counts in whole ms to a tenth.
	assert_float(LifeClock.ms(snap, 0.5)).is_equal_approx(3600033.333, 0.001)


func test_an_age_is_the_clock_minus_the_birth_and_never_negative() -> void:
	assert_float(LifeClock.age_ms(2100.0, 2000.0)).is_equal(100.0)
	assert_float(LifeClock.age_ms(2000.0, 2000.0)).is_equal(0.0)
	assert_float(LifeClock.age_ms(1933.0, 2000.0)).is_equal(0.0)  # The clock stepped back.
	var snap: MatchSnapshot = MatchSnapshot.new()
	snap.tick = 31
	# An event of tick 31 is born at 2066.7: the frame that first shows the tick at alpha 0 has
	# age 0, and a resume that restarts alpha at 0 on the tick before gives age 0 too, not -66.7.
	assert_float(LifeClock.age_ms(LifeClock.ms(snap, 0.0), LifeClock.tick_ms(31))).is_equal(0.0)
	snap.tick = 30
	assert_float(LifeClock.age_ms(LifeClock.ms(snap, 0.0), LifeClock.tick_ms(31))).is_equal(0.0)


func test_match_time_stands_still_while_the_runner_is_paused() -> void:
	var runner: MatchRunner = auto_free(Rig.runner())
	runner.paused = false
	runner._process(1.0 / 30.0)  # Half a tick.
	var at: float = LifeClock.ms(runner.snapshot, runner.alpha())
	assert_float(at).is_equal_approx(33.333, 0.01)
	runner._process(1.0 / 30.0)  # The second half: a tick is played, alpha restarts.
	assert_int(runner.snapshot.tick).is_equal(1)
	var played: float = LifeClock.ms(runner.snapshot, runner.alpha())
	assert_float(played).is_equal_approx(66.667, 0.01)
	runner.paused = true
	for _frame: int in 50:  # A second of frames, also long ones.
		runner._process(0.016)
		runner._process(0.5)
	assert_float(LifeClock.ms(runner.snapshot, runner.alpha())).is_equal(played)
	runner.paused = false
	runner._process(1.0 / 30.0)
	assert_float(LifeClock.ms(runner.snapshot, runner.alpha())).is_equal_approx(
		played + 33.333, 0.01
	)


func test_mix_matches_its_golden_values() -> void:
	for golden: Vector3i in GOLDEN:
		(
			assert_int(LifeClock.mix(golden.x, golden.y))
			. override_failure_message("mix(%d, %d)" % [golden.x, golden.y])
			. is_equal(golden.z)
		)


func test_mix_is_31_bits_and_depends_on_both_the_id_and_the_salt() -> void:
	var seen: Dictionary[int, bool] = {}
	for id: int in range(1, 1001):
		var value: int = LifeClock.mix(id, 0)
		assert_int(value).is_between(0, 0x7FFFFFFF)
		seen[value] = true
	assert_int(seen.size()).is_equal(1000)  # No collision among the first 1000 ids.
	assert_int(LifeClock.mix(5, 1)).is_not_equal(LifeClock.mix(5, 2))
	assert_int(LifeClock.mix(5, 1)).is_not_equal(LifeClock.mix(6, 1))
	assert_int(LifeClock.mix(5, 1)).is_equal(LifeClock.mix(5, 1))  # And is the same every time.
	assert_int(LifeClock.mix(5, 1)).is_not_equal(LifeClock.mix(1, 5))  # Not symmetric.


func test_mix_puts_exactly_the_pinned_number_of_1000_ids_in_each_window() -> void:
	assert_array(_windows(0, 4)).is_equal(FOUR_WINDOWS_SALT_0)
	assert_array(_windows(1, 4)).is_equal(FOUR_WINDOWS_SALT_1)
	assert_array(_windows(0, 10)).is_equal(TEN_WINDOWS_SALT_0)


func test_pick_is_the_mix_as_one_of_count_slots() -> void:
	assert_int(LifeClock.pick(1, 0, 4)).is_equal(1801978118 % 4)
	assert_int(LifeClock.pick(12345, 678, 1000)).is_equal(1170323460 % 1000)
	assert_int(LifeClock.pick(7, 3, 1)).is_equal(0)
	assert_int(LifeClock.pick(7, 3, 0)).is_equal(0)  # No window: slot 0, not a division by zero.


## How many of the ids 1 to 1000 fall in each of `count` windows by `salt`.
func _windows(salt: int, count: int) -> Array[int]:
	var found: Array[int] = []
	found.resize(count)
	found.fill(0)
	for id: int in range(1, 1001):
		found[LifeClock.pick(id, salt, count)] += 1
	return found
