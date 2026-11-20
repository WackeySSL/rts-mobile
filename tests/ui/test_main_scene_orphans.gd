extends GdUnitTestSuite
## The main battle scene, and each HUD script that builds parts for itself, leave no orphan nodes
## when freed without ever entering the tree (P446). A part that a script builds in code and parents
## only in `_ready` must be freed by its owner (`DetachedParts`).

const HUD_SCRIPTS: Array[String] = [
	"res://game/ui/AttackToast.gd",
	"res://game/ui/BuildSidebar.gd",
	"res://game/ui/CarryControls.gd",
	"res://game/ui/CommandBar.gd",
	"res://game/ui/EconomyCard.gd",
	"res://game/ui/EconomyPill.gd",
	"res://game/ui/GhostControls.gd",
	"res://game/ui/GroupColumn.gd",
	"res://game/ui/Minimap.gd",
	"res://game/ui/RadarMap.gd",
	"res://game/ui/RevealBadge.gd",
	"res://game/ui/StrikeControls.gd",
]


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
	await await_idle_frame()
	await await_idle_frame()
	var leaked: int = _orphans() - before
	assert_int(leaked).override_failure_message("orphans leaked: %d" % leaked).is_equal(0)


func test_each_hud_script_freed_outside_the_tree_leaves_no_orphans() -> void:
	await await_idle_frame()
	for path: String in HUD_SCRIPTS:
		var script: GDScript = load(path)
		var before: int = _orphans()
		var node: Node = script.new()
		node.free()
		var leaked: int = _orphans() - before
		(
			assert_int(leaked)
			. override_failure_message("%s: orphans leaked: %d" % [path, leaked])
			. is_equal(0)
		)
