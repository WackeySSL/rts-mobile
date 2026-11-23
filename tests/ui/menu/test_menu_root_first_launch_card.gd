extends GdUnitTestSuite
## P450: on a first launch the DeployCard shows in the same frame the start begins, however long
## the ads settle takes (it used to show only after it, leaving the menu dead).

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const UiStateGuard: GDScript = preload("res://tests/support/ui_state_guard.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const FLOW: GDScript = preload("res://game/ui/menu/menu_flow_service.gd")

var _size_before: Vector2i


class StuckAds:
	extends Node
	signal never

	func take_start_credits_bonus() -> int:
		return 0

	func settle_fullscreen() -> void:
		await never


func before_test() -> void:
	MenuRig.begin()
	_size_before = get_tree().root.size


func after_test() -> void:
	UiStateGuard.restore(get_tree().root, _size_before)
	MenuRig.end()


func test_the_card_shows_in_the_frame_the_lesson_start_begins_at_both_orientations() -> void:
	for size: Vector2i in [ScreenSizes.LANDSCAPE[0], ScreenSizes.PORTRAIT[0]]:
		get_tree().root.size = size
		var ads: StuckAds = auto_free(StuckAds.new())
		add_child(ads)
		var flow: Node = auto_free(FLOW.new())
		add_child(flow)
		flow.ads = ads
		var card: DeployCard = auto_free(DeployCard.new())
		add_child(card)
		card.attach(flow)
		assert_bool(card.is_showing()).is_false()
		TutorialStart.start(flow, TutorialStart.ORDER[0])  # Not awaited: the settle never ends.
		assert_bool(card.is_showing()).override_failure_message(str(size)).is_true()
