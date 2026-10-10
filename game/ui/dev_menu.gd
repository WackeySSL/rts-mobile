extends Control
## Developer menu: jump to the test map or the art gallery. When the dev menu is not enabled
## (a release export without the `dev_menu` feature) it opens the main scene instead.

@onready var _test_map_button: Button = %TestMapButton
@onready var _gallery_button: Button = %GalleryButton


func _ready() -> void:
	if not DevRoutes.is_enabled():
		_open_main.call_deferred()
		return
	# An entry whose scene does not exist yet stays visible but cannot be pressed.
	_gallery_button.disabled = not ResourceLoader.exists(DevRoutes.ART_GALLERY_SCENE)
	_test_map_button.pressed.connect(_on_test_map_pressed)
	_gallery_button.pressed.connect(_on_gallery_pressed)


func _open_main() -> void:
	DevRoutes.open(get_tree(), DevRoutes.MAIN_SCENE)


func _on_test_map_pressed() -> void:
	DevRoutes.open(get_tree(), DevRoutes.MAIN_SCENE)


func _on_gallery_pressed() -> void:
	DevRoutes.open(get_tree(), DevRoutes.ART_GALLERY_SCENE)
