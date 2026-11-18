class_name OfferSlot
extends VBoxContainer
## The slot a screen keeps for Phase 6's rewarded offer widget (ADR 0043 section 8, interface note
## of P500c): the result screen's (P532) and the map select's (P525). It lands empty. It is
## visible only while at least one child Control is visible, so it is 0 tall with no gap in its
## column while the widget is absent or hides itself, and it takes the widget's size when the
## widget shows. It is a VBoxContainer, never a plain Container (its size comes from the child).
## It calls no ad: the widget does, and its `on_reward` binds to an autoload, never to the screen.
##
## `slot.owner` is the screen that holds the slot (one offer per screen, claimed through it).
## `OfferSlot.add_to(parent, screen)` builds the slot under `parent` and sets that owner after
## `add_child`; a screen does not set it by hand.


## A new slot under `parent`, owned by `screen` (an ancestor of `parent`, or `parent` itself).
static func add_to(parent: Node, screen: Node) -> OfferSlot:
	var slot: OfferSlot = OfferSlot.new()
	slot.name = &"OfferSlot"
	parent.add_child(slot)
	slot.owner = screen
	return slot


func _init() -> void:
	visible = false
	child_entered_tree.connect(_on_child_entered)
	child_exiting_tree.connect(_on_child_exiting)
	child_order_changed.connect(_refresh)


func _on_child_entered(child: Node) -> void:
	var control: Control = child as Control
	if control != null and not control.visibility_changed.is_connected(_refresh):
		control.visibility_changed.connect(_refresh)


func _on_child_exiting(child: Node) -> void:
	var control: Control = child as Control
	if control != null and control.visibility_changed.is_connected(_refresh):
		control.visibility_changed.disconnect(_refresh)


func _refresh() -> void:
	var shown: bool = false
	for child: Node in get_children():
		if child is Control and (child as Control).visible:
			shown = true
	visible = shown
