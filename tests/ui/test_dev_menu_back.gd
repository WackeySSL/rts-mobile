extends GdUnitTestSuite
## The dev menu's Back (ADR 0043 section 4): when the menu is the app's start it returns to the
## menu through MenuFlow; otherwise (a build that starts in the match scene) it does nothing.

const DEV_MENU: String = "res://scenes/dev/dev_menu.tscn"

var _calls: Array[int] = []


func before_test() -> void:
	_calls.clear()


func _open(menu_is_start: bool) -> Control:
	var menu: Control = (load(DEV_MENU) as PackedScene).instantiate() as Control
	menu.set("menu_is_start", func() -> bool: return menu_is_start)
	menu.set("go_to_menu", func() -> void: _calls.append(1))
	add_child(menu)
	return menu


func test_back_returns_to_the_menu_when_the_menu_is_the_start() -> void:
	var menu: Control = await _open(true)
	menu.notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	assert_array(_calls).is_empty()  # Deferred: never inside the notification.
	await await_idle_frame()
	assert_array(_calls).has_size(1)
	remove_child(menu)
	menu.free()


func test_back_does_nothing_when_the_menu_is_not_the_start() -> void:
	var menu: Control = await _open(false)
	menu.notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	await await_idle_frame()
	assert_array(_calls).is_empty()
	remove_child(menu)
	menu.free()


func test_the_default_check_reads_the_projects_main_scene() -> void:
	var menu: Control = await _open(false)
	var check: Callable = Callable(menu, "_menu_is_start")
	assert_bool(bool(check.call())).is_true()  # project.godot starts on boot.tscn (P533).
	remove_child(menu)
	menu.free()
