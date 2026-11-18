extends GdUnitTestSuite
## The perf APK's start (preset "Android perf", custom feature `perf_boot`): with the feature the
## boot scene goes straight to the match scene and plays no intro; without it the intro plays.

const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")

var _changes: Array[String] = []


func before_test() -> void:
	_changes.clear()


func _player(feature: bool) -> IntroPlayer:
	var player: IntroPlayer = IntroPlayer.new()
	player.has_feature = func(tag: String) -> bool: return feature and tag == "perf_boot"
	player.change_scene = func(path: String) -> void: _changes.append(path)
	player.loader = FakeIntroLoader.new()
	player.consent = func() -> bool: return true
	player.size = Vector2(ScreenSizes.ALL[0])
	return player


func test_with_the_feature_the_boot_goes_to_the_match_scene_and_plays_no_intro() -> void:
	var player: IntroPlayer = _player(true)
	add_child(player)
	assert_array(_changes).contains_exactly(["res://scenes/main.tscn"])
	assert_int(player.get_child_count()).is_equal(0)  # Nothing was built: no still frame, no tank.
	assert_int(player.phase).is_equal(IntroPlayer.Phase.DONE)
	assert_bool(player.is_processing()).is_false()
	remove_child(player)
	player.free()


func test_without_the_feature_the_intro_plays_as_before() -> void:
	var player: IntroPlayer = _player(false)
	add_child(player)
	assert_array(_changes).is_empty()
	assert_int(player.phase).is_equal(IntroPlayer.Phase.DRIVE)
	assert_int(player.get_child_count()).is_greater(0)
	remove_child(player)
	player.free()


func test_the_real_feature_check_is_off_in_every_test_run() -> void:
	var player: IntroPlayer = IntroPlayer.new()
	assert_bool(bool(player.has_feature.call("perf_boot"))).is_false()
	player.free()
