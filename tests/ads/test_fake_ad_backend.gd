extends GdUnitTestSuite
## P403: the fake backend's script switches, its "Test ad" placeholders and the mode choice
## (ADR 0039 section 2), plus the scans that keep ads out of the sim and the SDK names in backends.

const SCAN_ROOTS: Array[String] = ["res://game/sim", "res://game/ai", "res://game/core"]
## Only these files may name the plugin's or Play Billing's classes (P405, P406).
const SDK_BACKENDS: Array[String] = [
	"res://game/ads/AdMobBackend.gd",
	"res://game/ads/UmpPluginBackend.gd",
	"res://game/ads/PlayBillingBackend.gd",
]
const SDK_NAMES: Array[String] = [
	"MobileAds",
	"InterstitialAdLoader",
	"RewardedAdLoader",
	"AdView",
	"BillingClient",
	"UserMessagingPlatform",
	"ConsentInformation",
]


func _frame() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame


func test_admob_mode_needs_android_a_non_editor_build_the_plugin_and_the_play_tag() -> void:
	assert_bool(AdBackend.is_admob_mode("Android", false, true, true)).is_true()
	assert_bool(AdBackend.is_admob_mode("iOS", false, true, true)).is_false()
	assert_bool(AdBackend.is_admob_mode("Android", true, true, true)).is_false()
	assert_bool(AdBackend.is_admob_mode("Android", false, false, true)).is_false()
	assert_bool(AdBackend.is_admob_mode("Android", false, true, false)).is_false()
	assert_bool(AdBackend.is_admob_mode("Linux", false, false, false)).is_false()


func test_the_service_uses_the_fake_backend_for_now() -> void:
	var service: Node = auto_free(load("res://game/ads/AdService.gd").new())
	assert_object(service._backend).is_instanceof(FakeAdBackend)


func test_the_base_backend_never_fills_and_shows_nothing() -> void:
	var backend: AdBackend = AdBackend.new()
	backend.request_load(AdBackend.KIND_REWARDED)
	assert_int(backend.load_state(AdBackend.KIND_REWARDED)).is_equal(AdBackend.LoadState.FAILED)
	assert_int(backend.banner_height_dp()).is_equal(0)


func test_the_fake_loads_per_its_script() -> void:
	var fake: FakeAdBackend = FakeAdBackend.new()
	assert_int(fake.load_state(&"interstitial")).is_equal(AdBackend.LoadState.IDLE)
	fake.request_load(&"interstitial")
	assert_int(fake.load_state(&"interstitial")).is_equal(AdBackend.LoadState.READY)
	fake.fill = false
	fake.request_load(&"rewarded")
	assert_int(fake.load_state(&"rewarded")).is_equal(AdBackend.LoadState.FAILED)
	fake.load_never_answers = true
	fake.request_load(&"rewarded")
	assert_int(fake.load_state(&"rewarded")).is_equal(AdBackend.LoadState.LOADING)


func test_the_placeholder_waits_for_its_close_button_then_rewards_and_closes() -> void:
	var host: Node = add_child_to_suite()
	var fake: FakeAdBackend = FakeAdBackend.new()
	fake.host = host
	var seen: Array[String] = []
	fake.opened.connect(func(_kind: StringName) -> void: seen.append("opened"))
	fake.reward_earned.connect(func(_kind: StringName) -> void: seen.append("reward"))
	fake.closed.connect(func(_kind: StringName) -> void: seen.append("closed"))
	fake.request_load(AdBackend.KIND_REWARDED)
	fake.show_ad(AdBackend.KIND_REWARDED, false)
	assert_array(seen).contains_exactly(["opened"])
	var layer: Node = host.get_node("FakeTestAd")
	var close: Button = layer.find_child("Close", true, false) as Button
	assert_str(close.text).is_equal("Close")
	assert_bool(close.custom_minimum_size.y >= 48.0).is_true()
	close.pressed.emit()
	assert_array(seen).contains_exactly(["opened", "reward", "closed"])
	await _frame()
	assert_bool(host.has_node("FakeTestAd")).is_false()


func test_auto_close_draws_no_placeholder() -> void:
	var host: Node = add_child_to_suite()
	var fake: FakeAdBackend = FakeAdBackend.new()
	fake.host = host
	fake.request_load(AdBackend.KIND_INTERSTITIAL)
	fake.show_ad(AdBackend.KIND_INTERSTITIAL, true)
	assert_int(host.get_child_count()).is_equal(0)


func test_the_banner_placeholder_draws_once_and_goes_on_hide() -> void:
	var host: Node = add_child_to_suite()
	var fake: FakeAdBackend = FakeAdBackend.new()
	fake.host = host
	fake.show_banner(true)
	fake.show_banner(true)
	assert_int(host.get_child_count()).is_equal(1)
	assert_bool(host.has_node("FakeTestBanner")).is_true()
	fake.hide_banner()
	await _frame()
	assert_int(host.get_child_count()).is_equal(0)


func add_child_to_suite() -> Node:
	var host: Node = auto_free(Node.new())
	add_child(host)
	return host


func test_no_ad_service_or_ads_code_in_sim_ai_or_core() -> void:
	for root: String in SCAN_ROOTS:
		for path: String in _gd_files(root):
			var text: String = FileAccess.get_file_as_string(path)
			(
				assert_bool(text.contains("AdService") or text.contains("game/ads"))
				. override_failure_message(path)
				. is_false()
			)


func test_sdk_classes_are_named_only_in_their_backends() -> void:
	var pattern: RegEx = RegEx.create_from_string("\\b(" + "|".join(SDK_NAMES) + ")\\b")
	for path: String in _gd_files("res://game"):
		if path in SDK_BACKENDS:
			continue
		var text: String = FileAccess.get_file_as_string(path)
		assert_object(pattern.search(text)).override_failure_message(path).is_null()


func _gd_files(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	for file_name: String in DirAccess.get_files_at(dir_path):
		if file_name.ends_with(".gd"):
			out.append(dir_path.path_join(file_name))
	for sub: String in DirAccess.get_directories_at(dir_path):
		out.append_array(_gd_files(dir_path.path_join(sub)))
	return out
