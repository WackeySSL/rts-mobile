extends GdUnitTestSuite
## The tutorial's anchors on the command bar still resolve (plan row P581): every `anchor_control`
## of `data/tutorial/*.tres` that names a control of the command bar (Deselect, Stop, Repair, Mine,
## Mend, Sell, ...) is found by name under the HUD, once, and is that bar's own button, at the six
## sizes of ScreenSizes.ALL. Stop stands above Deselect in one column and is still named "Stop".

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const LESSON_DIR: String = "res://data/tutorial/"
const MAIN_SCENE: String = "res://scenes/main.tscn"

var _window_size_before: Vector2i
var _main: Node


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	MenuRig.begin()


func after_test() -> void:
	MenuRig.end()
	UiScale.clear_override()


## The command bar's control names: Deselect and an order's id, capitalised.
func _bar_names() -> Dictionary[String, StringName]:
	var out: Dictionary[String, StringName] = {"Deselect": &""}
	for order: Dictionary in CommandBar.ORDERS:
		out[str(order["id"]).capitalize()] = order["id"]
	return out


## The command bar anchors the lesson files use (names), over every beat of every lesson.
func _anchors() -> Array[String]:
	var bar: Dictionary[String, StringName] = _bar_names()
	var out: Array[String] = []
	for file_name: String in DirAccess.get_files_at(LESSON_DIR):
		if not file_name.ends_with(".tres"):
			continue
		var lesson: TutorialLessonDef = load(LESSON_DIR + file_name) as TutorialLessonDef
		if lesson == null:
			continue
		for beat: TutorialBeatDef in lesson.beats:
			var name: String = String(beat.anchor_control)
			if bar.has(name) and not out.has(name):
				out.append(name)
	return out


func test_the_lessons_anchor_on_stop_deselect_and_the_mine_button() -> void:
	var anchors: Array[String] = _anchors()
	for name: String in ["Deselect", "Stop", "Mine", "Repair", "Mend", "Sell"]:
		assert_array(anchors).override_failure_message("no beat anchors on " + name).contains(
			[name]
		)


func test_every_command_bar_anchor_resolves_to_the_bars_own_button_at_every_size() -> void:
	var bar_names: Dictionary[String, StringName] = _bar_names()
	for size: Vector2i in ScreenSizes.ALL:
		UiScale.clear_override()
		get_window().size = size
		await await_idle_frame()
		if _main != null and is_instance_valid(_main):
			remove_child(_main)
			_main.free()
		_main = auto_free((load(MAIN_SCENE) as PackedScene).instantiate())
		add_child(_main)
		await await_idle_frame()
		await await_idle_frame()
		var hud: Node = _main.get_node("Hud")
		var bar: CommandBar = hud.find_child("CommandBar", true, false) as CommandBar
		for name: String in _anchors():
			var why: String = "%s %s" % [size, name]
			var found: Control = hud.find_child(name, true, false) as Control
			assert_object(found).override_failure_message(why).is_not_null()
			(
				assert_int(hud.find_children(name, "Button", true, false).size())
				. override_failure_message(why + " is not unique")
				. is_equal(1)
			)
			var own: Button = (
				bar.find_child("Deselect", true, false) as Button
				if name == "Deselect"
				else bar.order_button(bar_names[name])
			)
			assert_object(found).override_failure_message(why).is_same(own)
