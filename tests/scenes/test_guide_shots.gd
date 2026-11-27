extends GdUnitTestSuite
## Plan row P595: the developer scene `scenes/dev/guide_shots.tscn` (the guide's PNG shots for a
## PR) keeps its list of shots: four beats at each of the six sizes of ScreenSizes, one more with
## Reduced effects on at the first landscape size (25), and `support/mine` on the Web phone of
## 2400x912 (26). Every shot names a beat that exists, and the PNG names are unique. The scene
## itself saves nothing without `--out`, so the scene scan can open it.

const Shots: GDScript = preload("res://scenes/dev/guide_shots.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const SCENE: String = "res://scenes/dev/guide_shots.tscn"
const LESSON_DIR: String = "res://data/tutorial/"
const SHOTS: int = 26


func test_the_scene_lists_26_shots_with_unique_names() -> void:
	var specs: Array[Dictionary] = Shots.specs()
	assert_int(specs.size()).is_equal(SHOTS)
	var names: Array[String] = []
	for spec: Dictionary in specs:
		var file: String = spec["file"]
		assert_bool(names.has(file)).override_failure_message("duplicate " + file).is_false()
		assert_bool(file.ends_with(".png")).is_true()
		names.append(file)


func test_each_of_four_beats_is_shot_at_the_six_sizes() -> void:
	var specs: Array[Dictionary] = Shots.specs()
	var seen: Dictionary[String, Array] = {}
	for spec: Dictionary in specs:
		if spec["reduced"] or spec["size"] == UiProfiles.by_name(&"web_phone_small").window_size:
			continue
		var sizes: Array = seen.get_or_add(spec["pair"], [])
		sizes.append(spec["size"])
	var pairs: Array = seen.keys()
	pairs.sort()
	assert_array(pairs).is_equal(["air/tap-air", "basics/attack", "basics/groups", "support/mine"])
	for pair: String in seen:
		assert_array(seen[pair]).override_failure_message(pair).contains_exactly(ScreenSizes.ALL)


func test_the_extras_are_the_reduced_attack_and_the_mine_on_the_web_phone() -> void:
	var reduced: Array[Dictionary] = []
	var web: Array[Dictionary] = []
	for spec: Dictionary in Shots.specs():
		if spec["reduced"]:
			reduced.append(spec)
		elif spec["size"] == UiProfiles.by_name(&"web_phone_small").window_size:
			web.append(spec)
	assert_int(reduced.size()).is_equal(1)
	assert_str(reduced[0]["pair"]).is_equal("basics/attack")
	assert_bool(reduced[0]["size"] == ScreenSizes.LANDSCAPE[0]).is_true()
	assert_int(web.size()).is_equal(1)
	assert_str(web[0]["pair"]).is_equal("support/mine")


func test_every_shot_names_a_beat_of_a_lesson() -> void:
	for spec: Dictionary in Shots.specs():
		var pair: String = spec["pair"]
		var lesson: TutorialLessonDef = (
			load("%s%s.tres" % [LESSON_DIR, pair.get_slice("/", 0)]) as TutorialLessonDef
		)
		assert_object(lesson).override_failure_message("no lesson for " + pair).is_not_null()
		var ids: Array[String] = []
		for beat: TutorialBeatDef in lesson.beats:
			ids.append(String(beat.id))
		assert_array(ids).override_failure_message("no beat " + pair).contains(
			[pair.get_slice("/", 1)]
		)


func test_the_scene_does_nothing_without_an_out_directory() -> void:
	var root: Node = auto_free((load(SCENE) as PackedScene).instantiate())
	add_child(root)
	await await_idle_frame()
	assert_object(root).is_not_null()
	assert_int(root.get_child_count()).is_equal(0)
