extends "res://tests/ui/tutorial/support/coach_mark_suite.gd"
## The coach mark follows a beat's chain of targets (plan row P591, ADR 0048 section 5): the ring
## moves on `target_changed`, a drawer card is revealed once per step entry and after its layout
## has settled, a card out of view puts the ring on its list's nearest edge (up and down, or
## sideways), and the director-less and rebind paths.

const Spy: GDScript = preload("res://tests/ui/tutorial/support/spy_sidebar.gd")


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


func _asked(sidebar: BuildSidebar) -> int:
	return (sidebar.get(&"asked") as Array).size()


## A spy sidebar over a vertical list of 200 dp with `gap` px above the card `Tile_probe`.
func _list_with_card(gap: float) -> Array:
	var sidebar: BuildSidebar = Spy.new()
	_hud_root.add_child(sidebar)
	var list: ScrollContainer = ScrollContainer.new()
	list.size = Vector2(UiScale.dp(200.0), UiScale.dp(200.0))
	list.position = Vector2(UiScale.dp(40.0), UiScale.dp(300.0))
	sidebar.add_child(list)
	var column: VBoxContainer = VBoxContainer.new()
	list.add_child(column)
	var spacer: Control = Control.new()
	spacer.custom_minimum_size = Vector2(UiScale.dp(150.0), gap)
	column.add_child(spacer)
	var tile: ItemTile = ItemTile.new()
	tile.name = "Tile_probe"
	tile.custom_minimum_size = Vector2.ONE * UiScale.dp(96.0)
	column.add_child(tile)
	return [sidebar, list, spacer, tile]


func _enter_step() -> void:
	_director.hud.open(HudState.Unfold.DRAWER)
	_director.advance()


func test_a_card_out_of_view_puts_the_ring_on_the_lists_edge_and_is_revealed_once() -> void:
	await _open(_profile(ScreenSizes.PORTRAIT[0]), _chained(&"Tile_probe"))
	var parts: Array = _list_with_card(UiScale.dp(600.0))
	var sidebar: BuildSidebar = parts[0]
	var list: ScrollContainer = parts[1]
	var tile: ItemTile = parts[3]
	await await_idle_frame()
	_enter_step()
	for _i: int in 6:
		await await_idle_frame()
	assert_object(_mark.target_control()).is_same(tile)
	assert_int(_asked(sidebar)).is_equal(1)  # Six frames, one ask.
	var area: Rect2 = list.get_global_rect()
	var ring: Rect2 = _mark.ring_rect()
	assert_float(ring.get_center().y).is_greater(area.get_center().y)  # The edge nearest the card.
	assert_bool(area.grow(UiScale.dp(8.0)).encloses(ring)).is_true()
	assert_bool(ring.intersects(tile.get_global_rect())).is_false()  # Not on the card: it is out.
	list.scroll_vertical = 700  # The player scrolls by hand: the card comes into view, no new ask.
	for _i: int in 4:
		await await_idle_frame()
	assert_int(_asked(sidebar)).is_equal(1)
	var seen: Rect2 = tile.get_global_rect().intersection(area)
	assert_bool(seen.has_area()).is_true()
	assert_bool(_mark.ring_rect().encloses(seen)).is_true()  # Over the card, not the edge strip.
	_director.hud.close(HudState.Unfold.DRAWER)
	_director.advance()
	_enter_step()  # The step is entered again: it asks again, once.
	for _i: int in 5:
		await await_idle_frame()
	assert_int(_asked(sidebar)).is_equal(2)


func test_the_reveal_waits_for_the_layout_to_settle_on_a_step_entry() -> void:
	await _open(_profile(ScreenSizes.PORTRAIT[0]), _chained(&"Tile_probe"))
	var parts: Array = _list_with_card(UiScale.dp(100.0))
	var sidebar: BuildSidebar = parts[0]
	var spacer: Control = parts[2]
	await await_idle_frame()
	_enter_step()
	for step: int in 4:  # The grid is still sorting: the card moves for four frames.
		spacer.custom_minimum_size.y += UiScale.dp(10.0)
		await await_idle_frame()
		assert_int(_asked(sidebar)).override_failure_message("frame %d" % step).is_equal(0)
	for _i: int in 6:
		await await_idle_frame()
	assert_int(_asked(sidebar)).is_equal(1)


func test_a_card_of_a_sideways_list_puts_the_ring_on_its_left_or_right_edge() -> void:
	await _open(_profile(ScreenSizes.LANDSCAPE[0]), _chained(&"Tile_probe"))
	var parts: Array = _list_with_card(0.0)
	var list: ScrollContainer = parts[1]
	var spacer: Control = parts[2]
	var tile: ItemTile = parts[3]
	var column: Node = spacer.get_parent()
	list.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	column.remove_child(spacer)
	column.remove_child(tile)
	var row: HBoxContainer = HBoxContainer.new()
	column.replace_by(row)
	row.add_child(spacer)
	row.add_child(tile)
	column.free()
	spacer.custom_minimum_size = Vector2(UiScale.dp(600.0), UiScale.dp(60.0))
	await await_idle_frame()
	_enter_step()
	for _i: int in 3:
		await await_idle_frame()
	var area: Rect2 = list.get_global_rect()
	var ring: Rect2 = _mark.ring_rect()
	assert_float(ring.get_center().x).is_greater(area.get_center().x)  # The right edge.
	assert_float(ring.size.y).is_greater_equal(minf(area.size.y, UiScale.dp(48.0)) - 1.0)
	assert_bool(area.grow(UiScale.dp(8.0)).encloses(ring)).is_true()


func test_with_no_director_the_ring_is_on_the_beats_own_anchor() -> void:
	await _open(_profile(ScreenSizes.LANDSCAPE[0]), _chained())
	var second: Control = _plain()
	_mark.bind(null)
	_mark.show_beat(_chained())  # The lead-in is ignored: no director says where the player is.
	await await_idle_frame()
	assert_object(_mark.target_control()).is_same(second)


func test_a_rebind_leaves_nothing_connected_to_the_old_director() -> void:
	await _open(_profile(ScreenSizes.LANDSCAPE[0]), _chained())
	var other: TutorialDirector = auto_free(TutorialDirector.new())
	other.runner = _runner
	other.hud = HudState.new()
	other.selection = SelectionModel.new()
	_mark.bind(other)
	for connected: Signal in [_director.target_changed, _director.beat_shown, _director.beat_done]:
		for link: Dictionary in connected.get_connections():
			assert_object((link["callable"] as Callable).get_object()).is_not_same(_mark)
	_director.hud.open(HudState.Unfold.DRAWER)
	_director.advance()  # The old director moves its chain: the mark must not follow it.
	assert_bool(_mark.visible).is_false()
