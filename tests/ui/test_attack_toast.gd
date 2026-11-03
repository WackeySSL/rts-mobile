extends "res://tests/ui/support/attack_suite.gd"
## The attack toast and its place (plan P123, ADR 0025 sections 2 and 8): at every screen, with
## units selected, it is `HudCorners.place`'s rect and clear of the pill, the scope, the top-left
## stack and the selection panel; a turn replaces it; the placement buttons keep clear of it; a tap
## on it jumps the camera and nothing else; none while the full map or the pause menu is open; the
## longest title fits.


func test_no_toast_while_the_pause_menu_is_open() -> void:
	await _open(ScreenSizes.LANDSCAPE[0])
	_feed.state.open(HudState.Unfold.PAUSE)
	_hit(_unit, _far())
	assert_bool(_cues.active).is_true()
	assert_bool(_toast.visible).is_false()


func test_with_the_full_map_open_there_is_no_toast_but_a_ping() -> void:
	await _open(ScreenSizes.LANDSCAPE[0])
	_feed.state.open(HudState.Unfold.RADAR)
	await _settle()
	var pings: int = _minimap.ping_count()
	_hit(_unit, _edge())
	await _settle()
	assert_bool(_cues.active).is_true()
	assert_bool(_toast.visible).is_false()
	assert_int(_minimap.ping_count()).is_equal(pings + 1)  # Drawn anew, with the ping.
	assert_bool(_minimap.box_rect().has_point(_minimap.world_to_local(_cues.point))).is_true()
	_feed.state.close(HudState.Unfold.RADAR)
	assert_bool(_toast.visible).is_true()  # Folded, the cue still stands.


## A tap on the toast jumps the camera and closes the drawer, with units selected: no Command,
## no map gesture, no pan.
func test_a_tap_on_the_toast_jumps_the_camera_and_closes_the_drawer() -> void:
	await _open(ScreenSizes.LANDSCAPE[0])
	_controller.select_all_army()
	assert_int(_controller.selection.selected.size()).is_greater(0)
	_feed.state.open(HudState.Unfold.DRAWER)
	_hit(_unit, _edge())
	assert_bool(_toast.visible).is_true()
	var point: Vector2 = _cues.point
	var at: Vector2 = _toast.get_global_rect().get_center()
	TouchEvents.press(get_viewport(), 0, at)
	TouchEvents.release(get_viewport(), 0, at)
	await _settle()
	assert_vector(_camera.position).is_equal_approx(point, Vector2.ONE * 2.0)
	assert_bool(_cues.active).is_false()
	assert_bool(_feed.state.is_open(HudState.Unfold.DRAWER)).is_false()
	assert_int(_sent.size()).is_equal(0)
	assert_int(_told).is_equal(0)
	assert_int(_controller.selection.selected.size()).is_greater(0)  # Still selected.


## The toast keeps clear of what stands near it at every screen: the pill, the scope, the top-left
## stack and, with units selected, the selection panel; and it is the rect `HudCorners.place` gives.
func test_the_toast_keeps_clear_at_every_screen_with_units_selected() -> void:
	var screens: Array[Dictionary] = RadarRig.screens()
	var short: UiMetrics = RadarRig.short_landscape()
	screens.append({"label": "short landscape", "size": short.window_size, "metrics": short})
	var panels: int = 0
	for screen: Dictionary in screens:
		await _open(screen["size"], screen["metrics"])
		_controller.select_all_army()
		_hit(_unit, _far())
		await _settle()
		var panel: Control = _hud("SelectionPanel") as Control
		panels += int(panel.is_visible_in_tree())
		_expect_toast_placed(str(screen["label"]))
	assert_int(panels).is_greater(0)


## The open drawer, landscape and portrait: the toast keeps clear of the pill (which stays), the
## scope, the stack and the drawer, and keeps its least width, at every screen.
func test_the_toast_keeps_clear_of_the_pill_and_the_drawer_at_every_screen() -> void:
	var screens: Array[Dictionary] = RadarRig.screens()
	var short: UiMetrics = RadarRig.short_landscape()
	screens.append({"label": "short landscape", "size": short.window_size, "metrics": short})
	for screen: Dictionary in screens:
		await _open(screen["size"], screen["metrics"])
		_controller.select_all_army()
		_hit(_unit, _far())
		await _settle()
		await _expect_toast_clear_of_drawer(str(screen["label"]))


## A turn moves the toast to the other layout's place, still clear of the panel.
func test_a_turn_replaces_the_toast() -> void:
	await _open(ScreenSizes.LANDSCAPE[0])
	_controller.select_all_army()
	_hit(_unit, _far())
	for size: Vector2i in [
		ScreenSizes.PORTRAIT[0], ScreenSizes.LANDSCAPE[0], ScreenSizes.PORTRAIT[1]
	]:
		get_window().size = size
		await _settle()
		_expect_toast_placed("turned to %s" % size)


## The placement check mark and the X keep clear of a shown toast in both orientations, and the
## scene lists the toast for them (without it they stand under it).
func test_the_placement_buttons_keep_clear_of_the_toast() -> void:
	for profile: StringName in [&"android_6in", &"android_6in_portrait"]:
		var metrics: UiMetrics = UiProfiles.by_name(profile)
		await _open(metrics.window_size, metrics)
		var ghost: GhostControls = _main.get_node("Hud/GhostControls") as GhostControls
		assert_bool(ghost.clear_of.has(_toast)).override_failure_message(str(profile)).is_true()
		_hit(_unit, _far())
		Rig.make_ready(_runner.snapshot)
		assert_bool(_placement.begin(Rig.plant(_runner.snapshot))).is_true()
		await _settle()
		var toast: Rect2 = _toast.get_global_rect()
		var group: Rect2 = _rect("PlaceConfirm").merge(_rect("PlaceCancel"))
		var at: String = "%s: buttons %s, toast %s" % [profile, group, toast]
		assert_bool(_toast.visible).override_failure_message(at).is_true()
		assert_bool(group.intersects(toast)).override_failure_message(at).is_false()
		_placement.cancel()


## "SYNTHESIS WORKS UNDER ATTACK", the longest title, fits the toast's line on every phone profile,
## upright and sideways. The six plain sizes run with the engine's own metrics (a dp is a window
## px, the desktop window): the tracking is a fixed 3 base px there, which is wider relative to
## the 16 px type than on a phone, so they only say that the label never grows past its room.
func test_the_longest_title_fits_the_toast_on_every_phone_profile() -> void:
	var profiles: Dictionary[StringName, UiMetrics] = UiProfiles.all()
	profiles.merge(UiProfiles.portrait())
	for name: StringName in profiles:
		var metrics: UiMetrics = profiles[name]
		if name == &"desktop" or name == &"desktop_portrait" or str(name).contains("tablet"):
			continue  # Not phones: the dev window and the tablets are pinned above the band.
		await _open(metrics.window_size, metrics)
		await _expect_title_fits(str(name), true)


func test_the_longest_title_stays_inside_its_room_at_the_six_sizes() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size)
		await _expect_title_fits(str(size), false)


func _expect_title_fits(why: String, whole: bool) -> void:
	_hit(_unit, _far())
	var title: Label = _toast.find_children("*", "Label", true, false)[0] as Label
	title.text = "SYNTHESIS WORKS UNDER ATTACK"
	await _settle()
	var font: Font = title.get_theme_font(&"font")
	# The ADR 0025 section 13 title face (Big Shoulders caps), tinted danger by modulate.
	assert_str(((font as FontVariation).base_font).resource_path).contains("BigShoulders")
	assert_object(title.modulate).is_equal(title.get_theme_color(&"danger", &"HudTokens"))
	var wide: float = (
		font
		. get_string_size(
			title.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, title.get_theme_font_size(&"font_size")
		)
		. x
	)
	var at: String = "%s: %s of %s" % [why, wide, title.size.x]
	if whole:
		assert_float(wide).override_failure_message(at).is_less_equal(title.size.x + 0.5)
	assert_float(title.size.x).override_failure_message(at).is_less_equal(_toast.size.x)


func test_the_portrait_toast_stands_under_the_taller_top_left_stack() -> void:
	var shown: HudCorners.Shown = HudCorners.Shown.new()
	shown.toast = true
	shown.left_taken = 56.0
	shown.left_height = 104.0
	var safe: Rect2 = Rect2(0.0, 0.0, 336.0, 676.0)
	var rects: Dictionary[StringName, Rect2] = HudCorners.place(safe, true, 1.0, false, shown)
	assert_float(rects[HudCorners.TOAST].position.y).is_equal(112.0)
	shown.left_height = 0.0
	rects = HudCorners.place(safe, true, 1.0, false, shown)
	assert_float(rects[HudCorners.TOAST].position.y).is_equal(64.0)  # A gap under the scope.
