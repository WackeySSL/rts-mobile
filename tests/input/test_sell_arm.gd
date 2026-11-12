extends GdUnitTestSuite
## The two-tap Sell's state (plan P272, ADR 0037 section 3): the first press arms, the second sends
## only from `arm_min_ms` to before `confirm_ms` after it; a press sooner is ignored and keeps the
## arm; a press at or after `confirm_ms` or for another building arms again; the window runs out and
## a disarm clear it. Pure: the times are passed in.

const MIN_MS: int = 400
const CONFIRM_MS: int = 3000
const A: int = 7
const B: int = 9

var _arm: SellArm


func before_test() -> void:
	_arm = SellArm.new()


func _press(id: int, now: int) -> SellArm.Result:
	return _arm.press(id, now, MIN_MS, CONFIRM_MS)


func test_the_first_press_arms_and_the_second_after_the_minimum_sends() -> void:
	assert_bool(_arm.is_armed()).is_false()
	assert_int(_press(A, 1000)).is_equal(SellArm.Result.ARMED)
	assert_bool(_arm.is_armed()).is_true()
	assert_int(_press(A, 1000 + MIN_MS)).is_equal(SellArm.Result.SEND)
	assert_bool(_arm.is_armed()).is_false()  # A send ends the arm: the next press arms again.
	assert_int(_press(A, 1000 + MIN_MS + 10)).is_equal(SellArm.Result.ARMED)


func test_a_second_press_before_the_minimum_is_ignored_and_keeps_the_arm() -> void:
	_press(A, 1000)
	assert_int(_press(A, 1000)).is_equal(SellArm.Result.IGNORED)  # The same instant.
	assert_int(_press(A, 1000 + MIN_MS - 1)).is_equal(SellArm.Result.IGNORED)
	assert_bool(_arm.is_armed()).is_true()
	assert_int(_arm.armed_at).is_equal(1000)  # An ignored press does not restart the window.
	assert_int(_press(A, 1000 + MIN_MS)).is_equal(SellArm.Result.SEND)


func test_a_press_at_or_after_the_window_arms_again_and_never_sends() -> void:
	_press(A, 1000)
	assert_int(_press(A, 1000 + CONFIRM_MS - 1)).is_equal(SellArm.Result.SEND)
	_press(A, 5000)
	assert_int(_press(A, 5000 + CONFIRM_MS)).is_equal(SellArm.Result.ARMED)  # Re-arms.
	assert_int(_arm.armed_at).is_equal(5000 + CONFIRM_MS)
	assert_int(_press(A, 5000 + CONFIRM_MS + 100)).is_equal(SellArm.Result.IGNORED)


## A resting thumb: one press-and-release is one tap however long it rests, so it arms at most.
func test_one_tap_never_sends() -> void:
	assert_int(_press(A, 1000)).is_equal(SellArm.Result.ARMED)
	assert_bool(_arm.expired(1000 + CONFIRM_MS, CONFIRM_MS)).is_true()


func test_a_press_for_another_building_arms_that_one() -> void:
	_press(A, 1000)
	assert_int(_press(B, 1000 + MIN_MS + 1)).is_equal(SellArm.Result.ARMED)
	assert_int(_arm.target).is_equal(B)
	assert_int(_press(B, 1000 + 2 * MIN_MS + 2)).is_equal(SellArm.Result.SEND)


func test_the_window_running_out_and_a_disarm_clear_the_arm() -> void:
	assert_bool(_arm.expired(99999, CONFIRM_MS)).is_false()  # Nothing armed, nothing to expire.
	_press(A, 1000)
	assert_bool(_arm.expired(1000 + CONFIRM_MS - 1, CONFIRM_MS)).is_false()
	assert_bool(_arm.expired(1000 + CONFIRM_MS, CONFIRM_MS)).is_true()
	_arm.disarm()
	assert_bool(_arm.is_armed()).is_false()
	assert_bool(_arm.expired(99999, CONFIRM_MS)).is_false()
	assert_int(_press(A, 1000 + MIN_MS + 1)).is_equal(SellArm.Result.ARMED)  # Never SEND after it.
