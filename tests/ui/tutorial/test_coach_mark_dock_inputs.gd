extends "res://tests/ui/tutorial/support/coach_mark_suite.gd"
## The coach mark's dock in the small: a card that never outgrows its dock (a prompt that scrolls,
## buttons that stack), the tab and its slot, and what re-docks it (plan row P588, ADR 0048).


func _tight() -> void:
	var tight: GuideSettingsDef = _mark.settings.duplicate() as GuideSettingsDef
	tight.card_max_height_pct = 1
	_mark.settings = tight


## A long prompt in a short dock: the card stays inside the dock and the prompt scrolls.
func test_a_long_prompt_in_a_short_dock_keeps_the_card_inside_and_scrolls() -> void:
	var beat: TutorialBeatDef = _control_beat("hit", NEXT)
	var words: String = "A long prompt about what to do, where and why, and what comes after. "
	beat.prompt_key = StringName(words.repeat(5))
	await _open(_profile(ScreenSizes.LANDSCAPE[0]), beat)
	var wide: GuideSettingsDef = _mark.settings.duplicate() as GuideSettingsDef
	wide.card_max_height_pct = 20
	_mark.settings = wide
	await await_idle_frame()
	await await_idle_frame()
	await await_idle_frame()
	var dock: Rect2 = _mark.dock_rect()
	assert_bool(GuideDock.has_room(dock, UiScale.base_px_per_dp())).is_true()
	assert_bool(dock.grow(TOLERANCE_PX).encloses(_mark.card_rect())).is_true()
	assert_bool(_mark.prompt_scrolls()).is_true()
	for button_name: String in ["Next", "Skip"]:
		var button: Button = _mark.find_child(button_name, true, false) as Button
		(
			assert_bool(_mark.card_rect().grow(TOLERANCE_PX).encloses(button.get_global_rect()))
			. is_true()
		)
	_close()


## A dock narrower than Skip and Next side by side: the card stays in it, the buttons stack.
func test_a_dock_about_100_dp_wide_stacks_the_buttons_inside_it() -> void:
	await _open(_profile(ScreenSizes.LANDSCAPE[0]), _control_beat("hit", NEXT))
	var narrow: GuideSettingsDef = _mark.settings.duplicate() as GuideSettingsDef
	narrow.card_max_width_dp = 100.0
	_mark.settings = narrow
	await await_idle_frame()
	await await_idle_frame()
	await await_idle_frame()
	var dock: Rect2 = _mark.dock_rect()
	assert_float(dock.size.x).is_equal_approx(UiScale.dp(100.0), 1.0)
	var card: Rect2 = _mark.card_rect()
	assert_bool(dock.grow(TOLERANCE_PX).encloses(card)).is_true()
	var skip: Rect2 = (_mark.find_child("Skip", true, false) as Button).get_global_rect()
	var next: Rect2 = (_mark.find_child("Next", true, false) as Button).get_global_rect()
	assert_bool(card.grow(TOLERANCE_PX).encloses(skip)).is_true()
	assert_bool(card.grow(TOLERANCE_PX).encloses(next)).is_true()
	assert_bool(skip.intersects(next)).is_false()
	_close()


func test_the_tab_keeps_its_global_place_under_an_offset_parent() -> void:
	await _open(_profile(ScreenSizes.LANDSCAPE[0]), _control_beat("hit", NEXT))
	_tight()
	await await_idle_frame()
	await await_idle_frame()
	var slot: Rect2 = _mark.tab_rect()
	assert_bool(slot.has_area()).is_true()
	_offset = Control.new()
	_offset.position = Vector2(80.0, 60.0)
	add_child(_offset)
	_mark.get_parent().remove_child(_mark)
	_offset.add_child(_mark)
	_mark.set(&"_dirty", true)
	await await_idle_frame()
	await await_idle_frame()
	assert_that(_mark.tab_rect()).is_equal(slot)


## A control's ring is cut at the safe edge, not moved off its control.
func test_a_ring_at_the_safe_edge_is_cut_not_shifted() -> void:
	await _open(_profile(ScreenSizes.LANDSCAPE[0]), _control_beat("hit", NEXT))
	_put_target_at(_safe().position + _target.size * 0.5)  # Flush with the safe rect's corner.
	await await_idle_frame()
	await await_idle_frame()
	var ring: Rect2 = _mark.ring_rect()
	var grow: float = UiScale.dp(CoachMark.RING_GROW_DP)
	assert_float(ring.position.x).is_equal_approx(_safe().position.x, TOLERANCE_PX)
	assert_float(ring.end.x).is_equal_approx(_target.get_global_rect().end.x + grow, TOLERANCE_PX)
	_close()


## What the dock is built from re-docks it when it changes.
func test_the_dock_stands_again_for_each_input_it_reads() -> void:
	await _open(_profile(ScreenSizes.LANDSCAPE[0]), _control_beat("hit", NEXT))
	var pill: EconomyPill = auto_free(EconomyPill.new())
	pill.size = Vector2(UiScale.dp(200.0), UiScale.dp(48.0))
	var build: BuildButton = auto_free(BuildButton.new())
	var aim: StrikeAim = auto_free(StrikeAim.new())
	_mark.set(&"_pill", pill)
	_mark.set(&"_build", build)
	_director.strike_aim = aim
	await await_idle_frame()
	await await_idle_frame()
	var key: int = _mark.get(&"_dock_key")
	pill.size.x = UiScale.dp(300.0)
	await await_idle_frame()
	assert_int(_mark.get(&"_dock_key")).is_not_equal(key)
	key = _mark.get(&"_dock_key")
	_director.hud.set_bar(true, 150.0, true)
	await await_idle_frame()
	assert_int(_mark.get(&"_dock_key")).is_not_equal(key)
	key = _mark.get(&"_dock_key")
	_director.hud.set_bar(true, 250.0, true)
	await await_idle_frame()
	assert_int(_mark.get(&"_dock_key")).is_not_equal(key)
	key = _mark.get(&"_dock_key")
	build.ready_type = 0
	await await_idle_frame()
	assert_int(_mark.get(&"_dock_key")).is_not_equal(key)
	key = _mark.get(&"_dock_key")
	aim.active = true
	await await_idle_frame()
	assert_int(_mark.get(&"_dock_key")).is_not_equal(key)
	key = _mark.get(&"_dock_key")
	_mark.mirror = true
	_mark.set(&"_dock_key", -1)
	await await_idle_frame()
	assert_int(_mark.get(&"_dock_key")).is_not_equal(-1)
	_close()


func test_a_new_layout_folds_an_open_tab_again() -> void:
	await _open(_profile(ScreenSizes.LANDSCAPE[0]), _control_beat("hit", NEXT))
	_tight()
	await await_idle_frame()
	await await_idle_frame()
	var at: Vector2 = _mark.tab_rect().get_center()
	TouchEvents.press(get_viewport(), 0, at)
	TouchEvents.release(get_viewport(), 0, at)
	await await_idle_frame()
	await await_idle_frame()
	var card: Control = _mark.find_child("Card", true, false) as Control
	assert_bool(card.visible).is_true()
	_director.hud.set_bar(true, 150.0, true)  # The layout changes.
	await await_idle_frame()
	await await_idle_frame()
	assert_bool(card.visible).is_false()
	_close()


func test_with_no_slot_for_the_tab_the_card_shows_overlaid_and_no_tab() -> void:
	await _open(_profile(ScreenSizes.LANDSCAPE[0]), _control_beat("hit", NEXT))
	_tight()
	await await_idle_frame()
	await await_idle_frame()
	_mark.set(&"_tab_slot", Rect2())
	_mark.set(&"_dirty", true)
	await await_idle_frame()
	await await_idle_frame()
	assert_bool((_mark.find_child("Card", true, false) as Control).visible).is_true()
	assert_bool((_mark.find_child("Tab", true, false) as Button).visible).is_false()
	assert_that(_mark.tab_rect()).is_equal(Rect2())
	_close()
