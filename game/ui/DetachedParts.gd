class_name DetachedParts
extends RefCounted
## Frees the parts a HUD node built for itself and never parented (P446). Such a part is made in
## a member initializer or `_init` and added to the tree only when the node is ready, so a node
## that is freed before it ever entered the tree would orphan it. Call `free_unparented(self)` on
## `NOTIFICATION_PREDELETE`. Only private members (leading underscore) count: a public one may
## hold a node that somebody else owns. A part that was parented is left to its parent.


static func free_unparented(owner: Node) -> void:
	var script: Script = owner.get_script()
	while script != null:
		for prop: Dictionary in script.get_script_property_list():
			var key: String = prop["name"]
			if prop["type"] != TYPE_OBJECT or not key.begins_with("_"):
				continue
			var part: Variant = owner.get(key)  # A freed part (its root went first) fails the next test.
			if not is_instance_valid(part) or not part is Node or part == owner:
				continue
			var node: Node = part
			if node.get_parent() == null and not node.is_ancestor_of(owner):
				node.free()
		script = script.get_base_script()
