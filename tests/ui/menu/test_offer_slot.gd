extends GdUnitTestSuite
## The shared `OfferSlot` (P532, for P525 and Phase 6's rewarded offer): owned by the screen that
## holds it, empty and hidden and 0 tall at the start, visible only while a child Control is
## visible, and it calls no ad.


func test_the_slot_is_owned_by_its_screen_and_lands_empty_hidden_and_0_tall() -> void:
	var screen: Control = auto_free(Control.new())
	add_child(screen)  # Visibility changes only signal inside the tree.
	var column: VBoxContainer = VBoxContainer.new()
	screen.add_child(column)
	var slot: OfferSlot = OfferSlot.add_to(column, screen)
	assert_object(slot.owner).is_same(screen)
	assert_str(str(slot.name)).is_equal("OfferSlot")
	assert_int(slot.get_child_count()).is_equal(0)
	assert_bool(slot.visible).is_false()
	assert_float(slot.get_combined_minimum_size().y).is_equal(0.0)


func test_a_hidden_child_keeps_the_slot_hidden_and_0_tall_and_showing_it_shows_the_slot() -> void:
	var screen: Control = auto_free(Control.new())
	add_child(screen)  # Visibility changes only signal inside the tree.
	var slot: OfferSlot = OfferSlot.add_to(screen, screen)
	var widget: Control = Control.new()
	widget.custom_minimum_size = Vector2(10, 40)
	widget.visible = false
	slot.add_child(widget)
	assert_bool(slot.visible).is_false()
	assert_float(slot.get_combined_minimum_size().y).is_equal(0.0)
	widget.visible = true
	assert_bool(slot.visible).is_true()
	assert_float(slot.get_combined_minimum_size().y).is_equal(40.0)
	widget.visible = false  # A widget that hides itself takes the slot back: no gap.
	assert_bool(slot.visible).is_false()
	assert_float(slot.get_combined_minimum_size().y).is_equal(0.0)


func test_removing_the_last_visible_child_hides_the_slot_and_a_plain_node_does_not_show_it(
) -> void:
	var screen: Control = auto_free(Control.new())
	add_child(screen)  # Visibility changes only signal inside the tree.
	var slot: OfferSlot = OfferSlot.add_to(screen, screen)
	var plain: Node = Node.new()
	slot.add_child(plain)
	assert_bool(slot.visible).is_false()
	var widget: Control = Control.new()
	slot.add_child(widget)
	assert_bool(slot.visible).is_true()
	slot.remove_child(widget)
	assert_bool(slot.visible).is_false()
	widget.free()
	slot.remove_child(plain)
	plain.free()


func test_the_slot_script_calls_no_ad() -> void:
	var text: String = FileAccess.get_file_as_string("res://game/ui/menu/OfferSlot.gd").to_lower()
	for word: String in ["adservice", "admob", "interstitial", "show_rewarded"]:
		assert_bool(text.contains(word)).override_failure_message(word).is_false()
