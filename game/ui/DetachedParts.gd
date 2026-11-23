class_name DetachedParts
extends RefCounted
## Frees the parts a HUD node built for itself and never parented (P446). Such a part is made in
## a member initializer or `_init` and added to the tree only when the node is ready, so a node
## that is freed before it ever entered the tree would orphan it. Call `free_unparented` with the
## node's own parts on `NOTIFICATION_PREDELETE`. A part that was parented is left to its parent;
## a part whose root went first is already gone, and is skipped.
##
## List only parts that nothing else frees before the owner's PREDELETE. A part freed BEFORE the
## call fails the `Array[Node]` literal conversion at the call site: a debug build raises
## "previously freed" and the array comes out empty, so no part is freed. Today nothing frees a
## listed part early.
##
## New HUD code needs none of this: add each part as a child in `_init`, the way ItemTile,
## StrikeButton, PerfHud and RewardedOffer do, so the tree owns it from construction. The guard in
## tests/ui/test_hud_part_ownership.gd fails a script that builds a Node member with `.new()` and
## neither parents it in `_init` nor lists it here.


static func free_unparented(parts: Array[Node]) -> void:
	for part: Variant in parts:  # Untyped: a freed part must not fail the loop variable.
		if is_instance_valid(part) and (part as Node).get_parent() == null:
			(part as Node).free()
