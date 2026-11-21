extends RefCounted
## What a suite that sets the window size or a UiScale override must leave as it found it (P524c).
## Not a test suite. A suite that builds UI calls `restore` in `after_test`; a suite that reads dp
## or a stretch calls `leaks` in `before` and fails with the names, so a leak shows up at its
## source (the suite that ran just before) and not as a wrong dp width far from the cause.
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const LANDSCAPE_BASE: Vector2i = Vector2i(1280, 720)


## Puts the window back to `size` and clears the UiScale override, per test. The UiOrientation
## autoload follows the window's size_changed, so the content scale size comes back with it.
static func restore(window: Window, size: Vector2i) -> void:
	UiScale.clear_override()
	window.size = size


## The leaks to read off the live tree, as lines for a failure message; empty when there are none.
## The headless window is not any of the six test screens, so one of them is a suite's leftover.
static func leaks(tree: SceneTree) -> Array[String]:
	var found: Array[String] = []
	var root: Window = tree.root
	if UiScale.has_override():
		found.append("a UiScale override is still set")
	var base: Vector2i = UiScale.base_size_for(root.size, LANDSCAPE_BASE)
	if root.content_scale_size != base:
		found.append(
			(
				"content scale size %s is not the base %s of the window"
				% [root.content_scale_size, base]
			)
		)
	if DisplayServer.get_name() == "headless" and ScreenSizes.ALL.has(root.size):
		found.append("the window is still %s, a size a suite set" % [root.size])
	if tree.current_scene != null:
		found.append("current_scene is %s" % [tree.current_scene.name])
	return found
