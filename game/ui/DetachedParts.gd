class_name DetachedParts
extends RefCounted
## Frees the parts a HUD node built for itself and never parented (P446). Such a part is made in
## a member initializer or `_init` and added to the tree only when the node is ready, so a node
## that is freed before it ever entered the tree would orphan it. Call `free_unparented` with the
## node's own parts on `NOTIFICATION_PREDELETE`. A part that was parented is left to its parent;
## a part whose root went first is already gone, and is skipped.


static func free_unparented(parts: Array[Node]) -> void:
	for part: Variant in parts:  # Untyped: a freed part must not fail the loop variable.
		if is_instance_valid(part) and (part as Node).get_parent() == null:
			(part as Node).free()
