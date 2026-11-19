extends GdUnitTestSuite
## The main battle scene, instantiated and freed without ever entering the tree, leaves no
## orphan nodes (P446). Detached children that a script builds in code must be freed by their owner.


func test_main_scene_freed_outside_the_tree_leaves_no_orphans() -> void:
	var packed: PackedScene = load(DevRoutes.MAIN_SCENE)
	var before: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var root: Node = packed.instantiate()
	assert_bool(root.is_inside_tree()).is_false()
	root.free()
	await await_idle_frame()
	var after: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	assert_int(after - before).override_failure_message("orphans leaked").is_equal(0)


func test_main_scene_entered_then_freed_leaves_no_orphans() -> void:
	var packed: PackedScene = load(DevRoutes.MAIN_SCENE)
	var before: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var root: Node = packed.instantiate()
	add_child(root)
	await await_idle_frame()
	remove_child(root)
	root.free()
	await await_idle_frame()
	var after: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	assert_int(after - before).override_failure_message("orphans leaked").is_equal(0)
