class_name SellArm
extends RefCounted
## The two-tap Sell's state (ADR 0037 section 3, plan P272): pure, time passed in, no Node. The
## first tap arms it for a building; the second sends only from `arm_min_ms` to before `confirm_ms`
## after the arm. A second tap sooner is ignored and keeps the arm (a double-tap's second half must
## not sell); one at or after `confirm_ms`, or for another building, arms again; any other touch or
## the window running out disarms (`disarm`, `expired`). It is never a hold: only a tap calls
## `press`.

enum Result { ARMED, IGNORED, SEND }

var target: int = -1  ## The building id the arm is for, -1 when not armed.
var armed_at: int = 0  ## The ms of the release of the tap that armed it.


func is_armed() -> bool:
	return target >= 0


## A tap on Sell for building `id`: its finger went down at `down_ms` and up at `up_ms`. The gap
## `sell_arm_min_ms` guards runs from the arming tap's release to this tap's press, so a double-tap
## never sells however short its second contact. An arm is made at the release.
func press(id: int, down_ms: int, up_ms: int, arm_min_ms: int, confirm_ms: int) -> Result:
	if target != id or down_ms - armed_at >= confirm_ms:
		target = id
		armed_at = up_ms
		return Result.ARMED
	if down_ms - armed_at < arm_min_ms:
		return Result.IGNORED
	disarm()
	return Result.SEND


## Whether the arm's window has run out at `now`.
func expired(now: int, confirm_ms: int) -> bool:
	return target >= 0 and now - armed_at >= confirm_ms


func disarm() -> void:
	target = -1
