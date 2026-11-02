extends GdUnitTestSuite
## The income behind the economy card's "+N/min" (plan P119b, ADR 0025 section 3): the player's
## harvested total over the last 60 s of match ticks, from a ring of 60 one-second samples. Crafted
## `stat_harvested` samples at crafted ticks: a steady harvest, a change of pace, several ticks in
## one second, a snapshot that skips seconds, a new match, a clock that goes back. Pure: no node.

const TICKS: int = Sim.TICK_RATE
const MINUTE: int = IncomeRing.SECONDS

var _ring: IncomeRing


func before_test() -> void:
	_ring = IncomeRing.new()


## 100 credits a second: after a minute the figure is 6 000 and stays there; before that it is what
## was harvested since the first sample (not scaled up to a rate).
func test_a_steady_harvest_gives_the_last_minutes_total() -> void:
	for second: int in range(0, 3 * MINUTE + 1):
		_ring.feed(second * TICKS, 100 * second)
		var want: int = 100 * mini(second, MINUTE)
		assert_int(_ring.per_minute()).override_failure_message("second %d" % second).is_equal(want)


func test_a_change_of_pace_drops_out_of_the_figure_after_a_minute() -> void:
	var total: int = 0
	for second: int in range(0, MINUTE + 1):  # 100 a second for the first minute.
		_ring.feed(second * TICKS, total)
		total += 100
	var after: int = total - 100
	assert_int(_ring.per_minute()).is_equal(6000)
	for second: int in range(MINUTE + 1, MINUTE + 31):  # Then nothing for 30 s.
		_ring.feed(second * TICKS, after)
	assert_int(_ring.per_minute()).is_equal(3000)  # Only the last 30 s of the harvest are left.
	for second: int in range(MINUTE + 31, 2 * MINUTE + 1):
		_ring.feed(second * TICKS, after)
	assert_int(_ring.per_minute()).is_equal(0)


## The ring is the match's clock: ticks inside one second change nothing, and the sample of a second
## is the first total seen in it.
func test_ticks_in_one_second_change_nothing_and_a_second_samples_its_first_total() -> void:
	_ring.feed(0, 0)
	for tick: int in range(1, TICKS):
		_ring.feed(tick, 40 * tick)
		assert_int(_ring.per_minute()).is_equal(0)
	_ring.feed(TICKS, 700)  # Second 1 starts: its sample is 700.
	assert_int(_ring.per_minute()).is_equal(700)
	_ring.feed(TICKS + 5, 9000)  # Inside second 1: not sampled, not shown.
	assert_int(_ring.per_minute()).is_equal(700)
	for second: int in range(2, MINUTE + 1):
		_ring.feed(second * TICKS, 700)
	_ring.feed((MINUTE + 1) * TICKS, 1000)  # A minute after second 1: against its first total, 700.
	assert_int(_ring.per_minute()).is_equal(300)


func test_the_first_sample_is_every_slots_and_starts_at_nothing() -> void:
	_ring.feed(30 * TICKS, 5000)  # A pill that first sees the match in its 30th second.
	assert_int(_ring.per_minute()).is_equal(0)
	_ring.feed(31 * TICKS, 5100)
	assert_int(_ring.per_minute()).is_equal(100)


## A snapshot that skips seconds (a long frame) fills them on the straight line between the totals,
## so a steady harvest stays steady a minute later.
func test_a_jump_of_seconds_fills_the_skipped_ones_on_a_line() -> void:
	_ring.feed(0, 0)
	_ring.feed(10 * TICKS, 1000)
	assert_int(_ring.per_minute()).is_equal(1000)
	for second: int in range(11, MINUTE + 11):
		_ring.feed(second * TICKS, 1000 + 100 * (second - 10))
		if second >= MINUTE + 1:
			var why: String = "second %d" % second
			assert_int(_ring.per_minute()).override_failure_message(why).is_equal(6000)


## A jump of a minute or more says nothing about the minute before it: the figure starts again.
func test_a_jump_of_a_minute_forgets_the_history() -> void:
	_ring.feed(0, 0)
	_ring.feed(10 * TICKS, 500)
	_ring.feed(100 * TICKS, 5000)
	assert_int(_ring.per_minute()).is_equal(0)
	_ring.feed(101 * TICKS, 5100)
	assert_int(_ring.per_minute()).is_equal(100)


func test_a_new_match_starts_again() -> void:
	_ring.feed(0, 0)
	_ring.feed(30 * TICKS, 3000)
	assert_int(_ring.per_minute()).is_equal(3000)
	_ring.reset()
	assert_int(_ring.per_minute()).is_equal(0)
	_ring.feed(31 * TICKS, 9000)  # The next match's first sample.
	assert_int(_ring.per_minute()).is_equal(0)
	_ring.feed(32 * TICKS, 9100)
	assert_int(_ring.per_minute()).is_equal(100)


func test_a_clock_that_goes_back_starts_again_and_the_figure_is_never_negative() -> void:
	_ring.feed(100 * TICKS, 8000)
	_ring.feed(101 * TICKS, 8100)
	_ring.feed(5 * TICKS, 50)  # Another match's tick, without a reset.
	assert_int(_ring.per_minute()).is_equal(0)
	_ring.feed(6 * TICKS, 80)
	assert_int(_ring.per_minute()).is_equal(30)
	_ring.feed(7 * TICKS, 20)  # A total that fell (it never does): no negative income.
	assert_int(_ring.per_minute()).is_equal(0)


## The ring has 60 samples whatever is fed: made once, never grown.
func test_the_ring_keeps_its_60_samples_whatever_is_fed() -> void:
	assert_int(_ring._ring.size()).is_equal(MINUTE)
	_ring.feed(0, 1)
	_ring.feed(7 * TICKS, 100)
	_ring.feed(500 * TICKS, 9000)
	_ring.reset()
	_ring.feed(3 * TICKS, 2)
	assert_int(_ring._ring.size()).is_equal(MINUTE)
	assert_int(IncomeRing.SECONDS).is_equal(60)
