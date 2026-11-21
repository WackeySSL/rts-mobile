extends GdUnitTestSuite
## The main battle scene leaves no orphan nodes when freed without ever entering the tree (P446).
## A part that a script builds in code and parents only in `_ready` must be freed by its owner
## (`DetachedParts`). The per-script check is in test_hud_part_ownership.gd.


func _orphans() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))


func test_main_scene_freed_outside_the_tree_leaves_no_orphans() -> void:
	var packed: PackedScene = load(DevRoutes.MAIN_SCENE)
	await await_idle_frame()  # Frees queued by earlier tests land before the baseline.
	var before: int = _orphans()
	var root: Node = packed.instantiate()
	assert_bool(root.is_inside_tree()).is_false()
	root.free()
	var leaked: int = _orphans() - before
	assert_int(leaked).override_failure_message("orphans leaked: %d" % leaked).is_equal(0)


## Guards double free and use-after-free on the entered path only: the parts were parented in
## `_ready`, so the parent frees them and `DetachedParts` finds nothing of its own to free.
func test_main_scene_entered_then_freed_leaves_no_orphans() -> void:
	var packed: PackedScene = load(DevRoutes.MAIN_SCENE)
	await await_idle_frame()
	var before: int = _orphans()
	var root: Node = packed.instantiate()
	add_child(root)
	await await_idle_frame()
	remove_child(root)
	root.free()
	# One idle frame is enough (a second changed nothing in three runs): it lets the frees that
	# `_ready` and the menus queued (queue_free, deferred calls) land before the count is read.
	await await_idle_frame()
	var leaked: int = _orphans() - before
	assert_int(leaked).override_failure_message("orphans leaked: %d" % leaked).is_equal(0)
