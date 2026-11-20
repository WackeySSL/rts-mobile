extends GdUnitTestSuite
## Plan row P543b: the coach mark over a modal. On the main scene's real HUD, with real touches
## pushed through the viewport:
## - the `resume` card of Basics asks for Resume over the open pause menu: it is seen (the menu
##   clears the HUD, not the mark), drawn above the menu, its ring is on `ResumeButton` inside the
##   safe rect, and at the six sizes the card keeps 8 dp off every other button, off Resume itself
##   and 16 dp off the ad band;
## - every other beat stands down while a modal covers the HUD and does not hold its target (the
##   pause menu, the result screen, the How to play overlay): the mark is hidden and the touch goes
##   to the modal's button, not to the card under it.

const BASICS: String = "res://data/tutorial/basics.tres"
const Lesson: GDScript = preload("res://tests/ui/tutorial/support/lesson_rig.gd")
const Sizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const AdBandAsserts: GDScript = preload("res://tests/ui/support/ad_band_asserts.gd")
const MatchRig: GDScript = preload("res://tests/ui/support/match_rig.gd")
const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const Touch: GDScript = preload("res://tests/support/touch_events.gd")

var _main: Node
var _service: Node
var _harness: RefCounted
var _window_before: Vector2i = Vector2i.ZERO
var _presses: int = 0


func before_test() -> void:
	_window_before = get_window().size
	get_window().size = Sizes.LANDSCAPE[0]
	MenuRig.begin()
	CommandQueue.clear()
	_presses = 0


func after_test() -> void:
	if _main != null and is_instance_valid(_main):
		remove_child(_main)
		_main.free()
	_main = null
	if _harness != null:
		_harness.dispose()
		_harness = null
	CommandQueue.clear()
	MenuRig.end()
	UiScale.clear_override()
	var tree: SceneTree = get_tree()
	if tree.current_scene != null:
		tree.current_scene.free()
		tree.current_scene = null
	get_window().size = _window_before


func test_the_resume_card_is_seen_over_the_open_pause_menu() -> void:
	var stage: Dictionary = await _stage(Sizes.LANDSCAPE[0], &"resume", false)
	var mark: CoachMark = stage["mark"]
	var menu: Control = stage["menu"]
	var resume: Control = stage["hud"].find_child("ResumeButton", true, false) as Control
	assert_object(stage["director"].current).is_not_null()
	assert_bool(mark.visible).is_true()
	assert_int(mark.z_index).is_greater(menu.z_index)
	assert_float(mark.modulate.a).is_equal(1.0)  # The menu cleared the HUD, not the mark.
	assert_object(resume).is_not_null()
	assert_object(mark.target_control()).is_same(resume)
	assert_bool(mark.ring_rect().has_area()).is_true()
	assert_int(mark.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	# A touch on Resume reaches Resume: neither the mark nor its ring takes it.
	resume.pressed.connect(func() -> void: _presses += 1)
	_tap(resume.get_global_rect().get_center())
	assert_int(_presses).is_equal(1)
	assert_object(stage["director"].current).is_not_null()  # Ends on the next advance.
	stage["director"].advance()
	assert_object(stage["director"].current).is_null()
	stage["director"].skip()


## At each size the card stands clear of the ring and of Resume, 8 dp off every other button of
## the menu, and the ring lies inside the safe rect.
func test_the_card_keeps_clear_of_the_menu_at_the_six_sizes() -> void:
	for size: Vector2i in Sizes.ALL:
		var stage: Dictionary = await _stage(size, &"resume", false)
		var mark: CoachMark = stage["mark"]
		var menu: Control = stage["menu"]
		var resume: Control = stage["hud"].find_child("ResumeButton", true, false) as Control
		var card: Rect2 = mark.card_rect()
		var label: String = str(size)
		assert_bool(card.has_area()).override_failure_message(label).is_true()
		assert_object(mark.target_control()).override_failure_message(label).is_same(resume)
		(
			assert_bool(card.intersects(resume.get_global_rect()))
			. override_failure_message(label + " card over Resume")
			. is_false()
		)
		var visible: Rect2 = mark.get_viewport().get_visible_rect()
		var safe: Rect2 = SafeAreaMargin.rect_inside(visible, SafeAreaMargin.DEFAULT_MARGIN_DP)
		var ring: Rect2 = mark.ring_rect()
		(
			assert_bool(safe.grow(0.5).encloses(ring))
			. override_failure_message("%s ring %s outside %s" % [label, ring, safe])
			. is_true()
		)
		for node: Node in menu.find_children("*", "Button", true, false):
			var button: Button = node as Button
			if button == resume or not button.is_visible_in_tree():
				continue
			var air: float = UiScale.dp(8.0) - 0.01
			var text: String = "%s %s within the card's air at %s" % [label, button.name, card]
			(
				assert_bool(card.grow(air).intersects(button.get_global_rect()))
				. override_failure_message(text)
				. is_false()
			)
		await _free_stage()


## The pause menu's foot holds a live banner band (the fake-mode service of the pause banner suite,
## no ad request): the card never overlaps it and keeps the buttons' 16 dp from it. The band shows
## upright only, so the sideways sizes show none, and the test says so.
func test_the_card_keeps_off_the_banner_band_at_the_six_sizes() -> void:
	var upright: int = 0
	for size: Vector2i in Sizes.ALL:
		var stage: Dictionary = await _stage(size, &"resume", true)
		var mark: CoachMark = stage["mark"]
		var label: String = str(size)
		var bands: Array[Node] = _main.find_children("*", "AdBannerBand", true, false)
		var card: Rect2 = mark.card_rect()
		assert_bool(card.has_area()).override_failure_message(label).is_true()
		if size.y > size.x:
			assert_array(bands).override_failure_message(label).has_size(1)
			upright += 1
			var band: AdBannerBand = bands[0] as AdBannerBand
			var strip: Control = AdBandAsserts.strip_of(_service)
			assert_bool(band.is_visible_in_tree()).override_failure_message(label).is_true()
			var gap: float = UiScale.dp(16.0) - 0.01
			for taken: Rect2 in [band.get_global_rect(), strip.get_global_rect()]:
				var text: String = "%s: card %s near band %s" % [label, card, taken]
				(
					assert_bool(card.grow(gap).intersects(taken))
					. override_failure_message(text)
					. is_false()
				)
		else:
			assert_array(bands).override_failure_message(label).is_empty()
		await _free_stage()
	assert_int(upright).is_equal(3)


## A beat that is not about the menu (a pan, the pill) stands down while the pause menu is open:
## the mark is hidden, and a touch on Resume reaches Resume at the sideways and upright sizes (the
## card used to sit over it, and to eat the tap).
func test_a_beat_about_something_else_stands_down_over_the_pause_menu() -> void:
	for size: Vector2i in [Sizes.LANDSCAPE[0], Sizes.PORTRAIT[0], Sizes.PORTRAIT[2]]:
		for id: StringName in [&"pan", &"welcome", &"drawer"]:
			var stage: Dictionary = await _stage(size, id, false)
			var mark: CoachMark = stage["mark"]
			var label: String = "%s %s" % [size, id]
			assert_object(stage["director"].current).override_failure_message(label).is_not_null()
			assert_bool(mark.visible).override_failure_message(label).is_false()
			var resume: Button = stage["hud"].find_child("ResumeButton", true, false) as Button
			_presses = 0
			resume.pressed.connect(func() -> void: _presses += 1)
			_tap(resume.get_global_rect().get_center())
			assert_int(_presses).override_failure_message(label + " tap").is_equal(1)
			await _free_stage()


## The base falls during a beat: the result screen takes the touch on its button, not the card.
func test_the_result_screen_takes_the_touch_over_a_beat() -> void:
	for size: Vector2i in [Sizes.LANDSCAPE[0], Sizes.PORTRAIT[0]]:
		var stage: Dictionary = await _stage(size, &"pan", false, false)
		var mark: CoachMark = stage["mark"]
		var result: Control = stage["hud"].get_node("ResultScreen")
		assert_bool(mark.visible).is_true()  # The card is up before the match ends.
		MatchRig.end(_main, [1])  # Player 1 surrenders: the real end of a match.
		for _frame: int in 6:
			await await_idle_frame()
		var label: String = str(size)
		assert_bool(result.is_visible_in_tree()).override_failure_message(label).is_true()
		assert_bool(mark.visible).override_failure_message(label + " mark").is_false()
		var back: Button = result.find_child("BackButton", true, false) as Button
		# The button's own action would leave the match for the dev menu: swap it for a counter.
		for connection: Dictionary in back.pressed.get_connections():
			back.pressed.disconnect(connection["callable"])
		_presses = 0
		back.pressed.connect(func() -> void: _presses += 1)
		_tap(back.get_global_rect().get_center())
		assert_int(_presses).override_failure_message(label + " tap").is_equal(1)
		await await_idle_frame()
		assert_object(get_tree().current_scene).override_failure_message(label + " left").is_null()
		await _free_stage()


## The How to play overlay of the pause menu covers the Resume button: the resume card goes and
## comes back with it.
func test_the_resume_card_hides_under_the_how_to_play_overlay() -> void:
	var stage: Dictionary = await _stage(Sizes.LANDSCAPE[0], &"resume", false)
	var mark: CoachMark = stage["mark"]
	var menu: PauseMenu = stage["menu"]
	assert_bool(mark.visible).is_true()
	menu.call("_open_help")
	for _frame: int in 4:
		await await_idle_frame()
	assert_bool(mark.visible).is_false()
	menu.call("_close_help")
	for _frame: int in 4:
		await await_idle_frame()
	assert_bool(mark.visible).is_true()


## A real touch through the viewport: a press and a release on the same spot.
func _tap(at: Vector2) -> void:
	Touch.press(get_viewport(), 0, at)
	Touch.release(get_viewport(), 0, at)


## The main scene at `size`, a mark and a director with the basics beat `id` up (the pause menu
## opened first when `menu_open`), the fake-mode ad service in the menu when `with_ad`.
func _stage(size: Vector2i, id: StringName, with_ad: bool, menu_open: bool = true) -> Dictionary:
	var lesson: TutorialLessonDef = load(BASICS) as TutorialLessonDef
	var beat: TutorialBeatDef = null
	for candidate: TutorialBeatDef in lesson.beats:
		if candidate.id == id:
			beat = candidate
	assert_object(beat).is_not_null()
	get_window().size = size
	await await_idle_frame()
	_harness = (load("res://tests/ads/ad_service_harness.gd") as GDScript).new()
	_service = _harness.make(true)
	_service.fake_auto_close = false
	add_child(_service)
	_main = await MatchRig.open(self)
	var hud: Node = _main.get_node("Hud")
	var menu: PauseMenu = hud.get_node("PauseMenu") as PauseMenu
	if with_ad:
		menu.ad_service = _service
	var feed: HudStateFeed = hud.get_node("HudStateFeed") as HudStateFeed
	var director: TutorialDirector = auto_free(TutorialDirector.new())
	director.runner = _main.get_node("MatchRunner")
	director.hud = feed.state
	director.camera = _main.get_node("Camera")
	var mark: CoachMark = CoachMark.new()
	mark.director = director
	mark.hud_root = hud
	mark.camera = _main.get_node("Camera")
	hud.add_child(mark)
	await await_idle_frame()
	if menu_open:
		_main.get_node("Hud/EconomyPill").menu_pressed.emit()
	var single: TutorialLessonDef = Lesson.lesson("single", [beat])
	director.start(single)
	director.advance()
	for _frame: int in 8:
		await await_idle_frame()
	return {"hud": hud, "menu": menu, "mark": mark, "director": director, "feed": feed}


func _free_stage() -> void:
	var tree: SceneTree = get_tree()
	if tree.current_scene != null:  # A button that left the match changes the scene.
		tree.current_scene.free()
		tree.current_scene = null
	if _main != null and is_instance_valid(_main):
		_main.free()
	_main = null
	if _harness != null:
		_harness.dispose()
		remove_child(_service)
		_service.free()
		_harness = null
	await await_idle_frame()
