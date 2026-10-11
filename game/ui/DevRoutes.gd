class_name DevRoutes
extends RefCounted
## Scene paths and gating for the developer-only screens (dev menu, art gallery, touch probe).
##
## The dev menu is available in debug builds and in any export that sets the custom feature
## `dev_menu` (the Web preview preset does). Store presets must not set it.

const MAIN_SCENE: String = "res://scenes/main.tscn"
const DEV_MENU_SCENE: String = "res://scenes/dev/dev_menu.tscn"
const ART_GALLERY_SCENE: String = "res://scenes/dev/art_gallery.tscn"
const TOUCH_PROBE_SCENE: String = "res://scenes/dev/touch_probe.tscn"


static func is_enabled() -> bool:
	return OS.is_debug_build() or OS.has_feature("dev_menu")


## Changes to `scene_path`. Reports a missing scene with push_error instead of crashing.
static func open(tree: SceneTree, scene_path: String) -> Error:
	if not ResourceLoader.exists(scene_path):
		push_error("DevRoutes: scene not found: %s" % scene_path)
		return ERR_FILE_NOT_FOUND
	return tree.change_scene_to_file(scene_path)
