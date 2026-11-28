extends GdUnitTestSuite
## The map select's Figma look (plan P666): the breadcrumb, headline and the two faction cards
## side by side at the six sizes of ADR 0015 section 6 (two columns wide, one upright), START as
## a big target with the offer slot directly under it, and the footer.

const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const FakeRank: GDScript = preload("res://tests/ui/support/fake_rank_progression.gd")
const FakeFlow: GDScript = preload("res://tests/ui/support/fake_start_flow.gd")
const MENU_SCENE: String = "res://scenes/menu/menu.tscn"
const TOLERANCE_PX: float = 0.5

var _window_size_before: Vector2i
var _menu: Control
var _stack: MenuStack
var _screen: MapSelect
var _progression: Node
var _flow: Node


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	_progression = FakeRank.new()
	_flow = FakeFlow.new()


func after_test() -> void:
	UiScale.clear_override()
	if _menu != null:
		remove_child(_menu)
		_menu.free()
		_menu = null
	for node: Node in [_progression, _flow]:
		if is_instance_valid(node):
			node.free()


func test_the_figma_layout_at_the_six_sizes() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(_profile_with_window(size))
		var label: String = str(size)
		var fossil: Rect2 = _screen._side_cards[&"fossil"].get_global_rect()
		var renew: Rect2 = _screen._side_cards[&"renew"].get_global_rect()
		# The two cards side by side at every size, upright too, the same height and no overlap.
		assert_float(fossil.position.y).override_failure_message(label).is_equal_approx(
			renew.position.y, TOLERANCE_PX
		)
		assert_float(fossil.end.x).override_failure_message(label).is_less_equal(
			renew.position.x + TOLERANCE_PX
		)
		var start: Rect2 = _screen._start.get_global_rect()
		var cards: Rect2 = fossil.merge(renew)
		var map: Rect2 = _screen._map_cards[&"kestrel_flats"].get_global_rect()
		var last_map: Rect2 = _screen._map_cards[&"map_3"].get_global_rect()
		var level: Rect2 = _screen._level_cards[&"easy"].get_global_rect()
		var summary: Rect2 = _screen._summary.get_global_rect()
		_assert_steps(label)
		var offer: Rect2 = (
			(_screen.find_child("OfferSlot", true, false) as Control).get_global_rect()
		)
		if UiScale.is_portrait_size(size):
			# One column in order: 01 cards, 02 maps, 03 levels, the summary, START.
			assert_float(cards.end.y).override_failure_message(label).is_less_equal(map.position.y)
			assert_float(last_map.end.y).override_failure_message(label).is_less_equal(
				level.position.y
			)
			assert_float(level.end.y).override_failure_message(label).is_less_equal(
				summary.position.y
			)
			assert_float(start.size.x).override_failure_message(label).is_greater_equal(
				cards.size.x - TOLERANCE_PX
			)
		else:
			# Two columns: 01 and 03 left, 02, the summary and START right.
			assert_float(cards.end.y).override_failure_message(label).is_less_equal(
				level.position.y
			)
			assert_float(cards.end.x).override_failure_message(label).is_less_equal(
				map.position.x + TOLERANCE_PX
			)
			assert_float(level.end.x).override_failure_message(label).is_less_equal(
				start.position.x + TOLERANCE_PX
			)
			assert_float(last_map.end.y).override_failure_message(label).is_less_equal(
				summary.position.y
			)
		assert_float(summary.end.y).override_failure_message(label).is_less_equal(
			start.position.y + TOLERANCE_PX
		)
		# START is a big target, the offer slot (while shown) is directly under it, the footer shows.
		assert_float(start.size.y).override_failure_message(label).is_greater_equal(
			UiScale.dp(64.0) - TOLERANCE_PX
		)
		assert_object(_screen.find_child("OfferSlot", true, false).get_parent()).is_same(
			_screen._start.get_parent()
		)
		assert_float(offer.position.y).override_failure_message(label).is_greater_equal(
			start.end.y - TOLERANCE_PX
		)
		assert_bool(_screen.footer.visible).override_failure_message(label).is_true()
		assert_str(_screen.back_link.text).override_failure_message(label).is_not_empty()
		_close()
		UiScale.clear_override()


func test_the_header_and_the_cards_carry_the_copy_and_the_emblems() -> void:
	await _open(_profile_with_window(ScreenSizes.LANDSCAPE[0]))
	var words: Array[String] = []
	_collect_label_text(_screen.column, words)
	for word: String in [
		"TREADLINE / SKIRMISH",
		"CHOOSE YOUR FRONT",
		"01",
		"CHOOSE YOUR SIDE",
		"02",
		"CHOOSE A MAP",
		"03",
		"CHOOSE DIFFICULTY",
		"IRONWARD",
		"FACET",
		"KESTREL FLATS",
		"EASY",
		"NORMAL",
		"HARD",
	]:
		assert_array(words).override_failure_message(word).contains([word])
	for id: StringName in [&"fossil", &"renew"]:
		var card: Control = _screen._side_cards[id]
		var emblem: TextureRect = card.find_children("*", "TextureRect", true, false)[0]
		assert_object(emblem.texture).is_not_null()
	# No plate named for the map, and the old ">" mark is gone.
	assert_object(_screen.find_child("MapPreviewSlot", true, false)).is_null()
	for word: String in words:
		assert_bool(word.begins_with("> ")).override_failure_message(word).is_false()
	assert_str(_screen._start.text).is_equal("START BATTLE")


func test_each_step_shows_its_choice_and_the_summary_follows_it() -> void:
	await _open(_profile_with_window(ScreenSizes.LANDSCAPE[0]))
	assert_str(_screen._choice_labels[&"side"].text).is_equal("IRONWARD")
	assert_str(_screen._choice_labels[&"map"].text).is_equal("KESTREL FLATS")
	assert_str(_screen._choice_labels[&"level"].text).is_equal("NORMAL")
	assert_str(_screen._summary.text).is_equal("IRONWARD · KESTREL FLATS · NORMAL")
	_screen._sides[&"renew"].pressed.emit()
	_screen._levels[&"easy"].pressed.emit()
	assert_str(_screen._choice_labels[&"side"].text).is_equal("FACET")
	assert_str(_screen._choice_labels[&"level"].text).is_equal("EASY")
	assert_str(_screen._summary.text).is_equal("FACET · KESTREL FLATS · EASY")
	# One chosen item per step: exactly one amber card among the sides, maps and levels each.
	for cards: Dictionary in [_screen._side_cards, _screen._map_cards, _screen._level_cards]:
		var on: int = 0
		for card: PanelContainer in cards.values():
			if String(card.theme_type_variation).ends_with("On"):
				on += 1
		assert_int(on).is_equal(1)


func _assert_steps(label: String) -> void:
	# No option wraps: its word and its lock are one line each (two lines at most per option).
	for id: StringName in _screen._names:
		var name_label: Label = _screen._names[id]
		(
			assert_int(name_label.get_line_count())
			. override_failure_message("%s %s" % [label, id])
			. is_equal(1)
		)
		(
			assert_bool(name_label.size.x + 0.5 >= name_label.get_minimum_size().x)
			. override_failure_message("%s %s clipped" % [label, id])
			. is_true()
		)
		var note: Control = _screen._notes[id]
		if note.visible:
			(
				assert_int((note.get_child(1) as Label).get_line_count())
				. override_failure_message("%s %s lock" % [label, id])
				. is_equal(1)
			)
	for word: Label in _screen._step_words:
		(
			assert_int(word.get_line_count())
			. override_failure_message("%s %s" % [label, word.text])
			. is_equal(1)
		)
	# The header of each step keeps its choice in one line.
	for key: StringName in _screen._choice_labels:
		(
			assert_int(_screen._choice_labels[key].get_line_count())
			. override_failure_message("%s %s" % [label, key])
			. is_equal(1)
		)


func _collect_label_text(node: Node, into: Array[String]) -> void:
	for child: Node in node.get_children():
		if child is Label:
			into.append((child as Label).text)
		_collect_label_text(child, into)


func _open(profile: UiMetrics) -> void:
	assert_object(profile).is_not_null()
	UiScale.set_override(profile)
	get_window().size = profile.window_size
	await await_idle_frame()
	_menu = (load(MENU_SCENE) as PackedScene).instantiate()
	add_child(_menu)
	_stack = _menu.get_node("MenuStack") as MenuStack
	_stack.slide_ms = 0
	_screen = MapSelect.new()
	_screen.progression = _progression
	_screen.flow = _flow
	_screen.catalog = load(MapCatalog.DEFAULT_PATH) as MapCatalog
	_stack.push(_screen)
	for _frame: int in range(3):
		await await_idle_frame()


func _close() -> void:
	if _menu != null:
		remove_child(_menu)
		_menu.free()
		_menu = null


func _profile_with_window(size: Vector2i) -> UiMetrics:
	for profiles: Dictionary[StringName, UiMetrics] in [UiProfiles.all(), UiProfiles.portrait()]:
		for profile_name: StringName in profiles:
			if profiles[profile_name].window_size == size:
				return profiles[profile_name]
	assert_bool(false).override_failure_message("no profile for %s" % size).is_true()
	return null
