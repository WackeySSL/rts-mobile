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
		var level: Rect2 = _screen._levels[&"easy"].get_global_rect()
		var offer: Rect2 = (
			(_screen.find_child("OfferSlot", true, false) as Control).get_global_rect()
		)
		if UiScale.is_portrait_size(size):
			# One column in Figma's order: cards, map, level, START, all the width of the column.
			assert_float(cards.end.y).override_failure_message(label).is_less_equal(map.position.y)
			assert_float(map.end.y).override_failure_message(label).is_less_equal(level.position.y)
			assert_float(level.end.y).override_failure_message(label).is_less_equal(
				start.position.y
			)
			assert_float(start.size.x).override_failure_message(label).is_greater_equal(
				cards.size.x - TOLERANCE_PX
			)
		else:
			# Two columns: cards and level left, map and START right.
			assert_float(cards.end.x).override_failure_message(label).is_less_equal(
				map.position.x + TOLERANCE_PX
			)
			assert_float(level.end.x).override_failure_message(label).is_less_equal(
				start.position.x + TOLERANCE_PX
			)
			assert_float(map.end.y).override_failure_message(label).is_less_equal(start.position.y)
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
		"TREADLINE / SKIRMISH", "CHOOSE YOUR FRONT", "IRONWARD", "FACET", "MAP", "COMPUTER LEVEL"
	]:
		assert_array(words).override_failure_message(word).contains([word])
	for id: StringName in [&"fossil", &"renew"]:
		var card: Control = _screen._side_cards[id]
		var emblem: TextureRect = card.find_children("*", "TextureRect", true, false)[0]
		assert_object(emblem.texture).is_not_null()
	assert_object(_screen.find_child("MapPreviewSlot", true, false)).is_not_null()
	assert_str(_screen._preview_name.text).is_equal("KESTREL FLATS")


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
