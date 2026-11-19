extends GdUnitTestSuite
## Plan row P543b: the `resume` card of Basics asks for Resume while the pause menu is open, so it
## must be seen and its ring must sit on the menu's Resume button. On the main scene's real HUD:
## the pause menu clears the HUD's controls (`_hide_hud`), and it must leave the coach mark clear;
## the mark draws above the menu (`CoachMark.Z_ABOVE_MODALS`); its ring is on `ResumeButton`; the
## card does not cover that button, and neither the mark nor its ring takes a touch the button
## needs.

const Lesson: GDScript = preload("res://tests/ui/tutorial/support/lesson_rig.gd")
const Sizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")

var _main: Node2D
var _window_before: Vector2i = Vector2i.ZERO


func before_test() -> void:
	_window_before = get_window().size
	get_window().size = Sizes.LANDSCAPE[0]
	MenuRig.begin()
	CommandQueue.clear()


func after_test() -> void:
	if _main != null and is_instance_valid(_main):
		remove_child(_main)
		_main.free()
	_main = null
	CommandQueue.clear()
	MenuRig.end()
	get_window().size = _window_before


func test_the_resume_card_is_seen_over_the_open_pause_menu() -> void:
	var lesson: TutorialLessonDef = load("res://data/tutorial/basics.tres") as TutorialLessonDef
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	var runner: MatchRunner = _main.get_node("MatchRunner")
	runner.scenario = lesson.scenario
	runner.match_seed = lesson.match_seed
	runner.tick_mode = MatchRunner.TickMode.SYNC
	var opponents: Array[AiDef] = [lesson.enemy]
	runner.opponents = opponents
	add_child(_main)
	await await_idle_frame()
	var hud: Node = _main.get_node("Hud")
	var feed: HudStateFeed = hud.get_node("HudStateFeed")
	var menu: Control = hud.get_node("PauseMenu")
	var resume_beat: TutorialBeatDef = null
	for beat: TutorialBeatDef in lesson.beats:
		if beat.id == &"resume":
			resume_beat = beat
	assert_object(resume_beat).is_not_null()
	var director: TutorialDirector = auto_free(TutorialDirector.new())
	director.runner = runner
	director.hud = feed.state
	director.camera = _main.get_node("Camera")
	var mark: CoachMark = CoachMark.new()
	mark.director = director
	mark.hud_root = hud
	mark.camera = _main.get_node("Camera")
	hud.add_child(mark)
	await await_idle_frame()
	# The menu is open; the card of the beat after it is up.
	feed.state.open(HudState.Unfold.PAUSE)
	director.start(Lesson.lesson("pause", [resume_beat]))
	director.advance()
	for _frame: int in 4:
		await await_idle_frame()
	assert_object(director.current).is_not_null()
	assert_int(mark.z_index).is_greater(menu.z_index)
	assert_float(mark.modulate.a).is_equal(1.0)  # The menu cleared the HUD, not the mark.
	assert_float(mark.get_global_transform().get_scale().x).is_equal(1.0)
	var resume: Control = hud.find_child("ResumeButton", true, false) as Control
	assert_object(resume).is_not_null()
	assert_object(mark.target_control()).is_same(resume)
	var ring: Rect2 = mark.ring_rect()
	assert_bool(ring.has_area()).is_true()
	assert_bool(resume.get_global_rect().has_point(ring.get_center())).is_true()
	assert_bool(mark.card_rect().intersects(resume.get_global_rect())).is_false()
	assert_int(mark.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	# At each of the six sizes the card stands clear of every other button of the menu and of the
	# banner foot, and the dialogs (the pause menu's questions, the sell question) and the result
	# screen are drawn above it.
	for size: Vector2i in Sizes.ALL:
		get_window().size = size
		for _frame: int in 4:
			await await_idle_frame()
		var card: Rect2 = mark.card_rect()
		assert_bool(card.has_area()).override_failure_message(str(size)).is_true()
		assert_object(mark.target_control()).is_same(resume)
		for node: Node in menu.find_children("*", "Control", true, false):
			var control: Control = node as Control
			var shown: bool = control.is_visible_in_tree() and not control is ConfirmDialog
			var covered: bool = control is Button or control is AdBannerBand
			if shown and covered and control != resume and control.get_global_rect().has_area():
				var label: String = "%s %s under the card at %s" % [size, control.name, card]
				(
					assert_bool(card.intersects(control.get_global_rect()))
					. override_failure_message(label)
					. is_false()
				)
	for node: Node in hud.get_children():
		if node is ConfirmDialog or node is ResultScreen:
			assert_int((node as Control).z_index).is_greater(mark.z_index)
	# Resume closes the menu and ends the beat; the match runs again.
	feed.state.close(HudState.Unfold.PAUSE)
	director.advance()
	assert_object(director.current).is_null()
	director.skip()
