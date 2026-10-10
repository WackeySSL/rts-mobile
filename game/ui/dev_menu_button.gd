extends Button
## The Dev button on the main screen. Opens the dev menu; hidden when the menu is not enabled.


func _ready() -> void:
	visible = DevRoutes.is_enabled()
	pressed.connect(_on_pressed)


func _on_pressed() -> void:
	DevRoutes.open(get_tree(), DevRoutes.DEV_MENU_SCENE)
