extends GdUnitTestSuite
## The loading look of the deploy card (ADR 0052, P668): the tip order, the picture let go on close
## and no bar. The timing and the safe area are in `test_deploy_card.gd`.

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const MAP_ID: StringName = &"kestrel_flats"


class FakeFlow:
	extends Node
	signal match_loading(setup: MatchSetup)
	signal match_start_finished(error: Error)

	func current_runner() -> MatchRunner:
		return null


var _card: DeployCard
var _fake: FakeFlow


func before_test() -> void:
	MenuRig.begin()
	_fake = auto_free(FakeFlow.new())
	add_child(_fake)
	_card = auto_free(DeployCard.new())
	add_child(_card)
	_card.attach(_fake)


func after_test() -> void:
	MenuRig.end()


func _setup() -> MatchSetup:
	var setup: MatchSetup = MatchSetup.new()
	setup.map_id = MAP_ID
	return setup


func test_the_tip_order_is_pinned_and_the_counter_moves_once_per_card() -> void:
	var seen: Array[String] = []
	for i: int in DeployCardText.TIPS.size() + 1:
		_fake.match_loading.emit(_setup())
		seen.append(_tip_label().text)
		_fake.match_start_finished.emit(ERR_CANT_CREATE)  # The card closes.
	for i: int in DeployCardText.TIPS.size():
		var want: String = DeployCardText.ENGLISH[DeployCardText.TIPS[i]]
		assert_str(seen[i]).is_equal(want)
	assert_str(seen[DeployCardText.TIPS.size()]).is_equal(seen[0])
	assert_str(seen[0]).is_not_equal(seen[1])


func test_the_picture_is_let_go_when_the_card_closes() -> void:
	_fake.match_loading.emit(_setup())
	assert_object(_card.find_child("MenuBackdrop", true, false)).is_not_null()
	_fake.match_start_finished.emit(ERR_CANT_CREATE)
	assert_object(_card.find_child("MenuBackdrop", true, false)).is_null()
	_fake.match_loading.emit(_setup())  # Again: one picture, never two.
	assert_int(_card.find_children("MenuBackdrop", "", true, false).size()).is_equal(1)


func test_the_card_has_no_bar_and_its_buttons_are_none() -> void:
	assert_int(_card.find_children("*", "ProgressBar", true, false).size()).is_equal(0)
	assert_int(_card.find_children("*", "BaseButton", true, false).size()).is_equal(0)


func _tip_label() -> Label:
	var labels: Array[Node] = _card.find_children("*", "Label", true, false)
	return labels[labels.size() - 1] as Label
