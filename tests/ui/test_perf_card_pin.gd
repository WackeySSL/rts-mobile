extends GdUnitTestSuite
## The card's text, keys and summary are byte-identical after the `PerfHud` split (plan P184): five
## fixed runs (units arena, a failing and paused run, the base arena, Android with the library and
## without) render to `fixtures/perf_card_pin.txt`, made on the code before the move.

const Cases: GDScript = preload("res://tests/ui/support/perf_card_cases.gd")
const FIXTURE: String = "res://tests/ui/fixtures/perf_card_pin.txt"


func test_every_case_renders_as_before_the_split() -> void:
	var want: String = FileAccess.get_file_as_string(FIXTURE)
	var got: String = ""
	for case_name: String in Cases.CASES:
		got += Cases.render(case_name)
	assert_int(want.length()).is_greater(0)
	assert_str(got).is_equal(want)
