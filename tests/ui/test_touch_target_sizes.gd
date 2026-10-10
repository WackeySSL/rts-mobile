extends GdUnitTestSuite
## Dev touch targets are at least 120x120 base px until Phase 1's UiScale.dp() exists
## (ADR 0002 section 6: 51 dp in the worst case, the rule is 48 dp).

const MIN_SIZE: Vector2 = Vector2(120, 120)
## The paths come from DevRoutes, so a moved or mistyped scene fails here instead of being skipped.
const REQUIRED_SCENES: Array[String] = [
	DevRoutes.MAIN_SCENE,
	DevRoutes.DEV_MENU_SCENE,
	DevRoutes.ART_GALLERY_SCENE,
]


func test_required_scenes_exist() -> void:
	for path: String in REQUIRED_SCENES:
		assert_bool(ResourceLoader.exists(path)).override_failure_message(path).is_true()


func test_every_button_is_at_least_120_by_120() -> void:
	var too_small: Array[String] = []
	for path: String in REQUIRED_SCENES:
		var packed: PackedScene = load(path)
		# Not added to the tree: custom_minimum_size is a scene property, and _ready never runs.
		var root: Node = auto_free(packed.instantiate())
		var buttons: Array[Node] = root.find_children("*", "Button", true, false)
		assert_array(buttons).override_failure_message("no Button in %s" % path).is_not_empty()
		for node: Node in buttons:
			var button: Button = node as Button
			var size: Vector2 = button.custom_minimum_size
			if size.x < MIN_SIZE.x or size.y < MIN_SIZE.y:
				too_small.append("%s: %s is %s" % [path, node.name, size])
	assert_array(too_small).is_empty()
