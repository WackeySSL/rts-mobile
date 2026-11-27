extends GdUnitTestSuite
## Plan row P595 (ADR 0048 sections 5 and 13), the lead-in states of Basics. The chain
## sweep judges each chain in the start states the beats before it leave. This suite judges
## every beat with a lead-in in two more: the build drawer closed, and regressed (a step's
## condition met and then undone: the selection dropped after a SELECTED step, the drawer shut or
## another tab opened after the tab step, the strike aim released), at the six sizes and the two
## small phones of the sweep. The checks are the sweep's (`ChainRig.drive`: the ring on the
## control or unit the chain names, the card not hiding it, a real viewport touch at a unit step)
## plus the hand set on every control and unit step. The run and its floors are in
## `support/lead_in_run.gd`; the lessons are split over three suites so that each stays under the
## CI's per-suite time.

const LeadInRun: GDScript = preload("res://tests/ui/tutorial/support/lead_in_run.gd")

var _window_size_before: Vector2i
var _run: RefCounted


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	_run = LeadInRun.new(self)
	_run.begin()


func after_test() -> void:
	_run.end()


func test_basics_lead_ins_with_the_drawer_closed_and_regressed() -> void:
	var ids: Array[StringName] = [&"basics"]
	await _run.judge_lessons(ids)
