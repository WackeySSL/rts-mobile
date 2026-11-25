extends "res://tests/ui/tutorial/support/coach_mark_suite.gd"
## Where the coach mark's card stands (plan rows P542 and P588, ADR 0048 sections 1 and 3): in
## `GuideDock`'s rect at the six sizes and the real phones, still while the ring moves, stood again
## when the HUD changes, see-through and pass-through where the ring meets it, folded to its tab
## where no dock has room, under an offset parent and through turns. The sweep over every beat of
## every lesson is `test_coach_mark_keeps_off_controls.gd`.

const GuideDockRig: GDScript = preload("res://tests/ui/tutorial/support/guide_dock_rig.gd")


## The dock the fake HUD (no group column, no bar) gives, computed here and not read from the mark.
func _expected_dock(drawer: bool = false) -> Rect2:
	var portrait: bool = HudLayout.is_portrait()
	var dp: float = UiScale.base_px_per_dp()
	var rects: Dictionary[StringName, Rect2] = GuideDockRig.rects(
		_safe(), portrait, dp, [false, drawer, 1, false, false]
	)
	var values: Dictionary[StringName, float] = {
		&"card_max_width_dp": _mark.settings.card_max_width_dp,
		&"card_max_height_pct": float(_mark.settings.card_max_height_pct),
	}
	return GuideDock.place(_safe(), portrait, dp, false, rects, values)


func _expect_docked(label: String, drawer: bool = false) -> void:
	var dock: Rect2 = _expected_dock(drawer)
	assert_bool(GuideDock.has_room(dock, UiScale.base_px_per_dp())).is_true()
	var card: Rect2 = _mark.card_rect()
	(
		assert_bool(dock.grow(TOLERANCE_PX).encloses(card))
		. override_failure_message("%s: card %s outside the dock %s" % [label, card, dock])
		. is_true()
	)
	assert_vector(card.position).override_failure_message(label).is_equal_approx(
		dock.position, Vector2.ONE * TOLERANCE_PX
	)


func test_the_card_stands_in_the_dock_at_the_six_sizes() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(_profile(size), _control_beat("hit", NEXT))
		_expect_docked(str(size))
		_close()


func test_the_card_stays_while_the_ring_moves() -> void:
	await _open(_profile(ScreenSizes.LANDSCAPE[0]), _control_beat("hit", NEXT))
	var first: Rect2 = _mark.card_rect()
	for corner: Vector2 in [Vector2(0.1, 0.1), Vector2(0.9, 0.9), Vector2(0.5, 0.2)]:
		_put_target(corner)
		await await_idle_frame()
		await await_idle_frame()
		assert_that(_mark.card_rect()).is_equal(first)
	_close()


func test_a_turn_stands_the_card_in_the_new_dock() -> void:
	for index: int in ScreenSizes.LANDSCAPE.size():
		await _open(_profile(ScreenSizes.LANDSCAPE[index]), _control_beat("hit", NEXT))
		UiScale.set_override(_profile(ScreenSizes.PORTRAIT[index]))
		get_window().size = ScreenSizes.PORTRAIT[index]
		await await_idle_frame()
		await await_idle_frame()
		await await_idle_frame()
		_expect_docked("turned %d" % index)
		_close()


func test_an_open_drawer_stands_the_card_again_left_of_the_panel() -> void:
	await _open(_profile(ScreenSizes.LANDSCAPE[0]), _control_beat("hit", NEXT))
	var closed: Rect2 = _mark.card_rect()
	_director.hud.open(HudState.Unfold.DRAWER)
	await await_idle_frame()
	await await_idle_frame()
	_expect_docked("drawer", true)
	assert_float(_mark.card_rect().end.x).is_less(closed.end.x + 0.5)
	_director.hud.close(HudState.Unfold.DRAWER)
	await await_idle_frame()
	await await_idle_frame()
	assert_that(_mark.card_rect()).is_equal(closed)
	_close()


func test_the_card_buttons_are_48_dp() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(_profile(size), _control_beat("hit", NEXT))
		var floor_px: float = UiScale.dp(48.0) - TOLERANCE_PX
		for button_name: String in ["Next", "Skip"]:
			var button: Button = _mark.find_child(button_name, true, false) as Button
			assert_bool(button.size.x >= floor_px and button.size.y >= floor_px).is_true()
		_close()


## The ring on the card: the card turns see-through, its body lets the tap through to the target,
## and it goes back to its plate and stops touches when the ring leaves.
func test_a_ring_that_meets_the_card_makes_it_see_through_and_lets_a_tap_through() -> void:
	await _open(
		_profile(ScreenSizes.LANDSCAPE[0]),
		_control_beat("hit", TutorialConditions.Kind.CAMERA_PANNED)
	)
	var card: Control = _mark.find_child("Card", true, false) as Control
	assert_bool(_mark.see_through()).is_false()
	assert_int(card.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	assert_str(String(card.theme_type_variation)).is_equal("PauseCard")
	var inside: Rect2 = _mark.card_rect()
	_put_target_at(inside.get_center())  # The target stands under the prompt.
	await await_idle_frame()
	await await_idle_frame()
	assert_bool(_mark.see_through()).is_true()
	assert_int(card.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_str(String(card.theme_type_variation)).is_equal("GuideCardThrough")
	assert_that(_mark.card_rect()).is_equal(inside)  # The card stays (answer 3 A).
	var at: Vector2 = _target.get_global_rect().get_center()
	assert_bool(inside.has_point(at)).is_true()
	_taps = 0
	TouchEvents.press(get_viewport(), 0, at)
	TouchEvents.release(get_viewport(), 0, at)
	await await_idle_frame()
	assert_int(_taps).is_equal(1)
	_put_target(Vector2(0.5, 0.9))  # Away from the card: its plate and its touches come back.
	await await_idle_frame()
	await await_idle_frame()
	assert_bool(_mark.see_through()).is_false()
	assert_int(card.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	assert_str(String(card.theme_type_variation)).is_equal("PauseCard")
	_close()


func test_next_and_skip_still_take_a_touch_under_a_see_through_card() -> void:
	await _open(
		UiProfiles.by_name(&"web_phone_small"),
		_control_beat("hit", TutorialConditions.Kind.CAMERA_PANNED)
	)
	_put_target_at(_mark.card_rect().get_center())
	await await_idle_frame()
	await await_idle_frame()
	assert_bool(_mark.see_through()).is_true()
	var skip: Button = _mark.find_child("Skip", true, false) as Button
	var at: Vector2 = skip.get_global_rect().get_center()
	TouchEvents.press(get_viewport(), 0, at)
	TouchEvents.release(get_viewport(), 0, at)
	await await_idle_frame()
	assert_bool(_director.running()).is_false()


func test_a_mark_under_an_offset_parent_keeps_global_geometry() -> void:
	await _open(_profile(ScreenSizes.LANDSCAPE[0]), _control_beat("hit", NEXT))
	_offset = Control.new()
	_offset.position = Vector2(80.0, 60.0)
	add_child(_offset)
	_mark.get_parent().remove_child(_mark)
	_offset.add_child(_mark)
	_put_target(Vector2(0.3, 0.4))
	await await_idle_frame()
	await await_idle_frame()
	assert_bool(_mark.ring_rect().encloses(_target.get_global_rect())).is_true()
	(
		assert_bool(
			_mark.find_child("Ring", true, false).get_global_rect().position == Vector2.ZERO
		)
		. is_true()
	)
	_expect_docked("offset parent")


func test_with_no_ring_the_card_is_clear_of_the_top_hud_at_the_real_sizes() -> void:
	var profiles: Array[UiMetrics] = []
	for size: Vector2i in ScreenSizes.ALL:
		profiles.append(_profile(size))
	for profile_name: StringName in [
		&"web_phone_portrait", &"web_phone_small", &"notch_design", &"notch_design_portrait"
	]:
		profiles.append(UiProfiles.by_name(profile_name))
	for profile: UiMetrics in profiles:
		var beat: TutorialBeatDef = _control_beat("hit", NEXT)
		beat.anchor_control = &"NoSuchControl"
		await _open(profile, beat)
		var label: String = "%s %s" % [profile.os_name, profile.window_size]
		var safe: Rect2 = _safe()
		var shown: HudCorners.Shown = HudCorners.Shown.new()
		shown.toast = true
		var placed: Dictionary[StringName, Rect2] = HudCorners.place(
			safe, HudLayout.is_portrait(), UiScale.base_px_per_dp(), false, shown
		)
		var card: Rect2 = _mark.card_rect()
		for part: StringName in [HudCorners.PILL, HudCorners.SCOPE, HudCorners.TOAST]:
			var rect: Rect2 = placed[part]  # `place` gives screen px, safe origin included.
			(
				assert_bool(card.intersects(rect))
				. override_failure_message(label + " " + part)
				. is_false()
			)
		(
			assert_bool(safe.grow(TOLERANCE_PX).encloses(card))
			. override_failure_message(label)
			. is_true()
		)
		_close()
		UiScale.clear_override()


func test_the_pause_button_stays_tappable_under_the_card_upright() -> void:
	for profile_name: StringName in [&"web_phone_portrait", &"notch_design_portrait"]:
		var beat: TutorialBeatDef = _control_beat("hit", NEXT)
		beat.anchor_control = &"NoSuchControl"
		await _open(UiProfiles.by_name(profile_name), beat)
		var pill: Rect2 = Rect2(_safe().position, HudCorners.PILL_DP * UiScale.base_px_per_dp())
		_put_target_at(pill.get_center())  # Stands in for the pill's menu button.
		_taps = 0
		TouchEvents.press(get_viewport(), 0, pill.get_center())
		TouchEvents.release(get_viewport(), 0, pill.get_center())
		await await_idle_frame()
		assert_int(_taps).override_failure_message(str(profile_name)).is_equal(1)
		_close()
		UiScale.clear_override()


func test_the_real_phones_dock_a_two_line_prompt_with_48_dp_buttons_12_dp_apart() -> void:
	for profile_name: StringName in [
		&"web_phone_portrait", &"web_phone_small", &"notch_design", &"notch_design_portrait"
	]:
		var beat: TutorialBeatDef = _control_beat("hit", NEXT)
		beat.prompt_key = &"Tap the glowing button at the edge of the screen to open the build menu."
		await _open(UiProfiles.by_name(profile_name), beat)
		_expect_docked(String(profile_name))
		var floor_px: float = UiScale.dp(48.0) - TOLERANCE_PX
		for button_name: String in ["Next", "Skip"]:
			var button: Button = _mark.find_child(button_name, true, false) as Button
			assert_bool(button.size.x >= floor_px and button.size.y >= floor_px).is_true()
		var skip: Rect2 = (_mark.find_child("Skip", true, false) as Button).get_global_rect()
		var next: Rect2 = (_mark.find_child("Next", true, false) as Button).get_global_rect()
		assert_float(next.position.x - skip.end.x).is_greater_equal(UiScale.dp(12.0) - TOLERANCE_PX)
		_close()
		UiScale.clear_override()


## Ring or no ring, the card stays inside the safe rect.
func test_the_card_never_leaves_the_safe_rect_in_either_orientation() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(_profile(size), _control_beat("hit", NEXT))
		for corner: Vector2 in [Vector2(0.1, 0.1), Vector2(0.9, 0.9)]:
			_put_target(corner)
			await await_idle_frame()
			await await_idle_frame()
			assert_bool(_safe().grow(TOLERANCE_PX).encloses(_mark.card_rect())).is_true()
		_close()


## No room (here: a height cap too small for any dock): only the tab shows, in its slot, a touch
## target and clear of the HUD's parts; a tap on it opens the card, a second one folds it, and a
## new layout folds it again.
func test_with_no_room_the_card_folds_to_its_tab_and_the_tab_opens_it() -> void:
	await _open(_profile(ScreenSizes.LANDSCAPE[0]), _control_beat("hit", NEXT))
	var tight: GuideSettingsDef = _mark.settings.duplicate() as GuideSettingsDef
	tight.card_max_height_pct = 1
	_mark.settings = tight
	await await_idle_frame()
	await await_idle_frame()
	var card: Control = _mark.find_child("Card", true, false) as Control
	var tab: Button = _mark.find_child("Tab", true, false) as Button
	assert_bool(GuideDock.has_room(_mark.dock_rect(), UiScale.base_px_per_dp())).is_false()
	assert_bool(card.visible).is_false()
	assert_bool(tab.visible).is_true()
	var slot: Rect2 = _mark.tab_rect()
	var floor_px: float = UiScale.dp(48.0) - TOLERANCE_PX
	assert_bool(slot.size.x >= floor_px and slot.size.y >= floor_px).is_true()
	assert_bool(_safe().grow(TOLERANCE_PX).encloses(slot)).is_true()
	assert_float(slot.position.y).is_equal_approx(_safe().position.y, TOLERANCE_PX)  # Top row.
	var at: Vector2 = slot.get_center()
	TouchEvents.press(get_viewport(), 0, at)
	TouchEvents.release(get_viewport(), 0, at)
	await await_idle_frame()
	await await_idle_frame()
	assert_bool(card.visible).is_true()
	assert_bool(_safe().grow(TOLERANCE_PX).encloses(_mark.card_rect())).is_true()
	assert_bool(_mark.card_rect().intersects(_mark.tab_rect())).is_false()
	TouchEvents.press(get_viewport(), 0, at)
	TouchEvents.release(get_viewport(), 0, at)
	await await_idle_frame()
	assert_bool(card.visible).is_false()
	_close()


func test_a_beat_with_room_shows_no_tab() -> void:
	await _open(_profile(ScreenSizes.LANDSCAPE[0]), _control_beat("hit", NEXT))
	assert_bool((_mark.find_child("Tab", true, false) as Button).visible).is_false()
	assert_that(_mark.tab_rect()).is_equal(Rect2())
	_close()
