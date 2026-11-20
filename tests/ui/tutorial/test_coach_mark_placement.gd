extends "res://tests/ui/tutorial/support/coach_mark_suite.gd"
## Where the coach mark's card stands (plan row P542, ADR 0015 section 6, ADR 0025 section 2):
## inside the safe rect and off the ring at the six sizes and the real phones, clear of the top HUD
## row, through turns, under an offset parent, and the overlap fallback.


func test_the_card_is_inside_the_safe_rect_and_off_the_ring_at_the_six_sizes() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(_profile(size), _control_beat("hit", NEXT))
		for corner: Vector2 in [Vector2(0.5, 0.5), Vector2(0.1, 0.1), Vector2(0.9, 0.9)]:
			_put_target(corner)
			await await_idle_frame()
			await await_idle_frame()
			_expect_card_placed(str(size) + str(corner))
		_close()


func test_a_turn_keeps_the_card_inside_and_off_the_ring() -> void:
	for index: int in ScreenSizes.LANDSCAPE.size():
		await _open(_profile(ScreenSizes.LANDSCAPE[index]), _control_beat("hit", NEXT))
		_put_target(Vector2(0.3, 0.6))
		await await_idle_frame()
		UiScale.set_override(_profile(ScreenSizes.PORTRAIT[index]))
		get_window().size = ScreenSizes.PORTRAIT[index]
		await await_idle_frame()
		_put_target(Vector2(0.3, 0.6))
		await await_idle_frame()
		await await_idle_frame()
		_expect_card_placed("turned %d" % index)
		_close()


func test_the_card_buttons_are_48_dp() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(_profile(size), _control_beat("hit", NEXT))
		var floor_px: float = UiScale.dp(48.0) - TOLERANCE_PX
		for button_name: String in ["Next", "Skip"]:
			var button: Button = _mark.find_child(button_name, true, false) as Button
			assert_bool(button.size.x >= floor_px and button.size.y >= floor_px).is_true()
		_close()


func test_a_card_that_cannot_clear_the_ring_lets_a_tap_through_to_the_target() -> void:
	await _open(
		_profile(ScreenSizes.LANDSCAPE[0]),
		_control_beat("hit", TutorialConditions.Kind.CAMERA_PANNED)
	)
	# A ring as wide as the safe rect leaves no room: the card overlaps it.
	_target.size = _safe().size * 0.95
	_target.position = _safe().position + _safe().size * 0.025
	await await_idle_frame()
	await await_idle_frame()
	var card: Control = _mark.find_child("Card", true, false) as Control
	assert_bool(_mark.card_rect().intersects(_mark.ring_rect())).is_true()
	assert_int(card.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	var at: Vector2 = _mark.card_rect().position + Vector2.ONE * UiScale.dp(24.0)  # On the prompt.
	assert_bool(_target.get_global_rect().has_point(at)).is_true()
	_taps = 0
	TouchEvents.press(get_viewport(), 0, at)
	TouchEvents.release(get_viewport(), 0, at)
	await await_idle_frame()
	assert_int(_taps).is_equal(1)
	_put_target(Vector2(0.5, 0.5))  # Back to a small target: the card clears it and stops again.
	_target.size = Vector2.ONE * UiScale.dp(56.0)
	_put_target(Vector2(0.5, 0.5))
	await await_idle_frame()
	await await_idle_frame()
	assert_int(card.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)


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
	_expect_card_placed("offset parent")


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


func test_the_pause_button_stays_tappable_under_a_no_ring_card_upright() -> void:
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


func test_the_real_phones_place_a_two_line_prompt_off_the_ring() -> void:
	for profile_name: StringName in [
		&"web_phone_portrait", &"web_phone_small", &"notch_design", &"notch_design_portrait"
	]:
		var beat: TutorialBeatDef = _control_beat("hit", NEXT)
		beat.prompt_key = &"Tap the glowing button at the edge of the screen to open the build menu."
		await _open(UiProfiles.by_name(profile_name), beat)
		for corner: Vector2 in [Vector2(0.5, 0.5), Vector2(0.1, 0.12), Vector2(0.9, 0.9)]:
			_put_target(corner)
			await await_idle_frame()
			await await_idle_frame()
			_expect_card_placed("%s %s" % [profile_name, corner])
		var floor_px: float = UiScale.dp(48.0) - TOLERANCE_PX
		for button_name: String in ["Next", "Skip"]:
			var button: Button = _mark.find_child(button_name, true, false) as Button
			assert_bool(button.size.x >= floor_px and button.size.y >= floor_px).is_true()
		var skip: Rect2 = (_mark.find_child("Skip", true, false) as Button).get_global_rect()
		var next: Rect2 = (_mark.find_child("Next", true, false) as Button).get_global_rect()
		assert_float(next.position.x - skip.end.x).is_greater_equal(UiScale.dp(8.0) - TOLERANCE_PX)
		_close()
		UiScale.clear_override()


func test_in_the_overlap_fallback_a_real_touch_on_skip_ends_the_lesson() -> void:
	await _open(
		UiProfiles.by_name(&"web_phone_small"),
		_control_beat("hit", TutorialConditions.Kind.CAMERA_PANNED)
	)
	_target.size = _safe().size * 0.95
	_target.position = _safe().position + _safe().size * 0.025
	await await_idle_frame()
	await await_idle_frame()
	var card: Control = _mark.find_child("Card", true, false) as Control
	assert_int(card.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	var skip: Button = _mark.find_child("Skip", true, false) as Button
	var at: Vector2 = skip.get_global_rect().get_center()
	TouchEvents.press(get_viewport(), 0, at)
	TouchEvents.release(get_viewport(), 0, at)
	await await_idle_frame()
	assert_bool(_director.running()).is_false()


func test_the_fallback_prefers_a_card_whose_button_row_misses_the_ring() -> void:
	var room: Rect2 = Rect2(0.0, 0.0, 220.0, 160.0)
	var card: Vector2 = Vector2(200.0, 140.0)
	var ring: Rect2 = Rect2(0.0, 0.0, 220.0, 40.0)
	var row_h: float = 60.0
	var placed: Rect2 = CoachMark.place_card(ring, card, room, 8.0, row_h)
	var row: Rect2 = Rect2(placed.position.x, placed.end.y - row_h, placed.size.x, row_h)
	assert_bool(row.intersects(ring)).is_false()
	assert_bool(room.encloses(placed)).is_true()


## Rects the card must not cover (a menu's other buttons, an ad band) are kept clear when a place
## exists: the card goes where the blocked rect is not, and the ring stays clear too.
func test_blocked_rects_are_kept_clear_when_a_place_exists() -> void:
	var room: Rect2 = Rect2(0.0, 0.0, 400.0, 600.0)
	var card: Vector2 = Vector2(300.0, 100.0)
	var ring: Rect2 = Rect2(50.0, 200.0, 300.0, 50.0)
	var below: Rect2 = CoachMark.place_card(ring, card, room, 8.0)
	var blocked: Array[Rect2] = [below.grow(4.0), Rect2(0.0, 260.0, 400.0, 100.0)]
	var placed: Rect2 = CoachMark.place_card(ring, card, room, 8.0, 0.0, blocked)
	assert_bool(room.encloses(placed)).is_true()
	assert_bool(placed.intersects(ring)).is_false()
	for rect: Rect2 in blocked:
		assert_bool(placed.intersects(rect)).is_false()


## When no place clears the buttons' air, the card drops that air but never the ad band: the band
## and its 16 dp stay a hard constraint (ad policy), and the bottom of the room, where it sits, is
## no candidate.
func test_the_band_stays_a_hard_constraint_when_the_buttons_leave_no_room() -> void:
	var room: Rect2 = Rect2(0.0, 0.0, 400.0, 600.0)
	var card: Vector2 = Vector2(300.0, 100.0)
	var ring: Rect2 = Rect2(50.0, 100.0, 300.0, 50.0)
	var band: Rect2 = Rect2(0.0, 440.0, 400.0, 160.0)
	var everywhere: Array[Rect2] = [room]  # No place keeps off the buttons.
	var hard: Array[Rect2] = [band]
	var placed: Rect2 = CoachMark.place_card(ring, card, room, 8.0, 0.0, everywhere, hard)
	assert_bool(placed.intersects(band)).is_false()
	assert_bool(placed.intersects(ring)).is_false()
	assert_bool(room.encloses(placed)).is_true()
	# Even when the ring leaves the band's side as the only free one, the band is not touched.
	var low: Rect2 = Rect2(50.0, 200.0, 300.0, 200.0)
	var squeezed: Rect2 = CoachMark.place_card(low, card, room, 8.0, 0.0, everywhere, hard)
	assert_bool(squeezed.intersects(band)).is_false()


func test_a_turn_mid_beat_at_360_dp_keeps_the_card_inside() -> void:
	await _open(UiProfiles.by_name(&"web_phone_portrait"), _control_beat("hit", NEXT))
	_put_target(Vector2(0.3, 0.5))
	await await_idle_frame()
	var turned: UiMetrics = UiProfiles.by_name(&"web_phone")
	UiScale.set_override(turned)
	get_window().size = turned.window_size
	await await_idle_frame()
	_put_target(Vector2(0.3, 0.5))
	await await_idle_frame()
	await await_idle_frame()
	_expect_card_placed("turned at 360 dp")
