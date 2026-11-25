extends "res://tests/ui/tutorial/support/coach_mark_suite.gd"
## The guide's tab, counter and fold (plan row P589, ADR 0048 section 2): the counter `n/N`, a tap
## folding and unfolding the card in the tab's own place, every new beat and a stall opening it, a
## turn keeping the choice, the tab alone in a gap with the next number, and Skip on the first card
## only.


func _tab() -> Button:
	return _mark.find_child("Tab", true, false) as Button


func _tap_tab() -> void:
	var at: Vector2 = _mark.tab_rect().get_center()
	TouchEvents.press(get_viewport(), 0, at)
	TouchEvents.release(get_viewport(), 0, at)
	await await_idle_frame()
	await await_idle_frame()


func _beats() -> Array:
	return [
		_control_beat("one", NEXT),
		_control_beat("two", NEXT),
		_control_beat("three", NEXT),
	]


func test_the_counter_shows_the_beat_number_and_the_lessons_count_at_the_six_sizes() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		var beats: Array = _beats()
		await _open(_profile(size), beats[0], false, beats)
		assert_str(_mark.counter_text()).override_failure_message(str(size)).is_equal("1/3")
		_director.next()
		_director.advance()
		await await_idle_frame()
		assert_str(_mark.counter_text()).override_failure_message(str(size)).is_equal("2/3")
		_close()
		UiScale.clear_override()


func test_the_tab_is_one_48_dp_button_in_the_docks_scope_side_corner() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(_profile(size), _control_beat("hit", NEXT))
		var tab: Rect2 = _mark.tab_rect()
		var floor_px: float = UiScale.dp(48.0) - TOLERANCE_PX
		assert_bool(tab.size.x >= floor_px and tab.size.y >= floor_px).is_true()
		var dock: Rect2 = _mark.dock_rect()
		assert_float(tab.end.x).is_equal_approx(dock.end.x, TOLERANCE_PX)
		assert_float(tab.position.y).is_equal_approx(dock.position.y, TOLERANCE_PX)
		_close()
		UiScale.clear_override()


func test_a_tap_on_the_tab_folds_the_card_and_a_second_one_opens_it_in_the_same_place() -> void:
	await _open(_profile(ScreenSizes.LANDSCAPE[0]), _control_beat("hit", NEXT))
	var place: Rect2 = _mark.tab_rect()
	assert_bool(_mark.card_open()).is_true()
	await _tap_tab()
	assert_bool(_mark.card_open()).is_false()
	assert_that(_mark.tab_rect()).is_equal(place)
	assert_str(_mark.counter_text()).is_equal("1/1")
	await _tap_tab()
	assert_bool(_mark.card_open()).is_true()
	assert_that(_mark.tab_rect()).is_equal(place)
	_close()


func test_every_new_beat_opens_a_folded_card() -> void:
	var beats: Array = _beats()
	await _open(_profile(ScreenSizes.LANDSCAPE[0]), beats[0], false, beats)
	await _tap_tab()
	assert_bool(_mark.card_open()).is_false()
	_director.next()
	_director.advance()
	await await_idle_frame()
	await await_idle_frame()
	assert_bool(_mark.card_open()).is_true()
	await _tap_tab()  # Within a beat the player's choice stands.
	for _i: int in 3:
		await await_idle_frame()
	assert_bool(_mark.card_open()).is_false()
	_close()


func test_a_stall_opens_the_card_once() -> void:
	var beat: TutorialBeatDef = _control_beat("pan", TutorialConditions.Kind.CAMERA_PANNED)
	beat.budget_s = 2
	await _open(_profile(ScreenSizes.LANDSCAPE[0]), beat)
	await _tap_tab()
	assert_bool(_mark.card_open()).is_false()
	for _i: int in 2 * Sim.TICK_RATE:
		Rig.step(_world, _loop)
	_runner.snapshot = Lesson.snapshot(_world)
	await await_idle_frame()
	await await_idle_frame()
	assert_bool(_director.stalled()).is_true()
	assert_bool(_mark.card_open()).is_true()  # The hint line is new.
	await _tap_tab()  # Folded again by the player: it stays folded.
	for _i: int in 3:
		await await_idle_frame()
	assert_bool(_mark.card_open()).is_false()
	_close()


func test_a_turn_keeps_the_fold_state_and_the_tab_follows_the_dock() -> void:
	await _open(_profile(ScreenSizes.LANDSCAPE[0]), _control_beat("hit", NEXT))
	await _tap_tab()
	assert_bool(_mark.card_open()).is_false()
	var portrait: UiMetrics = _profile(ScreenSizes.PORTRAIT[0])
	UiScale.set_override(portrait)
	get_window().size = portrait.window_size
	for _i: int in 4:
		await await_idle_frame()
	assert_bool(_mark.card_open()).is_false()
	assert_bool(_safe().grow(TOLERANCE_PX).encloses(_mark.tab_rect())).is_true()
	assert_float(_mark.tab_rect().end.x).is_equal_approx(_mark.dock_rect().end.x, TOLERANCE_PX)
	_close()


func test_the_fold_is_never_saved() -> void:
	await _open(_profile(ScreenSizes.LANDSCAPE[0]), _control_beat("hit", NEXT))
	await _tap_tab()
	_close()
	assert_bool(FileAccess.file_exists(_dir.path_join("save.cfg"))).is_false()
	await _open(_profile(ScreenSizes.LANDSCAPE[0]), _control_beat("hit", NEXT))
	assert_bool(_mark.card_open()).is_true()
	_close()


func test_the_tab_stays_alone_in_a_gap_with_the_next_number() -> void:
	var beats: Array = _beats()
	beats[1].delay_ticks = 30
	await _open(_profile(ScreenSizes.LANDSCAPE[0]), beats[0], false, beats)
	_director.next()
	await await_idle_frame()
	await await_idle_frame()
	assert_bool(_mark.card_open()).is_false()
	assert_bool(_mark.tab_rect().has_area()).is_true()
	assert_str(_mark.counter_text()).is_equal("2/3")
	assert_bool(_mark.ring_rect().has_area()).is_false()
	_close()


func test_a_lesson_end_puts_the_tab_away() -> void:
	await _open(_profile(ScreenSizes.LANDSCAPE[0]), _control_beat("hit", NEXT))
	_director.next()
	await await_idle_frame()
	assert_bool(_director.running()).is_false()
	assert_that(_mark.tab_rect()).is_equal(Rect2())
	assert_bool(_mark.visible).is_false()
	_close()


func test_skip_shows_on_the_lessons_first_card_only() -> void:
	var beats: Array = _beats()
	await _open(_profile(ScreenSizes.LANDSCAPE[0]), beats[0], false, beats)
	var skip: Button = _mark.find_child("Skip", true, false) as Button
	assert_bool(skip.is_visible_in_tree()).is_true()
	_director.next()
	_director.advance()
	await await_idle_frame()
	await await_idle_frame()
	assert_bool(skip.is_visible_in_tree()).is_false()
	assert_bool((_mark.find_child("Next", true, false) as Button).is_visible_in_tree()).is_true()
	_close()


func test_the_wide_form_has_no_head_row_and_the_narrow_one_has() -> void:
	var beats: Array = _beats()
	await _open(_profile(ScreenSizes.LANDSCAPE[0]), beats[0], false, beats)
	assert_bool((_mark.find_child("Head", true, false) as Control).visible).is_false()
	_close()
	UiScale.clear_override()
	await _open(UiProfiles.by_name(&"web_phone_portrait"), beats[0], false, beats)
	assert_bool((_mark.find_child("Head", true, false) as Control).visible).is_true()
	_close()
