extends "res://tests/ui/tutorial/support/coach_mark_suite.gd"
## The coach mark (plan row P542, ADR 0044 section 2): the ring finds the named control, a world
## tile projects through the camera, a touch goes through to the target and not through the card,
## Next and Skip call the director, the stalled hint, reduced effects (no Tween), and the mark's
## binding and lifecycle. Placement is in `test_coach_mark_placement.gd`.


func test_the_ring_finds_the_named_control() -> void:
	await _open(_profile(ScreenSizes.LANDSCAPE[0]), _control_beat("hit", NEXT))
	assert_object(_mark.target_control()).is_same(_target)
	var ring: Rect2 = _mark.ring_rect()
	assert_bool(ring.encloses(_target.get_global_rect())).is_true()
	assert_bool(_mark.visible).is_true()


func test_a_missing_control_gives_a_card_alone() -> void:
	var beat: TutorialBeatDef = _control_beat("hit", NEXT)
	beat.anchor_control = &"NoSuchControl"
	await _open(_profile(ScreenSizes.LANDSCAPE[0]), beat)
	assert_object(_mark.target_control()).is_null()
	assert_bool(_mark.ring_rect().has_area()).is_false()
	assert_bool(_safe().grow(TOLERANCE_PX).encloses(_mark.card_rect())).is_true()


func test_a_world_tile_projects_through_the_camera() -> void:
	var beat: TutorialBeatDef = Lesson.beat(
		"tile", NEXT, {"anchor": TutorialBeatDef.Anchor.TILE, "anchor_tile": Vector2i(7, 5)}
	)
	await _open(_profile(ScreenSizes.LANDSCAPE[0]), beat, true)
	_camera.centre_on(IsoProjection.cell_centre_px(7, 5))
	await await_idle_frame()
	var ring: Rect2 = _mark.ring_rect()
	var at: Vector2 = _camera.world_to_screen(IsoProjection.cell_centre_px(7, 5))
	assert_vector(ring.get_center()).is_equal_approx(at, Vector2.ONE * 1.0)
	_camera.zoom = Vector2(2.0, 2.0)
	_camera.centre_on(IsoProjection.cell_centre_px(7, 5))
	await await_idle_frame()
	assert_float(_mark.ring_rect().size.x).is_greater_equal(
		IsoProjection.ellipse_px(ViewScale.MILLI_PER_TILE).x * 4.0 - 1.0
	)


func test_a_tile_off_the_screen_pins_its_ring_inside_the_safe_rect() -> void:
	var beat: TutorialBeatDef = Lesson.beat(
		"tile", NEXT, {"anchor": TutorialBeatDef.Anchor.TILE, "anchor_tile": Vector2i(60, 60)}
	)
	await _open(_profile(ScreenSizes.LANDSCAPE[0]), beat, true)
	assert_bool(_safe().grow(TOLERANCE_PX).encloses(_mark.ring_rect())).is_true()


func test_next_shows_only_for_a_read_only_beat_and_calls_the_director() -> void:
	var read: TutorialBeatDef = _control_beat("read", NEXT)
	var zoom: TutorialBeatDef = Lesson.beat("zoom", TutorialConditions.Kind.ZOOM_LEVEL, {})
	await _open(_profile(ScreenSizes.LANDSCAPE[0]), read, false, [read, zoom])
	var next: Button = _mark.find_child("Next", true, false) as Button
	assert_bool(next.is_visible_in_tree()).is_true()
	next.pressed.emit()
	_director.advance()
	assert_bool(_director.current == zoom or _director.current == null).is_true()
	assert_int(_director.progress().x).is_equal(1)


func test_next_is_hidden_on_an_action_beat() -> void:
	var beat: TutorialBeatDef = _control_beat("pan", TutorialConditions.Kind.CAMERA_PANNED)
	await _open(_profile(ScreenSizes.LANDSCAPE[0]), beat)
	assert_bool((_mark.find_child("Next", true, false) as Button).visible).is_false()


func test_skip_calls_the_director_and_hides_the_mark() -> void:
	await _open(_profile(ScreenSizes.LANDSCAPE[0]), _control_beat("read", NEXT))
	var skipped: Array[StringName] = []
	_director.lesson_skipped.connect(func(id: StringName) -> void: skipped.append(id))
	(_mark.find_child("Skip", true, false) as Button).pressed.emit()
	assert_array(skipped).is_equal([&"basics"])
	assert_bool(_director.running()).is_false()
	assert_bool(_mark.visible).is_false()


func test_a_beat_done_hides_the_card_until_the_next_prompt() -> void:
	var read: TutorialBeatDef = _control_beat("read", NEXT)
	var late: TutorialBeatDef = _control_beat("late", NEXT)
	late.delay_ticks = 30
	await _open(_profile(ScreenSizes.LANDSCAPE[0]), read, false, [read, late])
	_director.next()
	assert_bool(_mark.card_open()).is_false()  # In the gap: the tab alone, the next number.
	assert_bool(_mark.tab_rect().has_area()).is_true()
	assert_str(_mark.counter_text()).is_equal("2/2")
	assert_bool(_mark.ring_rect().has_area()).is_false()
	for _i: int in 30:
		Rig.step(_world, _loop)
	_runner.snapshot = Lesson.snapshot(_world)
	_director.advance()
	assert_bool(_mark.card_open()).is_true()


func test_a_tap_on_the_ring_target_reaches_it_and_the_ring_and_root_ignore() -> void:
	await _open(
		_profile(ScreenSizes.LANDSCAPE[0]),
		_control_beat("hit", TutorialConditions.Kind.CAMERA_PANNED)
	)
	assert_int(_mark.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_int(_mark.find_child("Ring", true, false).mouse_filter).is_equal(
		Control.MOUSE_FILTER_IGNORE
	)
	var at: Vector2 = _target.get_global_rect().get_center()
	TouchEvents.press(get_viewport(), 0, at)
	TouchEvents.release(get_viewport(), 0, at)
	await await_idle_frame()
	assert_int(_taps).is_equal(1)


func test_a_tap_on_the_card_body_does_not_reach_the_map() -> void:
	await _open(
		_profile(ScreenSizes.LANDSCAPE[0]),
		_control_beat("hit", TutorialConditions.Kind.CAMERA_PANNED)
	)
	var card: Control = _mark.find_child("Card", true, false) as Control
	assert_int(card.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	var on_card: Vector2 = _mark.card_rect().get_center()
	_map_taps = 0
	var map: Control = Control.new()  # Stands in for the map under the whole HUD.
	map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map.gui_input.connect(func(_e: InputEvent) -> void: _map_taps += 1)
	add_child(map)
	move_child(map, 0)
	TouchEvents.press(get_viewport(), 0, on_card)
	TouchEvents.release(get_viewport(), 0, on_card)
	await await_idle_frame()
	map.free()
	assert_int(_map_taps).is_equal(0)


func test_a_stalled_beat_shows_the_hint_and_a_read_only_one_does_not() -> void:
	var beat: TutorialBeatDef = _control_beat("pan", TutorialConditions.Kind.CAMERA_PANNED)
	beat.budget_s = 2
	await _open(_profile(ScreenSizes.LANDSCAPE[0]), beat)
	var hint: Label = _mark.find_child("Hint", true, false) as Label
	assert_bool(hint.visible).is_false()
	for _i: int in 2 * Sim.TICK_RATE:
		Rig.step(_world, _loop)
	_runner.snapshot = Lesson.snapshot(_world)
	assert_bool(_director.stalled()).is_true()
	await await_idle_frame()
	await await_idle_frame()
	assert_bool(hint.visible).is_true()
	_expect_card_placed("stalled")


func test_reduced_effects_make_no_tween() -> void:
	await _open(_profile(ScreenSizes.LANDSCAPE[0]), _control_beat("hit", NEXT), false, [], true)
	await await_idle_frame()
	assert_bool(_mark.ring_blinking()).is_false()
	assert_int(get_tree().get_processed_tweens().size()).is_equal(0)
	assert_float(_mark.ring_alpha()).is_equal(1.0)
	assert_float(_mark.ring_line_px()).is_equal(UiScale.dp(CoachMark.RING_LINE_DP + 1.0))
	_close()
	await _open(_profile(ScreenSizes.LANDSCAPE[0]), _control_beat("hit", NEXT))
	await await_idle_frame()
	assert_bool(_mark.ring_blinking()).is_true()  # Without reduced effects it blinks...
	_mark.hide_mark()
	assert_bool(_mark.ring_blinking()).is_false()  # ...and stops when hidden.


func test_freeing_the_target_mid_beat_gives_a_card_alone() -> void:
	await _open(_profile(ScreenSizes.LANDSCAPE[0]), _control_beat("hit", NEXT))
	assert_bool(_mark.ring_rect().has_area()).is_true()
	_target.get_parent().remove_child(_target)
	_target.free()
	await await_idle_frame()
	await await_idle_frame()
	assert_bool(_mark.ring_rect().has_area()).is_false()
	assert_bool(_mark.ring_blinking()).is_false()
	assert_object(_mark.target_control()).is_null()
	assert_bool(_safe().grow(TOLERANCE_PX).encloses(_mark.card_rect())).is_true()


func test_a_rebind_or_a_null_director_puts_the_old_card_away() -> void:
	await _open(_profile(ScreenSizes.LANDSCAPE[0]), _control_beat("hit", NEXT))
	assert_bool(_mark.visible).is_true()
	var other: TutorialDirector = auto_free(TutorialDirector.new())
	_mark.bind(other)
	assert_bool(_mark.visible).is_false()
	_mark.show_beat(_control_beat("again", NEXT))
	_mark.bind(null)
	assert_bool(_mark.visible).is_false()


func test_a_beat_shown_before_the_mark_is_in_the_tree_shows_when_it_enters() -> void:
	UiScale.set_override(_profile(ScreenSizes.LANDSCAPE[0]))
	_mark = CoachMark.new()
	_mark.hud_root = null
	_mark.bind(_director)
	_mark.show_beat(_control_beat("early", NEXT))  # No viewport yet: no error.
	assert_bool(_mark.visible).is_true()  # A new Control is visible by default.
	add_child(_mark)
	await await_idle_frame()
	assert_bool(_mark.visible).is_true()
	assert_bool(_mark.card_rect().has_area()).is_true()


func test_a_reduced_switch_set_before_ready_is_kept() -> void:
	var mark: CoachMark = CoachMark.new()
	mark.reduced = true
	add_child(mark)
	assert_bool(mark.reduced).is_true()
	remove_child(mark)
	mark.free()


func test_skip_is_on_the_first_card_only_and_next_on_read_only_beats() -> void:
	var first: TutorialBeatDef = _control_beat("first", NEXT)
	var second: TutorialBeatDef = _control_beat("second", NEXT)
	var third: TutorialBeatDef = _control_beat("third", TutorialConditions.Kind.CAMERA_PANNED)
	await _open(_profile(ScreenSizes.LANDSCAPE[0]), first, false, [first, second, third])
	var skip: Button = _mark.find_child("Skip", true, false) as Button
	var next: Button = _mark.find_child("Next", true, false) as Button
	assert_bool(skip.is_visible_in_tree() and next.is_visible_in_tree()).is_true()
	var floor_px: float = UiScale.dp(48.0) - TOLERANCE_PX
	for button: Button in [skip, next]:
		assert_bool(button.size.x >= floor_px and button.size.y >= floor_px).is_true()
	var a: Rect2 = skip.get_global_rect()
	var b: Rect2 = next.get_global_rect()
	var apart: float = maxf(
		maxf(b.position.x - a.end.x, a.position.x - b.end.x),
		maxf(b.position.y - a.end.y, a.position.y - b.end.y)
	)
	assert_float(apart).is_greater_equal(UiScale.dp(12.0) - TOLERANCE_PX)
	_director.next()
	_director.advance()
	await await_idle_frame()
	await await_idle_frame()
	assert_bool(skip.is_visible_in_tree()).is_false()
	assert_bool(next.is_visible_in_tree()).is_true()
	_director.next()
	_director.advance()
	await await_idle_frame()
	await await_idle_frame()
	assert_bool(next.is_visible_in_tree()).is_false()  # An action beat has no Next.
	assert_bool(skip.is_visible_in_tree()).is_false()
	_close()


## A chained beat: a lead-in on `CoachTarget` that holds once the drawer is open, then the beat's
## own anchor `final`, a second control at the screen's lower part.
func _chained(final: StringName = &"SecondTarget") -> TutorialBeatDef:
	return Lesson.beat(
		"chain",
		TutorialConditions.Kind.CAMERA_PANNED,
		{
			"anchor": TutorialBeatDef.Anchor.CONTROL,
			"anchor_control": final,
			"lead_in":
			[
				Lesson.lead_in(
					"CoachTarget", TutorialConditions.Kind.UNFOLD_OPEN, HudState.Unfold.DRAWER
				)
			]
		}
	)


func _second(node: Control, name: StringName) -> Control:
	node.name = name
	_hud_root.add_child(node)
	var centre: Vector2 = get_viewport().get_visible_rect().size * Vector2(0.5, 0.75)
	node.position = centre - node.size * 0.5
	return node


func _plain() -> Control:
	var second: Control = Control.new()
	second.size = Vector2.ONE * UiScale.dp(56.0)
	return _second(second, &"SecondTarget")


func test_the_ring_follows_the_chain_on_target_changed() -> void:
	await _open(_profile(ScreenSizes.LANDSCAPE[0]), _chained())
	var second: Control = _plain()
	assert_bool(_mark.ring_rect().encloses(_target.get_global_rect())).is_true()
	var changes: Array[StringName] = []
	_director.target_changed.connect(
		func(step: TutorialLeadInDef) -> void: changes.append(step.anchor_control)
	)
	_director.hud.open(HudState.Unfold.DRAWER)
	_director.advance()  # No frame in between: the mark follows the signal itself.
	assert_array(changes).is_equal([&"SecondTarget"])
	assert_object(_mark.target_control()).is_same(second)
	assert_bool(_mark.ring_rect().encloses(second.get_global_rect())).is_true()
	_director.hud.close(HudState.Unfold.DRAWER)  # The ring goes back to the step before.
	_director.advance()
	assert_object(_mark.target_control()).is_same(_target)


class SpySidebar:
	extends Control
	var asked: Array[ItemTile] = []

	func reveal_tile(tile: ItemTile) -> void:
		asked.append(tile)


func test_a_card_out_of_view_puts_the_ring_on_the_lists_edge_and_is_revealed_once() -> void:
	await _open(_profile(ScreenSizes.PORTRAIT[0]), _chained(&"Tile_probe"))
	var sidebar: SpySidebar = SpySidebar.new()
	_hud_root.add_child(sidebar)
	var list: ScrollContainer = ScrollContainer.new()
	list.size = Vector2(UiScale.dp(200.0), UiScale.dp(200.0))
	list.position = Vector2(UiScale.dp(40.0), UiScale.dp(300.0))
	sidebar.add_child(list)
	var column: VBoxContainer = VBoxContainer.new()
	list.add_child(column)
	var gap: Control = Control.new()
	gap.custom_minimum_size = Vector2(UiScale.dp(150.0), UiScale.dp(600.0))
	column.add_child(gap)
	var tile: ItemTile = ItemTile.new()
	tile.name = "Tile_probe"
	tile.custom_minimum_size = Vector2.ONE * UiScale.dp(96.0)
	column.add_child(tile)
	await await_idle_frame()
	_director.hud.open(HudState.Unfold.DRAWER)
	_director.advance()
	for _i: int in 5:
		await await_idle_frame()
	assert_object(_mark.target_control()).is_same(tile)
	assert_int(sidebar.asked.size()).is_equal(1)  # Five frames, one ask.
	var area: Rect2 = list.get_global_rect()
	var ring: Rect2 = _mark.ring_rect()
	assert_float(ring.get_center().y).is_greater(area.get_center().y)  # The edge nearest the card.
	assert_bool(area.grow(UiScale.dp(8.0)).encloses(ring)).is_true()
	list.scroll_vertical = 700  # The player scrolls by hand: the card comes into view, no new ask.
	for _i: int in 3:
		await await_idle_frame()
	assert_int(sidebar.asked.size()).is_equal(1)
	assert_bool(ring.intersects(_mark.ring_rect()) or _mark.ring_rect().has_area()).is_true()
	assert_bool(area.grow(UiScale.dp(8.0)).encloses(_mark.ring_rect())).is_true()
	_director.hud.close(HudState.Unfold.DRAWER)
	_director.advance()
	_director.hud.open(HudState.Unfold.DRAWER)
	_director.advance()  # The step is entered again: it asks again, once.
	await await_idle_frame()
	assert_int(sidebar.asked.size()).is_equal(2)
